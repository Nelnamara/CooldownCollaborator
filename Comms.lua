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

function CC:SendCooldownSync(spellID, playerName, usedAt)
    -- AreOutgoingAddonChatMessagesRestricted() was firing true far more often
    -- than expected (outside any encounter or death window), blocking every
    -- send before it was even attempted. Stop trusting that predictive check
    -- and just attempt the real send - SendAddonMessage's own return code is
    -- the authoritative signal, and is what we now act on.
    local chatType
    if IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup() then
        chatType = "PARTY"
    end
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
        print(string.format("|cFF54a3ffCDC|r sync send attempt: %s via %s (result=%s, restrictedCheck=%s)",
            msg, chatType, tostring(result), tostring(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted())))
    end

    -- nil/0 == success. Anything else (3 = throttled, 11 = lockdown, etc.)
    -- means it didn't go out - queue for retry instead of dropping it.
    if result then
        table.insert(CC.pendingSyncs, { spellID = spellID, playerName = playerName, usedAt = usedAt })
    end
end

-- "Ready now" announcement: "R:spellID". Sent by a player when their own
-- tracked spell comes off cooldown. Old clients parse "R" as the spell ID,
-- get nil from tonumber and drop it.
function CC:SendReadySync(spellID)
    local chatType
    if IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup() then
        chatType = "PARTY"
    end
    if not chatType then return end

    local msg = "R:" .. spellID
    local result = C_ChatInfo.SendAddonMessage(self.PREFIX, msg, chatType)
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r ready send attempt: %s via %s (result=%s)",
            msg, chatType, tostring(result)))
    end
    if result then
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
