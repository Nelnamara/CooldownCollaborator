-- Roster capability scan — knows who CAN provide a raid-wide resource before
-- anyone has cast it. Two layers of precision:
--
--   1. Class scan (instant, O(n)) — flags everyone whose CLASS can provide a
--      capability. Happens on every GROUP_ROSTER_UPDATE.
--
--   2. Spec refinement (throttled, one groupmate at a time, ~2.5 s apart,
--      Retail only) — NotifyInspect / INSPECT_READY read each groupmate's spec
--      once: CC.rosterSpecs[name] = the specialization ID GetInspectSpecialization
--      gives (254 = Marksmanship), which a spec-only provider spell needs
--      (Harrier's Cry, SpecAllows below). Era, TBC and Forever have no specs,
--      and MoP doesn't show one yet.
--
-- CC.roster[name] = { class="SHAMAN", unit="party2", spec=262, capabilities={ BLOODLUST={2825,32182} } }

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

-- The unit token a group member has now (tokens shift as the group changes);
-- `hint` is tried first. nil when they aren't in the group.
function CC:UnitTokenFor(name, hint)
    if hint and self:FullName(hint) == name then return hint end
    if self:FullName("player") == name then return "player" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local token = "raid" .. i
            if self:FullName(token) == name then return token end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local token = "party" .. i
            if self:FullName(token) == name then return token end
        end
    end
    return nil
end

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
        roster[name] = { class = classTag, unit = unit, capabilities = capabilities, spec = prevSpec }
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

    -- each on its own, so an error in one can't keep the other closed;
    -- the Lane view only opens in a group: joining one with it on shows it
    self:RefreshView("RefreshEssentials")
    self:RefreshView("RefreshLanes")
end

-------------------------------------------------------------------------------
-- Spec refinement via NotifyInspect: our own group members only, one at a
-- time, 2.5 s apart, each once (until they change spec). Only a result we
-- asked for moves the queue on: the Inspect window's or another addon's is
-- left alone. INSPECT_READY carries the inspected player's GUID (R15).
-------------------------------------------------------------------------------

CC.inspectQueue   = {}   -- names waiting for an inspect
CC.inspectPending = nil  -- { guid, name, unit }: our own request in flight
CC.rosterSpecs    = {}   -- [playerName] = specialization ID (GetInspectSpecialization)

local INSPECT_THROTTLE = 2.5  -- seconds between NotifyInspect calls

-- Our own spec's ID, read directly (no inspect needed); nil when unreadable.
local function OwnSpecID()
    local ok, id = pcall(function()
        local info = C_SpecializationInfo
        local index
        if info and info.GetSpecialization then
            index = info.GetSpecialization()
        elseif GetSpecialization then
            index = GetSpecialization()
        end
        if not index or index <= 0 then return nil end
        if info and info.GetSpecializationInfo then return (info.GetSpecializationInfo(index)) end
        if GetSpecializationInfo then return (GetSpecializationInfo(index)) end
    end)
    if ok and type(id) == "number" and id > 0 then return id end
    return nil
end

-- Our spec now, and every groupmate whose spec we don't know yet onto the queue.
function CC:QueueInspectAll()
    local selfName = CC:FullName("player")
    local selfSpec = OwnSpecID()
    if selfName and selfSpec then
        self.rosterSpecs[selfName] = selfSpec
        if self.roster and self.roster[selfName] then
            self.roster[selfName].spec = selfSpec
        end
    end
    local queued, keep = {}, {}
    for _, name in ipairs(self.inspectQueue) do
        if self.roster and self.roster[name] and not queued[name] then
            queued[name] = true
            keep[#keep + 1] = name
        end
    end
    local pending = self.inspectPending and self.inspectPending.name
    for name in pairs(self.roster or {}) do
        if name ~= selfName and not self.rosterSpecs[name] and not queued[name] and name ~= pending then
            queued[name] = true
            keep[#keep + 1] = name
        end
    end
    self.inspectQueue = keep
    self:ProcessInspectQueue()
end

local function CanInspectNow(unit)
    if InCombatLockdown() then return false end
    local ok, can = pcall(function()
        if not UnitIsConnected(unit) then return false end
        if CanInspect and not CanInspect(unit) then return false end
        -- NotifyInspect silently fails out of range
        return CheckInteractDistance(unit, 1) and true or false
    end)
    return ok and can == true
end

-- Ask for the next groupmate's spec, unless one of ours is still on its way.
function CC:ProcessInspectQueue()
    if self.inspectPending then return end
    while #self.inspectQueue > 0 do
        local name = table.remove(self.inspectQueue, 1)
        local info = self.roster and self.roster[name]
        local unit = info and self:UnitTokenFor(name, info.unit)
        local guid
        if unit and unit ~= "player" and not self.rosterSpecs[name] and CanInspectNow(unit) then
            guid = UnitGUID(unit)
        end
        if unit and guid then
            local pending = { guid = guid, name = name, unit = unit }
            self.inspectPending = pending
            NotifyInspect(unit)
            -- No answer (out of range, or the server let it go): move on; they are
            -- queued again at the next roster change.
            C_Timer.After(INSPECT_THROTTLE + 1, function()
                if CC.inspectPending == pending then
                    CC.inspectPending = nil
                    CC:ProcessInspectQueue()
                end
            end)
            return
        end
    end
end

-- INSPECT_READY(inspecteeGUID): ours sets that member's spec and redoes their
-- capabilities (a spec-only provider spell may now count); anyone else's is ignored.
function CC:OnInspectReady(guid)
    local pending = self.inspectPending
    if not pending or guid ~= pending.guid then return end
    self.inspectPending = nil

    local unit = self:UnitTokenFor(pending.name, pending.unit)
    if unit and UnitGUID(unit) == guid then
        -- 0 or nil while the spec can't be read
        local ok, specID = pcall(function()
            local id = GetInspectSpecialization(unit)
            if type(id) == "number" and id > 0 then return id end
        end)
        if ok and specID then
            self.rosterSpecs[pending.name] = specID
            local info = self.roster and self.roster[pending.name]
            if info then
                info.spec = specID
                info.capabilities = self:CapabilitiesFor(unit, info.class)
            end
            if CC.verbose then
                print(string.format("|cFF54a3ffCDC|r inspect: %s is %s", pending.name,
                    tostring(self:GetSpecName(pending.name) or specID)))
            end
            self:RefreshView("RefreshEssentials")
            self:RefreshView("RefreshLanes")
        end
    end

    -- our own request is done with, unless the Inspect window is showing someone
    local inspectFrame = InspectFrame
    if not (inspectFrame and inspectFrame:IsShown()) then ClearInspectPlayer() end
    C_Timer.After(INSPECT_THROTTLE, function() CC:ProcessInspectQueue() end)
end

-- PLAYER_SPECIALIZATION_CHANGED(unit): a groupmate changed spec; read it again.
function CC:OnSpecChanged(unit)
    if type(unit) ~= "string" or unit == "player" then
        self:QueueInspectAll()
        return
    end
    if not unit:match("^party%d+$") and not unit:match("^raid%d+$") then return end
    local name = CC:FullName(unit)
    local info = name and self.roster and self.roster[name]
    if not name or not info then return end
    self.rosterSpecs[name] = nil
    info.spec = nil
    info.capabilities = self:CapabilitiesFor(unit, info.class)
    self:QueueInspectAll()
    self:RefreshView("RefreshEssentials")
end

-------------------------------------------------------------------------------
-- Capability status query
-------------------------------------------------------------------------------

-- Online and alive, as far as the game says (an unreadable answer counts as yes).
local function UnitState(unit)
    if not unit then return true, true end
    local okC, connected = pcall(function() return UnitIsConnected(unit) and true or false end)
    local okD, dead = pcall(function() return UnitIsDeadOrGhost(unit) and true or false end)
    return (not okC) or connected, (not okD) or not dead
end

-- Returns { {name, class, spec, spellID, remaining, ready, online, alive,
-- guessed}, ... } for a capability, one entry per roster member who can provide it.
--   ready   = off cooldown and online (an offline owner is never ready, R6)
--   online / alive = the owner is connected / not dead (Request Rez skips both)
--   guessed = "ready as far as we know" (P44): not us, the owner runs no format 2
--             copy (no hello), and no cast of theirs was seen (message or combat log)
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
                local online, alive = UnitState(self:UnitTokenFor(name, info.unit))
                local seen = isLocal
                local entry = self.state[name]
                if entry and not seen then
                    for _, spellID in ipairs(spellIDs) do
                        if entry.spells[spellID] then seen = true break end
                    end
                end
                local peer = self.peers and self.peers[name]
                results[#results + 1] = {
                    name      = name,
                    class     = info.class,
                    spec      = info.spec,
                    spellID   = usedSpellID or spellIDs[1],
                    remaining = bestRemaining or 0,
                    ready     = online and (bestRemaining or 0) <= 0,
                    online    = online,
                    alive     = alive,
                    guessed   = not seen and not (peer and (peer.proto or 0) >= 2),
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
    local id = entry and entry.spec
    if not id or not GetSpecializationInfoByID then return nil end
    local ok, _, specName = pcall(GetSpecializationInfoByID, id)
    if ok and type(specName) == "string" and specName ~= "" then return specName end
    return nil
end
