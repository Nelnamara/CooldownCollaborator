-- Roster capability scan — knows who CAN provide a raid-wide resource before
-- anyone has cast it, by checking class on the current roster. This is a
-- class-only heuristic (not talent-precise): e.g. a Shaman is flagged as a
-- possible Bloodlust source even if they didn't talent it. A future pass
-- could refine this with NotifyInspect/INSPECT_READY for exact precision,
-- but that API is throttled and noticeably slower to populate.
--
-- CC.roster[name] = { class = "SHAMAN", capabilities = { BLOODLUST = {2825,32182} } }

-- capability key -> { label, classes = { CLASSTAG = {spellID, ...} } }
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

        roster[name] = { class = classTag, capabilities = capabilities }
    end

    addUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            addUnit("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            addUnit("party" .. i)
        end
    end

    self.roster = roster
    if CC.verbose then
        local count = 0
        for _ in pairs(roster) do count = count + 1 end
        print(string.format("|cFF54a3ffCDC|r roster scanned: %d member(s)", count))
    end

    if CC.RefreshEssentials then CC:RefreshEssentials() end
end

-- Returns { {name, class, spellIDs, remaining, ready}, ... } for a capability,
-- one entry per roster member who can provide it - "ready" if no recorded
-- usage among their spellIDs is still on cooldown, otherwise the soonest
-- remaining time among those spellIDs.
function CC:GetCapabilityStatus(capKey)
    local results = {}
    if not self.roster then return results end

    for name, info in pairs(self.roster) do
        local spellIDs = info.capabilities[capKey]
        if spellIDs then
            local bestRemaining = nil
            local usedSpellID = nil

            for _, spellID in ipairs(spellIDs) do
                local remaining = self:GetRemaining(name, spellID)
                if remaining and (not bestRemaining or remaining < bestRemaining) then
                    bestRemaining = remaining
                    usedSpellID = spellID
                end
            end

            results[#results + 1] = {
                name      = name,
                class     = info.class,
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
