-- The Asks tab (WhisperCast: Second Wind's request queue on the main panel) for one TOC: no tab without
-- WhisperCastSW (or with it switched off), the tab and its count badge with it, the next request, grouped
-- and plain drawing, "No requests", a redraw on QueueChanged and CombatChanged, one Cast button made once,
-- shown only on the Asks tab, and no protected call on it while InCombatLockdown() (a tab change in combat
-- waits for PLAYER_REGEN_ENABLED). The stub WhisperCastSW is the public API only: GetView, IsEnabled,
-- RegisterCallback, CreateCastButton.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/asks.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[asks %s %s]", HARNESS_TOCFILE, FLAVOR))

LoadTOC(HARNESS_TOCFILE)
Login()
CC.db.tourDone = true
check("loads: no Lua errors", #ERRORS == 0, ERRORS[1])

local function Plain(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- a group, so the panel shows
GROUP = {}
for i = 1, 2 do
	GROUP[i] = { unit = "party" .. i, name = "M" .. i, realm = "Realm", class = "PRIEST", guid = string.format("Player-1-5%05d", i) }
end
FireEvent("GROUP_ROSTER_UPDATE")

---------------------------------------------------------------- the combat switch and the stub Second Wind
local COMBAT = false
function InCombatLockdown() return COMBAT end

local QUEUE = { count = 0, next = nil, groups = {}, rest = {} }   -- what GetView answers
local ENABLED = true
local callbacks = {}      -- event -> { owner = fn }
local made = {}           -- the Cast buttons CreateCastButton returned
local protectedCalls = 0
local combatProtected = 0
local PROTECTED = { "Show", "Hide", "SetPoint", "SetSize", "SetParent", "ClearAllPoints" }

local function Stub()
	WhisperCastSW = {
		spells = {
			innervate = { key = "innervate", name = "Innervate", icon = "Interface\\Icons\\Spell_Nature_Lightning" },
			motw = { key = "motw", name = "Mark of the Wild", icon = "Interface\\Icons\\Spell_Nature_Regeneration" },
		},
	}
	local W = WhisperCastSW
	function W:GetView() return QUEUE end
	function W:IsEnabled() return ENABLED end
	function W.RegisterCallback(owner, event, fn)
		callbacks[event] = callbacks[event] or {}
		callbacks[event][owner] = fn
	end
	function W.UnregisterCallback(owner, event) if callbacks[event] then callbacks[event][owner] = nil end end
	function W:CreateCastButton(parent)
		local b = CreateFrame("Button", "WCSWStubCast" .. (#made + 1), parent)
		b.protectedCalls = {}
		for _, name in ipairs(PROTECTED) do
			local orig = b[name]
			b[name] = function(self, ...)
				protectedCalls = protectedCalls + 1
				b.protectedCalls[#b.protectedCalls + 1] = name
				if InCombatLockdown() then
					combatProtected = combatProtected + 1
					error("ADDON_ACTION_BLOCKED: " .. name .. " on a secure frame in combat", 2)
				end
				return orig(self, ...)
			end
		end
		made[#made + 1] = b
		return b
	end
end
local function Fire(event, ...)
	for owner, fn in pairs(callbacks[event] or {}) do xpcall(fn, ERRH or print, ...) end
end
local function CallbackCount(event)
	local n = 0
	for _ in pairs(callbacks[event] or {}) do n = n + 1 end
	return n
end

local function Req(name, class, spell, ago)
	return { name = name, short = name, class = class, spell = spell, time = GetTime() - (ago or 0), id = name .. spell }
end

-- the tab buttons: { key, text } of the shown ones
local function Tabs()
	local out = {}
	for _, t in ipairs(CC.tabs) do
		if t.__shown then out[#out + 1] = { key = t.key, text = Plain(t.text.__text), raw = t.text.__text, button = t } end
	end
	return out
end
local function AsksTab()
	for _, t in ipairs(Tabs()) do if t.key == "asks" then return t end end
end
-- the panel's shown lines, top to bottom: { kind, name, spell, owners, time, y, h }
local function Lines()
	local out = {}
	for _, line in ipairs(CC.rows) do
		if line.__shown then
			local p = line.__points[#line.__points]
			local kind = "text"
			if line.asks then
				kind = line.ownersText.__shown and "group" or "req"
			end
			out[#out + 1] = { kind = kind, line = line, y = -p[5], h = line.__h,
				name = line.nameText.__shown and Plain(line.nameText.__text) or nil,
				spell = line.spellText.__shown and Plain(line.spellText.__text) or nil,
				owners = line.ownersText.__shown and Plain(line.ownersText.__text) or nil,
				time = line.timeText.__shown and Plain(line.timeText.__text) or nil,
				head = line.headText.__shown and Plain(line.headText.__text) or nil,
				icon = line.icon.__shown and line.icon.__tex or nil, barColor = line.barColor }
		end
	end
	table.sort(out, function(a, b) return a.y < b.y end)
	return out
end
local function Refresh() CC:RefreshRows() end
local function ClickTab(key)
	for _, t in ipairs(Tabs()) do
		if t.key == key then t.button.__scripts.OnClick(t.button); return true end
	end
	return false
end

---------------------------------------------------------------- without Second Wind
CC.db.panelTab = "all"
Refresh()
check("no WhisperCastSW: no tabs at all", #Tabs() == 0, #Tabs())
check("no WhisperCastSW: no Cast button asked for", #made == 0)
CC.db.panelTab = "asks"
Refresh()
check("a saved Asks tab without Second Wind falls back to the main list", CC:PanelTab() == "all", CC:PanelTab())

---------------------------------------------------------------- with it (empty queue)
Stub()
CC.db.panelTab = "all"
Refresh()
local tabs = Tabs()
check("with WhisperCastSW: an Asks tab after the others", #tabs == 2 and tabs[1].key == "all" and tabs[2].key == "asks"
	and tabs[2].text == "Asks", #tabs .. " tabs")
check("empty queue: no count badge on the tab", tabs[2] and tabs[2].text == "Asks" and not tabs[2].raw:find("|c", 1, true),
	tabs[2] and tabs[2].raw)
check("the callbacks are registered once with CDC's own table", CallbackCount("QueueChanged") == 1 and CallbackCount("CombatChanged") == 1,
	CallbackCount("QueueChanged") .. "/" .. CallbackCount("CombatChanged"))
check("the Cast button is made once, out of combat", #made == 1, #made)
check("the Cast button is hidden on the main tab", made[1] and not made[1].__shown)
check("the Cast button's parent is the panel", made[1] and made[1].__parent == CC.frame)

-- more tabs: teams and Guild come before Asks
CC.db.teams = { Tanks = { "M1" } }
CC.db.guildSync = true
Refresh()
tabs = Tabs()
check("teams, Guild, then Asks", #tabs == 4 and tabs[1].key == "all" and tabs[2].key == "team:Tanks" and tabs[3].key == "guild"
	and tabs[4].key == "asks", #tabs)
CC.db.teams = {}
CC.db.guildSync = false
Refresh()

ENABLED = false
Refresh()
check("WhisperCastSW switched off: no Asks tab", AsksTab() == nil)
ENABLED = true
Refresh()
check("switched on again: the tab is back", AsksTab() ~= nil)

---------------------------------------------------------------- selecting the tab, the empty drawing
check("clicking the Asks tab", ClickTab("asks") and CC:PanelTab() == "asks", CC:PanelTab())
check("the Cast button shows on the Asks tab", made[1].__shown == true)
check("the Cast button is anchored at the panel's foot", made[1].__points[1] and made[1].__points[1][1] == "BOTTOM"
	and made[1].__points[1][3] == "BOTTOM", made[1].__points[1] and made[1].__points[1][1])
check("empty: 'No requests'", CC.emptyLabel.__shown and Plain(CC.emptyLabel.__text) == "No requests", CC.emptyLabel.__text)
check("still one Cast button", #made == 1, #made)

---------------------------------------------------------------- the next request, grouped
local first = Req("Sorella", "PRIEST", "innervate", 5)
local b1, b2 = Req("Brannoc", "WARRIOR", "motw", 30), Req("Ayla", "DRUID", "motw", 12)
QUEUE = { count = 3, next = first, groups = { { spell = "motw", count = 2, askers = { b1, b2 } } }, rest = {} }
Fire("QueueChanged")
local L = Lines()
check("redraw on QueueChanged: the next request first", L[1] and L[1].kind == "req" and L[1].name == "Sorella"
	and L[1].spell == "Innervate" and L[1].time == "5s", L[1] and (L[1].name .. " " .. tostring(L[1].spell) .. " " .. tostring(L[1].time)))
check("the next request has its icon and class colour", L[1] and L[1].icon == "Interface\\Icons\\Spell_Nature_Lightning"
	and L[1].barColor and L[1].barColor == CC.ClassColors.PRIEST)
check("the asker's name is class coloured", L[1] and L[1].line.nameText.__textColor[1] == CC.ClassColors.PRIEST[1])
check("grouped: a spell row with its count and askers", L[2] and L[2].kind == "group" and L[2].spell == "Mark of the Wild"
	and L[2].time == "\195\1512" and L[2].owners == "Brannoc, Ayla",
	L[2] and (tostring(L[2].spell) .. " " .. tostring(L[2].time) .. " " .. tostring(L[2].owners)))
check("grouped: exactly two lines", #L == 2, #L)
tabs = Tabs()
check("count badge on the tab (accent pink)", AsksTab() and AsksTab().text == "Asks 3" and AsksTab().raw:find("|cffff80ff3|r", 1, true) ~= nil,
	AsksTab() and AsksTab().raw)
check("still one Cast button", #made == 1, #made)

---------------------------------------------------------------- plain
QUEUE = { count = 3, next = first, groups = {}, rest = { b1, b2 } }
Fire("QueueChanged")
L = Lines()
check("plain: the next, then one row per request", #L == 3 and L[1].name == "Sorella" and L[2].kind == "req" and L[2].name == "Brannoc"
	and L[2].spell == "Mark of the Wild" and L[2].time == "30s" and L[3].name == "Ayla" and L[3].time == "12s",
	#L .. " lines")
check("plain rows have no ask-click info", L[2] and L[2].line.info == nil)
Advance(75)
Refresh()
L = Lines()
check("waited time moves on a refresh", L[2] and L[2].time == "1m" and L[1].time == "1m", L[2] and L[2].time)

---------------------------------------------------------------- empty again, and back
QUEUE = { count = 0, next = nil, groups = {}, rest = {} }
Fire("QueueChanged")
check("emptied: 'No requests', no badge", CC.emptyLabel.__shown and Plain(CC.emptyLabel.__text) == "No requests" and AsksTab().text == "Asks")
check("emptied: no request rows", #Lines() == 0, #Lines())

---------------------------------------------------------------- CombatChanged redraws too
QUEUE = { count = 1, next = first, groups = {}, rest = {} }
Fire("CombatChanged", true)
L = Lines()
check("redraw on CombatChanged", #L == 1 and L[1].name == "Sorella", #L)

---------------------------------------------------------------- the main tab again
check("back to the main tab", ClickTab("all") and CC:PanelTab() == "all")
check("the Cast button hides off the Asks tab", made[1].__shown == false)
check("no request rows on the main tab", #(function() local n = {} for _, l in ipairs(Lines()) do if l.kind ~= "text" then n[#n + 1] = l end end return n end)() == 0)

---------------------------------------------------------------- combat: nothing protected, the change waits
local before = protectedCalls
COMBAT = true
FireEvent("PLAYER_REGEN_DISABLED")
ClickTab("asks")
Fire("QueueChanged")
Refresh()
check("combat: the Asks tab draws its rows", CC:PanelTab() == "asks" and #Lines() >= 1)
check("combat: the Cast button's Show waits", made[1].__shown == false and protectedCalls == before, protectedCalls - before)
QUEUE = { count = 2, next = first, groups = {}, rest = { b1 } }
Fire("QueueChanged")
Advance(1)
check("combat: redraws keep the button alone", protectedCalls == before and combatProtected == 0, protectedCalls - before)
COMBAT = false
FireEvent("PLAYER_REGEN_ENABLED")
check("out of combat: the deferred Show is applied", made[1].__shown == true, tostring(made[1].__shown))
check("exactly one Show was needed", protectedCalls == before + 1, protectedCalls - before)

-- leaving the tab in combat
before = protectedCalls
COMBAT = true
FireEvent("PLAYER_REGEN_DISABLED")
ClickTab("all")
Refresh()
check("combat: leaving the tab leaves the button as it is", made[1].__shown == true and protectedCalls == before)
COMBAT = false
FireEvent("PLAYER_REGEN_ENABLED")
check("out of combat: the Hide is applied", made[1].__shown == false and protectedCalls == before + 1, protectedCalls - before)

-- the button is created out of combat even when Second Wind appears in combat
check("one Cast button in all", #made == 1, #made)
check("no protected call in combat, ever", combatProtected == 0, combatProtected)
check("no Lua errors", #ERRORS == 0, ERRORS[1])

OUT(string.format("RESULT asks %s %s: checks %d, fails %d, lua errors %d", HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
