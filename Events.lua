-------------------------------------------------------------------------------
-- Combat log (Era, TBC, MoP): other players' casts. Retail and WoW: Forever
-- close the combat log to addons (and other units' spell IDs are secret there),
-- so on those clients other players are heard only through addon messages.
-------------------------------------------------------------------------------

-- The Classic clients call it C_CombatLog.GetCurrentEventInfo; the old global is
-- a deprecated alias there (and a stub on Retail).
local GetCombatLogInfo = (C_CombatLog and C_CombatLog.GetCurrentEventInfo) or CombatLogGetCurrentEventInfo
local PARTY_OR_RAID = (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2) + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)
local TYPE_PLAYER   = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

CC.combatLogRegistered = false

-- RegisterUnitEvent only filters to the unit(s) passed in the MOST RECENT
-- call for a given event - it does not accumulate across separate calls.
-- Looping it per unit token left the frame listening only to the last
-- token registered (raid40), so nothing ever fired solo or in small groups.
-- Use a plain RegisterEvent instead and filter unitToken ourselves.
function CC:RegisterGroupEvents()
    self.eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    -- Retail still has CombatLogGetCurrentEventInfo as a stub, so the function
    -- alone proves nothing: only where retailAPI is false, and a refusal never
    -- aborts Init.
    if not CC.retailAPI and GetCombatLogInfo then
        local frame = self.eventFrame
        self.combatLogRegistered = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED") and true or false
    end
end

-- A tracked spell by its cast ID (any rank, or a custom spell) or, failing
-- that, by its name.
function CC:MatchSpell(spellID, spellName)
    local base = spellID and self.RankToBase[spellID]
    if base then return base end
    local data = spellID and CC.SpellData[spellID]
    if data and not data.consumable then return spellID end
    return spellName and self.SpellByName[spellName] or nil
end

-- A caster's class from their GUID. A failed lookup isn't kept: the next cast
-- tries again, at most every 10 s.
local classOf, classTry = {}, {}
local function ClassFromGUID(guid)
    if not guid then return nil end
    if classOf[guid] then return classOf[guid] end
    local now = GetTime()
    local last = classTry[guid]
    if last and now - last < 10 then return nil end
    classTry[guid] = now
    local ok, class = pcall(function() return select(2, GetPlayerInfoByGUID(guid)) end)
    if ok and class then
        classOf[guid], classTry[guid] = class, nil
        return class
    end
    return nil
end

-- SPELL_CAST_SUCCESS from a player in my party or raid: recorded like a synced
-- cast (no message is sent for it; that player's own CooldownCollaborator, if
-- any, sends theirs and RecordCooldownFromComm keeps one).
function CC:OnCombatLog()
    local _, sub, _, srcGUID, srcName, srcFlags = GetCombatLogInfo()
    if sub ~= "SPELL_CAST_SUCCESS" then return end
    if type(srcFlags) ~= "number" or type(srcName) ~= "string" then return end
    -- my own casts come from UNIT_SPELLCAST_SUCCEEDED
    if srcGUID == UnitGUID("player") then return end
    if bit.band(srcFlags, PARTY_OR_RAID) == 0 or bit.band(srcFlags, TYPE_PLAYER) == 0 then return end

    local spellID, spellName = select(12, GetCombatLogInfo())
    local baseID = self:MatchSpell(spellID, spellName)
    if not baseID then return end
    local owner = self:NormalizeSender(srcName)
    if not owner then return end
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r combat log cast: %s %s (%s)",
            tostring(owner), tostring(spellName), tostring(spellID)))
    end
    self:RecordCooldownFromComm(owner, baseID, GetTime(), ClassFromGUID(srcGUID))
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
