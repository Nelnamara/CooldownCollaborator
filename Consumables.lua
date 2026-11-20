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
-- Group status: flask/food presence goes out on CDCBUFF as "flask:1:food:0",
-- then one ":<key>:<0|1>" per buff count this client has (CC.BuffCategories:
-- world buffs, protection potions, elixirs; docs/MESSAGE_FORMAT_2.md), through
-- the send queue, when it changes, on joining a group and in answer to a state
-- request (Comms.lua). Receivers track CC.buffRoster[playerName] = { flask=bool,
-- food=bool, cats = { [key] = bool } }. On Era, TBC and MoP every group
-- member's buffs are readable, so CC.auraRoster holds what we read on them
-- ourselves (players without the addon count too), and a Soulstone seen on
-- someone is a placed stone (CC.stones). The Essentials bar shows the counts
-- (CC.db.essentialsBuffCounts) and, on a click, who lacks one.
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

local L = CC.L

CC.consumableActive = CC.consumableActive or {}   -- [spellID] = present at the last poll (nil: not polled yet)
CC.buffRoster       = CC.buffRoster or {}        -- [playerName] = { flask=bool, food=bool, cats={[key]=bool} } (CDCBUFF)
CC.auraRoster       = CC.auraRoster or {}        -- [playerName] = { flask, food, cats } read from their auras (Era, TBC, MoP)

-------------------------------------------------------------------------------
-- Buff counts beyond flask and food (P47), per client where the game has them.
-- Every ID checked against SpellName of the builds in cdtl3-dev/tools/
-- spell-list-check/builds.json (19 Nov 2026): the world buffs are in all five
-- builds' data but only Era, TBC and Forever count them; Era names some
-- protection potions with a trailing space, so these match by ID (readable on
-- Era, TBC and MoP; GetPlayerAuraBySpellID for our own on Forever).
-- key: the word on the wire (CDCBUFF), label: the bar's word, name: the full name.
-------------------------------------------------------------------------------

local WORLD_BUFFS = {
    { key = "ds", label = L["Dragonslayer"],        name = L["Rallying Cry of the Dragonslayer"], ids = { 22888, 355363 } },
    { key = "zg", label = L["Zandalar"],            name = L["Spirit of Zandalar"],               ids = { 24425 } },
    { key = "sf", label = L["Songflower"],          name = L["Songflower Serenade"],              ids = { 15366 } },
    { key = "wb", label = L["Warchief's Blessing"], name = L["Warchief's Blessing"],              ids = { 16609 } },
    -- Fengus' Ferocity, Mol'dar's Moxie, Slip'kik's Savvy: any one counts
    { key = "dm", label = L["Dire Maul"],           name = L["Dire Maul buffs"],                  ids = { 22817, 22818, 22820 } },
}
-- Fire, Frost, Holy, Nature, Shadow, Arcane: the Greater potions (1.x), then the plain ones
local PROTECTION_ERA = { 17543, 17544, 17545, 17546, 17548, 17549, 7233, 7239, 7248, 7254, 7242 }
-- the Major ones (TBC)
local PROTECTION_TBC = { 28511, 28512, 28538, 28513, 28537, 28536 }
-- Mongoose, Giants, Greater Arcane, Greater Firepower, Shadow Power, Frost Power,
-- Greater Agility, Superior Defense (its buff is Greater Armor)
local ELIXIRS_ERA = { 17538, 11405, 17539, 26276, 11474, 21920, 11334, 11348 }
-- TBC battle (Major Agility .. Fel Strength) and guardian (Major Defense .. Major Fortitude) elixirs
local ELIXIRS_TBC = { 28497, 28490, 28491, 28501, 28503, 28493, 33721, 33720, 33726, 38954,
    28502, 28509, 39627, 39628, 39626, 39625 }
-- Mantid, Mad Hozen, Weaponry, the Rapids, Peace, Perfection, Mirrors, Monk's
local ELIXIRS_MOP = { 105681, 105682, 105683, 105684, 105685, 105686, 105687, 105688 }

