-- Addon messaging — sync CD state with other CooldownCollaborator users.
-- Blocked during boss/M+ encounters AND briefly around death/resurrect; queues
-- and retries rather than dropping.
--
-- Message format: "spellID:secondsAgo:playerName:classTag" (playerName is the
-- bare name; the receiver takes Name-Realm from the sender)
-- Ready-now format: "R:spellID" (sender's own spell is off cooldown)
-- GetTime() is seconds since THAT CLIENT's own process started, not a shared
-- clock - sending a raw GetTime() timestamp and comparing it against the
-- receiver's own GetTime() is meaningless (produced a displayed "36839:39"
-- remaining bug). Send elapsed time since cast instead, and have the
-- receiver re-anchor it to their own GetTime() on arrival.

CC.pendingSyncs = CC.pendingSyncs or {}

-- The channel that reaches the whole group: INSTANCE_CHAT in an instance group
-- (dungeon finder, battleground), else RAID or PARTY; nil when not grouped.
function CC:GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

-- Did SendAddonMessage send it? Retail and Forever return an
-- Enum.SendAddonMessageResult (0 = Success); other builds nothing or true.
-- Anything else (3 = throttled, 11 = lockdown, false, ...) didn't go out.
function CC:AddonMessageSent(result)
    if result == nil or result == true or result == 0 then return true end
    local results = Enum and Enum.SendAddonMessageResult
    return results ~= nil and results.Success ~= nil and result == results.Success
end

function CC:SendCooldownSync(spellID, playerName, usedAt)
    -- AreOutgoingAddonChatMessagesRestricted() was firing true far more often
    -- than expected (outside any encounter or death window), blocking every
    -- send before it was even attempted. Stop trusting that predictive check
    -- and just attempt the real send - SendAddonMessage's own return code is
    -- the authoritative signal, and is what we now act on.
    local chatType = self:GroupChannel()
    if not chatType then
        if CC.verbose then print("|cFF54a3ffCDC|r sync skipped: not in a group") end
        return
    end

    local entry = self.state[playerName]
    local classTag = entry and entry.class or "UNKNOWN"
    local secondsAgo = math.max(0, GetTime() - usedAt)
    -- The wire still carries the bare name so older clients read it; new
    -- clients take identity (name + realm) from the message sender instead.
    local msg = string.format("%d:%.3f:%s:%s", spellID, secondsAgo, self:ShortName(playerName), classTag)

    local result = C_ChatInfo.SendAddonMessage(self.PREFIX, msg, chatType)
    if CC.verbose then
        -- Retail 12.x only; nil elsewhere
        local restricted = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
            and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()
        print(string.format("|cFF54a3ffCDC|r sync send attempt: %s via %s (result=%s, restrictedCheck=%s)",
            msg, chatType, tostring(result), tostring(restricted)))
    end

    -- Not sent (throttled, lockdown, etc.): queue for retry instead of dropping it.
    if not self:AddonMessageSent(result) then
        table.insert(CC.pendingSyncs, { spellID = spellID, playerName = playerName, usedAt = usedAt })
    end
end

-- "Ready now" announcement: "R:spellID". Sent by a player when their own
-- tracked spell comes off cooldown. Old clients parse "R" as the spell ID,
-- get nil from tonumber and drop it.
function CC:SendReadySync(spellID)
    local chatType = self:GroupChannel()
    if not chatType then return end

    local msg = "R:" .. spellID
    local result = C_ChatInfo.SendAddonMessage(self.PREFIX, msg, chatType)
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r ready send attempt: %s via %s (result=%s)",
            msg, chatType, tostring(result)))
    end
    if not self:AddonMessageSent(result) then
        table.insert(CC.pendingSyncs, { kind = "ready", spellID = spellID })
    end
end

function CC:OnAddonMessage(prefix, message, _, sender)
    -- Route buff-status messages to the consumables handler
    if prefix == "CDCBUFF" then
        CC:OnBuffStatusMessage(sender, message)
        return
    end

    if prefix ~= self.PREFIX then return end

    local owner = self:NormalizeSender(sender)

    if message:sub(1, 2) == "R:" then
        local readyID = tonumber(message:sub(3))
        if CC.verbose then
            print(string.format("|cFF54a3ffCDC|r ready received from %s: %s", tostring(sender), tostring(message)))
        end
        -- Our own echo was already applied locally.
        if readyID and owner and owner ~= self:FullName("player") then
            self:RecordReadyFromComm(owner, readyID)
        end
        return
    end

    local spellIDStr, secondsAgoStr, playerName, classTag = strsplit(":", message, 4)
    local spellID    = tonumber(spellIDStr)
    local secondsAgo = tonumber(secondsAgoStr)

    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r sync received from %s: %s", tostring(sender), tostring(message)))
    end

    if not spellID or not secondsAgo or not playerName or playerName == "" then return end

    -- Re-anchor to OUR OWN clock - secondsAgo is clock-independent, unlike
    -- the sender's raw GetTime() value.
    local localUsedAt = GetTime() - secondsAgo

    -- Identity comes from the sender (Name-Realm). If the bare name in the
    -- body is someone else (an old client relaying another player's state),
    -- resolve it against the group instead.
    if not owner or self:ShortName(owner) ~= playerName then
        owner = self:ResolveBareName(playerName)
    end
    self:RecordCooldownFromComm(owner, spellID, localUsedAt, classTag)
end

-- Retry anything that failed to send (throttled, lockdown, etc.). SendCooldownSync
-- itself re-queues on failure, so this just periodically drains the queue.
C_Timer.NewTicker(2, function()
    if #CC.pendingSyncs == 0 then return end

    local queue = CC.pendingSyncs
    CC.pendingSyncs = {}
    for _, item in ipairs(queue) do
        if item.kind == "ready" then
            CC:SendReadySync(item.spellID)
        else
            CC:SendCooldownSync(item.spellID, item.playerName, item.usedAt)
        end
    end
end)
