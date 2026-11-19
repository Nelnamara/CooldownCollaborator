-- CooldownCollaborator settings-lane checks for one TOC: Getting Started and the window list (on, lock,
-- reset), show presets and kinds (P2), per-spell ready alerts, rezzers to skip (P40), windows only in
-- combat or on boss fights (P30), lighter mode (P31) and the Goblin Sapper Charge row.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/settings.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[settings %s %s]", HARNESS_TOCFILE, FLAVOR))

local COMBAT = false
function UnitAffectingCombat() return COMBAT end

LoadTOC(HARNESS_TOCFILE)
for id, d in pairs(CC.SpellData) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
Login()
check("load and login: no Lua errors", #ERRORS == 0, ERRORS[1])
local db = CC.db

---------------------------------------------------------------- defaults, Sapper
check("new settings have defaults", db.showPreset == "everything" and db.showWindows == "always"
	and db.lighterMode == false and type(db.rezSkip) == "table" and db.spellGroupBy == "class")
local sapper = CC.SpellData[13241]
local hasSapper = FLAVOR == "era" or FLAVOR == "tbc" or FLAVOR == "forever"
check("Goblin Sapper Charge: a class-less Items row on Era, TBC and Forever only",
	hasSapper == (sapper ~= nil) and (not sapper or (sapper.class == "ITEMS" and sapper.duration == 300 and sapper.itemCooldown == true)))

---------------------------------------------------------------- the window list
local function window(key) for _, w in ipairs(CC.WINDOWS) do if w.key == key then return w end end end
check("seven windows listed", #CC.WINDOWS == 7)
CC:SetWindowOn(window("lanes"), true)
CC:SetWindowOn(window("burst"), true)
check("On sets the window's own setting", db.laneEnabled == true and db.burstEnabled == true and CC:WindowIsOn(window("burst")))
CC:SetWindowOn(window("burst"), false)
check("  and off again", db.burstEnabled == false and not CC:WindowIsOn(window("burst")))
CC:SetWindowOn(window("main"), false)
check("main panel: Off is closing it", db.panelClosed == true and not CC:WindowIsOn(window("main")))
CC:SetWindowOn(window("main"), true)
check("  and On opens it", db.panelClosed == false)
CC:SetOneWindowLocked(window("mana"), true)
check("Lock is per window", db.manaLocked == true and db.deadListLocked == false and not CC:AreWindowsLocked())
CC:SetWindowsLocked(true)
local all = true
for _, w in ipairs(CC.WINDOWS) do all = all and db[w.lockKey] == true end
check("the one Lock windows box locks all seven", all and CC:AreWindowsLocked())
CC:SetWindowsLocked(false)
db.laneX, db.laneY = 5, 6
CC:ResetWindow(window("lanes"))
check("Reset puts a window back where it starts", db.laneX == CC.DEFAULTS.laneX and db.laneY == CC.DEFAULTS.laneY)

---------------------------------------------------------------- presets
local function disabledCount()
	local n = 0
	for id, d in pairs(CC.SpellData) do
		if not d.consumable and db.disabledSpells[id] then n = n + 1 end
	end
	return n
end
CC:ApplyShowPreset("simple")
local ok = db.showPreset == "simple"
for id, d in pairs(CC.SpellData) do
	if not d.consumable and d.kind then
		local want = d.kind ~= "rez" and d.kind ~= "lust" and d.kind ~= "raid"
		if (db.disabledSpells[id] == true) ~= want then ok = false end
	end
end
check("Simple shows rez, lust and raid cooldowns only", ok)
CC:ApplyShowPreset("healer")
local externalOn, personalOff = true, true
for id, d in pairs(CC.SpellData) do
	if d.kind == "external" and db.disabledSpells[id] then externalOn = false end
	if d.kind == "personal" and not db.disabledSpells[id] then personalOff = false end
end
check("Healer adds externals and leaves personal defensives out", externalOn and personalOff)
CC:ApplyShowPreset("everything")
check("Everything shows all", disabledCount() == 0 and db.showPreset == "everything")
check("an unknown preset changes nothing", CC:ApplyShowPreset("nope") == false and db.showPreset == "everything")

---------------------------------------------------------------- alerts
local rez = CC.SpellByName["Rebirth"] or next(CC.SpellData)
CC:SetAlertEnabled(rez, true)
local cfg = CC:GetAlert(rez)
check("an alert starts with a sound and the row flash", cfg and cfg.sound == true and cfg.flash == true and cfg.midscreen == false and cfg.warn == 0)
CC:SetAlertField(rez, "midscreen", true); CC:SetAlertField(rez, "warn", 5); CC:SetAlertField(rez, "sound", CC.ALERT_SOUNDS[2].id)
check("  its fields are saved", cfg.midscreen == true and cfg.warn == 5 and CC:AlertSoundIndex(cfg) == 2)
check("  no alert, no fields", CC:SetAlertField(99999999, "flash", false) == false)
CC:SetAlertEnabled(rez, false)
check("  off removes it", CC:GetAlert(rez) == nil)

---------------------------------------------------------------- the window
local e0 = #ERRORS
CC:OpenOptions()
check("Settings opens on Getting Started with a card per window and the CooldownTimeline3 card",
	#ERRORS == e0 and CC.optionsFrame.page == 1 and CC.startPage ~= nil and CC.startPage:IsShown()
	and CC.startPage.cdtl3Card ~= nil)
CC.startPage.refresh()
CC:OpenAlertOptions(rez, nil)
CC:SetAlertEnabled(rez, true)
CC.alertFrame:Refresh()
db.spellGroupBy = "kind"
CC:RefreshDefaultSpellList()
db.spellGroupBy = "class"
CC:RefreshDefaultSpellList()
CC:SetRezSkip("Someone", "never")
check("the alert box, kind grouping and the skip list build with no Lua error", #ERRORS == e0, ERRORS[e0 + 1])
CC:SetRezSkip("Someone", nil)
CC:SetAlertEnabled(rez, false)
check("  a CooldownTimeline3 button asks for it only when loaded", CC:OpenCDTL3GroupSettings() == false)

---------------------------------------------------------------- rezzers to skip
do
	local realStatus = CC.GetCapabilityStatus
	local function entry(name) return { name = name .. "-Realm", ready = true, online = true, alive = true, spellID = 1 } end
	CC.GetCapabilityStatus = function() return { entry("Aaa"), entry("Bbb"), entry("Ccc") } end
	db.rezSkip = {}
	check("rezzers: the first ready one by default", CC:BestRezzer("Dead-Realm").name == "Aaa-Realm")
	db.rezSkip = { Aaa = "last" }
	check("  last choice goes behind the others", CC:BestRezzer("Dead-Realm").name == "Bbb-Realm")
	db.rezSkip = { Aaa = "never", ["Bbb-Realm"] = "never" }
	check("  never is passed over (short or full name)", CC:BestRezzer("Dead-Realm").name == "Ccc-Realm")
	CC.GetCapabilityStatus = function() return { entry("Aaa"), entry("Bbb") } end
	db.rezSkip = { Aaa = "last", Bbb = "never" }
	check("  last choice is used when nobody else can; never never is", CC:BestRezzer("Dead-Realm").name == "Aaa-Realm")
	db.rezSkip = { Aaa = "never", Bbb = "never" }
	check("  all never: nobody", CC:BestRezzer("Dead-Realm") == nil)
	CC.GetCapabilityStatus = realStatus
	db.rezSkip = {}
end

---------------------------------------------------------------- windows only in combat or on boss fights
GROUP = { { unit = "party1", name = "Aaa", realm = "Realm", class = "PRIEST", guid = "Player-1-0000002" } }
FireEvent("GROUP_ROSTER_UPDATE")
Advance(1)
db.essentialsEnabled, db.laneEnabled, db.panelClosed = true, true, false
local function shown() return CC.frame:IsShown(), CC.essentialsFrame:IsShown(), CC.laneFrame:IsShown() end
CC:RefreshAllViews()
local a, b, c = shown()
check("always: all three windows show in a group", a and b and c and CC:WindowsWanted())
db.showWindows = "combat"
CC:RefreshAllViews()
a, b, c = shown()
check("only in combat: hidden out of combat", not a and not b and not c and not CC:WindowsWanted())
FireEvent("PLAYER_REGEN_DISABLED")
a, b, c = shown()
check("  they show when combat starts", a and b and c and CC:WindowsWanted())
FireEvent("PLAYER_REGEN_ENABLED")
a, b, c = shown()
check("  and go when it ends", not a and not b and not c)
db.showWindows = "boss"
FireEvent("PLAYER_REGEN_DISABLED")
CC:RefreshAllViews()
check("only on boss fights: combat alone is not enough", not CC:WindowsWanted() and not CC.frame:IsShown())
FireEvent("ENCOUNTER_START", 1, "Boss", 1, 5)
a, b, c = shown()
check("  an encounter shows them", a and b and c and CC:WindowsWanted())
FireEvent("ENCOUNTER_END", 1, "Boss", 1, 5, 1)
a, b, c = shown()
check("  its end hides them", not a and not b and not c)
FireEvent("PLAYER_REGEN_ENABLED")
db.showWindows = "always"
CC:RefreshAllViews()
check("back to always: shown again", CC.frame:IsShown() and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown())
CC:ClosePanel()
CC:RefreshAllViews()
check("a panel the player closed stays shut", not CC.frame:IsShown())
db.panelClosed = false
CC:RefreshAllViews()

---------------------------------------------------------------- lighter mode
do
	local rows, lanes = 0, 0
	local realRows, realLanes = CC.RefreshRows, CC.RefreshLanes
	CC.RefreshRows = function(self) rows = rows + 1; return realRows(self) end
	CC.RefreshLanes = function(self) lanes = lanes + 1; return realLanes(self) end
	db.lighterMode = false
	Advance(10)
	local rowsNormal, lanesNormal = rows, lanes
	rows, lanes = 0, 0
	db.lighterMode = true
	Advance(10)
	local rowsLight, lanesLight = rows, lanes
	check("lighter mode slows the panel (0.5 s to 1 s) and the Lane view (0.2 s to 0.5 s)",
		rowsLight < rowsNormal * 0.6 and rowsLight >= 8 and lanesLight < lanesNormal * 0.6 and lanesLight >= 15,
		string.format("panel %d -> %d, lanes %d -> %d", rowsNormal, rowsLight, lanesNormal, lanesLight))
	check("  the rates are readable", CC:TickRate("panel") == 1 and CC:TickRate("lanes") == 0.5)
	local p0 = #PRINTS
	SlashCmdList["COOLDOWNCOLLABORATOR"]("debug")
	local said = false
	for i = p0 + 1, #PRINTS do if tostring(PRINTS[i]):find("Lighter mode: on", 1, true) then said = true end end
	check("  /cdc debug prints them", said)
	db.lighterMode = false
	CC.RefreshRows, CC.RefreshLanes = realRows, realLanes
	check("  normal again", CC:TickRate("panel") == 0.5 and CC:TickRate("lanes") == 0.2)
end

check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT settings %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
