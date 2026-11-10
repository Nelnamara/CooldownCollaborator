-- RegisterUnitEvent only filters to the unit(s) passed in the MOST RECENT
-- call for a given event - it does not accumulate across separate calls.
-- Looping it per unit token left the frame listening only to the last
-- token registered (raid40), so nothing ever fired solo or in small groups.
-- Use a plain RegisterEvent instead and filter unitToken ourselves.
function CC:RegisterGroupEvents()
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

-- Returns names, complete. complete is false when some member's name wasn't
-- readable yet (nil / "Unknown" while they load in).
function CC:GetActiveGroupNames()
    local names = {}
    local complete = true
    local playerName = UnitName("player")
    if playerName then names[playerName] = true end

    local function add(unit)
        local name = UnitName(unit)
        if name and name ~= "" and name ~= (UNKNOWNOBJECT or "Unknown") then
            names[name] = true
        else
            complete = false
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do add("party" .. i) end
    end
    return names, complete
end

function CC:PruneState()
    local active, complete = self:GetActiveGroupNames()
    -- Don't drop anyone on a half-loaded roster: their known-spells report
    -- isn't re-sent until they reload or change talents.
    if not complete then return end
    for name in pairs(self.state) do
        if not active[name] then
            self.state[name] = nil
        end
    end
    for name in pairs(self.knownSpells or {}) do
        if not active[name] then self.knownSpells[name] = nil end
    end
    for name in pairs(self.addonVersions or {}) do
        if not active[name] then self.addonVersions[name] = nil end
    end
end

-- After an encounter, re-send OUR OWN active cooldowns only (everyone else
-- re-sends theirs; re-sending the whole raid's state from every client was
-- pure spam).
function CC:BroadcastState()
    local me = UnitName("player")
    local entry = me and self.state[me]
    if not entry then return end
    local now = GetTime()
    for spellID, usedAt in pairs(entry.spells) do
        local data = self.SpellData[spellID]
        if not data or usedAt + data.duration > now then
            self:SendCooldownSync(spellID, me, usedAt)
        end
    end
end
