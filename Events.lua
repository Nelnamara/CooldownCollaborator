-- Register UNIT_SPELLCAST_SUCCEEDED for all possible group member unit tokens.
-- Pre-registering all tokens is idempotent and safe — tokens with no live unit never fire.
function CC:RegisterGroupEvents()
    local f = self.eventFrame
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    for i = 1, 4 do
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "party" .. i)
    end
    for i = 1, 40 do
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "raid" .. i)
    end
end

function CC:GetActiveGroupNames()
    local names = {}
    local playerName = UnitName("player")
    if playerName then names[playerName] = true end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = UnitName("raid" .. i)
            if name and name ~= "" then names[name] = true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local name = UnitName("party" .. i)
            if name and name ~= "" then names[name] = true end
        end
    end
    return names
end

function CC:PruneState()
    local active = self:GetActiveGroupNames()
    for name in pairs(self.state) do
        if not active[name] then
            self.state[name] = nil
        end
    end
end

function CC:BroadcastState()
    for name, entry in pairs(self.state) do
        for spellID, usedAt in pairs(entry.spells) do
            self:SendCooldownSync(spellID, name, usedAt)
        end
    end
end
