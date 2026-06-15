-- Addon messaging — sync CD state with other CooldownCollaborator users.
-- Blocked during boss/M+ encounters; broadcasts state to party/raid after ENCOUNTER_END.
-- Message format: "spellID:usedAt:playerName:classTag"

function CC:SendCooldownSync(spellID, playerName, usedAt)
    if self.inEncounter then return end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return end

    local chatType
    if IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup() then
        chatType = "PARTY"
    end
    if not chatType then return end

    local entry = self.state[playerName]
    local classTag = entry and entry.class or "UNKNOWN"
    local msg = string.format("%d:%.3f:%s:%s", spellID, usedAt, playerName, classTag)

    local result = C_ChatInfo.SendAddonMessage(self.PREFIX, msg, chatType)
    -- result == 3: throttled; result == 11: lockdown — both are transient, ignore
end

function CC:OnAddonMessage(prefix, message, _, sender)
    if prefix ~= self.PREFIX then return end

    local spellIDStr, usedAtStr, playerName, classTag = strsplit(":", message, 4)
    local spellID = tonumber(spellIDStr)
    local usedAt  = tonumber(usedAtStr)

    if not spellID or not usedAt or not playerName or playerName == "" then return end

    self:RecordCooldownFromComm(playerName, spellID, usedAt, classTag)
end
