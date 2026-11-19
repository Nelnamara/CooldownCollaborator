-- Cauldron/Feast tracking — each client detects its own buffs and broadcasts
-- its category status (flask/food) so the raid can see who is buffed.
--
-- Detection depends on the client (CC.ConsumableMatch, Data_<client>.lua):
--   "id"   (Retail, WoW: Forever): aura.name and .spellId are SECRET even on
--          the local player. The only safe lookup is
--          C_UnitAuras.GetPlayerAuraBySpellID(knownID), so consumables must be
--          known by ID up front (built-ins, /cdc consumable).
--   "name" (Era, TBC, MoP): auras are readable, and one flask or "Well Fed"
--          buff comes in many spell IDs, so the built-ins match by aura NAME
--          (English and the client's own); /cdc consumable entries match the
--          aura's spell ID.
--
-- Group status: flask/food presence is broadcast as "CDC:BUFF:flask:1" etc.
-- Receivers track CC.buffRoster[playerName] = { flask=bool, food=bool }.
-- The Essentials Bar displays "Flask N/N | Food N/N" with click-to-expand.
--
-- Category field on consumable entries:
--   "flask"  = counts toward group flask counter
--   "food"   = counts toward group food counter
--   nil/""   = tracked but not counted in either group total

CC.consumableActive = CC.consumableActive or {}
CC.buffRoster       = CC.buffRoster or {}        -- [playerName] = { flask=bool, food=bool }

-- Wire format for group buff sync
local BUFF_PREFIX = "CDCBUFF"

-- "name" matching: aura name -> built-in consumable ID (filled at load)
local builtinByName = {}

-------------------------------------------------------------------------------
-- Load / register consumables
-------------------------------------------------------------------------------

function CC:LoadConsumableBuffs()
    -- Built-ins (CC.BuiltinConsumables, with their category) are already merged
    -- into CC.SpellData by Init. "name" matching also knows each one by the
    -- client's own name for it.
    builtinByName = {}
    if CC.ConsumableMatch == "name" then
        for id, data in pairs(CC.BuiltinConsumables or {}) do
            builtinByName[data.name] = id
            local ok, localName = pcall(CC.Compat.GetSpellInfo, id)
            if ok and type(localName) == "string" and localName ~= "" then
                builtinByName[localName] = id
            end
        end
    end

    for idStr, data in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID and data.duration and data.duration > 0 then
            CC.SpellData[spellID] = {
                name       = data.name or ("Consumable " .. spellID),
                duration   = data.duration,
                icon       = data.icon or 134400,
                class      = "UNKNOWN",
                consumable = true,
                category   = data.category,
            }
        end
    end
end

-- /cdc consumable <spellID> <seconds> <flask|food|other> <name>
-- The category is explicit. Called without one (the old form, /cdc consumable <spellID>
-- <seconds> <name>), it is guessed from the name: "flask" or "food" as a word anywhere in it,
-- in any case, and a trailing lowercase flask / food word is taken as the category and dropped.
local function GuessCategory(name)
    local lower = name:lower()
    if lower:find("%f[%a]flask%f[%A]") then return "flask" end
    if lower:find("%f[%a]food%f[%A]") then return "food" end
    return nil
end

function CC:AddConsumableBuff(spellID, duration, name, category)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end

    if category == "other" or category == "" then
        category = nil
    elseif category == nil and name then
        -- the old form: a trailing lowercase flask / food word is the category flag
        -- (two matches in turn: "a or b" would keep only the first capture)
        local stripped, trailing = name:match("^(.-)%s+(flask)$")
        if not stripped then
            stripped, trailing = name:match("^(.-)%s+(food)$")
        end
        if stripped and trailing then
            name     = stripped ~= "" and stripped or nil
            category = trailing
        else
            category = GuessCategory(name)
        end
    end
    name = (name and name ~= "") and name or ("Consumable " .. spellID)

    self.db.consumableBuffs[tostring(spellID)] = {
        name     = name,
        duration = duration,
        icon     = 134400,
        category = category,
    }
    CC.SpellData[spellID] = {
        name       = name,
        duration   = duration,
        icon       = 134400,
        class      = "UNKNOWN",
        consumable = true,
        category   = category,
    }
    local catStr = category and (" [" .. category .. "]") or ""
    print(string.format("|cFF54a3ffCooldownCollaborator|r tracking consumable: %s (%ds)%s",
        name, duration, catStr))
    if self.RefreshSpellList then self:RefreshSpellList() end
    return true
end

-- /cdc consumable remove <spellID>, and the Remove buttons in Settings. Built-ins aren't
-- in the saved list and stay.
function CC:RemoveConsumableBuff(spellID, say)
    spellID = tonumber(spellID)
    if not spellID then return end
    local key = tostring(spellID)
    if not self.db.consumableBuffs[key] then
        if say then
            print("|cFF54a3ffCooldownCollaborator|r no consumable you added has spell ID " .. spellID
                .. " (the built-in ones can't be removed).")
        end
        return
    end
    local was = self.db.consumableBuffs[key].name
    self.db.consumableBuffs[key] = nil
    if CC.SpellData[spellID] and CC.SpellData[spellID].consumable
        and not (CC.BuiltinConsumables and CC.BuiltinConsumables[spellID]) then
        CC.SpellData[spellID] = nil
    end
    self.consumableActive[spellID] = nil
    if say then
        print("|cFF54a3ffCooldownCollaborator|r stopped tracking consumable: " .. tostring(was))
    end
    self:RefreshAllViews()
    if self.RefreshSpellList then self:RefreshSpellList() end
end

-------------------------------------------------------------------------------
-- Self-detection poll (rising-edge only)
-------------------------------------------------------------------------------

-- Retail and Forever: is this aura on the player? (by ID; secret-safe)
local function HasPlayerAuraID(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    return ok and aura ~= nil
end

-- Era, TBC and MoP: the player's buffs by name and by spell ID (readable there).
local function ScanPlayerBuffs()
    local names, ids = {}, {}
    for i = 1, 40 do
        local name, spellID
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            name, spellID = aura.name, aura.spellId
        -- UnitAura: a fallback only. Every current client has the call above; on Era, TBC and MoP
        -- UnitAura is Blizzard's deprecation copy of it.
        ---@diagnostic disable-next-line: undefined-global
        elseif UnitAura then
            ---@diagnostic disable-next-line: undefined-global
            local n, _, _, _, _, _, _, _, _, id = UnitAura("player", i, "HELPFUL")
            if not n then break end
            name, spellID = n, id
        else
            break
        end
        if name then names[name] = true end
        if spellID then ids[spellID] = true end
    end
    return names, ids
end

function CC:PollConsumables()
    local myName   = CC:FullName("player")
    local changed  = false
    local hasFlask = false
    local hasFood  = false

    local byName = CC.ConsumableMatch == "name"
    local auraNames, auraIDs, foundByName
    if byName then
        auraNames, auraIDs = ScanPlayerBuffs()
        foundByName = {}
        for name in pairs(auraNames) do
            local id = builtinByName[name]
            if id then foundByName[id] = true end
        end
    end

    -- Check built-ins
    for id, data in pairs(CC.BuiltinConsumables or {}) do
        local cat       = data.category
        local present
        if byName then
            present = foundByName[id] == true
        else
            present = HasPlayerAuraID(id)
        end
        local wasActive = self.consumableActive[id]

        if present and not wasActive then
            CC:RecordCooldown("player", id)
        end
        self.consumableActive[id] = present

        if present then
            if cat == "flask" then hasFlask = true end
            if cat == "food"  then hasFood  = true end
        end
        if present ~= wasActive then changed = true end
    end

    -- Check user-registered consumables
    for idStr in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID then
            local present
            if byName then
                present = auraIDs[spellID] == true
            else
                present = HasPlayerAuraID(spellID)
            end
            local wasActive = self.consumableActive[spellID]

            if present and not wasActive then
                CC:RecordCooldown("player", spellID)
            end
            self.consumableActive[spellID] = present

            local cat = CC.SpellData[spellID] and CC.SpellData[spellID].category
            if present then
                if cat == "flask" then hasFlask = true end
                if cat == "food"  then hasFood  = true end
            end
            if present ~= wasActive then changed = true end
        end
    end

    -- Broadcast status to group if anything changed, or do an initial broadcast
    if changed or not self.buffBroadcastDone then
        self.buffBroadcastDone = true
        self:BroadcastBuffStatus(myName, hasFlask, hasFood)
    end

    -- Update own entry in buffRoster for local display
    if myName then
        self.buffRoster[myName] = { flask = hasFlask, food = hasFood }
    end
end

-------------------------------------------------------------------------------
-- Group buff status sync
-------------------------------------------------------------------------------

function CC:BroadcastBuffStatus(playerName, hasFlask, hasFood)
    if not IsInGroup() then return end
    -- Message format: "flask:1:food:1"
    local msg = string.format("flask:%d:food:%d",
        hasFlask and 1 or 0, hasFood and 1 or 0)
    local chatType = self:GroupChannel()
    if not chatType then return end
    C_ChatInfo.SendAddonMessage(BUFF_PREFIX, msg, chatType)
end

-- Called from Comms.lua or directly from the event handler
function CC:OnBuffStatusMessage(sender, msg)
    local flask, food = msg:match("flask:(%d):food:(%d)")
    if not flask then return end
    self.buffRoster[self:NormalizeSender(sender) or sender] = { flask = flask == "1", food = food == "1" }
    if CC.RefreshEssentials then CC:RefreshEssentials() end
end

-- Returns { total=N, flask=N, food=N, missingFlask={names}, missingFood={names} }
-- for the current group.
function CC:GetGroupBuffStatus()
    local total        = 0
    local seen         = {}
    local hasFlask     = 0
    local hasFood      = 0
    local missingFlask = {}
    local missingFood  = {}

    if not IsInGroup() then return nil end

    local function check(unit)
        local name = CC:FullName(unit)
        if not name or not UnitIsConnected(unit) then return end
        -- in a raid the raidN tokens include you, so count each name once
        if seen[name] then return end
        seen[name] = true
        total = total + 1
        local entry = self.buffRoster[name]
        if entry and entry.flask then
            hasFlask = hasFlask + 1
        else
            missingFlask[#missingFlask + 1] = CC:ShortName(name)
        end
        if entry and entry.food then
            hasFood = hasFood + 1
        else
            missingFood[#missingFood + 1] = CC:ShortName(name)
        end
    end

    check("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do check("raid" .. i) end
    else
        for i = 1, GetNumGroupMembers() - 1 do check("party" .. i) end
    end

    return { total=total, flask=hasFlask, food=hasFood,
             missingFlask=missingFlask, missingFood=missingFood }
end

C_Timer.NewTicker(2, function() CC:PollConsumables() end)
