-- Addon messaging — sync CD state with other CooldownCollaborator users.
-- Blocked during boss/M+ encounters AND briefly around death/resurrect; queues
-- and retries rather than dropping. Message format: "spellID:usedAt:playerName:classTag"

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
    local msg = string.format("%d:%.3f:%s:%s", spellID, usedAt, playerName, classTag)

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

function CC:OnAddonMessage(prefix, message, _, sender)
    if prefix ~= self.PREFIX then return end

    local spellIDStr, usedAtStr, playerName, classTag = strsplit(":", message, 4)
    local spellID = tonumber(spellIDStr)
    local usedAt  = tonumber(usedAtStr)

    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r sync received from %s: %s", tostring(sender), tostring(message)))
    end

    if not spellID or not usedAt or not playerName or playerName == "" then return end

    self:RecordCooldownFromComm(playerName, spellID, usedAt, classTag)
end

-- Retry anything that failed to send (throttled, lockdown, etc.). SendCooldownSync
-- itself re-queues on failure, so this just periodically drains the queue.
C_Timer.NewTicker(2, function()
    if #CC.pendingSyncs == 0 then return end

    local queue = CC.pendingSyncs
    CC.pendingSyncs = {}
    for _, item in ipairs(queue) do
        CC:SendCooldownSync(item.spellID, item.playerName, item.usedAt)
    end
end)
