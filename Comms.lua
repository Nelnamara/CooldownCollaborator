-- Addon messaging — sync CD state with other CooldownCollaborator users.
-- Blocked during boss/M+ encounters AND briefly around death/resurrect; queues
-- and retries rather than dropping. Message format: "spellID:usedAt:playerName:classTag"

CC.pendingSyncs = CC.pendingSyncs or {}

function CC:SendCooldownSync(spellID, playerName, usedAt)
    -- Rely solely on the real-time restriction check, not a flag toggled by
    -- ENCOUNTER_START/END. self.inEncounter previously gated this too, but if
    -- ENCOUNTER_END ever fails to fire cleanly (wipe edge case, zone transition,
    -- disconnect mid-fight) that flag gets stuck true and silently blocks every
    -- send for the rest of the session with zero error output.
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
        -- Restriction also fires briefly around death/resurrect, not just
        -- encounters - e.g. a Battle Rez cast on someone who just died. Queue
        -- it instead of dropping; a ticker retries once restriction clears.
        table.insert(CC.pendingSyncs, { spellID = spellID, playerName = playerName, usedAt = usedAt })
        if CC.verbose then print("|cFF54a3ffCDC|r sync queued (restricted): " .. tostring(spellID)) end
        return
    end

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
        print(string.format("|cFF54a3ffCDC|r sync sent: %s via %s (result=%s)",
            msg, chatType, tostring(result)))
    end
    -- result == 3: throttled; result == 11: lockdown — both are transient, ignore
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

-- Retry anything queued while addon messages were restricted (death/resurrect,
-- boss encounters, etc.) as soon as the restriction clears.
C_Timer.NewTicker(2, function()
    if #CC.pendingSyncs == 0 then return end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return end

    local queue = CC.pendingSyncs
    CC.pendingSyncs = {}
    for _, item in ipairs(queue) do
        CC:SendCooldownSync(item.spellID, item.playerName, item.usedAt)
    end
end)
