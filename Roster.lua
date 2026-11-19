-- Roster capability scan — knows who CAN provide a raid-wide resource before
-- anyone has cast it. Two layers of precision:
--
--   1. Class scan (instant, O(n)) — flags everyone whose CLASS can provide a
--      capability. Happens on every GROUP_ROSTER_UPDATE.
--
--   2. Spec refinement (throttled, ~2s/unit, Retail only) — uses
--      NotifyInspect/INSPECT_READY to narrow down to exact spec. Matters mainly
--      for Evoker (Augmentation is the spec that typically brings Fury of the
--      Aspects) and for future talent-level checks if Blizzard re-gates
--      abilities behind talent rows. Results stored in
--      CC.rosterSpecs[name] = specIndex. The spec is only a label: Era, TBC and
--      Forever have no specs, and MoP doesn't show one yet.
--
-- CC.roster[name] = { class="SHAMAN", capabilities={ BLOODLUST={2825,32182} } }

-- capability key -> { label, classes = { CLASSTAG = {spellID,...} } }, built
-- from the client's providers (CC.Providers, Data_<client>.lua). A capability
-- nobody can provide on this client (no lust on Era or Forever) gets no entry,
-- so it has no lane, header or Essentials slot.
local CAPABILITY_LABELS = {
    BLOODLUST = "Bloodlust/Heroism",
    BATTLEREZ = "Battle Rez",
}