local function Join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do out[#out + 1] = id end
    end
    return out
end

local function BuildCategories(client)
    local cats = {}
    if client == "era" or client == "forever" or client == "tbc" then
        for _, c in ipairs(WORLD_BUFFS) do cats[#cats + 1] = c end
        local tbc = client == "tbc"
        cats[#cats + 1] = { key = "pp", label = L["Protection potion"], name = L["Protection potion"],
            ids = tbc and Join(PROTECTION_ERA, PROTECTION_TBC) or PROTECTION_ERA }
        cats[#cats + 1] = { key = "el", label = L["Elixir"], name = L["Elixir"],
            ids = tbc and Join(ELIXIRS_ERA, ELIXIRS_TBC) or ELIXIRS_ERA }
    elseif client == "mists" then
        cats[#cats + 1] = { key = "el", label = L["Elixir"], name = L["Elixir"], ids = ELIXIRS_MOP }
    end
    return cats
end

-- This client's extra counts, in order, and every count (flask and food first) by key.
CC.BuffCategories = BuildCategories(CC:ClientTag())
CC.BuffCounts = {
    flask = { key = "flask", label = L["Flask"], name = L["Flask"] },
    food  = { key = "food",  label = L["Food"],  name = L["Food"] },
}
local categoryByID = {}   -- spell ID -> category key
for _, c in ipairs(CC.BuffCategories) do
    CC.BuffCounts[c.key] = c
    for _, id in ipairs(c.ids) do categoryByID[id] = c.key end
end

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
                name       = data.name or string.format(L["Consumable %d"], spellID),
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
    name = (name and name ~= "") and name or string.format(L["Consumable %d"], spellID)

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
    print(string.format("|cFF54a3ffCooldownCollaborator|r " .. L["tracking consumable: %s (%ds)%s"],
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
            print("|cFF54a3ffCooldownCollaborator|r " .. string.format(L["no consumable you added has spell ID %d (the built-in ones can't be removed)."], spellID))
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
        print("|cFF54a3ffCooldownCollaborator|r " .. string.format(L["stopped tracking consumable: %s"], tostring(was)))
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

-- Our own extra buff counts: is any of each category's buffs on us?
local function OwnCategories(byName, auraIDs)
    local cats = {}
    for _, c in ipairs(CC.BuffCategories) do
        local present = false
        for _, id in ipairs(c.ids) do
            if byName then
                present = auraIDs[id] ~= nil
            else
                present = PlayerAuraByID(id)
            end
            if present then break end
        end
        cats[c.key] = present
    end
    return cats
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

    -- World buffs, protection potions, elixirs (P47)
    local cats = OwnCategories(byName, auraIDs)
    local lastCats = self.myBuffStatus and self.myBuffStatus.cats
    for key, present in pairs(cats) do
        if not lastCats or lastCats[key] ~= present then changed = true end
    end

    -- Broadcast status to group if anything changed, or the first time we are in a group
    if changed or not self.buffBroadcastDone then
        if self:BroadcastBuffStatus(myName, hasFlask, hasFood, cats) then self.buffBroadcastDone = true end
    end

    -- Update own entry in buffRoster for local display
    if myName then
        self.buffRoster[myName] = { flask = hasFlask, food = hasFood, cats = cats }
    end

    self:ScanGroupAuras()
end

-------------------------------------------------------------------------------
-- Era, TBC and MoP: every group member's buffs are readable, so their flask,
-- food and other counts are read directly (players without the addon count
-- too), and a Soulstone seen on someone is a placed stone. A member out of
-- sight keeps what we last read on them.
-------------------------------------------------------------------------------

local function ReadUnitAura(unit, i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then return nil end
        return aura.name, aura.spellId, aura.expirationTime, aura.duration, aura.sourceUnit
    -- UnitAura: a fallback only, as in ScanPlayerBuffs above.
    ---@diagnostic disable-next-line: undefined-global
    elseif UnitAura then
        ---@diagnostic disable-next-line: undefined-global
        local n, _, _, _, dur, exp, source, _, _, id = UnitAura(unit, i, "HELPFUL")
        if not n then return nil end
        return n, id, exp, dur, source
    end
end

-- A Soulstone on a member: placed when its buff began (its end less its length).
-- Marked as seen on them, so its buff going away ends it (used, dispelled).
local function NoteStoneAura(target, expires, duration, source)
    local now = GetTime()
    local placedAt = now
    if type(expires) == "number" and type(duration) == "number" and expires > 0 and duration > 0 then
        placedAt = math.min(expires - duration, now)
    end
    local from = source and CC:FullName(source)
    if from then
        CC:PlaceStone(from, target, placedAt)
    elseif not CC.stones[target] then
        -- the warlock is out of the group or unreadable: still a stone on them
        CC.stones[target] = { from = "", placedAt = placedAt, duration = CC:StoneDuration() }
    end
    if CC.stones[target] then CC.stones[target].seenOn = true end
end

function CC:ScanUnitAuras(unit)
    local name = self:FullName(unit)
    if not name then return end
    local okVisible, visible = pcall(function() return not UnitIsVisible or UnitIsVisible(unit) and true or false end)
    if okVisible and not visible then return end
    local seen = { flask = false, food = false, cats = {}, at = GetTime() }
    for _, c in ipairs(self.BuffCategories) do seen.cats[c.key] = false end
    local stone
    for i = 1, 40 do
        local auraName, spellID, expires, duration, source = ReadUnitAura(unit, i)
        if not auraName then break end
        local id = builtinByName[auraName]
        local custom = spellID and self.db.consumableBuffs and self.db.consumableBuffs[tostring(spellID)]
        local cat = (id and CC.BuiltinConsumables[id].category) or (custom and custom.category)
        if cat == "flask" then seen.flask = true end
        if cat == "food" then seen.food = true end
        local key = spellID and categoryByID[spellID]
        if key then seen.cats[key] = true end
        if spellID and CC.SpellData[CC.SOULSTONE_ID] and self:BaseSpellID(spellID) == CC.SOULSTONE_ID then
            stone = { expires = expires, duration = duration, source = source }
        end
    end
    self.auraRoster[name] = seen
    if stone then
        NoteStoneAura(name, stone.expires, stone.duration, stone.source)
    elseif self.stones[name] and self.stones[name].seenOn then
        -- the buff we read on them is gone: used, dispelled or run out
        self.stones[name] = nil
    end
end

function CC:ScanGroupAuras()
    if self.retailAPI or not IsInGroup() then
        if next(self.auraRoster) then wipe(self.auraRoster) end
        return
    end
    local function scan(unit)
        local ok, err = pcall(self.ScanUnitAuras, self, unit)
        if not ok and CC.verbose then print("|cFF54a3ffCDC|r aura read: " .. tostring(err)) end -- debug
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do scan("raid" .. i) end
    else
        scan("player")
        for i = 1, GetNumGroupMembers() - 1 do scan("party" .. i) end
    end
    local active = self:GetActiveGroupNames()
    for name in pairs(self.auraRoster) do
        if not active[name] then self.auraRoster[name] = nil end
    end
end

-------------------------------------------------------------------------------
-- Group buff status sync
-------------------------------------------------------------------------------

-- Our status to the group; true once it is queued (false solo, so the first
-- poll in a group sends it). Comms.lua SendBuffStatus sends it again.
function CC:BroadcastBuffStatus(_, hasFlask, hasFood, cats)
    self.myBuffStatus = { flask = hasFlask and true or false, food = hasFood and true or false, cats = cats or {} }
    if not self:GroupChannel() then return false end
    self:SendBuffStatus()
    return true
end

-- The CDCBUFF text: "flask:N:food:N" (what every copy reads), then ":<key>:<0|1>"
-- for each extra count this client has, e.g. "flask:1:food:0:ds:1:zg:0".
function CC:BuffStatusText()
    local s = self.myBuffStatus or {}
    local parts = { string.format("flask:%d:food:%d", s.flask and 1 or 0, s.food and 1 or 0) }
    for _, c in ipairs(self.BuffCategories) do
        parts[#parts + 1] = c.key .. ":" .. ((s.cats and s.cats[c.key]) and 1 or 0)
    end
    return table.concat(parts, ":")
end

-- Called from Comms.lua or directly from the event handler
function CC:OnBuffStatusMessage(sender, msg)
    local flask, food, rest = msg:match("flask:(%d):food:(%d)(.*)")
    if not flask then return end
    local cats = {}
    for key, v in rest:gmatch(":(%l+):(%d)") do
        -- only counts this client has; another client's (or a later copy's) are left out
        if self.BuffCounts[key] and key ~= "flask" and key ~= "food" then cats[key] = v == "1" end
    end
    self.buffRoster[self:NormalizeSender(sender) or sender] = { flask = flask == "1", food = food == "1", cats = cats }
    if CC.RefreshEssentials then CC:RefreshEssentials() end
end

-- Does this member have the count's buff? true / false, or nil when we can't
-- know (Retail and Forever: they don't run the addon, or their copy doesn't
-- send that count). Either source saying yes is a yes: their copy knows its own
-- /cdc consumable entries, our read knows the buffs their copy doesn't send.
local function HasBuff(report, aura, key)
    local function from(entry)
        if not entry then return nil end
        if key == "flask" or key == "food" then return entry[key] and true or false end
        if entry.cats and entry.cats[key] ~= nil then return entry.cats[key] and true or false end
        return nil
    end
    local seen, said = from(aura), from(report)
    if seen or said then return true end
    if seen == false or said == false then return false end
    return nil
end

-- For the current group:
-- { total, flask, food, missingFlask = {short names}, missingFood = {short names},
--   counts = { [key] = { key, label, name, have, missing = {full names}, unknown = {full names} } } }
-- (missingFlask / missingFood also hold the unknown ones, as before).
function CC:GetGroupBuffStatus()
    if not IsInGroup() then return nil end
    local total, seen = 0, {}
    local counts = {}
    for key, c in pairs(self.BuffCounts) do
        counts[key] = { key = key, label = c.label, name = c.name, have = 0, missing = {}, unknown = {} }
    end

    local function check(unit)
        local name = CC:FullName(unit)
        if not name or not UnitIsConnected(unit) then return end
        -- in a raid the raidN tokens include you, so count each name once
        if seen[name] then return end
        seen[name] = true
        total = total + 1
        local report, aura = self.buffRoster[name], self.auraRoster[name]
        for key, count in pairs(counts) do
            local has = HasBuff(report, aura, key)
            if has then
                count.have = count.have + 1
            elseif has == false then
                count.missing[#count.missing + 1] = name
            else
                count.unknown[#count.unknown + 1] = name
            end
        end
    end

    check("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do check("raid" .. i) end
    else
        for i = 1, GetNumGroupMembers() - 1 do check("party" .. i) end
    end

    local function short(count)
        local out = {}
        for _, list in ipairs({ count.missing, count.unknown }) do
            for _, name in ipairs(list) do out[#out + 1] = CC:ShortName(name) end
        end
        return out
    end
    return { total = total, flask = counts.flask.have, food = counts.food.have,
             missingFlask = short(counts.flask), missingFood = short(counts.food), counts = counts }
end

C_Timer.NewTicker(2, function() CC:PollConsumables() end)
