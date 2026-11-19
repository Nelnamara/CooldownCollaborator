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
-- Group status: flask/food presence goes out on CDCBUFF as "flask:1:food:0"
-- (through the send queue, so a refused send is tried again), when it changes,
-- on joining a group and in answer to a state request (Comms.lua).
-- Receivers track CC.buffRoster[playerName] = { flask=bool, food=bool }.
-- The Essentials Bar displays "Flask N/N | Food N/N" with click-to-expand.
--
-- Timing: a flask or food timer runs from when the buff really began: the
-- aura's own expiration where the client lets us read it (Era, TBC, MoP; on
-- Retail and Forever only if that value isn't hidden), else the timer saved at
-- the last logout or /reload, else when we first saw the buff (R8).
--
-- Category field on consumable entries:
--   "flask"  = counts toward group flask counter
--   "food"   = counts toward group food counter
--   nil/""   = tracked but not counted in either group total

CC.consumableActive = CC.consumableActive or {}   -- [spellID] = present at the last poll (nil: not polled yet)
CC.buffRoster       = CC.buffRoster or {}        -- [playerName] = { flask=bool, food=bool }

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

-- Retail and Forever: is this aura on the player? (by ID; secret-safe) Also its
-- expiration time, as the client gives it (it may be a hidden value).
local function PlayerAuraByID(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or aura == nil then return false end
    return true, aura.expirationTime
end

-- Era, TBC and MoP: the player's buffs by name and by spell ID (readable there),
-- each with its expiration time (0 for a buff that doesn't run out).
local function ScanPlayerBuffs()
    local names, ids = {}, {}
    for i = 1, 40 do
        local name, spellID, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            name, spellID, expires = aura.name, aura.spellId, aura.expirationTime
        -- UnitAura: a fallback only. Every current client has the call above; on Era, TBC and MoP
        -- UnitAura is Blizzard's deprecation copy of it.
        ---@diagnostic disable-next-line: undefined-global
        elseif UnitAura then
            ---@diagnostic disable-next-line: undefined-global
            local n, _, _, _, _, exp, _, _, _, id = UnitAura("player", i, "HELPFUL")
            if not n then break end
            name, spellID, expires = n, id, exp
        else
            break
        end
        if name then names[name] = expires or 0 end
        if spellID then ids[spellID] = expires or 0 end
    end
    return names, ids
end

-- When the buff began, as its timer counts (the end it really has, less our
-- length for it), or nil when the client hides or lacks the expiration.
local function StartFromExpiry(expires, duration)
    local ok, at = pcall(function()
        if expires and expires > 0 then return math.min(expires - duration, GetTime()) end
    end)
    if ok then return at end
    return nil
end

-- Our own flask or food is on: time it from when it really began (R8). A buff
-- already running when we first look this session (a /reload, a relog) keeps
-- the timer saved at the last logout when its expiration can't be read; a
-- flask drunk again before it ran out restarts where its expiration shows it.
function CC:NoteOwnConsumable(id, wasActive, expires)
    local data = CC.SpellData[id]
    if not data then return end
    local me = self:FullName("player")
    local entry = me and self.state[me]
    local cur = entry and entry.spells[id]
    local startAt = StartFromExpiry(expires, data.duration)
    if not wasActive then
        if startAt then
            if not cur or math.abs(cur - startAt) > 2 then self:RecordCooldown("player", id, startAt) end
        elseif wasActive == nil and cur and cur + data.duration > GetTime() then
            return   -- the same buff as before the /reload: its saved timer stands
        else
            self:RecordCooldown("player", id)
        end
    elseif startAt and cur and startAt - cur > 5 then
        self:RecordCooldown("player", id, startAt)
    end
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
        for name, expires in pairs(auraNames) do
            local id = builtinByName[name]
            if id then foundByName[id] = expires end
        end
    end

    -- Check built-ins
    for id, data in pairs(CC.BuiltinConsumables or {}) do
        local cat       = data.category
        local present, expires
        if byName then
            expires = foundByName[id]
            present = expires ~= nil
        else
            present, expires = PlayerAuraByID(id)
        end
        local wasActive = self.consumableActive[id]

        if present then self:NoteOwnConsumable(id, wasActive, expires) end
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
            local present, expires
            if byName then
                expires = auraIDs[spellID]
                present = expires ~= nil
            else
                present, expires = PlayerAuraByID(spellID)
            end
            local wasActive = self.consumableActive[spellID]

            if present then self:NoteOwnConsumable(spellID, wasActive, expires) end
            self.consumableActive[spellID] = present

            local cat = CC.SpellData[spellID] and CC.SpellData[spellID].category
            if present then
                if cat == "flask" then hasFlask = true end
                if cat == "food"  then hasFood  = true end
            end
            if present ~= wasActive then changed = true end
        end
    end

    -- Broadcast status to group if anything changed, or the first time we are in a group
    if changed or not self.buffBroadcastDone then
        if self:BroadcastBuffStatus(myName, hasFlask, hasFood) then self.buffBroadcastDone = true end
    end

    -- Update own entry in buffRoster for local display
    if myName then
        self.buffRoster[myName] = { flask = hasFlask, food = hasFood }
    end
end

-------------------------------------------------------------------------------
-- Group buff status sync
-------------------------------------------------------------------------------

-- Our status ("flask:1:food:1") to the group; true once it is queued (false solo,
-- so the first poll in a group sends it). Comms.lua SendBuffStatus sends it again.
function CC:BroadcastBuffStatus(_, hasFlask, hasFood)
    self.myBuffStatus = { flask = hasFlask and true or false, food = hasFood and true or false }
    if not self:GroupChannel() then return false end
    self:SendBuffStatus()
    return true
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
