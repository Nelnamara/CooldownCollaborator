-- CooldownCollaborator
-- Group and raid cooldown coordinator for World of Warcraft: Retail (Midnight
-- 12.x), MoP Classic, TBC Anniversary, Classic Era and WoW: Forever.
-- Author: Nelnamara

CooldownCollaborator = {}
CC = CooldownCollaborator

CC.version     = "1.1.1"
CC.PREFIX      = "CDCOLLAB"   -- cooldowns (Comms.lua, docs/MESSAGE_FORMAT_2.md)
CC.BUFF_PREFIX = "CDCBUFF"    -- flask and food status

-- The translations load after this file (Locales/), so L looks each phrase up in CC.L when it is used.
local L = setmetatable({}, { __index = function(_, key) return CC.L[key] end })

-------------------------------------------------------------------------------
-- Client detection (the same rules as CooldownTimeline3). WoW: Forever runs
-- the modern engine and API (the old spell globals are gone, values can be
-- secret, no combat log) but reports a vanilla-era interface number (16xxx).
-- So tocversion only picks CONTENT (the TOCs load each client's spell list);
-- retailAPI picks which API calls exist. Never pick an API by tocversion alone.
-------------------------------------------------------------------------------

local _, _, _, tocversion = GetBuildInfo()
CC.tocversion = tocversion
CC.isForever = (tocversion >= 16000 and tocversion < 17000)
    or (WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and tocversion < 110000)
CC.retailAPI = tocversion >= 110000 or CC.isForever
-- Specs (and the inspect pipeline that reads them) are used on Retail only.
CC.isRetail = tocversion >= 110000

-- Frames with a backdrop take the template only where the client has it.
CC.BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Globals that don't exist on every client, resolved per call. WoW: Forever
-- ships no deprecation fallbacks: no IsSpellKnown / IsSpellKnownOrOverridesKnown
-- and no GetSpellInfo globals there.
local function PlayerSpellBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
end

CC.Compat = {
    IsSpellKnown = function(spellID)
        -- Deliberate shim: these globals are deprecated on Retail but are the
        -- only spellbook check on the Classic clients. The second argument
        -- (isPetSpell) defaults to false, so passing it changes nothing.
        ---@diagnostic disable-next-line: deprecated
        if IsSpellKnownOrOverridesKnown or IsSpellKnown then
            ---@diagnostic disable-next-line: deprecated
            return (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID, false))
                ---@diagnostic disable-next-line: deprecated
                or (IsSpellKnown and IsSpellKnown(spellID, false)) or false
        end
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            return C_SpellBook.IsSpellKnown(spellID, PlayerSpellBank()) or false
        end
        return false
    end,
    -- name, icon, spellID of a spell (an ID, or a name where the client takes one)
    GetSpellInfo = function(spell)
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spell)
            if info and info.name then return info.name, info.iconID, info.spellID end
        end
        -- The bare GetSpellInfo exists only on the Classic clients.
        ---@diagnostic disable-next-line: undefined-global
        if GetSpellInfo then
            ---@diagnostic disable-next-line: undefined-global
            local name, _, icon, _, _, _, spellID = GetSpellInfo(spell)
            if name then return name, icon, spellID end
        end
    end,
}

-- state["Name-Realm"] = { class = "WARRIOR", spells = { [spellID] = usedAt (local GetTime()) },
--     restored = { [spellID] = true } (from saved data, until a live message),
--     log = { [spellID] = true } (from the combat log) }
CC.state = {}

CC.inEncounter = false

-- Local player's own tracked spells that were used and have not yet been
-- announced as ready: [spellID] = usedAt (local GetTime()).
CC.localActive = {}

-------------------------------------------------------------------------------
-- Player identity: "Name-Realm" so same-named players from different realms
-- never clash. Display code uses CC:ShortName().
-------------------------------------------------------------------------------

function CC:FullName(unit)
    local name, realm = UnitFullName(unit)
    if not name or name == "" then return nil end
    if not realm or realm == "" then realm = GetNormalizedRealmName() end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function CC:ShortName(full)
    if not full then return full end
    return full:match("^([^-]+)") or full
end

-- A sender name from chat, the combat log or the guild roster, as Name-Realm the way
-- FullName names the same player. WoW: Forever shows a surname there ("Devilin Nyx",
-- "Devilin Nyx-Realm") while UnitName / UnitFullName give only "Devilin" (seen in game,
-- 19 Nov 2026: every message was dropped as "not from a group member"), so only the
-- word before the first space is the name. A group member with that name wins, so an
-- odd realm part can't hide them.
function CC:NormalizeSender(sender)
    if type(sender) ~= "string" or sender == "" then return nil end
    local first = sender:match("^(%S+)") or sender
    local name, realm = first:match("^([^%-]+)%-(.+)$")
    if not name then
        name = first
        realm = sender:match("%-([^%s%-]+)$")
    end
    if (not realm or realm == "") and GetNormalizedRealmName then realm = GetNormalizedRealmName() end
    local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
    if self.GetActiveGroupNames and (IsInGroup() or IsInRaid()) then
        local names = self:GetActiveGroupNames()
        if not names[full] then
            for member in pairs(names) do
                if self:ShortName(member) == name then return member end
            end
        end
    end
    return full
end

-- Turn a bare name (old-format message body) into a group member's full name.
function CC:ResolveBareName(bare)
    local function check(unit)
        if UnitExists(unit) and UnitName(unit) == bare then return self:FullName(unit) end
    end
    local found = check("player")
    if found then return found end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            found = check("raid" .. i)
            if found then return found end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            found = check("party" .. i)
            if found then return found end
        end
    end
    return self:NormalizeSender(bare)
end

