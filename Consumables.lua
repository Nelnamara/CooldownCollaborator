-- Cauldron/Feast tracking — each client detects its own buffs and broadcasts
-- its category status (flask/food) so the raid can see who is buffed.
--
-- Detection: aura.name and .spellId are SECRET even on the local player.
-- The only safe lookup is C_UnitAuras.GetPlayerAuraBySpellID(knownID), so
-- consumables must be registered by ID up front (/cdc consumable).
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

-------------------------------------------------------------------------------
-- Built-in consumable categories — known Midnight IDs
-------------------------------------------------------------------------------

-- Applied on top of CC.BuiltinConsumables (Data.lua) at load time
local BUILTIN_CATEGORIES = {
    [1232585] = "food",   -- Well Fed (Feast of the Midnight Masquerade)
    [462187]  = "food",   -- Hearty Well Fed (Hearty Feast of the Midnight Masquerade)
    [1230876] = "flask",  -- Flask of the Magisters (Mastery)
    [1230877] = "flask",  -- Flask of the Blood Knights (Haste)
    [1230878] = "flask",  -- Flask of the Shattered Sun (Crit)
    [1235057] = "flask",  -- Flask of Thalassian Resistance (Versatility)
}

-------------------------------------------------------------------------------
-- Load / register consumables
-------------------------------------------------------------------------------

function CC:LoadConsumableBuffs()
    -- Apply categories to built-ins first
    for id, cat in pairs(BUILTIN_CATEGORIES) do
        if CC.SpellData[id] then
            CC.SpellData[id].category = cat
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

-- /cdc consumable <spellID> <duration> <name> [flask|food]
-- The last word of the name, if it is "flask" or "food", is treated as the
-- category flag so users can type: /cdc consumable 12345 3600 Haste Flask flask
function CC:AddConsumableBuff(spellID, duration, name)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end

    -- Parse optional trailing category keyword
    local category = nil
    if name then
        local stripped, trailing = name:match("^(.-)%s+(flask)$")
                                or name:match("^(.-)%s+(food)$")
        if stripped and trailing then
            name     = stripped ~= "" and stripped or nil
            category = trailing
        end
    end
    name = name ~= "" and name or ("Consumable " .. spellID)

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
    return true
end

function CC:RemoveConsumableBuff(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    self.db.consumableBuffs[tostring(spellID)] = nil
    if CC.SpellData[spellID] and CC.SpellData[spellID].consumable then
        CC.SpellData[spellID] = nil
    end
    self.consumableActive[spellID] = nil
    self:RefreshAllViews()
end

-------------------------------------------------------------------------------
-- Self-detection poll (rising-edge only)
-------------------------------------------------------------------------------

function CC:PollConsumables()
    local myName   = UnitName("player")
    local changed  = false
    local hasFlask = false
    local hasFood  = false

    -- Check built-ins
    for id, cat in pairs(BUILTIN_CATEGORIES) do
        local present   = C_UnitAuras.GetPlayerAuraBySpellID(id) ~= nil
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
    for idStr, data in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID then
            local present   = C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
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
    local chatType = IsInRaid() and "RAID" or "PARTY"
    C_ChatInfo.SendAddonMessage(BUFF_PREFIX, msg, chatType)
end

-- Called from Comms.lua or directly from the event handler
function CC:OnBuffStatusMessage(sender, msg)
    local flask, food = msg:match("flask:(%d):food:(%d)")
    if not flask then return end
    self.buffRoster[sender] = { flask = flask == "1", food = food == "1" }
    if CC.RefreshEssentials then CC:RefreshEssentials() end
end

-- Returns { total=N, flask=N, food=N, missingFlask={names}, missingFood={names} }
-- for the current group.
function CC:GetGroupBuffStatus()
    local total        = 0
    local hasFlask     = 0
    local hasFood      = 0
    local missingFlask = {}
    local missingFood  = {}

    if not IsInGroup() then return nil end

    local function check(unit)
        local name = UnitName(unit)
        if not name or not UnitIsConnected(unit) then return end
        total = total + 1
        local entry = self.buffRoster[name]
        if entry and entry.flask then
            hasFlask = hasFlask + 1
        else
            missingFlask[#missingFlask + 1] = name
        end
        if entry and entry.food then
            hasFood = hasFood + 1
        else
            missingFood[#missingFood + 1] = name
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
