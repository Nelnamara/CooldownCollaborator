-- RegisterUnitEvent only filters to the unit(s) passed in the MOST RECENT
-- call for a given event - it does not accumulate across separate calls.
-- Looping it per unit token left the frame listening only to the last
-- token registered (raid40), so nothing ever fired solo or in small groups.
-- Use a plain RegisterEvent instead and filter unitToken ourselves.
function CC:RegisterGroupEvents()
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

function CC:IsTrackedUnit(unitToken)
    return unitToken == "player"
        or unitToken:match("^party%d$")
        or unitToken:match("^raid%d%d?$")
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
