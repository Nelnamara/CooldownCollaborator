-- RegisterUnitEvent only filters to the unit(s) passed in the MOST RECENT
-- call for a given event - it does not accumulate across separate calls.
-- Looping it per unit token left the frame listening only to the last
-- token registered (raid40), so nothing ever fired solo or in small groups.
-- Use a plain RegisterEvent instead and filter unitToken ourselves.
function CC:RegisterGroupEvents()
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

function CC:GetActiveGroupNames()
    local names = {}
    local playerName = self:FullName("player")
    if playerName then names[playerName] = true end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = self:FullName("raid" .. i)
            if name then names[name] = true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local name = self:FullName("party" .. i)
            if name then names[name] = true end
        end
    end
    return names
end

function CC:PruneState()
    local active = self:GetActiveGroupNames()
    for name, entry in pairs(self.state) do
        if not active[name] then
            for spellID in pairs(entry.spells) do
                self:BridgeStop(name, spellID)
            end
            self.state[name] = nil
        end
    end
end

-- Re-send OUR OWN recorded cooldowns. Identity travels with the message
-- sender, so relaying other players' entries would mis-attribute them.
function CC:BroadcastState()
    local me = self:FullName("player")
    local entry = me and self.state[me]
    if not entry then return end
    for spellID, usedAt in pairs(entry.spells) do
        -- Skip spells already announced ready; no point re-arming them.
        if not CC.SpellData[spellID] or (usedAt + CC.SpellData[spellID].duration) > GetTime() then
            self:SendCooldownSync(spellID, me, usedAt)
        end
    end
end
