-- Stub WoW client for loading the REAL CooldownCollaborator files under fengari.
-- Adapted from cdtl3-dev's tools/tests/wow.lua (frame mock, timers, events,
-- secret values), cut to what this addon calls, plus a party, addon chat and
-- auras. Each client gets only the APIs it has: no GetSpecialization on Era,
-- TBC or Forever; no isActive in Classic cooldown tables; no IsSpellKnown
-- globals on Forever; no combat log on Retail or Forever.
-- Set HARNESS_SRC / HARNESS_TOC before dofile'ing this. Exposes:
--   NOW, Advance(dt), RunTimers(), FireEvent(e, ...), ERRORS, PRINTS, PLAYER,
--   GROUP / INSTANCE_GROUP, SENT (addon messages), SendResult(), SPELLCD,
--   SPELLCHARGES, KNOWN, SPELLINFO, AURAS, PLAYER_AURA_IDS, CLEU_ARGS, SECRET,
--   INSPECTS, LoadTOC(tocName), Login().
local TOC = HARNESS_TOC
FLAVOR = (TOC >= 110000 and "retail") or (TOC >= 50000 and "mop") or (TOC >= 20000 and "tbc")
	or ((TOC >= 16000 and TOC < 17000) and "forever") or "era"
RETAILAPI = (FLAVOR == "retail" or FLAVOR == "forever")

