-- CooldownCollaborator
-- Group and raid cooldown coordinator for World of Warcraft: Retail (Midnight
-- 12.x), MoP Classic, TBC Anniversary, Classic Era and WoW: Forever.
-- Author: Nelnamara

CooldownCollaborator = {}
CC = CooldownCollaborator

CC.version     = "1.1.1"
CC.PREFIX      = "CDCOLLAB"   -- cooldowns (Comms.lua, docs/MESSAGE_FORMAT_2.md)
CC.BUFF_PREFIX = "CDCBUFF"    -- flask and food status

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

-- Addon-message senders normally carry a realm; add ours if one is missing.
function CC:NormalizeSender(sender)
    if not sender or sender == "" then return nil end
    if sender:find("-", 1, true) then return sender end
    local realm = GetNormalizedRealmName()
    if realm and realm ~= "" then return sender .. "-" .. realm end
    return sender
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

local DEFAULTS = {
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

    laneEnabled = false,
    laneX       = 0,
    laneY       = -200,
    laneScale   = 1.0,
    laneLocked  = false,

    showOnCDTL3 = true,   -- feed group cooldowns to CDTL3's lanes (if CDTL3 is loaded)
}

function CC:Init()
    if not CooldownCollaboratorDB then
        CooldownCollaboratorDB = CopyTable(DEFAULTS)
    end
    self.db = CooldownCollaboratorDB
    for k, v in pairs(DEFAULTS) do
        if self.db[k] == nil then self.db[k] = v end
    end

    -- Rank map and name index from this client's own list (Data_<client>.lua)
    self:BuildSpellIndex()

    -- Merge built-in consumables, then user's custom/registered ones
    for id, data in pairs(CC.BuiltinConsumables or {}) do
        CC.SpellData[id] = data
    end
    self:LoadCustomSpells()
    self:LoadConsumableBuffs()

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
            ApplyCustomSpell(spellID, data.name or ("Spell " .. spellID), data.duration, data.icon)
        end
    end
end

