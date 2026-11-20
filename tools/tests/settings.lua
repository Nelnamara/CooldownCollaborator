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
-- 1.1.1's saved variables from a copy whose windows were never moved (the main panel's place goes through
-- GetCenter at each logout), as the owner's review install found them on 19 Nov
CooldownCollaboratorDB = { x = 0.0, y = 200.0, scale = 1, essentialsX = 220, essentialsY = 200, essentialsScale = 1,
	laneX = 0, laneY = -200, laneScale = 1, laneEnabled = false, customSpells = {}, disabledSpells = {}, consumableBuffs = {} }
Login()
check("load and login: no Lua errors", #ERRORS == 0, ERRORS[1])
local db = CC.db

---------------------------------------------------------------- the three main windows over a 1.1.1 save
-- Screen rects in UIParent units at UI scale 1 (the stub's geometry: tools/tests/wow.lua).
local BLOCK = { "essentialsFrame", "frame", "laneFrame" }
local function rect(f) return STUB_RECT(f) end
local function overlaps(a, b) return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5 end
-- the first pair of the shown three that lie on each other, as text, or nil
local function onEachOther()
	for i = 1, #BLOCK do
		for j = i + 1, #BLOCK do
			local a, b = CC[BLOCK[i]], CC[BLOCK[j]]
			if a:IsShown() and b:IsShown() and overlaps(rect(a), rect(b)) then
				local ra, rb = rect(a), rect(b)
				return string.format("%s [%.0f %.0f %.0f %.0f] on %s [%.0f %.0f %.0f %.0f]", BLOCK[i], ra[1], ra[2], ra[3], ra[4],
					BLOCK[j], rb[1], rb[2], rb[3], rb[4])
			end
		end
	end
end
do
	GROUP = { { unit = "party1", name = "Tania", realm = "Realm", class = "PRIEST", guid = "Player-1-0000009" } }
	db.laneEnabled = true
	FireEvent("GROUP_ROSTER_UPDATE")
	Advance(1)
	check("1.1.1 save, party of two: the panel, the Essentials bar and the Lane view all show",
		CC.frame:IsShown() and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown())
	local hit = onEachOther()
	check("  and none of them lies on another (was: the Essentials bar over the panel's title bar)", hit == nil, hit)
	db.laneEnabled = false
	GROUP = {}
	FireEvent("GROUP_ROSTER_UPDATE")
	Advance(1)
end

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
check("Settings opens on Getting Started with the window list, the picked window and the CooldownTimeline3 card",
	#ERRORS == e0 and CC.optionsFrame.page == 1 and CC.startPage ~= nil and CC.startPage:IsShown()
	and CC.startPage.cdtl3Card ~= nil and #CC.startPage.rows == #CC.WINDOWS)
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

---------------------------------------------------------------- Getting Started: pick and see
do
	local eg = #ERRORS
	local sp = CC.startPage
	local function est(fs) local t = fs:GetText() or "" return math.max(1, math.ceil(#t * 6.5 / fs:GetWidth())) * 13 end
	check("Getting Started opens with the Main panel picked, its name, one line and numbered notes",
		sp.picked and sp.picked.key == "main" and sp.nameFS:GetText() == "Main panel"
		and sp.lineFS:GetText() == CC.WINDOW_HELP.main.line and sp.noteFS[1]:GetText():sub(1, 3) == "1. "
		and sp.noteFS[4]:IsShown() and not sp.rows[1].pick:IsEnabled())
	check("  every window has its line and two to four notes", (function()
		for _, w in ipairs(CC.WINDOWS) do
			local h = CC.WINDOW_HELP[w.key]
			if not (h and type(h.line) == "string" and h.line ~= "" and #h.notes >= 2 and #h.notes <= 4) then return false end
		end
		return true
	end)())
	-- the page's own rectangle, in screen units; everything in it must stay inside it
	local pr = STUB_RECT(sp)
	local function inside(r, what)
		if r[1] < pr[1] - 0.5 or r[3] > pr[3] + 0.5 or r[4] > pr[4] + 0.5 or r[2] < pr[2] - 0.5 then
			return what .. string.format(" [%.0f %.0f %.0f %.0f] outside [%.0f %.0f %.0f %.0f]", r[1], r[2], r[3], r[4], pr[1], pr[2], pr[3], pr[4])
		end
	end
	local function overlap(a, b) return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5 end
	local card = sp.cdtl3Card
	local cardR = STUB_RECT(card)
	for i, w in ipairs(CC.WINDOWS) do
		sp.rows[i].pick:GetScript("OnClick")(sp.rows[i].pick)
		local h = CC.WINDOW_HELP[w.key]
		local bad
		-- right column, top down: name, line, notes, then Lock / Reset / Show it now; each below the one before
		local seq, prevBottom = {}, nil
		local nr = STUB_RECT(sp.nameFS)
		local function textRect(fs) local r = STUB_RECT(fs); return { r[1], r[4] - est(fs), r[3], r[4] } end
		seq[#seq + 1] = textRect(sp.lineFS)
		for _, n in ipairs(sp.noteFS) do if n:IsShown() then seq[#seq + 1] = textRect(n) end end
		seq[#seq + 1] = STUB_RECT(sp.lockCB); seq[#seq + 1] = STUB_RECT(sp.resetBtn); seq[#seq + 1] = STUB_RECT(sp.showBtn)
		for k, r in ipairs(seq) do
			bad = bad or inside(r, w.key .. " item " .. k)
			if k <= #seq - 3 and k > 1 and seq[k - 1][2] < r[4] - 0.5 then bad = bad or (w.key .. " note " .. k .. " runs into the one above") end
		end
		-- the controls sit in one row under the last note, clear of the card
		bad = bad or (seq[#seq][2] < cardR[4] + 4 and (w.key .. " buttons run into the CooldownTimeline3 card"))
		bad = bad or (overlap(seq[#seq - 2], seq[#seq - 1]) and (w.key .. " Lock on Reset")) or (overlap(seq[#seq - 1], seq[#seq]) and (w.key .. " Reset on Show it now"))
		if bad == false then bad = nil end
		check("  " .. w.label .. ": name '" .. sp.nameFS:GetText() .. "', its line, " .. #h.notes .. " notes; all fit the page", sp.picked == w
			and sp.nameFS:GetText() == w.label and sp.lineFS:GetText() == h.line and sp.noteFS[#h.notes]:IsShown()
			and (#h.notes == 4 or not sp.noteFS[4]:IsShown()) and bad == nil, bad)
		-- the list: tick, name button, left of the right column
		local row = sp.rows[i]
		local lr = STUB_RECT(row.pick)
		bad = inside(STUB_RECT(row.on), "tick") or inside(lr, "pick")
		check("  its list row fits and is left of the right column", bad == nil and lr[3] < STUB_RECT(sp.nameFS)[1] - 4, bad)
	end
	-- the foot
	local tr, rr = STUB_RECT(sp.tourBtn), STUB_RECT(sp.reportBtn)
	local fb = inside(tr, "tour") or inside(rr, "report") or inside(cardR, "card") or inside(STUB_RECT(card.button), "card button")
	check("the foot: Take the tour, Report a problem and the CooldownTimeline3 card fit and don't overlap",
		fb == nil and not overlap(tr, rr) and tr[4] <= cardR[2] + 0.5 and rr[4] <= cardR[2] + 0.5 and sp.tourBtn:GetWidth() >= #sp.tourBtn.__text * 6 + 12
		and sp.reportBtn:GetWidth() >= #sp.reportBtn.__text * 6 + 12, fb)
	check("  the card's button text fits its button", card.button:GetWidth() >= #card.button.__text * 6 + 12, card.button:GetWidth())
	-- the on ticks and Lock follow the settings
	db.deadListEnabled = true; sp.refresh()
	local deadRow
	for _, row in ipairs(sp.rows) do if row.window.key == "dead" then deadRow = row end end
	check("a window's On tick shows its setting and sets it", deadRow.on:GetChecked() == true)
	deadRow.on:SetChecked(false); deadRow.on:GetScript("OnClick")(deadRow.on)
	check("  unticking turns the window off", db.deadListEnabled == false)
	sp.rows[2].pick:GetScript("OnClick")(sp.rows[2].pick)
	sp.lockCB:SetChecked(true); sp.lockCB:GetScript("OnClick")(sp.lockCB)
	check("Lock locks the picked window", db.essentialsLocked == true and sp.picked.key == "essentials")
	sp.lockCB:SetChecked(false); sp.lockCB:GetScript("OnClick")(sp.lockCB)
	check("  and unlocks it", db.essentialsLocked == false)
	db.essentialsX = 999
	sp.resetBtn:GetScript("OnClick")(sp.resetBtn)
	check("Reset sends the picked window back to where it starts", db.essentialsX ~= 999)
	-- Show it now: the real window, with its sample, even solo
	local frame = CC[sp.picked.frame]
	frame:Hide()
	sp.showBtn:GetScript("OnClick")(sp.showBtn)
	check("Show it now shows the picked window with its sample", CC.sample and CC.sample.key == "essentials" and frame:IsShown())
	CC.optionsFrame:Hide()
	check("  and closing Settings ends it", CC.sample == nil and not frame:IsShown())
	CC.optionsFrame:Show()
	check("  reopening Settings picks the Main panel again", sp.picked.key == "main")
	-- Report a problem opens the report
	local asked
	local realReport = CC.ShowReport
	CC.ShowReport = function() asked = true end
	sp.reportBtn:GetScript("OnClick")(sp.reportBtn)
	CC.ShowReport = realReport
	check("Report a problem opens the report box", asked == true)
	check("Getting Started raises no Lua error", #ERRORS == eg, ERRORS[eg + 1])
end

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

---------------------------------------------------------------- joined windows
do
	local e1 = #ERRORS
	local W = {}
	for _, w in ipairs(CC.WINDOWS) do W[w.key] = w end
	local F = { essentials = "essentialsFrame", main = "frame", lanes = "laneFrame" }
	local function fr(key) return CC[F[key]] end
	local function order() return table.concat(CC:BlockOrder(), ",") end
	local function near(a, b) return math.abs(a - b) < 0.01 end
	-- the shown joined windows hang one under the other, left edges in line, all on the screen
	local function edgeToEdge()
		local prev
		for _, key in ipairs(CC:BlockOrder()) do
			local f = fr(key)
			if f:IsShown() then
				local r = rect(f)
				if r[1] < -0.01 or r[3] > SCREEN_W + 0.01 or r[4] > SCREEN_H + 0.01 then return false, key .. " off the screen" end
				if prev and not (near(r[4], prev[2]) and near(r[1], prev[1])) then
					return false, string.format("%s top %.1f left %.1f, the one above: bottom %.1f left %.1f", key, r[4], r[1], prev[2], prev[1])
				end
				prev = r
			end
		end
		return true
	end
	local function blockOK()
		local ok, why = edgeToEdge()
		local hit = onEachOther()
		return ok and hit == nil, why or hit
	end
	local rb = CC.SpellByName["Rebirth"] or next(CC.SpellData)
	local CLASSES = { "DRUID", "PRIEST", "PALADIN", "WARRIOR", "MAGE", "SHAMAN", "ROGUE", "HUNTER", "WARLOCK" }
	-- a group of n with a spell running for up to six of them (every one of their spells when full), so the
	-- panel has rows
	local function group(n, full)
		GROUP = {}
		STUB_IN_RAID = n > 5
		for i = 1, n - 1 do
			GROUP[i] = { unit = (n > 5 and "raid" or "party") .. i, name = "M" .. i, realm = "Realm",
				class = CLASSES[(i - 1) % #CLASSES + 1], guid = "Player-1-30" .. i }
		end
		FireEvent("GROUP_ROSTER_UPDATE")
		Advance(1)
		for i = 1, full and n - 1 or math.min(n - 1, 6) do
			for id, d in pairs(CC.SpellData) do
				if d.class == GROUP[i].class and (d.duration or 0) >= 60 and (full or not CC.state["M" .. i .. "-Realm"]) then
					CC:RecordCooldownFromComm("M" .. i .. "-Realm", id, GetTime() - 5, d.class)
				end
			end
		end
		CC:RefreshAllViews()
		Advance(1)
	end

	CC:ResetAllWindows()
	db.laneEnabled, db.essentialsEnabled, db.panelClosed = true, true, false
	check("joined windows: Reset all windows puts the three in one block, Essentials bar, main panel, Lane view",
		order() == "essentials,main,lanes" and db.blockX == CC.DEFAULTS.blockX and db.blockY == CC.DEFAULTS.blockY)
	for _, n in ipairs({ 5, 20, 40 }) do
		group(n)
		local ok, why = blockOK()
		local top = rect(CC.essentialsFrame)
		local bottom = rect(CC.laneFrame)[2]
		check(string.format("  %d players: all three show, edge to edge top down, none on another, on the screen", n),
			ok and CC.frame:IsShown() and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown() and bottom >= -0.01,
			why or string.format("block %.0f tall, top %.0f", top[4] - bottom, top[4]))
		if n == 5 then
			check("  the block starts right of the screen centre, near the top (UI scale 1)",
				near(top[1], SCREEN_W / 2 + CC.DEFAULTS.blockX) and near(top[4], SCREEN_H + CC.DEFAULTS.blockY),
				string.format("%.0f%% across, %.0f%% down", top[1] / SCREEN_W * 100, (SCREEN_H - top[4]) / SCREEN_H * 100))
		end
	end
	group(40, true)
	local ok40, why40 = blockOK()
	local r40 = rect(CC.essentialsFrame)
	check("  40 players, every spell running (the block taller than the screen): still edge to edge, none on another, its top on the screen",
		ok40, why40)
	check("    the top held at the screen's top", near(r40[4], SCREEN_H) or r40[4] < SCREEN_H)
	CC.state = {}
	group(5)

	-- growth: the panel taller, the Lane view moves down with its bottom
	-- (the block moves up when its bottom would leave the screen: that rise counted back in)
	local laneTop, blockTop = rect(CC.laneFrame)[4], rect(CC.essentialsFrame)[4]
	CC.frame:SetHeight(CC.frame:GetHeight() + 60)
	local rise = rect(CC.essentialsFrame)[4] - blockTop
	check("  the panel growing pushes the Lane view down by as much", near(rect(CC.laneFrame)[4], laneTop - 60 + rise) and blockOK(),
		string.format("lane top %.1f -> %.1f; block rose %.1f", laneTop, rect(CC.laneFrame)[4], rise))
	CC:RefreshRows()

	-- a hidden window is skipped: the Essentials bar off, the panel takes the top
	db.essentialsEnabled = false
	CC:RefreshEssentials()
	local mainR = rect(CC.frame)
	check("  the Essentials bar hidden: the panel moves up to the block's top, the Lane view under it",
		not CC.essentialsFrame:IsShown() and near(mainR[4], SCREEN_H + db.blockY) and blockOK())
	db.essentialsEnabled = true
	CC:RefreshEssentials()
	check("  shown again: back on top, the others under it", near(rect(CC.essentialsFrame)[4], SCREEN_H + db.blockY) and blockOK())
	db.showWindows = "combat"
	CC:RefreshAllViews()
	check("  only in combat, out of it: all three hidden", not CC.frame:IsShown() and not CC.essentialsFrame:IsShown()
		and not CC.laneFrame:IsShown())
	db.showWindows = "always"
	CC:RefreshAllViews()
	check("  and back: the block as before", blockOK())

	-- drag the top window: the block moves
	local before = { rect(CC.essentialsFrame), rect(CC.frame), rect(CC.laneFrame) }
	DragWidget(CC.essentialsFrame, -150, -40)
	local moved = true
	for i, key in ipairs({ "essentials", "main", "lanes" }) do
		local r = rect(fr(key))
		moved = moved and near(r[1], before[i][1] - 150) and near(r[4], before[i][4] - 40)
	end
	check("  dragging the top window moves all three, still joined", moved and order() == "essentials,main,lanes" and blockOK())
	check("  and the block keeps its new place", near(db.blockX, CC.DEFAULTS.blockX - 150) and near(db.blockY, CC.DEFAULTS.blockY - 40))
	DragWidget(CC.frame.rowsParent or CC.frame, 0, 0)
	check("  a plain click on the panel changes nothing", order() == "essentials,main,lanes" and blockOK())

	-- drag the middle window: it comes loose where it is dropped
	local mr = rect(CC.frame)
	DragWidget(CC.frame, -500, -60)
	local nr = rect(CC.frame)
	check("  dragging the panel pulls it loose, a free window where it is dropped", order() == "essentials,lanes"
		and near(nr[1], mr[1] - 500) and near(nr[4], mr[4] - 60))
	check("  the Lane view closes the gap under the Essentials bar", near(rect(CC.laneFrame)[4], rect(CC.essentialsFrame)[2]) and blockOK())
	FireEvent("PLAYER_LOGOUT")
	CC:LayoutBlock()
	check("  its place is kept (a logout doesn't move it)", near(rect(CC.frame)[1], nr[1]) and near(rect(CC.frame)[4], nr[4]))

	-- a loose window dropped near the block's bottom edge joins at the bottom
	local lane = rect(CC.laneFrame)
	nr = rect(CC.frame)
	DragWidget(CC.frame, lane[1] + 10 - nr[1], lane[2] - 8 - nr[4])
	check("  dropped 8 px under the block's bottom: it joins there, edge to edge",
		order() == "essentials,lanes,main" and near(rect(CC.frame)[4], rect(CC.laneFrame)[2]) and blockOK(), order())

	-- dropped onto a block window: joins at the nearer edge, never on top
	DragWidget(CC.frame, -500, 0)
	local er = rect(CC.essentialsFrame)
	nr = rect(CC.frame)
	DragWidget(CC.frame, er[1] - nr[1] + 20, er[4] + 20 - nr[4])
	check("  dropped onto the Essentials bar's top half: it joins at the block's top, none on another",
		order() == "main,essentials,lanes" and blockOK(), order())
	local mt, mh, lb = rect(CC.frame)[4], rect(CC.frame)[4] - rect(CC.frame)[2], rect(CC.laneFrame)[2]
	check("    the block stays where it was, the panel above it (as far as the screen lets it)",
		near(mt, er[4] + mh) or near(mt, SCREEN_H) or near(lb, 0))
	DragWidget(CC.frame, 0, 0)
	check("    a plain click on the new top changes nothing", order() == "main,essentials,lanes")

	-- loose on loose: edge to edge, not on top
	DragWidget(CC.laneFrame, -500, -100)
	DragWidget(CC.essentialsFrame, 0, -300)   -- not the top now: comes loose
	local lr = rect(CC.laneFrame)
	er = rect(CC.essentialsFrame)
	DragWidget(CC.essentialsFrame, lr[1] - er[1] + 15, (lr[2] + lr[4]) / 2 - (er[2] + er[4]) / 2)
	local hit = onEachOther()
	check("  a loose window dropped on another loose one goes edge to edge with it", order() == "main" and hit == nil, hit or order())

	-- reset: back in the slot
	CC:ResetWindow(W.lanes)
	check("  Reset puts the Lane view back in the block, in its slot", order() == "main,lanes" and blockOK(), order())
	CC:ResetWindow(W.essentials)
	check("  and the Essentials bar in its slot above the panel", order() == "essentials,main,lanes" and blockOK(), order())
	DragWidget(CC.laneFrame, -400, 0)
	SlashCmdList["COOLDOWNCOLLABORATOR"]("reset")
	check("  /cdc reset puts the panel back in its slot too", order() == "essentials,main" and blockOK(), order())
	CC:ResetAllWindows()
	check("  Reset all windows: all three in their slots, the block home", order() == "essentials,main,lanes"
		and near(rect(CC.essentialsFrame)[1], SCREEN_W / 2 + CC.DEFAULTS.blockX) and blockOK())

	-- a panel line passes the drag on to the panel
	CC:ResetAllWindows()
	local line
	for _, l in ipairs(CC.rows or {}) do if l:IsShown() then line = l; break end end
	if line then
		local before = rect(CC.frame)
		DragWidget(line, -420, 0)
		check("  dragging a panel line drags the panel (here: pulls it loose)", order() == "essentials,lanes"
			and near(rect(CC.frame)[1], before[1] - 420), order())
	end
	CC:ResetAllWindows()

	-- lock: locked windows don't drag, joined or not
	local lr0 = rect(CC.laneFrame)
	CC:SetOneWindowLocked(W.lanes, true)
	DragWidget(CC.laneFrame, -300, 0)
	check("  a locked joined window doesn't drag or come loose", order() == "essentials,main,lanes" and near(rect(CC.laneFrame)[1], lr0[1]))
	CC:SetWindowsLocked(true)
	local er0 = rect(CC.essentialsFrame)
	DragWidget(CC.essentialsFrame, -300, 0)
	check("  locked, the top window doesn't move the block", near(rect(CC.essentialsFrame)[1], er0[1]))
	CC:SetWindowsLocked(false)

	-- layouts keep joined or loose per party and raid
	group(20)
	group(5)
	DragWidget(CC.laneFrame, -450, 0)
	check("  party: the Lane view loose", order() == "essentials,main")
	group(20)
	check("  a raid has its own places: all three joined (the party's kept)", order() == "essentials,main,lanes"
		and db.layouts.party and db.layouts.party.lanes[3] == 0 and blockOK(), order())
	DragWidget(CC.essentialsFrame, 40, 0)
	group(5)
	check("  back in the party: the Lane view loose again where it was", order() == "essentials,main"
		and near(db.blockX, CC.DEFAULTS.blockX) and onEachOther() == nil, order())
	group(20)
	check("  and the raid's moved block comes back", order() == "essentials,main,lanes" and near(db.blockX, CC.DEFAULTS.blockX + 40))
	group(5)

	-- profiles and exported setups hold it
	local snap = CC:SnapshotProfile()
	check("  a profile holds each window's slot and the block's place", snap.places.lanes[3] == 0 and snap.places.main[3] == 2
		and snap.places.block and near(snap.places.block[1], db.blockX))
	CC:ResetAllWindows()
	CC:ApplyProfile(snap)
	check("  and putting it back makes the Lane view loose again", order() == "essentials,main" and onEachOther() == nil, order())
	local text = CC:ExportSetup("places")
	check("  an exported setup writes the slots", text:find("w=lanes,[-%d]+,[-%d]+,0") ~= nil and text:find("w=main,[-%d]+,[-%d]+,2") ~= nil
		and text:find("w=block,") ~= nil, text)
	CC:ResetAllWindows()
	check("  and importing it brings them back", CC:ImportSetup(text) and order() == "essentials,main" and onEachOther() == nil, order())
	CC:UndoSetup()

	-- places from before joined windows (1.1.1, this branch's layouts and profiles): start joined only if never moved
	CC:ResetAllWindows()
	CC:ApplyPlaces({ main = { 0, 200 }, essentials = { 220, 200 }, lanes = { -300, 50 } })
	check("  old places without a slot: the unmoved ones join, a moved one stays loose where it was",
		order() == "essentials,main" and near(db.laneX, -300) and near(db.laneY, 50) and onEachOther() == nil, order())
	db.blockOrder = nil
	db.essentialsX, db.essentialsY = 220, 200
	db.x, db.y, db.laneX, db.laneY = 0.0, 200.0000001, 0, -200
	check("  a save with no block at all (1.1.1): never moved, all three join", order() == "essentials,main,lanes")
	db.blockOrder = nil
	db.x, db.y = -310, 120
	check("  a moved main panel stays loose", order() == "essentials,lanes")
	CC:LayoutBlock()
	local c = { CC.frame:GetCenter() }
	check("    where it was", near(c[1] - UIParent:GetWidth() / 2, -310) and near(c[2] - UIParent:GetHeight() / 2, 120))

	-- a scaled panel keeps its loose place across logouts (its place is in its own scale)
	db.scale = 1.4
	CC.frame:SetScale(1.4)
	CC:LayoutBlock()
	local c1 = { CC.frame:GetCenter() }
	for _ = 1, 3 do FireEvent("PLAYER_LOGOUT"); CC:LayoutBlock() end
	local c2 = { CC.frame:GetCenter() }
	check("  a loose panel at scale 1.4 stays put across logouts", near(c1[1], c2[1]) and near(c1[2], c2[2]),
		string.format("%.1f,%.1f -> %.1f,%.1f", c1[1], c1[2], c2[1], c2[2]))
	db.scale = 1
	CC.frame:SetScale(1)

	CC:ResetAllWindows()
	GROUP = {}
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
	Advance(1)
	db.laneEnabled = false
	check("joined windows code raises no Lua error", #ERRORS == e1, ERRORS[e1 + 1])
end

---------------------------------------------------------------- sample windows (Tour.lua)
do
	local e6 = #ERRORS
	GROUP = {}
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
	Advance(1)
	for _, w in ipairs(CC.WINDOWS) do
		if w.onKey then db[w.onKey] = false end
	end
	db.panelClosed = true
	CC:RefreshAllViews()
	local stateBefore, nState = CC.state, 0
	for _ in pairs(CC.state) do nState = nState + 1 end
	local sent0, chat0 = #SENT, #CHATSENT
	local has = {
		main = function() local d = CC:BuildPanelData(); return #d.running + #d.folded > 0 end,
		essentials = function() for _, m in ipairs(CC:EssentialsModel()) do if m.kind == "provider" then return true end end end,
		lanes = function() for _, k in ipairs(CC.CAPABILITY_ORDER) do if #CC:GetCapabilityStatus(k) > 0 then return true end end end,
		dead = function() return #CC:DeadList() == 2 end,
		externals = function() return #CC:ExternalTiles() > 0 end,
		mana = function() return #CC:ManaTiles() > 0 end,
		burst = function() return #CC:SampleBurstOwn() > 0 and #CC:BurstGroup() > 0 end,
	}
	for _, w in ipairs(CC.WINDOWS) do
		local frame = CC[w.frame]
		check("sample " .. w.key .. ": shows solo with its window off", CC:ShowSample(w.key) == true and frame:IsShown(), w.key)
		check("  it holds made-up players and real spells for this client", CC:WithSample(has[w.key]) == true, w.key)
		check("  the group's data is the group's again", CC.state == stateBefore and CC.sampling == nil and CC:IsSampleName("Sylwen-Sample"))
		CC:HideSample()
		check("  ends: the window is back to hidden, no sample left", not frame:IsShown() and CC.sample == nil and not CC:IsSampleName("Sylwen-Sample"))
	end
	local nAfter = 0
	for name in pairs(CC.state) do nAfter = nAfter + 1; if name:find("-Sample", 1, true) then nAfter = -999 end end
	check("samples leave no rows in the group's data, and send nothing", nAfter == nState and #SENT == sent0 and #CHATSENT == chat0, nAfter)
	-- the real refresh methods are back, not wrappers
	CC:ShowSample("main"); local wrapped = CC.RefreshRows; CC:HideSample()
	check("  the refresh methods are put back", CC.RefreshRows ~= wrapped)

	-- twenty seconds
	CC:ShowSample("main")
	Advance(19)
	check("a sample lasts 20 seconds: still there at 19", CC.sample ~= nil and CC.frame:IsShown())
	Advance(2)
	check("  and gone at 21", CC.sample == nil and not CC.frame:IsShown())
	-- one at a time
	CC:ShowSample("main"); CC:ShowSample("lanes")
	check("showing another replaces it", CC.sample.key == "lanes" and not CC.frame:IsShown() and CC.laneFrame:IsShown())
	CC:HideSample()

	-- a real group event ends it, and a real cast heard from the group does too
	CC:ShowSample("essentials")
	GROUP = { { unit = "party1", name = "Tania", realm = "Realm", class = "PRIEST", guid = "Player-1-0000009" } }
	FireEvent("GROUP_ROSTER_UPDATE")
	check("a roster change in a real group ends it", CC.sample == nil)
	GROUP = {}
	FireEvent("GROUP_ROSTER_UPDATE")
	CC:ShowSample("main")
	CC:SetRemoteCooldown("Tania-Realm", next(CC.SpellData), GetTime(), "PRIEST", "comm")
	check("  so does a cooldown heard from a group member", CC.sample == nil)
	CC.state["Tania-Realm"] = nil
	CC:ShowSample("main")
	FireEvent("PLAYER_REGEN_DISABLED")
	check("  and so does combat starting", CC.sample == nil)
	FireEvent("PLAYER_REGEN_ENABLED")

	-- nothing is sent from a sample
	PRINTS = {}
	CC:ShowSample("dead")
	local dead1 = CC:WithSample(function() return CC:DeadList()[1].name end)
	CC:CallRez(dead1)
	CC:RequestRez()
	check("Call on a made-up dead player sends nothing", #CHATSENT == chat0 and #SENT == sent0 and #PRINTS >= 1, PRINTS[1])
	CC:HideSample()
	CC:ShowSample("mana")
	CC:AskForMana()
	check("  nor does Ask on the Mana window", #CHATSENT == chat0)
	CC:HideSample()
	CC:ShowSample("main")
	local sampleOwner = CC:WithSample(function() local d = CC:BuildPanelData(); return (d.folded[1] or d.running[1]).owners and d.folded[1].owners[1].name or d.running[1].name end)
	CC:AskForCooldown({ name = sampleOwner, spellID = next(CC.SpellData), remaining = 0 })
	check("  nor does a click on a made-up player's cooldown", #CHATSENT == chat0)
	local lines = CC:CooldownTooltipLines(sampleOwner, (CC:WithSample(function() local d = CC:BuildPanelData(); return (d.folded[1] or d.running[1]).spellID end)))
	check("  and its tooltip reads from the sample", #lines > 0)
	CC:HideSample()

	-- an error inside a sampled refresh still puts the group's data back
	CC:ShowSample("main")
	local ok = pcall(CC.WithSample, CC, function() error("boom") end)
	check("an error while drawing a sample puts the group's data back", not ok and CC.sampling == nil and CC.state == stateBefore)
	CC:HideSample()
	check("sample code raises no Lua error", #ERRORS == e6, ERRORS[e6 + 1])
	db.panelClosed = false
end

---------------------------------------------------------------- the tour (Tour.lua)
do
	local e7 = #ERRORS
	GROUP = {}
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
	Advance(3)
	CC.db.tourDone = nil
	local function setOn(keys)
		for _, w in ipairs(CC.WINDOWS) do
			local on = keys[w.key] == true
			if w.onKey then db[w.onKey] = on else db.panelClosed = not on end
		end
		CC:RefreshAllViews()
	end
	local function tour() return CC.tour end
	local function head() return CC.tourFrame.head:GetText() end
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

	-- steps follow which windows are on
	setOn({ main = true, essentials = true })
	check("tour: two windows on, two steps", CC:StartTour(true) and #tour().steps == 2 and head() == "1 of 2 \194\183 Main panel", head())
	CC:EndTour()
	setOn({ main = true, essentials = true, lanes = true, dead = true })
	CC:StartTour(true)
	check("  the four main windows: four steps", #tour().steps == 4)
	CC:EndTour()
	setOn({ main = true, essentials = true, lanes = true, dead = true, externals = true, mana = true, burst = true })
	CC:StartTour(true)
	check("  all seven on: seven steps, in the window list's order", #tour().steps == 7 and tour().steps[1].key == "main"
		and tour().steps[2].key == "essentials" and tour().steps[3].key == "lanes" and tour().steps[4].key == "dead"
		and tour().steps[5].key == "externals" and tour().steps[6].key == "mana" and tour().steps[7].key == "burst")
	CC:EndTour()
	setOn({})
	PRINTS = {}
	check("  none on: it does not start and says why", CC:StartTour(true) == false and CC.tour == nil and #PRINTS == 1)

	-- each step: the window shows (its sample, solo), the gold edge, the bubble, its one sentence, Next
	setOn({ main = true, essentials = true, lanes = true, dead = true, externals = true, mana = true, burst = true })
	CC:StartTour(true)
	local f = CC.tourFrame
	local steps = tour().steps
	for i, w in ipairs(steps) do
		local frame = CC[w.frame]
		local help = CC.WINDOW_HELP[w.key]
		local br = STUB_RECT(f)
		local wr = STUB_RECT(frame)
		local onScreen = br and br[1] >= -0.5 and br[3] <= sw + 0.5 and br[2] >= -0.5 and br[4] <= sh + 0.5
		local apart = br and wr and not (br[1] < wr[3] - 0.5 and wr[1] < br[3] - 0.5 and br[2] < wr[4] - 0.5 and wr[2] < br[4] - 0.5)
		check("  step " .. i .. ", " .. w.label .. ": window shown by a sample, gold edge, bubble beside it on screen",
			head() == string.format("%d of 7 \194\183 %s", i, w.label) and f.body:GetText() == help.line and frame:IsShown()
			and CC.sample and CC.sample.key == w.key and f.edge:IsShown() and f:IsShown() and onScreen and apart,
			string.format("%s [%s]", head(), br and string.format("%.0f %.0f %.0f %.0f", br[1], br[2], br[3], br[4]) or "none"))
		check("    Next on every step but the last; Lock in place and Open settings only on the last",
			f.next:IsShown() == (i < 7) and f.lock:IsShown() == (i == 7) and f.settings:IsShown() == (i == 7))
		if i < 7 then
			f.next:GetScript("OnClick")(f.next)
		end
	end
	-- Lock in place
	CC:SetWindowsLocked(false)
	f.lock:GetScript("OnClick")(f.lock)
	check("Lock in place locks every window and ends the tour", CC:AreWindowsLocked() and CC.tour == nil and CC.sample == nil and not f:IsShown() and not f.edge:IsShown())
	CC:SetWindowsLocked(false)

	-- Open settings
	CC:StartTour(true)
	for _ = 1, 6 do CC:TourNext() end
	if CC.optionsFrame then CC.optionsFrame:Hide() end
	f.settings:GetScript("OnClick")(f.settings)
	check("Open settings ends the tour and opens Settings", CC.tour == nil and CC.optionsFrame:IsShown())
	-- Take the tour on Getting Started closes Settings and starts it
	local sp = CC.startPage
	sp.tourBtn:GetScript("OnClick")(sp.tourBtn)
	check("Take the tour starts it and puts Settings away", CC.tour ~= nil and not CC.optionsFrame:IsShown() and head() == "1 of 7 \194\183 Main panel", head())
	-- Escape, the close button, a slash
	local inSpecial = false
	for _, n in ipairs(UISpecialFrames) do if n == "CCTourFrame" then inSpecial = true end end
	_G["CCTourFrame"]:Hide()   -- what Escape does to every frame in UISpecialFrames
	check("Escape ends it", inSpecial and CC.tour == nil and CC.sample == nil and not f.edge:IsShown())
	CC:StartTour(true)
	f.close:GetScript("OnClick")(f.close)
	check("  so does its close button", CC.tour == nil and not f:IsShown())
	SlashCmdList["COOLDOWNCOLLABORATOR"]("tour")
	check("  /cdc tour starts it", CC.tour ~= nil)
	-- never in combat, and combat ends it quietly
	PRINTS = {}
	FireEvent("PLAYER_REGEN_DISABLED")
	check("combat starting mid-tour ends it with nothing said", CC.tour == nil and CC.sample == nil and not f:IsShown() and #PRINTS == 0)
	check("  it won't start while in combat", CC:StartTour(true) == false and CC.tour == nil)
	FireEvent("PLAYER_REGEN_ENABLED")
	CC.inCombat = false

	-- by itself: once, in a group, windows showing, not in combat
	setOn({ main = true, essentials = true, lanes = true })
	CC.db.tourDone = nil
	CC:TryAutoTour()
	check("on its own: not when solo", CC.tour == nil and CC.db.tourDone == nil)
	GROUP = { { unit = "party1", name = "Tania", realm = "Realm", class = "PRIEST", guid = "Player-1-0000009" } }
	CC.inCombat = true
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(3)
	check("  not in combat", CC.tour == nil and CC.db.tourDone == nil)
	CC.inCombat = false
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(3)
	check("  in a group with the windows showing, it starts, with the real windows (no sample)",
		CC.tour ~= nil and CC.db.tourDone == true and CC.sample == nil and CC.frame:IsShown() and head() == "1 of 3 \194\183 Main panel", head())
	CC:EndTour()
	GROUP = {}
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(3)
	GROUP = { { unit = "party1", name = "Tania", realm = "Realm", class = "PRIEST", guid = "Player-1-0000009" } }
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(3)
	check("  and only once", CC.tour == nil)
	CC.db.tourDone = nil
	db.showWindows = "combat"
	CC:RefreshAllViews()
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(3)
	check("  not while the windows are hidden", CC.tour == nil and CC.db.tourDone == nil)
	db.showWindows = "always"
	GROUP = {}
	FireEvent("GROUP_ROSTER_UPDATE"); Advance(3)
	CC.db.tourDone = nil
	check("a profile switch leaves the flag alone (it is the account's)", (function()
		for _, k in ipairs(CC.PROFILE_KEYS) do if k == "tourDone" then return false end end
		return true
	end)())
	check("the tour code raises no Lua error", #ERRORS == e7, ERRORS[e7 + 1])
	setOn({ main = true, essentials = true, lanes = false, dead = true })
	db.laneEnabled = false
end

check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT settings %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