-- Window places. The Essentials bar, the main panel and the Lane view start joined, one block edge to
-- edge in that order (Setups.lua, "Joined windows"): blockX / blockY is the block's top-left, in UIParent
-- units from UIParent's top centre (left edge 65% across, top 16% down at UI scale 1). db.blockOrder,
-- the joined windows top down, has no default on purpose: a save without it (1.1.1, the review build)
-- joins only the windows still at the start places below. Those x / y pairs (each window's centre from
-- the screen centre, in its own scale) are where a loose window sits; they keep their old values.
local DEFAULTS = {
    blockX         = 200,
    blockY         = -120,
    x              = 0,
    y              = 200,
    scale          = 1.0,
    locked         = false,
    minDuration    = 60,
    showReady      = true,
    alpha          = 0.9,
    minimapAngle   = 225,
    minimapHide    = false,
    customSpells     = {},    -- [spellID] = { name, duration, icon }
    disabledSpells   = {},    -- [spellID] = true when user unchecks a default spell
    consumableBuffs  = {},    -- [spellID] = { name, duration, icon } -- Cauldron/Feast etc

    essentialsEnabled = true,
    essentialsX       = 220,
    essentialsY        = 200,
    essentialsScale   = 1.0,
    essentialsLocked  = false,

    -- Essentials bar picks (look-essentials lane, 19 Nov 2026)
    essentialsBuffCounts = { "flask", "food" },  -- buff counts the bar shows, in order (keys: CC.BuffCounts in Consumables.lua)
    essentialsBuffAim    = 0,    -- a buff count shows green from this many players (0: the whole group)
    essentialsDefensives = {},   -- spell IDs the Defensives line counts; empty: every spell of kind "external" or "raid"

    laneEnabled = false,
    laneX       = 0,
    laneY       = -200,
    laneScale   = 1.0,
    laneLocked  = false,

    showOnCDTL3 = true,   -- feed group cooldowns to CDTL3's lanes (if CDTL3 is loaded)

    -- look-lanes (19 Nov): the dead list (DeadList.lua), the externals and mana strips
    -- (Strips.lua), the burst line (Burst.lua) and the raid plan's runtime (Plan.lua).
    -- The four windows' x / y below are the start places for a 1365 x 768 screen; Init recomputes them from
    -- the real screen (Setups.lua, CC.START_PLACES).
    deadListEnabled  = true,   -- opens when someone dies in combat, closes when nobody is dead
    deadListX        = -385,
    deadListY        = 184,
    externalsEnabled = false,
    externalsX       = -440,
    externalsY       = 46,
    manaEnabled      = false,
    manaX            = -440,
    manaY            = -40,
    burstEnabled     = false,
    burstX           = 0,
    burstY           = -219,
    burstSpells      = {},     -- [spellID] = true: your counted spells (empty: kind personal or raid, 90 s or more)
    plans            = {},     -- [planName] = { rows = { { timer = text or at = seconds, player, spellID } }, from, at }
    activePlan       = false,  -- the plan whose rows prompt (a plan shared by the leader becomes it)
    planLead         = 5,      -- seconds the prompt bar shows before a planned use
    planBarX         = 0,
    planBarY         = 160,

    -- look-panel lane: the main panel, its alerts and the guild channel
    panelClosed = false,   -- closed by the player: stays shut until /cdc or the minimap opens it (R19)
    panelStyle  = "text",  -- "text" rows, or "icons" (a row of spell icons, P9)
    panelTab    = "all",   -- "all", "guild" or "team:<name>"
    teams       = {},      -- [team name] = { "Name-Realm", ... } (P43)
    rotations   = {},      -- [spellID] = { "Name-Realm", ... }: our own rotation orders (P39)
    alerts      = {},      -- [spellID] = { sound = <SoundKit ID, file or true>, flash = true, midscreen = false, warn = 0 } (P1)
    setupFrom   = "officers", -- officer setups taken from: "officers" (guild master and officers), "any", "nobody"
    guildSync   = false,   -- also share over the guild channel; the panel gets a Guild tab (P41)

    -- settings lane (19 Nov): the new windows' own locks, presets, when the windows show, lighter mode
    deadListLocked   = false,
    externalsLocked  = false,
    manaLocked       = false,
    burstLocked      = false,
    showPreset       = "everything",  -- "everything", "simple", "healer", "tank" or "dps" (P2): which spells show, by kind
    spellGroupBy     = "class",       -- Default Spells tab: "class" or "kind"
    showWindows      = "always",      -- "always", "combat" or "boss": when the three main windows show (P30)
    lighterMode      = false,         -- slower refresh for the panel, Essentials bar and Lane view (P31)
    profiles         = {},            -- [name] = a profile's settings (Setups.lua); "Default" always exists
    charProfile      = {},            -- [Name-Realm] = the profile that character follows (none: Default)
    charPlaces       = {},            -- [Name-Realm] = window places that character keeps over its profile's
    layouts          = {},            -- ["party" or "raid"] = window places for that group type (P21)
    setupNever       = {},            -- [Name-Realm] = true: no officer setups from them
    lastPullOffer    = false,         -- say after a boss that the pull's log is there (P33)
    postSpells       = {},            -- [spellID] = true: what /cdc post lists (none: rez and lust)
    resetOnNewRun    = true,          -- a key start drops players who left and asks the group for its state again (P45)
    rezSkip          = {},            -- [name] = "last" or "never": players the rez call and dead list pass over (P40)
}
CC.DEFAULTS = DEFAULTS

function CC:Init()
    self:ComputeStartPlaces()   -- the dead list, externals, mana and burst windows start by this screen's size
    if not CooldownCollaboratorDB then
        CooldownCollaboratorDB = CopyTable(DEFAULTS)
    end
    self.db = CooldownCollaboratorDB
    for k, v in pairs(DEFAULTS) do
        if self.db[k] == nil then self.db[k] = v end
    end
    self:MoveOldPlaces()
    -- a saved guildSync that isn't exactly true (a stray 0, 1 or "false") is off, as its checkbox shows it
    if self.db.guildSync ~= true then self.db.guildSync = false end

    -- Rank map and name index from this client's own list (Data_<client>.lua)
    self:BuildSpellIndex()

    -- Merge built-in consumables, then user's custom/registered ones
    for id, data in pairs(CC.BuiltinConsumables or {}) do
        CC.SpellData[id] = data
    end
    self:LoadCustomSpells()
    self:LoadConsumableBuffs()
    -- the character's profile waits for PLAYER_LOGIN: the realm isn't readable before it

    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(self.BUFF_PREFIX)
    self:RegisterGroupEvents()
    self:BuildOptionsPanel()
    self:BuildMinimapButton()
    self:BuildUI()
    self:BuildEssentialsBar()
    self:BuildLaneView()
    self.wasInGroup = IsInGroup()
    self:ScanRoster()
end

-- A custom entry for a built-in's ID overrides the cooldown length only: the built-in keeps its
-- class, name, icon and listing, and its untouched row is kept here so Remove can restore it.
CC.builtinOriginal = CC.builtinOriginal or {}

local function ApplyCustomSpell(spellID, name, duration, icon)
    local cur = CC.SpellData[spellID]
    local orig = CC.builtinOriginal[spellID]
    if not orig and cur and not cur.custom then
        orig = cur
        CC.builtinOriginal[spellID] = cur
    end
    if orig then
        local row = {}
        for k, v in pairs(orig) do row[k] = v end
        row.duration = duration
        CC.SpellData[spellID] = row
    else
        CC.SpellData[spellID] = {
            name     = name,
            duration = duration,
            icon     = icon or 134400,
            class    = "UNKNOWN",
            custom   = true,
        }
    end