function CC:AddCustomSpell(spellID, duration)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end

    local name, icon = CC.Compat.GetSpellInfo(spellID)

    if not name then
        print("|cFF54a3ffCooldownCollaborator|r Unknown spell ID: " .. spellID)
        return false
    end

    self.db.customSpells[tostring(spellID)] = {
        name     = name,
        duration = duration,
        icon     = icon or 134400,
    }
    ApplyCustomSpell(spellID, name, duration, icon)
    print(string.format("|cFF54a3ffCooldownCollaborator|r Added: %s (%ds)", name, duration))
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
        print(string.format("|cFF54a3ffCDC|r cast seen: unit=%s spellID=%s known=%s",
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
    self.db.timers = { wall = wall, clock = now, players = saved }
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

-- Raid lead / assist only: target a dead player and announce who should
-- rez them, naming the specific provider whose Battle Rez is ready right
-- now rather than a generic "someone rez" callout.
-- (IsRaidLeader / IsRaidOfficer are gone on every client; these two are on all five.)
function CC:CanRequestRez()
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    elseif IsInGroup() then
        return UnitIsGroupLeader("player")
    end
    return false
end

-- The target's full name, or nil when it can't be read: on Retail and Forever a hidden name must
-- not raise an error, so the read and its comparisons run in a pcall.
local function TargetName()
    local ok, name = pcall(CC.FullName, CC, "target")
    if ok then return name end
    return nil
end

function CC:RequestRez()
    if not self:CanRequestRez() then
        print("|cFF54a3ffCDC|r Only the raid leader/assist (or party leader) can request a rez.")
        return
    end
    -- Only a dead, friendly player may be named; a friendly player outside the group is fine
    -- (a Battle Rez works on them). A dead monster or enemy is refused.
    if not UnitExists("target") or not UnitIsPlayer("target")
        or not UnitIsFriend("player", "target") or not UnitIsDeadOrGhost("target") then
        print("|cFF54a3ffCDC|r Target a dead friendly player first.")
        return
    end

    local targetName = TargetName()
    if not targetName then
        print("|cFF54a3ffCDC|r Can't read that target's name. Target a dead friendly player first.")
        return
    end
    local status = CC:GetCapabilityStatus("BATTLEREZ")
    local provider = nil
    for _, entry in ipairs(status) do
        -- A dead or offline player can't rez anyone: skip the target, and anyone
        -- else who is dead, a ghost or disconnected (R6).
        if entry.ready and entry.name ~= targetName and entry.online ~= false and entry.alive ~= false then
            provider = entry
            break
        end
    end

    if not provider then
        print("|cFF54a3ffCDC|r No living Battle Rez provider available right now.")
        return
    end

    local data = CC.SpellData[provider.spellID]
    local spellName = data and data.name or "Battle Rez"
    local msg = string.format("%s, please %s %s!", self:ShortName(provider.name), spellName, self:ShortName(targetName))

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
    local ids = cap and classTag and cap.classes[classTag]
    if not ids then return nil, false end
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
    elseif event == "ENCOUNTER_START" then
        CC.inEncounter = true
    elseif event == "ENCOUNTER_END" then
        CC.inEncounter = false
        -- a second, then a random 0 to 2 s more, so a raid doesn't all send at once
        C_Timer.After(1 + math.random() * 2, function() CC:BroadcastState() end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- spellID is SECRET for party/raid tokens — confirmed by live crash
        -- ("attempted to index a table that cannot be indexed with secret
        -- keys") when a party member's cast fired this event. Only "player"
        -- gives a safe, indexable spellID. Other players' cooldowns must
        -- arrive exclusively via the addon-message sync (OnAddonMessage),
        -- never by reading this event for their unit token directly.
        local unitToken, _, spellID = ...
        if unitToken == "player" then
            CC:RecordCooldown(unitToken, spellID)
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Era, TBC and MoP only (Events.lua): other players' casts
        local ok, err = pcall(CC.OnCombatLog, CC)
        if not ok and CC.verbose then
            print("|cFF54a3ffCDC|r combat log error: " .. tostring(err))
        end
    elseif event == "INSPECT_READY" then
        CC:OnInspectReady(...)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        CC:OnSpecChanged(...)
    elseif event == "CHAT_MSG_ADDON" then
        CC:OnAddonMessage(...)
    elseif event == "PLAYER_LOGIN" then
        -- our full name (and realm) is readable by now: timers saved at the last logout
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
        print("|cFF54a3ffCooldownCollaborator|r windows locked.")
    elseif cmd == "unlock" then
        CC:SetWindowsLocked(false)
        print("|cFF54a3ffCooldownCollaborator|r windows unlocked.")
    elseif cmd == "reset" then
        CC.db.x, CC.db.y = 0, 200
        CC.frame:ClearAllPoints()
        CC.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        print("|cFF54a3ffCooldownCollaborator|r position reset.")
    elseif cmd == "settings" then
        CC:OpenOptions()
    elseif cmd == "verbose" then
        CC.verbose = not CC.verbose
        print("|cFF54a3ffCooldownCollaborator|r verbose cast logging: " .. (CC.verbose and "ON" or "OFF"))
    elseif cmd == "essentials" then
        CC.db.essentialsEnabled = not CC.db.essentialsEnabled
        CC:RefreshEssentials()
        print("|cFF54a3ffCooldownCollaborator|r Essentials bar: " .. (CC.db.essentialsEnabled and "ON" or "OFF"))
    elseif cmd == "lanes" then
        CC.db.laneEnabled = not CC.db.laneEnabled
        CC:RefreshLanes()
        local soloHint = (CC.db.laneEnabled and not IsInGroup()) and " (it shows when you're in a group)" or ""
        print("|cFF54a3ffCooldownCollaborator|r Lane view: " .. (CC.db.laneEnabled and "ON" or "OFF") .. soloHint)
    elseif cmd == "rez" then
        CC:RequestRez()
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
                print("|cFF54a3ffCooldownCollaborator|r usage: /cdc consumable <spellID> <seconds> <flask|food|other> <name>  |  /cdc consumable remove <spellID>")
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
        print("|cFF54a3ffCooldownCollaborator|r roster" .. (CC.isRetail and " (spec refinement queued)" or "") .. ":")
        for name, info in pairs(CC.roster or {}) do
            local caps = {}
            for key in pairs(info.capabilities) do caps[#caps + 1] = key end
            local specName = CC:GetSpecName(name)
            local classStr = specName and (specName .. " " .. info.class) or info.class
            print(string.format("    %s [%s] capabilities: %s; %s",
                CC:ShortName(name), classStr, #caps > 0 and table.concat(caps, ", ") or "none", CC:PeerNote(name)))
        end
    elseif cmd == "debug" then
        print("|cFF54a3ffCooldownCollaborator|r " .. CC.version)
        print("  In group:", tostring(IsInGroup()), " In raid:", tostring(IsInRaid()))
        print("  In encounter:", tostring(CC.inEncounter))
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
    else
        if CC.frame then
            CC.frame:SetShown(not CC.frame:IsShown())
        end
    end
end
