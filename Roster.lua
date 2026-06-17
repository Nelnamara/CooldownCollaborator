-- Roster capability scan — knows who CAN provide a raid-wide resource before
-- anyone has cast it. Two layers of precision:
--
--   1. Class scan (instant, O(n)) — flags everyone whose CLASS can provide a
--      capability. Happens on every GROUP_ROSTER_UPDATE.
--
--   2. Spec refinement (throttled, ~2s/unit) — uses NotifyInspect/INSPECT_READY
--      to narrow down to exact spec. Matters mainly for Evoker (Augmentation
--      is the spec that typically brings Fury of the Aspects) and for future
--      talent-level checks if Blizzard re-gates abilities behind talent rows.
--      Results stored in CC.rosterSpecs[name] = specIndex.
--
-- CC.roster[name] = { class="SHAMAN", capabilities={ BLOODLUST={2825,32182} } }

-- capability key -> { label, classes = { CLASSTAG = {spellID,...} } }
CC.CAPABILITIES = {
    BLOODLUST = {
        label = "Bloodlust/Heroism",
        classes = {
            SHAMAN = { 2825, 32182 },
            MAGE   = { 80353 },
            EVOKER = { 391215 },
        },
    },
    BATTLEREZ = {
        label = "Battle Rez",
        classes = {
            DRUID       = { 20484 },
            DEATHKNIGHT = { 61999 },
        },
    },
}

-- Ordered list for stable display
CC.CAPABILITY_ORDER = { "BLOODLUST", "BATTLEREZ" }

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

function CC:ScanRoster()
    local roster = {}

    local function addUnit(unit)
        local name = UnitName(unit)
        if not name or name == "" then return end
        local _, classTag = UnitClass(unit)
        if not classTag then return end

        local capabilities = {}
        for key, cap in pairs(CC.CAPABILITIES) do
            local spellIDs = cap.classes[classTag]
            if spellIDs then
                capabilities[key] = spellIDs
            end
        end

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
    self:QueueInspectAll()

    if CC.RefreshEssentials then CC:RefreshEssentials() end
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
    local selfSpec = GetSpecialization()
    local selfName = UnitName("player")
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

    local name = UnitName(unitID)
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

    for name, info in pairs(self.roster) do
        local spellIDs = info.capabilities[capKey]
        if spellIDs then
            local bestRemaining = nil
            local usedSpellID   = nil

            for _, spellID in ipairs(spellIDs) do
                local remaining = self:GetRemaining(name, spellID)
                if remaining and (not bestRemaining or remaining < bestRemaining) then
                    bestRemaining = remaining
                    usedSpellID   = spellID
                end
            end

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