end

function CC:LoadCustomSpells()
    for idStr, data in pairs(self.db.customSpells) do
        local spellID = tonumber(idStr)
        if spellID and data.duration and data.duration > 0 then
            ApplyCustomSpell(spellID, data.name or string.format(L["Spell %d"], spellID), data.duration, data.icon)
        end
    end
end

function CC:AddCustomSpell(spellID, duration)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end

    local name, icon = CC.Compat.GetSpellInfo(spellID)

    if not name then
        print("|cFF54a3ffCooldownCollaborator|r " .. string.format(L["Unknown spell ID: %d"], spellID))
        return false
    end

    self.db.customSpells[tostring(spellID)] = {
        name     = name,
        duration = duration,
        icon     = icon or 134400,
    }
    ApplyCustomSpell(spellID, name, duration, icon)
    print(string.format("|cFF54a3ffCooldownCollaborator|r " .. L["Added: %s (%ds)"], name, duration))
    return true
end

function CC:RemoveCustomSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    self.db.customSpells[tostring(spellID)] = nil
    if CC.builtinOriginal[spellID] then
        CC.SpellData[spellID] = CC.builtinOriginal[spellID]
        CC.builtinOriginal[spellID] = nil
    elseif CC.SpellData[spellID] and CC.SpellData[spellID].custom then
        CC.SpellData[spellID] = nil
    end
    self:RefreshRows()
    self:RefreshSpellList()
end

-- Our own cast (or our own flask or food), at usedAt (default now). Always
-- recorded and sent: unticking a spell or a higher minimum length only filters
-- what this client shows (UI.lua, Bridge.lua), never what the group hears (R5).
function CC:RecordCooldown(unitToken, spellID, usedAt)
    -- Every rank records under (and is sent as) its base ID.
    local castID = spellID
    spellID = self:BaseSpellID(spellID)
    local data = CC.SpellData[spellID]
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r cast seen: unit=%s spellID=%s known=%s", -- debug
            tostring(unitToken), tostring(castID), tostring(data ~= nil)))
    end
    if not data then return end

    local name = self:FullName(unitToken)
    if not name then return end

    local entry = self.state[name]
    if not entry then
        local _, classTag = UnitClass(unitToken)
        entry = { class = classTag or "UNKNOWN", spells = {} }
        self.state[name] = entry
    end
    local now = usedAt or GetTime()
    entry.spells[spellID] = now
    if entry.restored then entry.restored[spellID] = nil end

    -- Watch our own spell so we can announce "ready now" (talents shorten
    -- the real cooldown below the base length everyone else assumes). Not
    -- for a spell whose cooldown sits on an item: its own cooldown reads 0.
    if unitToken == "player" and not data.consumable and not data.itemCooldown then
        self.localActive[spellID] = now
        self.heldReady[spellID] = nil
    end

    self:SendCooldownSync(spellID, name, now)
    self:BridgeStart(name, spellID, now, entry.class)
    self:RefreshAllViews()
end

-- A remote player's spell is ready now (their "ready now" announcement).
function CC:RecordReadyFromComm(playerName, spellID)
    spellID = self:BaseSpellID(spellID)
    local data = CC.SpellData[spellID]
    local entry = self.state[playerName]
    if not data or not entry or not entry.spells[spellID] then return end
    entry.spells[spellID] = GetTime() - data.duration
    if entry.restored then entry.restored[spellID] = nil end
    if entry.log then entry.log[spellID] = nil end
    self:BridgeStop(playerName, spellID)
    self:RefreshAllViews()
end

-- Another player's cast, from their addon message or (Era, TBC, MoP) from the
-- combat log. On those clients the same cast can arrive both ways: a second
-- report within DUPLICATE_WINDOW seconds of the recorded one is that same cast
-- and changes nothing.
local DUPLICATE_WINDOW = 5

-- One timer of another player; true when it changed. how: nil = their cast
-- message (a later cast wins), "log" = the combat log (the same rule), "state" =
-- their S list (their own word: it replaces), "restored" = our saved data (only
-- where nothing live is held). A restored time never beats a live report.
function CC:SetRemoteCooldown(playerName, spellID, usedAt, classTag, how)
    local data = CC.SpellData[spellID]
    if not data or not playerName then return false end

    local entry = self.state[playerName]
    if not entry then
        entry = { class = classTag or "UNKNOWN", spells = {} }
        self.state[playerName] = entry
    elseif classTag and classTag ~= "UNKNOWN" and entry.class == "UNKNOWN" then
        entry.class = classTag
    end
    local cur = entry.spells[spellID]
    local wasRestored = entry.restored and entry.restored[spellID]
    if how == "restored" then
        if cur then return false end
    elseif how == "state" or wasRestored then
        -- the owner's word, or any live report over a saved time (a saved one can be a
        -- second out): only a real difference restarts it
        if cur and math.abs(usedAt - cur) < (wasRestored and 0.25 or 2) then
            if wasRestored then entry.restored[spellID] = nil end
            return false
        end
    else
        if cur and math.abs(usedAt - cur) < DUPLICATE_WINDOW then return false end
        if cur and usedAt <= cur then return false end
    end
    entry.spells[spellID] = usedAt
    if how == "restored" then
        entry.restored = entry.restored or {}
        entry.restored[spellID] = true
    elseif entry.restored then
        entry.restored[spellID] = nil
    end
    if how == "log" then
        entry.log = entry.log or {}
        entry.log[spellID] = true
    elseif entry.log then
        entry.log[spellID] = nil
    end
    self:BridgeStart(playerName, spellID, usedAt, entry.class)
    return true
end

function CC:RecordCooldownFromComm(playerName, spellID, usedAt, classTag, how)
    spellID = self:BaseSpellID(spellID)
    if self:SetRemoteCooldown(playerName, spellID, usedAt, classTag, how) then
        self:RefreshAllViews()
    end
end