-- Ordered list for stable display
CC.CAPABILITIES     = {}
CC.CAPABILITY_ORDER = {}
for _, key in ipairs({ "BLOODLUST", "BATTLEREZ" }) do
    local classes = CC.Providers and CC.Providers[key]
    if classes and next(classes) then
        CC.CAPABILITIES[key] = { label = CAPABILITY_LABELS[key], classes = classes }
        CC.CAPABILITY_ORDER[#CC.CAPABILITY_ORDER + 1] = key
    end
end

-- Spec names for /cdc roster printout
local SPEC_NAMES = {
    DRUID       = { "Balance", "Feral", "Guardian", "Restoration" },
    SHAMAN      = { "Elemental", "Enhancement", "Restoration" },
    MAGE        = { "Arcane", "Fire", "Frost" },
    EVOKER      = { "Devastation", "Preservation", "Augmentation" },
    DEATHKNIGHT = { "Blood", "Frost", "Unholy" },
    WARRIOR     = { "Arms", "Fury", "Protection" },
    PALADIN     = { "Holy", "Protection", "Retribution" },
    PRIEST      = { "Discipline", "Holy", "Shadow" },
    ROGUE       = { "Assassination", "Outlaw", "Subtlety" },
    HUNTER      = { "Beast Mastery", "Marksmanship", "Survival" },
    WARLOCK     = { "Affliction", "Demonology", "Destruction" },
    MONK        = { "Brewmaster", "Mistweaver", "Windwalker" },
    DEMONHUNTER = { "Havoc", "Vengeance" },
}

-------------------------------------------------------------------------------
-- Class-level scan (instant)
-------------------------------------------------------------------------------

-- Is a player of this level past the level their client teaches the spell at
-- (SpellData `level`, from the SpellLevels game data)? A spell without a level,
-- or a level we can't read (0, -1, or a hidden value), counts as yes.
local function LevelAllows(spellID, level)
    local data = CC.SpellData[spellID]
    local need = data and data.level
    if not need then return true end
    local ok, allowed = pcall(function()
        return not (level and level > 0) or level >= need
    end)
    return not ok or allowed
end

-- A provider spell only one specialization has (SpellData `spec`, its
-- ChrSpecialization ID, the number GetInspectSpecialization returns: Harrier's
-- Cry is Marksmanship's, 254) counts for a groupmate only once CC.rosterSpecs
-- holds that ID for them. Ourselves: yes here, and the spellbook decides
-- (GetCapabilityStatus asks KnownRank).
local function SpecAllows(spellID, name, isSelf)
    local data = CC.SpellData[spellID]
    local need = data and data.spec
    if not need or isSelf then return true end
    -- a spec we can't read (none yet, or a hidden value that throws) is not known
    local ok, same = pcall(function() return CC.rosterSpecs[name] == need end)
    return ok and same == true
end

-- capability key -> the provider spells this unit's class has, its level has
-- reached and (spec-only spells) its known spec has. A capability with none
-- left is not there at all.
function CC:CapabilitiesFor(unit, classTag)
    local level = UnitLevel and UnitLevel(unit)
    -- in a raid we are also a raidN unit, so go by name
    local name = CC:FullName(unit)
    local isSelf = name ~= nil and name == CC:FullName("player")
    local capabilities = {}
    for key, cap in pairs(CC.CAPABILITIES) do
        local spellIDs = cap.classes[classTag]
        if spellIDs then
            local learned = {}
            for _, id in ipairs(spellIDs) do
                if LevelAllows(id, level) and SpecAllows(id, name, isSelf) then learned[#learned + 1] = id end
            end
            if #learned > 0 then capabilities[key] = learned end
        end
    end
    return capabilities
end

-- UNIT_LEVEL: someone in the group (or we) levelled up; redo just their
-- capabilities. No rescan, so Retail's inspect queue isn't restarted.
function CC:OnUnitLevel(unit)
    if type(unit) ~= "string" then return end
    if unit ~= "player" and not unit:match("^party%d+$") and not unit:match("^raid%d+$") then return end
    local name = CC:FullName(unit)
    local info = name and self.roster and self.roster[name]
    if not info then return end
    info.capabilities = self:CapabilitiesFor(unit, info.class)
    if CC.RefreshEssentials then CC:RefreshEssentials() end
end

function CC:ScanRoster()
    local roster = {}

    local function addUnit(unit)
        local name = CC:FullName(unit)
        if not name then return end
        local _, classTag = UnitClass(unit)
        if not classTag then return end

        local capabilities = self:CapabilitiesFor(unit, classTag)

        -- Preserve spec info from a previous inspect if we have it
        local prevSpec = self.rosterSpecs and self.rosterSpecs[name]
        roster[name] = { class = classTag, capabilities = capabilities, spec = prevSpec }
    end

    addUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do addUnit("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do addUnit("party" .. i) end
    end

    self.roster = roster
    if CC.verbose then
        local count = 0
        for _ in pairs(roster) do count = count + 1 end
        print(string.format("|cFF54a3ffCDC|r roster scanned: %d member(s)", count))
    end

    -- Queue a spec refinement pass now that we have fresh unit tokens
    if CC.isRetail then
        self:QueueInspectAll()
    end

    if CC.RefreshEssentials then CC:RefreshEssentials() end
    -- the Lane view only opens in a group: joining one with it on shows it
    if CC.RefreshLanes then CC:RefreshLanes() end
end

-------------------------------------------------------------------------------
-- Spec refinement via NotifyInspect — throttled queue, 2.5s between calls
-------------------------------------------------------------------------------

CC.inspectQueue  = {}
CC.inspectActive = false
CC.rosterSpecs   = {}  -- [playerName] = specIndex

local INSPECT_THROTTLE = 2.5  -- seconds between NotifyInspect calls

-- Build or rebuild the inspect queue from current group members.
function CC:QueueInspectAll()
    self.inspectQueue = {}
    local function enqueue(unit)
        local name = UnitName(unit)
        if name and name ~= "" and UnitIsConnected(unit) then
            self.inspectQueue[#self.inspectQueue + 1] = unit
        end
    end
    -- Self-inspect is instant and doesn't use the throttled API
    local getSpec = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    local selfSpec = getSpec and getSpec()
    local selfName = CC:FullName("player")
    if selfName and selfSpec then
        self.rosterSpecs[selfName] = selfSpec
        if self.roster and self.roster[selfName] then
            self.roster[selfName].spec = selfSpec
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do enqueue("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do enqueue("party" .. i) end
    end
    self:ProcessInspectQueue()
end

-- Drain one entry from the inspect queue.
function CC:ProcessInspectQueue()
    if self.inspectActive then return end
    if #self.inspectQueue == 0 then return end

    local unit = table.remove(self.inspectQueue, 1)
    -- Skip units that are out of range (NotifyInspect silently fails for them)
    if not UnitExists(unit) or not CheckInteractDistance(unit, 1) then
        -- Not in range — skip and try next after a short delay
        C_Timer.After(0.1, function() CC:ProcessInspectQueue() end)
        return
    end

    self.inspectActive = true
    NotifyInspect(unit)
    -- Failsafe: if INSPECT_READY never fires (unit out of range, etc.), advance
    C_Timer.After(INSPECT_THROTTLE + 1, function()
        if CC.inspectActive then
            CC.inspectActive = false
            CC:ProcessInspectQueue()
        end
    end)
end

-- Called from the event handler when INSPECT_READY fires.
function CC:OnInspectReady(unitID)
    self.inspectActive = false

    local name = CC:FullName(unitID)
    if not name or name == "" then
        C_Timer.After(0.1, function() CC:ProcessInspectQueue() end)
        return
    end

    -- GetInspectSpecialization returns the spec index (1/2/3/4) for the unit.
    -- Returns 0 or nil if the unit's spec is hidden (high-privacy mode).
    local specIndex = GetInspectSpecialization and GetInspectSpecialization(unitID) or 0

    if specIndex and specIndex > 0 then
        self.rosterSpecs[name] = specIndex
        if self.roster and self.roster[name] then
            self.roster[name].spec = specIndex
        end
        if CC.verbose then
            local classTag  = self.roster and self.roster[name] and self.roster[name].class or "?"
            local specNames = SPEC_NAMES[classTag]
            local specName  = (specNames and specNames[specIndex]) or ("Spec " .. specIndex)
            print(string.format("|cFF54a3ffCDC|r inspect: %s → %s %s", name, specName, classTag))
        end
    end

    ClearInspectPlayer()
    -- Continue the queue after the mandatory throttle window
    C_Timer.After(INSPECT_THROTTLE, function() CC:ProcessInspectQueue() end)
end

-------------------------------------------------------------------------------
-- Capability status query
-------------------------------------------------------------------------------

-- Returns { {name, class, spec, spellID, remaining, ready}, ... } for a
-- capability, one entry per roster member who can provide it.
function CC:GetCapabilityStatus(capKey)
    local results = {}
    if not self.roster then return results end

    local playerName = self:FullName("player")

    for name, info in pairs(self.roster) do
        local spellIDs = info.capabilities[capKey]
        if spellIDs then
            local bestRemaining = nil
            local usedSpellID   = nil
            local isLocal       = (name == playerName)
            local provides      = false

            for _, spellID in ipairs(spellIDs) do
                -- Our own spellbook has the final word: a spell we haven't
                -- learned (too low, or not bought from the trainer yet) never
                -- makes us a provider. Others go by class and level (CapabilitiesFor).
                if not isLocal or self:KnownRank(spellID) then
                    provides = true
                    -- For ourselves, prefer the true live cooldown/charge readout
                    -- (12.0.7 un-secreted these); fall back to the observed-cast
                    -- model if it's unreadable. Remote players: comm only.
                    local remaining = isLocal and self:GetLocalReadiness(spellID) or nil
                    if remaining == nil then
                        remaining = self:GetRemaining(name, spellID)
                    end
                    if remaining and (not bestRemaining or remaining < bestRemaining) then
                        bestRemaining = remaining
                        usedSpellID   = spellID
                    end
                end
            end

            if provides then
                results[#results + 1] = {
                    name      = name,
                    class     = info.class,
                    spec      = info.spec,
                    spellID   = usedSpellID or spellIDs[1],
                    remaining = bestRemaining or 0,
                    ready     = (bestRemaining or 0) <= 0,
                }
            end
        end
    end

    table.sort(results, function(a, b)
        if a.ready ~= b.ready then return a.ready end
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.name < b.name
    end)

    return results
end

-- Returns a display name for the spec of a roster entry, or nil if unknown.
function CC:GetSpecName(name)
    local entry = self.roster and self.roster[name]
    if not entry or not entry.spec then return nil end
    local specNames = SPEC_NAMES[entry.class]
    return specNames and specNames[entry.spec] or nil
end