---------------------------------------------------------------- Lua 5.1 compat
loadstring = function(s, name) return load(s, name) end
unpack = table.unpack
getfenv = function() return _G end
math.mod = math.fmod
strlen, strsub, strlower, strupper = string.len, string.sub, string.lower, string.upper
strfind, strmatch, gsub, strrep = string.find, string.match, string.gsub, string.rep
format = string.format
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min
function strsplit(delim, str, pieces)
	local out, pos = {}, 1
	while true do
		if pieces and #out == pieces - 1 then out[#out + 1] = str:sub(pos); break end
		local s, e = str:find(delim, pos, true)
		if not s then out[#out + 1] = str:sub(pos); break end
		out[#out + 1] = str:sub(pos, s - 1)
		pos = e + 1
	end
	return table.unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
	local c = {}
	for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
	return c
end
bit = {
	band = function(a, b, ...) local r = math.tointeger(a) & math.tointeger(b); for _, x in ipairs({ ... }) do r = r & x end return r end,
	bor = function(a, b, ...) local r = math.tointeger(a) | math.tointeger(b); for _, x in ipairs({ ... }) do r = r | x end return r end,
}

---------------------------------------------------------------- errors / print / time / events
-- harness output; the addon's own print() goes to PRINTS
OUT = print
ERRORS = {}
local function errh(e)
	local tb = debug.traceback(tostring(e), 2)
	ERRORS[#ERRORS + 1] = tb
	OUT("!! LUA ERROR: " .. tb)
	return e
end
ERRH = errh
function geterrorhandler() return errh end
PRINTS = {}
print = function(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	PRINTS[#PRINTS + 1] = table.concat(t, " ")
end
function InCombatLockdown() return false end
function hooksecurefunc() end

NOW = 1000
function GetTime() return NOW end
local timers = {}
function Advance(dt)
	NOW = NOW + dt
	RunTimers()
end
function RunTimers()
	local again = true
	while again do
		again = false
		table.sort(timers, function(a, b) return a.t < b.t end)
		for i, tm in ipairs(timers) do
			if tm.t <= NOW then
				table.remove(timers, i)
				xpcall(tm.f, errh)
				again = true
				break
			end
		end
	end
end
C_Timer = {
	After = function(d, f) timers[#timers + 1] = { t = NOW + d, f = f } end,
	-- tickers run (once per Advance at most, then re-arm d seconds later)
	NewTicker = function(d, f)
		local h = { cancelled = false }
		local function arm()
			timers[#timers + 1] = { t = NOW + d, f = function()
				if h.cancelled then return end
				arm()
				f(h)
			end }
		end
		arm()
		h.Cancel = function() h.cancelled = true end
		return h
	end,
}

local eventFrames = {}   -- event -> { frame = true }
function FireEvent(event, ...)
	local list = {}
	for f in pairs(eventFrames[event] or {}) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		local h = f.__scripts and f.__scripts.OnEvent
		if h then xpcall(h, errh, f, event, ...) end
	end
	return #list
end
function IsEventRegisteredAnywhere(event)
	for _ in pairs(eventFrames[event] or {}) do return true end
	return false
end
REFUSED_EVENTS = {}  -- event -> true: RegisterEvent errors (combat log on retailAPI clients)

---------------------------------------------------------------- frame / region mock
local Methods = {}
local MockMT = {}
local function newObj(otype, name, parent)
	return setmetatable({ __otype = otype, __name = name, __parent = parent, __shown = true,
		__scripts = {}, __points = {}, __w = 0, __h = 0, __alpha = 1, __level = 1, __enabled = true }, MockMT)
end
MockMT.__index = function(t, k)
	local m = Methods[k]
	if m then return m end
	if type(k) ~= "string" or not k:match("^%u") then return nil end
	if k:match("^Create") then
		return function(self) return newObj(k:sub(7), nil, self) end
	end
	if k:match("^Is") or k:match("^Has") or k:match("^Can") then return function() return false end end
	if k:match("^Get") then return function() return nil end end
	return function() end
end
local function child(self, key, otype)
	local c = rawget(self, key)
	if not c then c = newObj(otype or "Texture", nil, self); rawset(self, key, c) end
	return c
end
Methods.GetName = function(s) return s.__name end
Methods.GetParent = function(s) return s.__parent end
Methods.SetParent = function(s, p) s.__parent = p end
Methods.Show = function(s) s.__shown = true end
Methods.Hide = function(s) s.__shown = false end
Methods.SetShown = function(s, v) s.__shown = v and true or false end
Methods.IsShown = function(s) return s.__shown end
Methods.SetScript = function(s, k, f) s.__scripts[k] = f end
Methods.GetScript = function(s, k) return s.__scripts[k] end
Methods.RegisterEvent = function(s, e)
	if REFUSED_EVENTS[e] then error("Attempt to register a forbidden event: " .. e) end
	eventFrames[e] = eventFrames[e] or {}; eventFrames[e][s] = true
	return true
end
Methods.UnregisterEvent = function(s, e) if eventFrames[e] then eventFrames[e][s] = nil end end
Methods.IsEventRegistered = function(s, e) return eventFrames[e] and eventFrames[e][s] or false end
Methods.SetWidth = function(s, w) s.__w = w end
Methods.SetHeight = function(s, h) s.__h = h end
Methods.SetSize = function(s, w, h) s.__w, s.__h = w, h or w end
Methods.GetWidth = function(s) return s.__w or 0 end
Methods.GetHeight = function(s) return s.__h or 0 end
Methods.SetPoint = function(s, ...) s.__points[#s.__points + 1] = { ... } end
Methods.ClearAllPoints = function(s) s.__points = {} end
Methods.GetCenter = function() return 0, 0 end
Methods.GetEffectiveScale = function() return 1 end
Methods.SetAlpha = function(s, a) s.__alpha = a end
Methods.GetAlpha = function(s) return s.__alpha end
Methods.SetText = function(s, t) s.__text = t end
Methods.GetText = function(s) return s.__text end
Methods.SetEnabled = function(s, v) s.__enabled = v and true or false end
Methods.IsEnabled = function(s) return s.__enabled end
Methods.GetChecked = function(s) return s.__checked end
Methods.SetChecked = function(s, v) s.__checked = v end
Methods.SetTexture = function(s, t) s.__tex = t; return true end
Methods.GetTexture = function(s) return s.__tex end
Methods.GetFontString = function(s) return child(s, "__fs", "FontString") end
Methods.GetRegions = function() end
Methods.GetChildren = function() end
Methods.GetScrollChild = function(s) return s.__scrollchild end
Methods.SetScrollChild = function(s, c) s.__scrollchild = c end
-- SetBackdrop exists only on frames made with BackdropTemplate (or on very old clients)
Methods.SetBackdrop = function(s, b)
	if not s.__backdrop_ok then error("SetBackdrop on a frame without BackdropTemplate") end
	s.__backdrop = b
end

BACKDROP_FRAMES = 0
function CreateFrame(otype, name, parent, template)
	local f = newObj(otype or "Frame", name, parent or nil)
	if name then _G[name] = f end
	if otype == "GameTooltip" then f.__shown = false end
	if type(template) == "string" then
		if template:find("BackdropTemplate", 1, true) then
			f.__backdrop_ok = true
			BACKDROP_FRAMES = BACKDROP_FRAMES + 1
		end
		if template:find("OptionsSliderTemplate", 1, true) then
			f.Text = newObj("FontString", nil, f)
			f.Low = newObj("FontString", nil, f)
			f.High = newObj("FontString", nil, f)
		end
	end
	return f
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Minimap", "Minimap", UIParent)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
for _, n in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall", "GameFontHighlightSmall",
	"GameFontDisable", "GameFontDisableSmall", "GameFontNormalLarge" }) do
	_G[n] = newObj("Font", n)
end
UISpecialFrames = {}
BackdropTemplateMixin = {}
function GetCursorPosition() return 0, 0 end
SlashCmdList = {}
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_TYPE_PET = 0x1000
COMBATLOG_OBJECT_AFFILIATION_MINE = 0x1
COMBATLOG_OBJECT_AFFILIATION_PARTY = 0x2
COMBATLOG_OBJECT_AFFILIATION_RAID = 0x4
COMBATLOG_OBJECT_AFFILIATION_OUTSIDER = 0x8
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_ID = ({ retail = 1, era = 2, tbc = 5, mop = 19, forever = 18 })[FLAVOR]
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
Enum = setmetatable({
	SpellBookSpellBank = { Player = 0, Pet = 1 },
	SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9, NotInGroup = 5 },
}, { __index = function(t, k) local e = setmetatable({}, { __index = function() return 0 end }); rawset(t, k, e); return e end })

---------------------------------------------------------------- player and group
PLAYER = { guid = "Player-1-0000001", name = "Tester", realm = "Realm", class = "DRUID", unit = "player" }
-- GROUP = { { unit = "party1", name = , realm = , class = , guid = }, ... }; a party when non-empty
GROUP = {}
INSTANCE_GROUP = false   -- also in an instance group (dungeon finder, battleground)
local function member(u)
	if u == "player" then return PLAYER end
	for _, m in ipairs(GROUP) do if m.unit == u then return m end end
end
function GetBuildInfo() return "test", "70000", "Nov 14 2026", TOC end
function GetNormalizedRealmName() return PLAYER.realm end
function UnitName(u)
	local m = member(u)
	if m then return m.name, (m.realm ~= PLAYER.realm) and m.realm or nil end
end
function UnitFullName(u)
	local m = member(u)
	if m then return m.name, m.realm end
end
function UnitGUID(u) local m = member(u); return m and m.guid end
function UnitClass(u) local m = member(u); if m then return m.class, m.class, 1 end end
function UnitExists(u) return member(u) ~= nil end
function UnitIsConnected(u) return member(u) ~= nil end
function UnitIsDeadOrGhost() return false end
function UnitIsGroupLeader(u) return u == "player" end
function IsRaidLeader() return false end
function IsRaidOfficer() return false end
function IsInRaid() return false end
function IsInGroup(category)
	if category == LE_PARTY_CATEGORY_INSTANCE then return INSTANCE_GROUP end
	return #GROUP > 0 or INSTANCE_GROUP
end
function GetNumGroupMembers() return #GROUP > 0 and #GROUP + 1 or 0 end
function GetPlayerInfoByGUID(guid)
	for _, m in ipairs({ PLAYER, table.unpack(GROUP) }) do
		if m.guid == guid then return m.class, m.class, "Human", "Human", 2, m.name, m.realm end
	end
end
function CheckInteractDistance() return true end
-- the inspect API exists on every client; CooldownCollaborator should only use it on Retail
INSPECTS = 0
function NotifyInspect() INSPECTS = INSPECTS + 1 end
function ClearInspectPlayer() end
function GetInspectSpecialization() return 1 end
if FLAVOR == "retail" or FLAVOR == "mop" then
	function GetSpecialization() return 2 end
end
if FLAVOR == "retail" then
	C_SpecializationInfo = { GetSpecialization = function() return 2 end }
end
CHATSENT = {}
function SendChatMessage(msg, chan) CHATSENT[#CHATSENT + 1] = { msg = msg, chan = chan } end

---------------------------------------------------------------- addon messages
SENT = {}      -- { prefix, msg, channel }
PREFIXES = {}
-- what SendAddonMessage returns: an Enum.SendAddonMessageResult on retailAPI clients, true on the others
SendResult = RETAILAPI and function() return 0 end or function() return true end
C_ChatInfo = {
	RegisterAddonMessagePrefix = function(p) PREFIXES[p] = true; return true end,
	SendAddonMessage = function(prefix, msg, channel)
		SENT[#SENT + 1] = { prefix = prefix, msg = msg, channel = channel }
		return SendResult()
	end,
}
if FLAVOR == "retail" then
	C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return false end
end

---------------------------------------------------------------- settings panel
-- the modern Settings panel on retailAPI clients; the Classic stubs have only the old list
if RETAILAPI then
	Settings = {
		RegisterCanvasLayoutCategory = function(frame, name) return { ID = name, name = name } end,
		RegisterAddOnCategory = function(cat) SETTINGS_CATEGORY = cat end,
	}
else
	function InterfaceOptions_AddCategory(panel) INTERFACE_OPTIONS_PANEL = panel end
end

---------------------------------------------------------------- spells (flavor-specific)
-- SPELLINFO[id] = { name, icon }; SPELLCD[id] = C_Spell.GetSpellCooldown-style table;
-- SPELLCHARGES[id] = { currentCharges, maxCharges, cooldownStartTime, cooldownDuration }; KNOWN[id] = true
SPELLINFO, SPELLCD, SPELLCHARGES, KNOWN = {}, {}, {}, {}
-- a value whose comparison / arithmetic throws, like a Midnight secret number
SECRET = setmetatable({}, {
	__lt = function() error("attempt to compare a secret number value") end,
	__le = function() error("attempt to compare a secret number value") end,
	__add = function() error("attempt to perform arithmetic on a secret number value") end,
	__sub = function() error("attempt to perform arithmetic on a secret number value") end,
	__concat = function() error("attempt to concatenate a secret value") end,
	__tostring = function() return "<secret>" end,
})
local function cdOf(id)
	local c = SPELLCD[id]
	if c then return c end
	return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 }
end
local function infoByName(name)
	for id, s in pairs(SPELLINFO) do if s[1] == name then return id, s end end
end
if RETAILAPI then
	C_Spell = {
		GetSpellInfo = function(spell)
			local id, s = spell, SPELLINFO[spell]
			if type(spell) == "string" then id, s = infoByName(spell) end
			if s then return { name = s[1], iconID = s[2] or 136000, spellID = id } end
		end,
		GetSpellCooldown = function(id) return cdOf(id) end,
		GetSpellCharges = function(id) return SPELLCHARGES[id] end,
	}
	C_SpellBook = {
		IsSpellKnown = function(id) return KNOWN[id] or false end,
		IsSpellKnownOrInSpellBook = function(id) return KNOWN[id] or false end,
	}
	if FLAVOR == "retail" then
		-- retail 12.x keeps these in its deprecation fallbacks; Forever has none of them
		function IsSpellKnown(id) return KNOWN[id] or false end
		function IsSpellKnownOrOverridesKnown(id) return KNOWN[id] or false end
		CombatLogGetCurrentEventInfo = function() return nil end
	end
	REFUSED_EVENTS["COMBAT_LOG_EVENT_UNFILTERED"] = true
else
	C_Spell = {
		-- the Classic clients' cooldown tables have no isActive (a 12.0.1 field)
		GetSpellCooldown = function(id)
			local c = cdOf(id)
			return { startTime = c.startTime, duration = c.duration, isEnabled = c.isEnabled, modRate = 1 }
		end,
	}
	function GetSpellInfo(spell)
		local id, s = spell, SPELLINFO[spell]
		if type(spell) == "string" then id, s = infoByName(spell) end
		if s then return s[1], "", s[2] or 136000, 0, 0, 0, id end
	end
	function GetSpellCooldown(id)
		local c = cdOf(id)
		if c.isEnabled == false then return c.startTime, c.duration, 0, 1 end
		if c.isActive == false then return 0, 0, 1, 1 end
		return c.startTime, c.duration, 1, 1
	end
	function GetSpellCharges(id)
		local c = SPELLCHARGES[id]
		if c then return c.currentCharges, c.maxCharges, c.cooldownStartTime, c.cooldownDuration end
	end
	function IsSpellKnown(id) return KNOWN[id] or false end
	function IsSpellKnownOrOverridesKnown(id) return KNOWN[id] or false end
	function UnitAura(u, i, f)
		local l = AURAS[f or "HELPFUL"]
		local a = l and l[i]
		if a then return a.name, a.icon, 0, "", a.duration or 0, 0, nil, nil, nil, a.spellId end
	end
	CLEU_ARGS = nil
	function CombatLogGetCurrentEventInfo() return table.unpack(CLEU_ARGS or {}) end
	C_CombatLog = { GetCurrentEventInfo = function() return table.unpack(CLEU_ARGS or {}) end }
end

---------------------------------------------------------------- auras
AURAS = { HELPFUL = {} }      -- readable buff list (Classic): { name =, spellId = }
PLAYER_AURA_IDS = {}          -- id -> true (GetPlayerAuraBySpellID on Retail / Forever)
C_UnitAuras = {}
if RETAILAPI then
	-- aura data is secret here: reading it by index is a bug, so it throws
	C_UnitAuras.GetAuraDataByIndex = function() error("aura data by index read on a client where it is secret") end
	C_UnitAuras.GetPlayerAuraBySpellID = function(id)
		if PLAYER_AURA_IDS[id] then return { spellId = SECRET, name = SECRET } end
	end
else
	-- CDTL3 confirms GetAuraDataByIndex on the Classic clients; GetPlayerAuraBySpellID is unverified there, so absent
	C_UnitAuras.GetAuraDataByIndex = function(u, i, f) local l = AURAS[f or "HELPFUL"]; return l and l[i] end
end

---------------------------------------------------------------- loader
local ADDON = "CooldownCollaborator"
local SRC = HARNESS_SRC
LOADED_FILES = {}
local function norm(p) return (p:gsub("\\", "/")) end
function ReadTOC(tocName)
	return HARNESS_READ(SRC .. "/" .. tocName)
end
function LoadTOC(tocName)
	local t = ReadTOC(tocName)
	local files = {}
	for line in t:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then
			files[#files + 1] = norm(line:match("^%s*(.-)%s*$"))
		end
	end
	for _, f in ipairs(files) do
		local path = SRC .. "/" .. f
		local fn, err = loadfile(path)
		if not fn then
			errh("LOAD " .. path .. ": " .. tostring(err))
		else
			LOADED_FILES[#LOADED_FILES + 1] = f
			xpcall(fn, errh, ADDON, {})
		end
	end
	return files
end

function Login()
	FireEvent("ADDON_LOADED", ADDON)
	FireEvent("PLAYER_LOGIN")
	FireEvent("PLAYER_ENTERING_WORLD", true, false)
end
