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
local BUTTONS = {}   -- every button the window builds, to check its words fit
do
	local realCreate = CreateFrame
	function CreateFrame(otype, ...)
		local f = realCreate(otype, ...)
		if otype == "Button" then BUTTONS[#BUTTONS + 1] = f end
		return f
	end
end
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

do
	local tight = {}
	for _, b in ipairs(BUTTONS) do
		local t = b.__text
		if type(t) == "string" and t ~= "" and b:GetWidth() > 0 and #t * 6 + 12 > b:GetWidth() then
			tight[#tight + 1] = t .. " (" .. b:GetWidth() .. ")"
		end
	end
	check("no button's words are wider than the button", #BUTTONS > 20 and #tight == 0, table.concat(tight, ", "))
end

---------------------------------------------------------------- the dropdown and the sound list
do
	local e2 = #ERRORS
	CC:SetAlertEnabled(rez, true)
	CC:OpenAlertOptions(rez, nil)
	local af = CC.alertFrame
	local list = CC:AlertSoundList()
	check("sound list: the four first, in order, then Blizzard's file sounds",
		#list > #CC.ALERT_SOUNDS + 10 and list[1].value == CC.ALERT_SOUNDS[1].id and list[4].value == CC.ALERT_SOUNDS[4].id
		and tostring(list[5].value):match("^file:%d+$") ~= nil)
	local dupe = false
	for _, it in ipairs(list) do if it.value == "file:567397" or it.value == "file:567399" then dupe = true end end
	check("  none repeats one of the four", not dupe)
	check("  no other addon's sounds without LibSharedMedia", list[#list].value:match("^lsm:") == nil)
	af.soundBtn:GetScript("OnClick")(af.soundBtn)
	local dd = CC.dropdown
	check("dropdown: a click opens the list under the button, one row per sound",
		dd and dd:IsShown() and dd.catcher:IsShown() and dd.n == #list and dd.rows[1].value == list[1].value and dd.rows[#list].value == list[#list].value)
	check("  the first sound is shown for an alert saved as true", af.soundBtn.__text == CC.ALERT_SOUNDS[1].label, af.soundBtn.__text)
	dd.rows[6]:GetScript("OnClick")(dd.rows[6])
	check("  picking saves it, shows it and closes the list", CC:GetAlert(rez).sound == list[6].value
		and not dd:IsShown() and not dd.catcher:IsShown() and af.soundBtn.__text == list[6].label)
	af.soundBtn:GetScript("OnClick")(af.soundBtn)
	dd:GetScript("OnKeyDown")(dd, "ESCAPE")
	check("  Escape closes it", not dd:IsShown())
	af.soundBtn:GetScript("OnClick")(af.soundBtn)
	dd.catcher:GetScript("OnClick")(dd.catcher)
	check("  so does a click elsewhere", not dd:IsShown())
	af.soundBtn:GetScript("OnClick")(af.soundBtn)
	af.soundBtn:GetScript("OnClick")(af.soundBtn)
	check("  and a second click on the button", not dd:IsShown())
	-- saves from before the dropdown keep their sound
	local function heard(sound)
		CC:SetAlertField(rez, "sound", sound)
		SOUNDS = {}
		CC:FireReadyAlert("Someone-Realm", rez)
		return SOUNDS[1]
	end
	local h = heard(8960)
	check("old saves: a SoundKit number plays as before", h and h.id == 8960 and h.channel == "Master")
	h = heard(true)
	check("  true is still the raid warning", h and h.id == CC.ALERT_SOUNDS[1].id)
	h = heard("Interface\\AddOns\\Some\\ding.ogg")
	check("  a file path still plays as a file", h and h.file == "Interface\\AddOns\\Some\\ding.ogg")
	h = heard("file:567488")
	check("  a Blizzard file sound plays by its file ID", h and h.file == 567488)
	CC:SetAlertField(rez, "sound", 8960)
	af:Refresh()
	check("  an old number shows its name in the box", af.soundBtn.__text == CC.ALERT_SOUNDS[2].label, af.soundBtn.__text)
	SOUNDS = {}
	af.testBtn:GetScript("OnClick")(af.testBtn)
	check("  Test plays what is picked", SOUNDS[1] and SOUNDS[1].id == 8960)
	-- another addon's sounds
	local lsmSounds = { None = "", ["Bell Ding"] = "Interface\\AddOns\\Other\\bell.ogg", ["Blizzard: Queue Pop"] = 568011 }
	LibStub = setmetatable({}, { __call = function(_, name, silent)
		if name ~= "LibSharedMedia-3.0" then return nil end
		return {
			List = function() return { "Bell Ding", "Blizzard: Queue Pop", "None" } end,
			Fetch = function(_, kind, key) return lsmSounds[key] end,
		}
	end })
	local withLSM = CC:AlertSoundList()
	check("LibSharedMedia loaded: its sounds follow Blizzard's, without None or what is already listed",
		withLSM[#withLSM].value == "lsm:Bell Ding" and #withLSM == #list + 1, #withLSM)
	h = heard("lsm:Bell Ding")
	check("  and one plays from its registered path", h and h.file == "Interface\\AddOns\\Other\\bell.ogg")
	LibStub = nil
	h = heard("lsm:Bell Ding")
	check("  with the library gone it is silent, no error", h == nil and #ERRORS == e2, ERRORS[e2 + 1])
	CC:SetAlertEnabled(rez, false)
end

---------------------------------------------------------------- your role, the kinds, a reopened window
do
	local e5 = #ERRORS
	CC:ApplyShowPreset("everything")
	local cards = CC.roleCards
	local names = {}
	for _, c in ipairs(cards) do names[#names + 1] = c.key end
	check("role cards: Everything, Basics, Healer, Tank, DPS and My own", table.concat(names, ",") == "everything,simple,healer,tank,dps,custom"
		and CC.PRESETS.simple.label == "Basics" and CC.PRESETS.simple.desc == "Battle rez, lust and raid cooldowns")
	local function picked() local p = {} for _, c in ipairs(cards) do if c.picked then p[#p + 1] = c.key end end return table.concat(p, ",") end
	check("  the picked one has the gold edge", picked() == "everything")
	cards[3]:GetScript("OnClick")(cards[3])
	check("  clicking a card picks that role", db.showPreset == "healer" and picked() == "healer")
	check("  My own cannot be clicked", cards[6]:GetScript("OnClick") == nil)
	local kinds = CC:KindsPresent()
	check("kinds: folded by default, one tick for each kind this client has spells of",
		#kinds >= 3 and #CC.kindChecks == #kinds and CC.kindChecks[1].cb:IsShown() == false)
	local absent = true
	for _, k in ipairs({ "rez", "lust", "raid", "external", "mana", "personal", "utility" }) do
		local has = false
		for _, d in pairs(CC.SpellData) do if d.kind == k and not d.custom and not d.consumable then has = true end end
		local ticked = false
		for _, kc in ipairs(CC.kindChecks) do if kc.kind == k then ticked = true end end
		if has ~= ticked then absent = false end
	end
	check("  a kind with no spells on this client has no tick", absent)
	CC.kindsToggle:GetScript("OnClick")(CC.kindsToggle)
	check("  the small button opens them", CC.kindChecks[1].cb:IsShown() == true and CC.kindsToggle.__text:find("Kinds of spells", 1, true) ~= nil)
	local kind = kinds[#kinds]
	local ticks = CC.kindChecks[#CC.kindChecks]
	CC:ApplyShowPreset("everything")
	check("  a tick is on while every spell of its kind is", ticks.kind == kind and CC:KindIsShown(kind))
	CC:SetKindShown(kind, false)
	local allOff, others = true, false
	for id, d in pairs(CC.SpellData) do
		if not d.custom and not d.consumable then
			if d.kind == kind and not db.disabledSpells[id] then allOff = false end
			if d.kind ~= kind and not db.disabledSpells[id] then others = true end
		end
	end
	check("  unticking switches every spell of the kind off and makes the role My own",
		allOff and others and db.showPreset == "custom" and picked() == "custom" and not CC:KindIsShown(kind))
	CC:SetKindShown(kind, true)
	check("  ticking switches them back on", CC:KindIsShown(kind) and db.showPreset == "custom")
	CC.kindsToggle:GetScript("OnClick")(CC.kindsToggle)
	CC:ApplyShowPreset("everything")
	check("  and Your role works with no Lua error", #ERRORS == e5, ERRORS[e5 + 1])
	-- reopening the window shows what is set now
	db.guildSync = true
	db.alpha, db.showReady = 0.4, false
	CC.optionsFrame:GetScript("OnShow")(CC.optionsFrame)
	check("a reopened window shows what is set now (the guild tick, the opacity slider)",
		CC.guildCheck:GetChecked() == true and CC.optionsFrame.page ~= nil, tostring(CC.guildCheck:GetChecked()))
	db.guildSync, db.alpha, db.showReady = false, 0.9, true
	CC.optionsFrame:GetScript("OnShow")(CC.optionsFrame)
	check("  and again when it changes back", CC.guildCheck:GetChecked() == false)
end

---------------------------------------------------------------- the speaker
do
	local e3 = #ERRORS
	db.spellGroupBy = "class"
	CC:RefreshDefaultSpellList()
	local tid = next(CC.SpellData)
	for id, d in pairs(CC.SpellData) do if not d.custom and not d.consumable then tid = id break end end
	CC:SetAlertEnabled(tid, false)
	CC:RefreshDefaultSpellList()
	local icons = {}
	for _, b in ipairs(BUTTONS) do if b.icon then icons[#icons + 1] = b.icon end end
	local last = icons[#icons]
	check("speaker: a spell with no alert shows the speaker, grey", last and last.__tex and last.__tex:find("speaker%-off%.tga$")
		and last.__vertex and last.__vertex[1] == last.__vertex[2])
	local f = io.open and io.open("Media/speaker-on.tga", "rb")
	if f then
		local d = f:read("*a"); f:close()
		check("  the textures are 32 by 32 uncompressed 32-bit TGAs", #d == 18 + 32 * 32 * 4 and d:byte(3) == 2 and d:byte(17) == 32)
	end
	CC:SetAlertEnabled(tid, true)
	local anyOn = false
	for _, b in ipairs(BUTTONS) do
		if b.icon and b.icon.__tex and b.icon.__tex:find("speaker%-on%.tga$") and b.icon.__vertex[1] == 1 and b.icon.__vertex[3] == 0 then anyOn = true end
	end
	check("  setting an alert turns its speaker on and gold", anyOn)
	CC:SetAlertEnabled(tid, false)
	check("  and off again", #ERRORS == e3, ERRORS[e3 + 1])
end

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
CC.panelForced = nil   -- (opening the panel by hand earlier set it; the next combat change clears it)
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

---------------------------------------------------------------- editors
do
	local e1 = #ERRORS
	local rb = CC.SpellByName["Rebirth"]
	local ok, n, skipped = CC:SavePlan("Boss1", {
		{ trigger = "Bomb 2", player = "Aaa", spell = "Rebirth" },
		{ trigger = "1:30", player = "Bbb", spell = tostring(rb) },
		{ trigger = "", player = "", spell = "" },
		{ trigger = "45", player = "", spell = "Rebirth" },
	})
	local plan = db.plans.Boss1
	check("plan editor: timer text and 1:30 rows saved, an empty row ignored, a partial one skipped",
		ok and n == 2 and skipped == 1 and plan.rows[1].timer == "Bomb 2" and plan.rows[2].at == 90
		and plan.rows[2].spellID == rb and plan.rows[1].player:find("Aaa", 1, true) == 1)
	local back = CC:PlanInputsFromRows(plan.rows)
	check("  and shows again as typed", back[1].trigger == "Bomb 2" and back[2].trigger == "1:30" and back[2].spell == "Rebirth")
	check("  Share is Plan.lua's SharePlan", type(CC.SharePlan) == "function" and CC.db.plans.Boss1 ~= nil)
	local ok2, sid = CC:SaveRotationFromText("Rebirth", "Aaa, Bbb\nCcc")
	check("rotation editor: a spell and its players in order", ok2 and sid == rb and #db.rotations[rb] == 3
		and db.rotations[rb][3]:find("Ccc", 1, true) == 1 and CC.rotations[rb] ~= nil)
	CC:SaveRotationFromText("Rebirth", "")
	check("  an empty order clears it", db.rotations[rb] == nil)
	CC:SaveTeam("Healers", { "Aaa", " Bbb ", "" })
	check("teams editor: saved with its members, and the panel can pick it",
		#db.teams.Healers == 2 and db.teams.Healers[2] == "Bbb" and CC:TeamNames()[1] == "Healers")
	CC:SetPanelTab("team:Healers")
	check("  the team tab reads it", CC:PanelTab() == "team:Healers")
	CC:RemoveTeam("Healers")
	check("  removed: back to All", CC:PanelTab() == "all" and CC:RemoveTeam("Healers") == false)
	check("the editors raise no Lua error", #ERRORS == e1, ERRORS[e1 + 1])
end

---------------------------------------------------------------- setups and profiles
do
	local rb = CC.SpellByName["Rebirth"]
	SPELLINFO[777002] = { "Odd Spell", 5 }
	CC:AddCustomSpell(777002, 90)
	db.disabledSpells[rb] = true
	CC:SetAlertEnabled(rb, true); CC:SetAlertField(rb, "warn", 7); CC:SetAlertField(rb, "sound", 8960)
	db.laneX, db.laneY = 123, -45
	local text = CC:ExportSetup("Mine")
	local setup, name = CC:DecodeSetup(text)
	check("export: a setup survives its text", setup and name == "Mine" and setup.disabled[1] ~= nil
		and setup.custom[777002] and setup.custom[777002].duration == 90 and setup.alerts[rb].warn == 7
		and setup.alerts[rb].sound == 8960 and setup.places.lanes[1] == 123 and setup.places.lanes[2] == -45)
	check("  text that is not a setup is refused", CC:DecodeSetup("hello") == nil and CC:DecodeSetup(nil) == nil
		and CC:DecodeSetup("1;k=plan;n=x") == nil and CC:DecodeSetup("2;k=setup") == nil)
	local bad = CC:DecodeSetup("1;k=setup;c=5,x,99999999,1;w=lanes,999999,1;a=abc,t,1,0,0")
	check("  out of range numbers are dropped", bad and next(bad.custom) == nil and next(bad.places) == nil and next(bad.alerts) == nil)
	-- change things, then import
	db.disabledSpells = {}
	CC:RemoveCustomSpell(777002)
	CC:SetAlertEnabled(rb, false)
	db.laneX, db.laneY = 0, 0
	local lines = CC:DescribeSetup(setup)
	check("import shows what it will change", #lines >= 3 and lines[1]:find("%d") ~= nil, table.concat(lines, " | "))
	CC:ApplySetup(setup)
	check("  applying brings it all back", db.disabledSpells[rb] == true and db.customSpells["777002"] ~= nil
		and CC.SpellData[777002] ~= nil and CC:GetAlert(rb) and CC:GetAlert(rb).warn == 7 and db.laneX == 123)
	check("  and the same setup then changes nothing", CC:DescribeSetup(setup)[1]:find("Nothing changes", 1, true) ~= nil)
	check("  undo puts back what was there", CC:UndoSetup() and db.disabledSpells[rb] == nil and db.customSpells["777002"] == nil
		and CC:GetAlert(rb) == nil and db.laneX == 0 and CC:UndoSetup() == false)
	-- profiles (Ace style: Default always there, New / Copy from / Reset / Delete)
	CC:ApplySetup(setup, { noUndo = true })
	check("profiles: Default always exists and this character follows it",
		CC:ProfileNames()[1] == "Default" and CC:CurrentProfile() == "Default" and #CC:ProfileNames() == 1)
	db.alpha, db.minDuration, db.showWindows, db.lighterMode, db.panelStyle = 0.5, 120, "combat", true, "icons"
	db.guildSync, db.setupFrom = true, "any"
	check("  New makes a profile with default settings and switches to it", CC:NewProfile("Raid") == true
		and CC:CurrentProfile() == "Raid" and db.alpha == CC.DEFAULTS.alpha and db.minDuration == CC.DEFAULTS.minDuration
		and db.showWindows == "always" and db.lighterMode == false and db.panelStyle == "text"
		and next(db.disabledSpells) == nil and next(db.alerts) == nil and next(db.customSpells) == nil
		and CC.SpellData[777002] == nil and db.laneX == CC.DEFAULTS.laneX)
	check("  the one left is kept as it was", db.profiles.Default.alpha == 0.5 and db.profiles.Default.minDuration == 120
		and db.profiles.Default.custom == nil and db.profiles.Default.customSpells["777002"] ~= nil
		and db.profiles.Default.places.lanes[1] == 123)
	check("  guild sharing and accept setups from stay shared by every profile", db.guildSync == true and db.setupFrom == "any")
	check("  a name already there, or an empty one, makes nothing",
		CC:NewProfile("Raid") == false and CC:NewProfile("   ") == false and #CC:ProfileNames() == 2)
	db.alpha = 0.7; db.laneX = 11
	check("  switching applies a profile's settings", CC:UseProfile("Default") and db.alpha == 0.5 and db.minDuration == 120
		and db.showWindows == "combat" and db.lighterMode == true and CC.SpellData[777002] ~= nil
		and db.disabledSpells[rb] == true and db.laneX == 123 and CC:GetAlert(rb) and CC:GetAlert(rb).warn == 7)
	check("  and the profile left behind keeps its own", db.profiles.Raid.alpha == 0.7 and db.profiles.Raid.places.lanes[1] == 11)
	check("  Copy from puts another profile's settings into this one",
		CC:CopyProfile("Raid") and db.alpha == 0.7 and CC.SpellData[777002] == nil and CC:CurrentProfile() == "Default"
		and CC:CopyProfile("Default") == false and CC:CopyProfile("Nope") == false)
	db.alpha = 0.3
	check("  Reset Profile sends the one in use back to the defaults", CC:ResetProfile() and db.alpha == CC.DEFAULTS.alpha
		and db.minDuration == 60 and CC:CurrentProfile() == "Default" and db.profiles.Raid.alpha == 0.7)
	check("  the profile in use is never deleted, nor is Default",
		CC:DeleteProfile("Default") == false and CC:UseProfile("Raid") and CC:DeleteProfile("Raid") == false
		and CC:DeleteProfile("Default") == false)
	CC:UseProfile("Default")
	db.charProfile["Other-Realm"] = "Raid"
	check("  deleting one lets go of everyone who followed it", CC:DeleteProfile("Raid") and CC:DeleteProfile("Raid") == false
		and db.charProfile["Other-Realm"] == nil and #CC:ProfileNames() == 1)
	-- login, window places
	db.alpha, db.laneX = 0.4, 5
	CC:ApplyCharacterProfile()
	check("  login puts the profile in place", db.alpha == CC.DEFAULTS.alpha and db.laneX == CC.DEFAULTS.laneX)
	CC:SetKeepOwnPlaces(true)
	db.laneX = 77
	CC:NewProfile("Healing")
	CC:SaveCurrentProfile()
	CC:ApplyCharacterProfile()
	check("  a character keeping its own places keeps them over any profile's", db.laneX == 77 and CC:CurrentProfile() == "Healing")
	CC:SetKeepOwnPlaces(false)
	db.laneX = 0
	-- the Profiles page
	local e4 = #ERRORS
	CC:OpenOptions()
	local cur = CC.profileDrops.current
	cur:GetScript("OnClick")(cur)
	check("  the Current profile dropdown lists them, the current one shown",
		CC.dropdown:IsShown() and CC.dropdown.n == 2 and cur.__text == "Healing", cur.__text)
	local pick
	for i = 1, CC.dropdown.n do if CC.dropdown.rows[i].value == "Default" then pick = CC.dropdown.rows[i] end end
	pick:GetScript("OnClick")(pick)
	check("  picking Default switches to it", CC:CurrentProfile() == "Default" and cur.__text == "Default" and not CC.dropdown:IsShown())
	local box = CC.profileNewBox
	box:SetText("Tanking")
	box:GetScript("OnEnterPressed")(box)
	check("  New: Enter makes it, switches to it and empties the box", CC:CurrentProfile() == "Tanking" and box:GetText() == "")
	local del = CC.profileDrops.delete
	del:GetScript("OnClick")(del)
	check("  Delete lists neither the current profile nor Default", CC.dropdown.n == 1 and CC.dropdown.rows[1].value == "Healing")
	CC.dropdown.rows[1]:GetScript("OnClick")(CC.dropdown.rows[1])
	local cp = CC.profileDrops.copy
	cp:GetScript("OnClick")(cp)
	check("  Copy from lists the others; Healing is gone", CC.dropdown.n == 1 and CC.dropdown.rows[1].value == "Default")
	CC.dropdown.catcher:GetScript("OnClick")(CC.dropdown.catcher)
	check("  the Profiles page works with no Lua error", #ERRORS == e4, ERRORS[e4 + 1])
	CC:UseProfile("Default")
	CC:DeleteProfile("Tanking")
	db.guildSync, db.setupFrom = false, "officers"
	CC:ApplyShowPreset("everything")
	CC:ApplySetup({ disabled = {}, custom = {}, alerts = {}, places = {} }, { noUndo = true })
	CC:ResetWindow(window("lanes"))
end

---------------------------------------------------------------- officer setups
do
	local rb = CC.SpellByName["Rebirth"]
	local setup = CC:DecodeSetup(CC:ExportSetup("Guild"))
	setup.disabled = { rb }
	local text = CC:EncodeSetup(setup, "Guild")
	check("officer setup: only an officer sends", CC:IsOfficer() == false and CC:SendOfficerSetup() == false)
	STUB_IN_GUILD = true
	C_GuildInfo = { CanEditOfficerNote = function() return true end }
	local s0 = #SENT
	check("  an officer's goes out on the guild channel, guild sharing off or not",
		db.guildSync == false and CC:SendOfficerSetup() == true)
	Advance(10)
	local parts, guild = 0, true
	for i = s0 + 1, #SENT do
		if SENT[i].msg:match("^O:2:s%d+:%d+/%d+:") then
			parts = parts + 1
			if SENT[i].channel ~= "GUILD" or #SENT[i].msg > 255 then guild = false end
		end
	end
	check("  in parts under 255 bytes", parts >= 1 and guild, parts)
	C_GuildInfo = nil
	-- receiving
	local sender = "Boss-Realm"
	CC.payloads.O[sender] = { s1 = { data = text, at = GetTime() } }
	db.guildSync, db.setupFrom = true, "any"   -- (the rank and sharing rules are in final.lua)
	local function OfferSetup() CC.setupShownAt = {}; CC:OnOfficerSetup(sender, "s1") end
	local e1 = #ERRORS
	OfferSetup()
	check("  a member gets a dialog naming the sender", CC.pendingSetup and CC.pendingSetup.owner == sender
		and CC.setupDialog and CC.setupDialog:IsShown() and CC.setupDialog.text.__text:find("Boss", 1, true) ~= nil)
	check("  and their guild rank is not shown while the roster lacks it", CC.pendingSetup.rank == nil)
	CC:AnswerSetup("later")
	GetNumGuildMembers = function() return 2 end
	GetGuildRosterInfo = function(i)
		if i == 1 then return "Other-Realm", "Member", 3 end
		return "Boss-Realm", "Officer", 1
	end
	OfferSetup()
	check("  with the rank name once the roster has it", CC.pendingSetup.rank == "Officer"
		and CC.setupDialog.text.__text:find("Boss (Officer) sent", 1, true) ~= nil, CC.setupDialog.text.__text)
	GetNumGuildMembers, GetGuildRosterInfo = nil, nil
	CC:AnswerSetup("later")
	check("  Not now closes it and changes nothing", not CC.setupDialog:IsShown() and not db.disabledSpells[rb])
	OfferSetup()
	CC:AnswerSetup("accept")
	check("  Accept applies it", db.disabledSpells[rb] == true)
	check("  and Undo takes it back", CC:UndoSetup() and not db.disabledSpells[rb])
	OfferSetup()
	CC:AnswerSetup("never")
	OfferSetup()
	check("  Never silences that person", CC.pendingSetup == nil and db.setupNever[sender] == true)
	db.setupNever = {}
	STUB_IN_GUILD = false
	db.guildSync, db.setupFrom = false, "officers"
	check("officer setup code raises no Lua error", #ERRORS == e1, ERRORS[e1 + 1])
end

---------------------------------------------------------------- layouts
do
	STUB_IN_RAID = false
	GROUP = { { unit = "party1", name = "Aaa", realm = "Realm", class = "DRUID", guid = "Player-1-0000002" } }
	FireEvent("GROUP_ROSTER_UPDATE")
	db.laneX, db.laneY = 10, 20
	STUB_IN_RAID = true
	FireEvent("GROUP_ROSTER_UPDATE")
	check("layouts: leaving a party for a raid saves the party's places", db.layouts.party and db.layouts.party.lanes[1] == 10)
	db.laneX, db.laneY = 300, 400
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
	check("  and going back brings them back, the raid's kept for later",
		db.laneX == 10 and db.laneY == 20 and db.layouts.raid.lanes[1] == 300)
	STUB_IN_RAID = true
	FireEvent("GROUP_ROSTER_UPDATE")
	check("  and the raid's likewise", db.laneX == 300)
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
	CC:ResetAllWindows()
	check("Reset all windows: every window home, layouts forgotten",
		db.laneX == CC.DEFAULTS.laneX and db.deadListX == CC.DEFAULTS.deadListX and next(db.layouts) == nil)
end

---------------------------------------------------------------- last pull, post, key start, support
do
	local rb = CC.SpellByName["Rebirth"]
	GROUP = { { unit = "party1", name = "Aaa", realm = "Realm", class = "DRUID", guid = "Player-1-0000002" } }
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(1)
	db.lastPullOffer = true
	local p0 = #PRINTS
	FireEvent("PLAYER_REGEN_DISABLED")
	Advance(30)
	CC:RecordCooldownFromComm("Aaa-Realm", rb, GetTime() - 1, "DRUID")
	CC:RecordCooldownFromComm("Aaa-Realm", rb, GetTime() - 1, "DRUID")
	FireEvent("ENCOUNTER_START", 1, "Boss", 1, 5)
	Advance(10)
	FireEvent("ENCOUNTER_END", 1, "Boss", 1, 5, 0)
	FireEvent("PLAYER_REGEN_ENABLED")
	local lines = CC:PullLines()
	check("last pull: one tracked use logged with the time into the fight and who", #lines == 1
		and lines[1]:find("Aaa", 1, true) and lines[1]:find("Rebirth", 1, true) and CC.lastPull.boss == "Boss"
		and CC.lastPull.success == false, lines[1])
	local offered = false
	for i = p0 + 1, #PRINTS do if tostring(PRINTS[i]):find("wipe", 1, true) then offered = true end end
	check("  offered after a wipe when the setting is on", offered)
	local p1 = #PRINTS
	SlashCmdList["COOLDOWNCOLLABORATOR"]("lastpull")
	check("  /cdc lastpull prints it", #PRINTS > p1)
	db.lastPullOffer = false

	-- post
	local postLines = CC:PostLines()
	local found = false
	for _, l in ipairs(postLines) do if l:find("Rebirth", 1, true) and l:find("Aaa", 1, true) then found = true end end
	check("post: a line per picked spell with who has it and when it is back", found, postLines[1])
	local c0 = #CHATSENT
	SlashCmdList["COOLDOWNCOLLABORATOR"]("post")
	db.postSpells = { [rb] = true }
	check("  picked spells only", #CC:PostSpellIDs() == 1 and CC:PostSpellIDs()[1] == rb)
	db.postSpells = {}

	-- key start
	CC:RecordCooldownFromComm("Aaa-Realm", rb, GetTime() - 1, "DRUID")
	check("key start: a running timer to start with", CC.state["Aaa-Realm"] and CC.state["Aaa-Realm"].spells[rb] ~= nil)
	CC.state["Gone-Realm"] = { class = "DRUID", spells = { [rb] = GetTime() - 1 } }
	local s0 = #SENT
	local e1 = #ERRORS
	pcall(FireEvent, "CHALLENGE_MODE_START")
	Advance(6)
	local asked = false
	for i = s0 + 1, #SENT do if SENT[i].msg == "Q:2" then asked = true end end
	check("  a key start drops players who left and keeps timers (the game's resets come from their own clients)",
		CC.state["Gone-Realm"] == nil and CC.state["Aaa-Realm"] and CC.state["Aaa-Realm"].spells[rb] ~= nil and #ERRORS == e1)
	check("  and asks the group for its state", asked)
	db.resetOnNewRun = false
	s0 = #SENT
	pcall(FireEvent, "CHALLENGE_MODE_START")
	Advance(6)
	asked = false
	for i = s0 + 1, #SENT do if SENT[i].msg == "Q:2" then asked = true end end
	check("  the setting turns it off", not asked)
	db.resetOnNewRun = true

	-- /cdc report
	CC:ApplyShowPreset("everything")
	CC.sendErrors = {}
	CC:NoteSendError(8)
	local text = CC:ReportText()
	local clientName = ({ retail = "Retail", mop = "MoP Classic", tbc = "TBC Anniversary", era = "Classic Era", forever = "WoW: Forever" })[FLAVOR]
	check("report: version and client, group, who answered, what is tracked, refused messages",
		text:find("CooldownCollaborator " .. CC.version .. " on " .. clientName, 1, true)
		and text:find("In a party of %d+%.") and text:find("Heard from", 1, true)
		and text:find("Tracking: Everything, no spells changed", 1, true)
		and text:find("Messages the game refused lately: 8 at", 1, true), text)
	local realKind, realPeers = CC.GroupKind, CC.peers
	CC.GroupKind = function() return nil end
	CC.peers = {}
	local rb = CC.SpellByName["Rebirth"]
	CC:ApplyShowPreset("healer")
	db.disabledSpells[rb] = true
	CC.sendErrors = {}
	text = CC:ReportText()
	check("  solo, nobody heard, a role with one spell unticked, nothing refused",
		text:find("Not in a group.", 1, true) and text:find("Heard from nobody.", 1, true)
		and text:find("Tracking: Healer, minus 1 spells you changed", 1, true)
		and text:find("Messages the game refused lately: none", 1, true), text)
	CC.GroupKind, CC.peers = realKind, realPeers
	CC:ApplyShowPreset("everything")
	local box = CC:ShowReport()
	check("  /cdc report's box is titled Report a problem and says where to paste it", box:IsShown()
		and box.title.__text == "Report a problem" and box.note.__text:find("github.com/Nelnamara/CooldownCollaborator/issues", 1, true) ~= nil
		and box.edit.__text == CC:ReportText())
	box:Hide()
	SlashCmdList["COOLDOWNCOLLABORATOR"]("report")
	check("  the slash word opens it", CC.copyBox:IsShown())
	CC.copyBox:Hide()
	SlashCmdList["COOLDOWNCOLLABORATOR"]("support")
	check("  and /cdc support is gone", not CC.copyBox:IsShown())
end

---------------------------------------------------------------- the public feed
do
	local rb = CC.SpellByName["Rebirth"]
	local starts, readies, ends = {}, {}, {}
	local listener = {}
	check("API: a listener registers", CC.API.RegisterCallback(listener, "start", function(...) starts[#starts + 1] = { ... } end)
		and CC.API.RegisterCallback(listener, "ready", function(...) readies[#readies + 1] = { ... } end)
		and CC.API.RegisterCallback(listener, "end", function(...) ends[#ends + 1] = { ... } end)
		and not CC.API.RegisterCallback(listener, "nonsense", function() end))
	Advance(6)
	CC.state["Aaa-Realm"] = nil
	local dur = CC.SpellData[rb].duration
	CC:RecordCooldownFromComm("Aaa-Realm", rb, GetTime() - dur + 3, "DRUID")
	check("  a cooldown starting reaches it, once", #starts == 1 and starts[1][1] == "Aaa-Realm" and starts[1][2] == rb
		and starts[1][3] == dur)
	local rem = CC.API.GetCooldown("Aaa-Realm", rb)
	local listed = false
	for _, m in ipairs(CC.API.GetGroup()) do
		if m.name == "Aaa-Realm" then
			for _, sp in ipairs(m.spells) do if sp.spellID == rb and sp.remaining ~= nil and sp.ready == false then listed = true end end
		end
	end
	check("  who has what and when it is back", rem ~= nil and rem <= 3.1 and rem > 0 and listed)
	Advance(5)
	check("  it is told when the cooldown is back", #readies == 1 and readies[1][1] == "Aaa-Realm" and readies[1][2] == rb)
	FireEvent("PLAYER_REGEN_DISABLED")
	FireEvent("PLAYER_REGEN_ENABLED")
	check("  and when a fight ends", #ends >= 1)
	CC.API.UnregisterCallback(listener, "start")
	Advance(6)
	CC:RecordCooldownFromComm("Aaa-Realm", rb, GetTime() - dur + 100, "DRUID")
	check("  unregistered, it hears nothing more", #starts == 1)
end

check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT settings %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