-------------------------------------------------------------------------------
-- Soulstones placed on living group members: CC.stones[target] = { from,
-- placedAt (local GetTime()), duration (the buff's length) }. Retail hides other
-- players' buffs in combat and Forever has no combat log, so there the
-- warlock's own client says who it stoned (T, Comms.lua); Era, TBC and MoP see
-- it in the combat log (Events.lua). One stone per warlock: a new one replaces
-- their last. A Soulstone cast on the dead is a rez, not a placement.
-------------------------------------------------------------------------------

CC.SOULSTONE_ID = 20707
CC.stones = CC.stones or {}

-- The buff's length in the game data: SpellMisc DurationIndex 347 (900 s) on
-- 12.1.5 and 5.5.4, 30 (1800 s) on Era, TBC and Forever. A `buff` on the data row wins.
function CC:StoneDuration()
    local data = CC.SpellData[CC.SOULSTONE_ID]
    if data and data.buff then return data.buff end
    return (self.tocversion or 0) >= 50000 and 900 or 1800
end

-- Record a stone; true when it is new or moved.
function CC:PlaceStone(from, target, placedAt)
    if not from or not target then return false end
    for name, stone in pairs(self.stones) do
        if stone.from == from and name ~= target then self.stones[name] = nil end
    end
    local cur = self.stones[target]
    if cur and cur.from == from and math.abs(cur.placedAt - placedAt) < 2 then return false end
    self.stones[target] = { from = from, placedAt = placedAt, duration = self:StoneDuration() }
    return true
end

-- The stone still on a player, or nil (a run-out one is forgotten).
function CC:GetStone(target)
    local stone = self.stones[target]
    if stone and stone.placedAt + stone.duration <= GetTime() then
        self.stones[target] = nil
        return nil
    end
    return stone
end

local function IsStone(spellID)
    local ok, yes = pcall(function() return CC:BaseSpellID(spellID) == CC.SOULSTONE_ID end)
    return ok and yes == true and CC.SpellData[CC.SOULSTONE_ID] ~= nil
end

-- Who our Soulstone is going on, as the cast starts: the name the cast carries
-- (UNIT_SPELLCAST_SENT), else our target when it is a friendly player, else
-- ourselves (with no friendly target it goes on us). nil: someone outside the
-- group, or nothing readable. Every read in a pcall: on Retail a name can be hidden.
local function StoneTargetAtCast(sentTarget)
    local ok, named = pcall(CC.MemberByName, CC, sentTarget)
    if ok and named then return named end
    local okEmpty, empty = pcall(function() return sentTarget == nil or sentTarget == "" end)
    if ok and okEmpty and not empty then return nil end
    local okT, who = pcall(function()
        if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") then
            return CC:MemberByName(CC:FullName("target")) or false
        end
        return CC:FullName("player")
    end)
    if okT and who then return who end
    return nil
end

local stoneCasts = {}  -- castGUID -> the target our Soulstone cast started on (false: none to record)

function CC:OnSpellcastSent(unit, target, castGUID, spellID)
    if unit ~= "player" or not IsStone(spellID) then return end
    local who = StoneTargetAtCast(target) or false
    pcall(function() stoneCasts[castGUID] = who end)
end

-- Our Soulstone landed: on a living group member it is a placement, which the
-- group hears from us on Retail and Forever.
function CC:OnStoneCastDone(castGUID, spellID)
    if not IsStone(spellID) then return end
    local target
    pcall(function()
        target = stoneCasts[castGUID]
        stoneCasts[castGUID] = nil
    end)
    if not target then return end
    local unit = self:UnitTokenFor(target)
    if not unit then return end
    local okDead, dead = pcall(function() return UnitIsDeadOrGhost(unit) and true or false end)
    if not okDead or dead then return end
    if self:PlaceStone(self:FullName("player"), target, GetTime()) then self:SendStone(target) end
end

-------------------------------------------------------------------------------
-- Timers kept across a /reload or relog (R4, P16): saved at logout as real
-- clock times (time(): GetTime() restarts with the game), restored at login
-- when still running. Ours at once; a groupmate's once they are in our group
-- (the group may not be readable yet at login), for a minute after login. The
-- game writes saved data only at logout or /reload, so after a crash what the
-- group answers to our state request fills them in.
-- db.timers = { wall = time(), clock = GetTime(), players = { [name] = { class, spells = { [id] = wall time used } } } }
-- time() counts whole seconds; after a /reload GetTime() has gone on, so the
-- saved clock pair restores to the exact time.
-------------------------------------------------------------------------------

local RESTORE_WINDOW = 60

function CC:SaveTimers()
    if not self.db then return end
    local now, wall = GetTime(), time()
    local saved = {}
    for name, entry in pairs(self.state) do
        local spells
        for id, usedAt in pairs(entry.spells) do
            local data = CC.SpellData[id]
            if data and usedAt + data.duration > now then
                spells = spells or {}
                spells[id] = wall - (now - usedAt)
            end
        end
        if spells then saved[name] = { class = entry.class, spells = spells } end
    end
    local stones = {}
    for target, stone in pairs(self.stones) do
        if stone.placedAt + stone.duration > now then
            stones[target] = { from = stone.from, at = wall - (now - stone.placedAt), duration = stone.duration }
        end
    end
    self.db.timers = { wall = wall, clock = now, players = saved, stones = stones }
end

function CC:RestoreTimers()
    local saved = self.db and self.db.timers
    if type(saved) ~= "table" or type(saved.players) ~= "table" then return end
    local me = self:FullName("player")
    local now, wall = GetTime(), time()
    -- the same game clock as at the save (a /reload): GetTime() has moved on as far as time()
    local wall0, clock0 = saved.wall, saved.clock
    local sameClock = type(wall0) == "number" and type(clock0) == "number" and now >= clock0
        and math.abs((now - clock0) - (wall - wall0)) < 2
    local pending, ownChanged = {}, false
    for name, e in pairs(saved.players) do
        if type(name) == "string" and type(e) == "table" and type(e.spells) == "table" then
            for key, at in pairs(e.spells) do
                local id = tonumber(key)
                local data = id and CC.SpellData[id]
                local ago = type(at) == "number" and wall - at
                if id and data and ago and ago >= 0 and ago < data.duration then
                    local usedAt = now - ago
                    if sameClock then usedAt = clock0 - (wall0 - at) end
                    if me and name == me then
                        local entry = self.state[me]
                        if not entry then
                            local _, classTag = UnitClass("player")
                            entry = { class = classTag or e.class or "UNKNOWN", spells = {} }
                            self.state[me] = entry
                        end
                        if not entry.spells[id] then
                            entry.spells[id] = usedAt
                            entry.restored = entry.restored or {}
                            entry.restored[id] = true
                            if not data.consumable and not data.itemCooldown then self.localActive[id] = usedAt end
                            ownChanged = true
                        end
                    else
                        pending[name] = pending[name] or { class = e.class, spells = {} }
                        pending[name].spells[id] = usedAt
                    end
                end
            end
        end
    end
    for target, stone in pairs(type(saved.stones) == "table" and saved.stones or {}) do
        local at, duration = stone.at, stone.duration
        if type(target) == "string" and type(stone.from) == "string" and type(at) == "number"
            and type(duration) == "number" and wall - at >= 0 and wall - at < duration then
            local placedAt = sameClock and (clock0 - (wall0 - at)) or (now - (wall - at))
            self.stones[target] = self.stones[target] or { from = stone.from, placedAt = placedAt, duration = duration }
        end
    end
    self.restorePending = next(pending) and pending or nil
    self.restoreUntil = now + RESTORE_WINDOW
    self:MergeRestored()
    if ownChanged then
        self:BridgeResync()
        self:RefreshAllViews()
    end
end

-- Restored timers of players who are in our group now.
function CC:MergeRestored()
    local pending = self.restorePending
    if not pending then return end
    if GetTime() > (self.restoreUntil or 0) then
        self.restorePending = nil
        return
    end
    local active = self:GetActiveGroupNames()
    local changed = false
    for name, e in pairs(pending) do
        if active[name] then
            for id, usedAt in pairs(e.spells) do
                if self:SetRemoteCooldown(name, id, usedAt, e.class, "restored") then changed = true end
            end
            pending[name] = nil
        end
    end
    if not next(pending) then self.restorePending = nil end
    if changed then self:RefreshAllViews() end
end

-- Every client has C_ChatInfo.SendChatMessage; the bare SendChatMessage now lives only in
-- Blizzard's deprecation fallbacks (on unless a player turns them off).
local function SendChat(msg, chatType)
    -- Deliberate fallback to the old global.
    ---@diagnostic disable-next-line: deprecated
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then send(msg, chatType) end
end

-- Announce who should rez a dead player, naming the specific provider whose
-- Battle Rez is ready right now rather than a generic "someone rez" callout.
-- In a raid the leader or an assist may ask; in a 5-player group anyone may (P3).
-- (IsRaidLeader / IsRaidOfficer are gone on every client; these two are on all five.)
function CC:CanRequestRez()
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    return IsInGroup()
end

-- The target's full name, or nil when it can't be read: on Retail and Forever a hidden name must
-- not raise an error, so the read and its comparisons run in a pcall.
local function TargetName()
    local ok, name = pcall(CC.FullName, CC, "target")
    if ok then return name end
    return nil
end

-- In raids and Mythic+ every combat rez (Soulstone too on Retail and MoP) uses one
-- charge pool: with none left nobody can be brought back. The line saying so, or
-- nil while a charge is there (or no pool is known).
function CC:NoRezChargesText()
    local charges, _, nextAt = self:RezPool()
    if charges ~= 0 then return nil end
    local wait = nextAt and math.max(0, nextAt - GetTime())
    if not wait then return L["No Battle Rez charges."] end
    return string.format(L["No Battle Rez charges; next in %d:%02d"], math.floor(wait / 60), math.floor(wait % 60))
end

-- The rezzer who would answer a call for targetName: the first ready one who is
-- not the target, and not dead, a ghost or disconnected (R6). nil: nobody.
function CC:BestRezzer(targetName)
    -- rezzers marked "never" are passed over; "last" ones only when nobody else is ready (P40)
    -- a rezzer confirmed ready beats one only guessed ready (no hello, never seen casting)
    local skip = self.db and self.db.rezSkip or {}
    local lastChoice, guessedChoice, guessedLast
    for _, entry in ipairs(self:GetCapabilityStatus("BATTLEREZ")) do
        if entry.ready and entry.name ~= targetName and entry.online ~= false and entry.alive ~= false then
            local mode = skip[entry.name] or skip[self:ShortName(entry.name)]
            local guessed = self.retailAPI and entry.guessed
            if mode == "last" then
                if guessed then guessedLast = guessedLast or entry else lastChoice = lastChoice or entry end
            elseif mode ~= "never" then
                if not guessed then return entry end
                guessedChoice = guessedChoice or entry
            end
        end
    end
    return guessedChoice or lastChoice or guessedLast
end

function CC:RequestRez()
    if not self:CanRequestRez() then
        print("|cFF54a3ffCDC|r " .. L["Only the raid leader or an assist can request a rez in a raid."])
        return
    end
    -- Nobody targeted: the top of the dead list (DeadList.lua), if anyone is dead.
    local top = not UnitExists("target") and self.DeadList and self:DeadList()[1]
    if top then
        self:CallRez(top.name)
        return
    end
    -- Only a dead, friendly player may be named; a friendly player outside the group is fine
    -- (a Battle Rez works on them). A dead monster or enemy is refused.
    if not UnitExists("target") or not UnitIsPlayer("target")
        or not UnitIsFriend("player", "target") or not UnitIsDeadOrGhost("target") then
        print("|cFF54a3ffCDC|r " .. L["Target a dead friendly player first."])
        return
    end

    local targetName = TargetName()
    if not targetName then
        print("|cFF54a3ffCDC|r " .. L["Can't read that target's name. Target a dead friendly player first."])
        return
    end
    self:CallRez(targetName)
end

-- Name the rezzer for a dead player (the target, or a dead list row) on the
-- channel that reaches the whole group.
function CC:CallRez(targetName)
    if not self:CanRequestRez() then
        print("|cFF54a3ffCDC|r " .. L["Only the raid leader or an assist can request a rez in a raid."])
        return
    end
    local noCharges = self:NoRezChargesText()
    if noCharges then
        print("|cFF54a3ffCDC|r " .. noCharges)
        return
    end
    local provider = self:BestRezzer(targetName)
    if not provider then
        print("|cFF54a3ffCDC|r " .. L["No living Battle Rez provider available right now."])
        return
    end

    local data = CC.SpellData[provider.spellID]
    local spellName = data and data.name or L["Battle Rez"]
    local msg = string.format(L["%s, please %s %s!"], self:ShortName(provider.name), spellName, self:ShortName(targetName))

    -- The channel that reaches the whole group (instance chat in Dungeon Finder, Raid Finder and
    -- battlegrounds, where /party and /raid are the home group's). A raid warning only goes out
    -- in a normal raid, where the game lets a leader or assistant post one.
    local channel = self:GroupChannel()
    if not channel then return end
    SendChat(msg, channel)
    if channel == "RAID" and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        SendChat(msg, "RAID_WARNING")
    end
end

-- Refresh one window by its method name. An error in it goes to the game's
-- error handler but never stops the caller, so the other windows (and the
-- roster scan) still update.
function CC:RefreshView(method)
    local refresh = self[method]
    if not refresh then return end
    xpcall(function() refresh(self) end, geterrorhandler())
end

-- When the three main windows (panel, Essentials bar, Lane view) show: always, only in combat, or
-- only on a boss fight (db.showWindows, P30). Each window's show logic asks this one helper.
function CC:WindowsWanted()
    local mode = self.db and self.db.showWindows
    if mode == "combat" then
        return (self.inCombat or (UnitAffectingCombat and UnitAffectingCombat("player")) or false) and true or false
    elseif mode == "boss" then
        return self.inEncounter and true or false
    end
    return true
end

-- Lighter mode (P31): the refresh tickers run at the slower rate. Rates are seconds between
-- refreshes: { normal, lighter }.
CC.TICK_RATES = { panel = { 0.5, 1 }, lanes = { 0.2, 0.5 } }
local lastTick = {}
function CC:TickRate(key)
    local r = CC.TICK_RATES[key == "essentials" and "panel" or key]
    return r and (self.db and self.db.lighterMode and r[2] or r[1]) or 0
end

-- Called by a ticker running at the normal rate: true when a refresh is due at the current rate.
function CC:TickDue(key)
    local now = GetTime()
    if now - (lastTick[key] or -1000) >= self:TickRate(key) - 0.001 then
        lastTick[key] = now
        return true
    end
    return false
end

function CC:RefreshAllViews()
    self:RefreshView("RefreshRows")
    self:RefreshView("RefreshEssentials")
    self:RefreshView("RefreshLanes")
end

-- Leaving the group closes the windows that opened for it: the main panel, the
-- Essentials bar and the Lane view. Only on that change, so /cdc still shows the
-- panel while solo; joining a group again opens them as before.
function CC:CloseWindowsIfLeftGroup()
    local inGroup = IsInGroup()
    if self.wasInGroup and not inGroup then
        if self.frame then self.frame:Hide() end
        if self.essentialsFrame then self.essentialsFrame:Hide() end
        if self.laneFrame then self.laneFrame:Hide() end
    end
    self.wasInGroup = inGroup
end

function CC:GetRemaining(playerName, spellID)
    local entry = self.state[playerName]
    if not entry then return nil end
    local usedAt = entry.spells[spellID]
    if not usedAt then return nil end
    local data = CC.SpellData[spellID]
    if not data then return nil end
    local rem = (usedAt + data.duration) - GetTime()
    -- a spell marked ready (usedAt = now - duration) can come back a hair above
    -- 0 in floating point; under a millisecond is ready
    return rem > 0.001 and rem or 0
end

-- Live readiness for the LOCAL player's own spell, in seconds (0 = ready), or nil
-- if we can't read it (spell unknown, or a value is still secret in this context).
--
-- Midnight 12.0.7 un-secreted combat-res (and other whitelisted) cooldowns AND
-- charge counts, so for our own capability spells we can show true readiness
-- immediately — even right after /reload or before we've observed a cast — and
-- respect the raid-wide Battle Rez charge pool. Remote players are still learned
-- only via the CDCOLLAB sync (their values remain secret to us).
--
-- pcall-guarded: a bare read of a secret value doesn't error, but comparing/using
-- one does. If any field is still secret here the compare throws, ok is false, and
-- we return nil so the caller falls back to the observed-cast model (GetRemaining).
--
-- Retail and Forever read C_Spell (tables with isActive). Era, TBC and MoP read
-- the legacy GetSpellCooldown / GetSpellCharges: their tables have no isActive,
-- so the C_Spell path would call every spell ready.

-- The highest rank of a tracked spell the player knows (any rank counts as
-- knowing it), or nil. A spell without ranks is just itself.
function CC:KnownRank(spellID)
    local data = CC.SpellData[spellID]
    local ids = data and data.ranks or { spellID }
    for i = #ids, 1, -1 do
        local ok, known = pcall(CC.Compat.IsSpellKnown, ids[i])
        if ok and known then return ids[i] end
    end
    return nil
end

-- The player's charges of a spell: current, max, recharge start, recharge
-- length; nothing for a spell without charges. Call inside a pcall.
local function ReadCharges(id)
    if CC.retailAPI then
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
        if ch then
            return ch.currentCharges, ch.maxCharges, ch.cooldownStartTime, ch.cooldownDuration
        end
    -- GetSpellCharges: the Classic clients' global; Retail and Forever use C_Spell above.
    ---@diagnostic disable-next-line: undefined-global
    elseif GetSpellCharges then
        ---@diagnostic disable-next-line: undefined-global
        return GetSpellCharges(id)
    end
end

function CC:GetLocalReadiness(spellID)
    local id = self:KnownRank(spellID)
    if not id then return nil end

    local remaining
    local ok = pcall(function()
        -- Charge-based (raid Battle Rez pool): ready while >=1 charge is banked,
        -- otherwise count down to the next charge.
        local current, maxCharges, chStart, chDuration = ReadCharges(id)
        if maxCharges and maxCharges > 1 then
            if (current or 0) >= 1 then
                remaining = 0
            else
                local rem = (chStart or 0) + (chDuration or 0) - GetTime()
                remaining = rem > 0 and rem or 0
            end
            return
        end
        -- Plain cooldown. duration <= 1.5 is just the GCD → treat as ready.
        if CC.retailAPI then
            local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
            if cd and cd.isEnabled ~= false and cd.isActive and cd.duration and cd.duration > 1.5 then
                local rem = (cd.startTime + cd.duration) - GetTime()
                remaining = rem > 0 and rem or 0
            else
                remaining = 0  -- known and not on a real cooldown → ready
            end
        else
            local start, duration, enabled = GetSpellCooldown(id)
            -- enabled 0: the cooldown starts when the spell's effect ends; unknown yet
            if enabled == 0 then return end
            if start and start > 0 and duration and duration > 1.5 then
                local rem = (start + duration) - GetTime()
                remaining = rem > 0 and rem or 0
            else
                remaining = 0
            end
        end
    end)
    if not ok then return nil end
    return remaining
end

-- Is our own spell off cooldown right now? Returns true / false, or nil when
-- it can't be read. cd.isActive is never secret; reads are pcall-guarded.
local function LocalSpellIsReady(spellID)
    -- A ranked spell reads the rank the player knows; none known: can't tell.
    local data = CC.SpellData[spellID]
    local id = spellID
    if data and data.ranks then
        id = CC:KnownRank(spellID)
        if not id then return nil end
    end
    local ready
    local ok = pcall(function()
        local current, maxCharges = ReadCharges(id)
        if maxCharges and maxCharges > 1 then
            ready = (current or 0) >= 1
            return
        end
        if CC.retailAPI then
            local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
            if not cd then return end
            ready = not cd.isActive
        else
            local start, duration, enabled = GetSpellCooldown(id)
            if enabled == 0 then
                ready = false  -- waiting for its effect to end
                return
            end
            ready = not (start and start > 0 and duration and duration > 1.5)
        end
    end)
    if not ok then return nil end
    return ready
end

-- Cheap poll: only the spells we've used and not yet announced. Skipped
-- entirely (one next() call) when nothing is outstanding.
function CC:PollLocalReady()
    if not next(self.localActive) then return end
    local now = GetTime()
    for spellID, usedAt in pairs(self.localActive) do
        -- Grace so the cooldown has actually started before we judge it.
        if now - usedAt > 3 and LocalSpellIsReady(spellID) == true then
            self.localActive[spellID] = nil
            local me = self:FullName("player")
            local data = CC.SpellData[spellID]
            local entry = me and self.state[me]
            if entry and data and entry.spells[spellID] then
                entry.spells[spellID] = now - data.duration
            end
            if me then self:BridgeStop(me, spellID) end
            self:SendReadySync(spellID)
            self:RefreshAllViews()
        end
    end
end

-- P11: whoever can read the raid's battle rez charge pool (the charges of their
-- own Battle Rez spell) shares it as C; everyone keeps CC.rezCharges =
-- { charges, max, nextAt, from }. Our own reading is CC.rezChargesRead.
-- Returns the pool or nil, and whether our spell could be read at all.
local function ReadRezPool()
    local cap = CC.CAPABILITIES and CC.CAPABILITIES.BATTLEREZ
    local _, classTag = UnitClass("player")
    local ids = {}
    for _, id in ipairs(cap and classTag and cap.classes[classTag] or {}) do ids[#ids + 1] = id end
    -- Retail and MoP: a warlock's Soulstone draws on the same pool
    if classTag == "WARLOCK" and (CC.tocversion or 0) >= 50000 and CC.SpellData[CC.SOULSTONE_ID] then
        ids[#ids + 1] = CC.SOULSTONE_ID
    end
    for _, spellID in ipairs(ids) do
        local id = CC:KnownRank(spellID)
        if id then
            local pool
            local ok = pcall(function()
                local current, maxCharges, start, duration = ReadCharges(id)
                if current and maxCharges and maxCharges > 1 then
                    local nextAt
                    if current < maxCharges and start and duration and start > 0 and duration > 0 then
                        nextAt = start + duration
                    end
                    pool = { charges = current, max = maxCharges, nextAt = nextAt }
                end
            end)
            return pool, ok
        end
    end
    return nil, false
end

-- The pool as last read or heard, counted on to now: a recharge that has come
-- due adds its charge (the one after it is then unknown). Returns charges, max,
-- nextAt (nil: unknown), or nothing when no pool is known.
CC.REZ_POOL_KEEP = 600

function CC:RezPool()
    local pool = self.rezCharges
    if not pool then return nil end
    -- a pool heard from someone else lapses after 10 minutes without a refresh
    if pool.from ~= self:FullName("player") and GetTime() - (pool.heardAt or 0) > CC.REZ_POOL_KEEP then
        self.rezCharges = nil
        return nil
    end
    local charges, nextAt = pool.charges, pool.nextAt
    if nextAt and GetTime() >= nextAt and charges < pool.max then
        charges, nextAt = charges + 1, nil
    end
    return charges, pool.max, nextAt
end

function CC:PollRezCharges()
    if not IsInGroup() then
        self.rezChargesRead = nil
        return
    end
    local pool, readable = ReadRezPool()
    if not readable then return end
    local last = self.rezChargesRead
    local me = self:FullName("player")
    if not pool then
        if last then
            -- the pool is gone (the fight or the key is over)
            self.rezChargesRead = nil
            if self.rezCharges and self.rezCharges.from == me then self.rezCharges = nil end
            self:SendRezCharges(math.random() * 1.5)
        end
        return
    end
    if last and last.charges == pool.charges and last.max == pool.max
        and math.abs((last.nextAt or 0) - (pool.nextAt or 0)) < 2 then
        return
    end
    local now = GetTime()
    pool.changedAt = now
    self.rezChargesRead = pool
    self.rezCharges = { charges = pool.charges, max = pool.max, nextAt = pool.nextAt, from = me, heardAt = now }
    self:SendRezCharges(math.random() * 1.5)
end

C_Timer.NewTicker(1, function()
    CC:PollLocalReady()
    CC:PollRezCharges()
    CC:BridgeCheckFilter()
end)

-- Event frame
local ef = CreateFrame("Frame", "CCEventFrame")
CC.eventFrame = ef

ef:RegisterEvent("ADDON_LOADED")
ef:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "CooldownCollaborator" then
            -- Events first: an error in Init (say its first refresh, after a
            -- /reload in a raid) must not leave the addon deaf for the session.
            self:RegisterEvent("GROUP_ROSTER_UPDATE")
            self:RegisterEvent("UNIT_LEVEL")
            self:RegisterEvent("ENCOUNTER_START")
            self:RegisterEvent("ENCOUNTER_END")
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            self:RegisterEvent("CHAT_MSG_ADDON")
            if CC.isRetail then
                self:RegisterEvent("INSPECT_READY")
                self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            end
            self:RegisterEvent("PLAYER_LOGOUT")
            self:RegisterEvent("PLAYER_LOGIN")
            CC:Init()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        CC:CloseWindowsIfLeftGroup()
        CC:PruneState()
        CC:MergeRestored()
        CC:RefreshView("RefreshRows")
        CC:ScanRoster()
        -- joined (or left) a group: hello, state request, our state (Comms.lua)
        CC:CheckGroupChange()
    elseif event == "UNIT_LEVEL" then
        -- a provider spell may have just come in reach (Roster.lua)
        CC:OnUnitLevel(...)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        CC.inCombat = event == "PLAYER_REGEN_DISABLED"
        CC.panelForced = nil   -- a combat change ends a panel opened by hand under "only in combat"
        if CC.db and CC.db.showWindows == "combat" then CC:RefreshAllViews() end
    elseif event == "ENCOUNTER_START" then
        CC.inEncounter = true
        CC.panelForced = nil
        if CC.db and CC.db.showWindows == "boss" then CC:RefreshAllViews() end
    elseif event == "ENCOUNTER_END" then
        CC.inEncounter = false
        CC.panelForced = nil
        if CC.db and CC.db.showWindows == "boss" then CC:RefreshAllViews() end
        -- a second, then a random 0 to 2 s more, so a raid doesn't all send at once
        C_Timer.After(1 + math.random() * 2, function() CC:BroadcastState() end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- spellID is SECRET for party/raid tokens — confirmed by live crash
        -- ("attempted to index a table that cannot be indexed with secret
        -- keys") when a party member's cast fired this event. Only "player"
        -- gives a safe, indexable spellID. Other players' cooldowns must
        -- arrive exclusively via the addon-message sync (OnAddonMessage),
        -- never by reading this event for their unit token directly.
        local unitToken, castGUID, spellID = ...
        if unitToken == "player" then
            CC:RecordCooldown(unitToken, spellID)
            CC:OnStoneCastDone(castGUID, spellID)
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- our own Soulstone's target, as the cast starts
        CC:OnSpellcastSent(...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Era, TBC and MoP only (Events.lua): other players' casts
        local ok, err = pcall(CC.OnCombatLog, CC)
        if not ok and CC.verbose then
            print("|cFF54a3ffCDC|r combat log error: " .. tostring(err)) -- debug
        end
    elseif event == "INSPECT_READY" then
        CC:OnInspectReady(...)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        CC:OnSpecChanged(...)
    elseif event == "CHAT_MSG_ADDON" then
        CC:OnAddonMessage(...)
    elseif event == "PLAYER_LOGIN" then
        -- our full name (and realm) is readable by now: this character's profile, then timers saved at the last logout
        CC:ApplyCharacterProfile()
        CC:RestoreTimers()
        -- Every addon is loaded by now, so CDTL3 (if present) is ready.
        CC:BridgeRegister()
        -- the minimap has its real size by now (Minimap.lua)
        CC:PlaceMinimapButton()
        -- a /reload or login inside a group says hello and asks for the group's state
        CC:CheckGroupChange()
    elseif event == "PLAYER_LOGOUT" then
        CC:SavePosition()
        CC:SaveTimers()
    end
end)

SLASH_COOLDOWNCOLLABORATOR1 = "/cdc"
SlashCmdList["COOLDOWNCOLLABORATOR"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    if cmd == "lock" then
        CC:SetWindowsLocked(true)
        print("|cFF54a3ffCooldownCollaborator|r " .. L["windows locked."])
    elseif cmd == "unlock" then
        CC:SetWindowsLocked(false)
        print("|cFF54a3ffCooldownCollaborator|r " .. L["windows unlocked."])
    elseif cmd == "reset" then
        -- the main panel back in its slot of the joined windows (Options.lua ResetWindow)
        CC:ResetWindow(CC.WINDOWS[1])
        print("|cFF54a3ffCooldownCollaborator|r " .. L["position reset."])
    elseif cmd == "settings" then
        CC:OpenOptions()
    elseif cmd == "verbose" then
        CC.verbose = not CC.verbose
        print("|cFF54a3ffCooldownCollaborator|r " .. string.format(L["verbose cast logging: %s"], CC.verbose and L["ON"] or L["OFF"]))
    elseif cmd == "essentials" then
        CC.db.essentialsEnabled = not CC.db.essentialsEnabled
        CC:RefreshEssentials()
        print("|cFF54a3ffCooldownCollaborator|r " .. string.format(L["Essentials bar: %s"], CC.db.essentialsEnabled and L["ON"] or L["OFF"]))
    elseif cmd == "lanes" then
        CC.db.laneEnabled = not CC.db.laneEnabled
        CC:RefreshLanes()
        local soloHint = (CC.db.laneEnabled and not IsInGroup()) and (" " .. L["(it shows when you're in a group)"]) or ""
        print("|cFF54a3ffCooldownCollaborator|r " .. string.format(L["Lane view: %s"], CC.db.laneEnabled and L["ON"] or L["OFF"]) .. soloHint)
    elseif cmd == "rez" then
        CC:RequestRez()
    elseif cmd == "lastpull" then
        CC:PrintLastPull()
    elseif cmd == "post" then
        CC:PostReady()
    elseif cmd == "report" then
        CC:ShowReport()
    elseif cmd == "tour" then
        CC:StartTour(true)
    elseif cmd == "nexthit" then
        -- /cdc nexthit <seconds or M:SS> | off: the Lane view's look-ahead (Lanes.lua)
        CC:NextHitCommand(msg:match("^%s*%S+%s*(.-)%s*$") or "")
    elseif cmd == "consumable" then
        -- /cdc consumable <spellID> <seconds> [flask|food|other] <name...>
        -- /cdc consumable remove <spellID>
        local rest = msg:match("^%S+%s+(.*)$") or ""
        local removeID = rest:match("^[Rr][Ee][Mm][Oo][Vv][Ee]%s+(%d+)%s*$")
        if removeID then
            CC:RemoveConsumableBuff(tonumber(removeID), true)
        else
            local spellIDStr, durStr, tail = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
            local spellID = tonumber(spellIDStr)
            local dur = tonumber(durStr)
            if not spellID or not dur then
                print("|cFF54a3ffCooldownCollaborator|r " .. L["usage: /cdc consumable <spellID> <seconds> <flask|food|other> <name>  |  /cdc consumable remove <spellID>"])
            else
                -- a lowercase flask / food / other right after the seconds is the category
                local category, name = tail:match("^(%l+)%s+(.+)$")
                if category ~= "flask" and category ~= "food" and category ~= "other" then
                    category, name = nil, tail
                end
                CC:AddConsumableBuff(spellID, dur, name ~= "" and name or nil, category)
            end
        end
    elseif cmd == "roster" then
        CC:ScanRoster()
        print("|cFF54a3ffCooldownCollaborator|r " .. L["roster:"])
        for name, info in pairs(CC.roster or {}) do
            print("    " .. CC:RosterLine(name, info))
        end
    elseif cmd == "debug" then
        -- debug begin: the debug dump stays in English
        print("|cFF54a3ffCooldownCollaborator|r " .. CC.version)
        print("  In group:", tostring(IsInGroup()), " In raid:", tostring(IsInRaid()))
        print("  In encounter:", tostring(CC.inEncounter))
        print(string.format("  Lighter mode: %s; refresh every %.1fs (panel and Essentials bar), %.1fs (Lane view); windows show: %s",
            CC.db.lighterMode and "on" or "off", CC:TickRate("panel"), CC:TickRate("lanes"), tostring(CC.db.showWindows)))
        print("  Min duration filter:", CC.db.minDuration)
        local any = false
        for name, entry in pairs(CC.state) do
            for sid, _ in pairs(entry.spells) do
                any = true
                local rem = CC:GetRemaining(name, sid)
                local spell = CC.SpellData[sid]
                print(string.format("    %s [%s] %s = %.0fs",
                    CC:ShortName(name), entry.class, spell and spell.name or tostring(sid), rem or 0))
            end
        end
        if not any then
            print("  (no cooldowns recorded yet — try /cdc verbose, then use a tracked CD)")
        end
        -- debug end
    else
        -- the panel: a close here (or with its button) lasts until /cdc or the minimap opens it (R19)
        CC:TogglePanel()
    end
end
