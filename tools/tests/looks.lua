-- CooldownCollaborator look-lane checks for one TOC: the Lane view's ready rows,
-- rings and marks (R20, R21, R22, P44, dead or offline owners), the next hit
-- (P25: /cdc nexthit, the game's countdown, BigWigs and DBM pulls), the dead list
-- (P3), the externals strip (P32), the mana strip with Ask (P24), the burst line
-- (P29) and the raid plan's runtime (P12: sharing as P, prompts, late spells), at
-- 5, 20 and 40 players, with hidden values where Retail and Forever have them.
-- Kinds come from a fixture here (the Data rows may not carry them yet).
-- Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/looks.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
local function near(a, b, tol) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or 0.01) end
OUT(string.format("[looks %s %s]", HARNESS_TOCFILE, FLAVOR))

-- Two calls every client has that the stub leaves out: a member's `role` and `combat`.
local function memberOf(u)
	if u == "player" then return PLAYER end
	for _, m in ipairs(GROUP) do if m.unit == u then return m end end
end
function UnitGroupRolesAssigned(u) local m = memberOf(u); return m and m.role or "NONE" end
function UnitAffectingCombat(u) local m = memberOf(u); return m ~= nil and m.combat == true end

-- whispers, with their target (the stub's chat call keeps only text and channel)
local WHISPERS = {}
local stubSend = C_ChatInfo.SendChatMessage
C_ChatInfo.SendChatMessage = function(msg, chan, lang, target)
	if chan == "WHISPER" then WHISPERS[#WHISPERS + 1] = { msg = msg, target = target } end
	return stubSend(msg, chan, lang, target)
end

-- BigWigs and DBM stand-ins, loaded before us like the real ones
local BW, DBMH = {}, {}
BigWigsLoader = { RegisterMessage = function(owner, msg, fn) BW[msg] = fn end }
DBM = { RegisterCallback = function(self, event, fn) DBMH[event] = fn end }
local function BigWigs(msg, ...) if BW[msg] then BW[msg](msg, ...) end end
local function DBMFire(event, ...) if DBMH[event] then DBMH[event](event, ...) end end

---------------------------------------------------------------- load, kinds fixture
LoadTOC(HARNESS_TOCFILE)
for id, d in pairs(CC.SpellData) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
local KIND = {
	["Innervate"] = "mana", ["Mana Tide Totem"] = "mana", ["Shadowfiend"] = "mana", ["Hymn of Hope"] = "mana",
	["Pain Suppression"] = "external", ["Guardian Spirit"] = "external", ["Blessing of Sacrifice"] = "external",
	["Hand of Sacrifice"] = "external", ["Life Cocoon"] = "external", ["Ironbark"] = "external",
	["Blessing of Protection"] = "external", ["Hand of Protection"] = "external", ["Lay on Hands"] = "external",
	["Time Dilation"] = "external",
	["Tranquility"] = "raid", ["Rallying Cry"] = "raid", ["Aura Mastery"] = "raid", ["Spirit Link Totem"] = "raid",
	["Survival Instincts"] = "personal", ["Shield Wall"] = "personal", ["Ice Block"] = "personal",
	["Rebirth"] = "rez",
}
for _, d in pairs(CC.SpellData) do
	if KIND[d.name] then d.kind = KIND[d.name] end
end
local function castID(base) local d = CC.SpellData[base]; return d.ranks and d.ranks[#d.ranks] or base end

Login()
-- the name index is built at login
local function idOf(name) return CC.SpellByName[name] end
local REBIRTH, TRANQ, INNERVATE, PI = idOf("Rebirth"), idOf("Tranquility"), idOf("Innervate"), 10060
check("load and login: no Lua errors", #ERRORS == 0, ERRORS[1])
check("BigWigs and DBM hooked at login (when they are there)", BW.BigWigs_StartBar ~= nil and DBMH.DBM_TimerStart ~= nil)
check("the new windows are built", CC.deadFrame ~= nil and CC.externalsFrame ~= nil and CC.manaFrame ~= nil
	and CC.burstFrame ~= nil and CC.planBars ~= nil)
check("their saved settings have defaults", CC.db.deadListEnabled == true and CC.db.externalsEnabled == false
	and CC.db.manaEnabled == false and CC.db.burstEnabled == false and type(CC.db.plans) == "table"
	and CC.db.planLead == 5 and type(CC.db.burstSpells) == "table")

---------------------------------------------------------------- groups of 5, 20 and 40
local ME = PLAYER.name .. "-" .. PLAYER.realm
local guidN = 0
local function Mk(name, class, extra)
	guidN = guidN + 1
	local m = { name = name, realm = "Realm", class = class, guid = string.format("Player-1-%07d", guidN) }
	for k, v in pairs(extra or {}) do m[k] = v end
	return m
end
local COMPS = {
	[5]  = { DRUID = 1, PRIEST = 1, SHAMAN = 1, PALADIN = 1 },
	[20] = { DRUID = 5, PRIEST = 3, SHAMAN = 3, PALADIN = 3, MAGE = 2, WARRIOR = 2, WARLOCK = 1 },
	[40] = { DRUID = 12, PRIEST = 6, SHAMAN = 6, PALADIN = 5, MAGE = 4, WARRIOR = 4, WARLOCK = 2 },
}
local ORDER = { "DRUID", "PRIEST", "SHAMAN", "PALADIN", "MAGE", "WARRIOR", "WARLOCK" }
local CODE = { DRUID = "Dr", PRIEST = "Pr", SHAMAN = "Sh", PALADIN = "Pa", MAGE = "Ma", WARRIOR = "Wa", WARLOCK = "Wl" }
local byName = {}
-- size players in all, us (a druid) included: a party at 5, else a raid with us on the last raid unit
local function SetGroup(size)
	GROUP, byName = {}, {}
	local raid = size > 5
	for _, class in ipairs(ORDER) do
		for i = 1, COMPS[size][class] or 0 do
			local m = Mk(CODE[class] .. i, class)
			m.unit = (raid and "raid" or "party") .. (#GROUP + 1)
			GROUP[#GROUP + 1] = m
			byName[m.name] = m
		end
	end
	if raid then
		GROUP[#GROUP + 1] = { unit = "raid" .. (#GROUP + 1), name = PLAYER.name, realm = PLAYER.realm, class = PLAYER.class, guid = PLAYER.guid }
	end
	STUB_IN_RAID = raid
	FireEvent("GROUP_ROSTER_UPDATE")
end
local function Solo()
	GROUP, byName = {}, {}
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
end
local function full(n) return n .. "-Realm" end
-- another player's cast, `ago` seconds ago, as their message would record it
local function Cast(name, base, ago)
	CC:RecordCooldownFromComm(full(name), base, GetTime() - ago, byName[name] and byName[name].class)
end
local function ResetState()
	for name in pairs(CC.state) do if name ~= ME then CC.state[name] = nil end end
	wipe(CC.peers)
	CC.rezCharges = nil
end

---------------------------------------------------------------- the Lane view
local function LaneView(capKey)
	local lane = CC.lanes[capKey]
	local row = lane.readyRow
	local v = { ready = {}, cooling = {}, height = lane.__h, label = row.label.__text,
		more = row.more.__shown and row.more.__text or nil }
	for _, w in ipairs(row.icons) do if w.__shown then v.ready[#v.ready + 1] = w end end
	for _, w in ipairs(lane.icons) do if w.__shown then v.cooling[#v.cooling + 1] = w end end
	return v
end
local function Expected(capKey)
	local ready, cooling = 0, 0
	for _, e in ipairs(CC:GetCapabilityStatus(capKey)) do
		if e.remaining > 0 then cooling = cooling + 1 else ready = ready + 1 end
	end
	return ready, cooling
end
-- every provider is drawn once: up to eight on the ready row, "+N" for the rest, the cooling ones on the lane
local function LaneAddsUp(capKey)
	local v = LaneView(capKey)
	local ready, cooling = Expected(capKey)
	local shown = math.min(ready, 8)
	local more = ready > 8 and ("+" .. (ready - 8)) or nil
	return #v.ready == shown and v.more == more and #v.cooling == cooling
		and v.label == (ready > 0 and "Ready" or "none ready"),
		string.format("ready %d (row %d, %s), cooling %d (lane %d)", ready, #v.ready, tostring(v.more), cooling, #v.cooling)
end
local function FrameFits()
	local h = 20
	for i, capKey in ipairs(CC.CAPABILITY_ORDER) do
		h = h + CC.lanes[capKey].__h + 21 + (i < #CC.CAPABILITY_ORDER and 15 or 0)
	end
	return CC.laneFrame.__h == h + 5, CC.laneFrame.__h .. " for " .. (h + 5)
end

CC.db.laneEnabled = true
for _, size in ipairs({ 5, 20, 40 }) do
	ResetState()
	SetGroup(size)
	Advance(0.3)
	local e0 = #ERRORS
	local okAll, why = true, {}
	for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
		local ok, d = LaneAddsUp(capKey)
		if not ok then okAll = false end
		why[#why + 1] = CC.CAPABILITIES[capKey].label .. ": " .. d
	end
	check(string.format("%d players, all ready: every provider on its ready row, up to 8 then +N (R20, R21)", size),
		okAll and #ERRORS == e0 and CC.laneFrame:IsShown(), table.concat(why, "; "))
	local rez = LaneView("BATTLEREZ")
	local ringOK = #rez.ready > 0
	for _, w in ipairs(rez.ready) do
		if w.look.ring ~= "ready" or not w.ring.__shown or not w.tex.__shown then ringOK = false end
	end
	check("  ready icons: a thin green ring around the icon, not a square over it (R22)", ringOK)

	-- druids cast Rebirth: the same moment (they stack in levels) and one later
	local druids = COMPS[size].DRUID
	local casting = math.max(1, druids - 1)
	for i = 1, casting do Cast("Dr" .. i, REBIRTH, 30) end
	Advance(0.3)
	local ok, d = LaneAddsUp("BATTLEREZ")
	rez = LaneView("BATTLEREZ")
	local classRing = #rez.cooling > 0
	for _, w in ipairs(rez.cooling) do
		if w.look.ring ~= "class" or w.look.class ~= "DRUID" then classRing = false end
	end
	local fits, fd = FrameFits()
	check(string.format("  %d druids cooling: they ride the lane with a class ring, the ready ones stay on the row", casting),
		ok and classRing, d)
	check("  the window grows to fit the lanes (stacked cooling icons too)", fits
		and rez.height == 28 + 18 * math.min(casting - 1, 4), fd .. ", lane " .. tostring(rez.height))
end

do
	-- marks: dead and offline owners greyed with a mark, after the live ones; guessed "?" (Retail and Forever)
	ResetState()
	SetGroup(20)
	byName.Dr1.dead = true
	byName.Dr2.offline = true
	Cast("Dr3", REBIRTH, 30)
	byName.Dr3.dead = true
	CC.peers[full("Dr4")] = { version = CC.version, proto = 2 }
	Advance(0.3)
	local v = LaneView("BATTLEREZ")
	local states, lastLive = {}, true
	local orderOK = true
	for _, w in ipairs(v.ready) do
		local s = w.look.state
		if s then lastLive = false elseif not lastLive then orderOK = false end
		states[w.owner] = w
	end
	local dead, off = states[full("Dr1")], states[full("Dr2")]
	check("dead owner: greyed with the skull, after the live ones", dead ~= nil and dead.look.state == "dead"
		and dead.mark.__shown and dead.mark.__tex:find("RaidTargetingIcon_8", 1, true) ~= nil and orderOK)
	check("offline owner: greyed with the plug", off ~= nil and off.look.state == "offline" and off.mark.__shown
		and off.mark.__tex:find("Disconnect", 1, true) ~= nil)
	local cool = v.cooling[1]
	check("  a dead owner's cooling icon on the lane: greyed with the skull", cool ~= nil and cool.look.state == "dead"
		and cool.mark.__shown)
	local live, guessedShown, peerQ = nil, false, nil
	for _, w in ipairs(v.ready) do
		if not w.look.state and w.owner ~= full("Dr4") then live = w end
		if w.owner == full("Dr4") then peerQ = w.qdot.__shown end
		if w.qdot.__shown then guessedShown = true end
	end
	if RETAILAPI then
		check("guessed (no copy, no cast seen): a ? on the ready icon; one who runs it: none (P44)",
			live ~= nil and live.qdot.__shown and live.q.__shown and peerQ == false)
	else
		check("no ? on Era, TBC and MoP (the combat log sees casts)", not guessedShown)
	end
	check("  no ? on a greyed icon", not (dead.qdot.__shown or off.qdot.__shown))
	byName.Dr1.dead, byName.Dr2.offline, byName.Dr3.dead = nil, nil, nil
end

do
	-- next hit (P25)
	ResetState()
	SetGroup(20)
	Cast("Dr1", REBIRTH, CC.SpellData[REBIRTH].duration - 30)   -- back in 30 s
	Cast("Dr2", REBIRTH, 60)                                    -- back much later
	local p0 = #PRINTS
	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit 45")
	Advance(0.3)
	local v = LaneView("BATTLEREZ")
	local rings = {}
	for _, w in ipairs(v.cooling) do rings[w.owner] = w.look.ring end
	check("/cdc nexthit 45: the title says when", (CC.laneFrame.title.__text or ""):find("next hit 0:4[45]") ~= nil,
		CC.laneFrame.title.__text)
	check("  icons back by then get a gold ring, the others keep their class ring",
		rings[full("Dr1")] == "gold" and rings[full("Dr2")] == "class" and v.cooling[1].glow ~= nil,
		tostring(rings[full("Dr1")]) .. " " .. tostring(rings[full("Dr2")]))
	check("  and it says so in chat", #PRINTS > p0 and PRINTS[#PRINTS]:find("next hit in 0:45", 1, true) ~= nil, PRINTS[#PRINTS])
	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit 1:30")
	check("  M:SS works too", CC:NextHitIn() ~= nil and near(CC:NextHitIn(), 90, 0.5))
	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit soon")
	check("  a bad time prints the usage and keeps the last one", PRINTS[#PRINTS]:find("usage", 1, true) ~= nil and CC:NextHitIn() ~= nil)
	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit off")
	Advance(0.3)
	v = LaneView("BATTLEREZ")
	local anyGold = false
	for _, w in ipairs(v.cooling) do if w.look.ring == "gold" then anyGold = true end end
	check("/cdc nexthit off: no gold, the title is Lanes again", not anyGold and CC.laneFrame.title.__text == "|cFF54a3ffLanes|r",
		CC.laneFrame.title.__text)

	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit 5")
	Advance(5.3)
	check("a next hit that has come is forgotten", CC:NextHitIn() == nil and CC.laneFrame.title.__text == "|cFF54a3ffLanes|r")

	FireEvent("START_PLAYER_COUNTDOWN", "Leader", 10, 10)
	Advance(0.3)
	check("the game's pull countdown sets the next hit", CC.nextHit ~= nil and CC.nextHit.from == "pull"
		and near(CC:NextHitIn(), 9.7, 0.2), CC:NextHitIn())
	FireEvent("CANCEL_PLAYER_COUNTDOWN", "Leader")
	check("  cancelled: gone", CC:NextHitIn() == nil)
	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit 40")
	FireEvent("CANCEL_PLAYER_COUNTDOWN", "Leader")
	check("  a cancelled countdown leaves a typed time alone", CC:NextHitIn() ~= nil)
	SlashCmdList["COOLDOWNCOLLABORATOR"]("nexthit off")
	BigWigs("BigWigs_StartBar", {}, nil, "Pull", 8, 132337)
	check("a BigWigs pull bar sets the next hit", near(CC:NextHitIn(), 8, 0.05))
	BigWigs("BigWigs_StopBar", {}, "Pull")
	check("  and its stop clears it", CC:NextHitIn() == nil)
	BigWigs("BigWigs_StartPull", {}, 12)
	check("  BigWigs_StartPull too", near(CC:NextHitIn(), 12, 0.05))
	BigWigs("BigWigs_StopPull", {})
	DBMFire("DBM_TimerStart", "pull", "Pull in", 10, 0, "pull")
	check("a DBM pull timer sets it", near(CC:NextHitIn(), 10, 0.05))
	DBMFire("DBM_TimerStop", "pull")
	check("  and its stop clears it", CC:NextHitIn() == nil)
	local e0 = #ERRORS
	BigWigs("BigWigs_StartBar", {}, nil, SECRET, SECRET, 0)
	DBMFire("DBM_TimerStart", SECRET, SECRET, SECRET, 0, SECRET)
	FireEvent("START_PLAYER_COUNTDOWN", "Leader", SECRET, SECRET)
	check("hidden bar texts and lengths: no Lua error, nothing set", #ERRORS == e0 and CC:NextHitIn() == nil)

	-- the close button turns the view off, as /cdc lanes does
	CC.laneFrame.closeButton.__scripts.OnClick(CC.laneFrame.closeButton)
	check("Lane view close button: off, hidden, says how to bring it back", not CC.db.laneEnabled and not CC.laneFrame:IsShown()
		and PRINTS[#PRINTS]:find("/cdc lanes", 1, true) ~= nil)
	CC.db.laneEnabled = true
end

if RETAILAPI then
	-- our own Battle Rez cooldown hidden (combat): the lane still refreshes
	KNOWN[castID(REBIRTH)] = true
	SPELLCD[castID(REBIRTH)] = { startTime = SECRET, duration = SECRET, isEnabled = true, isActive = true }
	local e0 = #ERRORS
	CC:RefreshLanes()
	Advance(0.5)
	check("hidden own cooldown: the Lane view refreshes with no Lua error", #ERRORS == e0, ERRORS[e0 + 1])
	SPELLCD[castID(REBIRTH)], KNOWN[castID(REBIRTH)] = nil, nil
end

---------------------------------------------------------------- the dead list (P3)
local function DeadRows()
	local out = {}
	for _, row in ipairs(CC.deadFrame.rows) do
		if row.__shown then out[#out + 1] = row end
	end
	return out
end
local function rowName(row) return (row.name.__text or ""):match("|c%x%x%x%x%x%x%x%x(.-)|r") end
do
	ResetState()
	SetGroup(5)
	STUB_IS_LEADER = false
	-- a tank, a healer and a damage dealer; the healer dies last
	byName.Dr1.role, byName.Pr1.role, byName.Pa1.role, byName.Sh1.role = "HEALER", "HEALER", "TANK", "DAMAGER"
	byName.Pa1.dead = true
	Advance(0.6)
	check("dead out of combat: the dead list stays closed", not CC.deadFrame:IsShown())
	byName.Pa1.dead = nil
	Advance(0.6)
	CC.inEncounter = true
	byName.Pa1.dead = true
	Advance(1)
	byName.Sh1.dead = true
	Advance(1)
	byName.Pr1.dead = true
	Advance(0.6)
	local rows = DeadRows()
	local names = {}
	for _, r in ipairs(rows) do names[#names + 1] = rowName(r) .. "/" .. (r.role.__text or "") end
	check("5 players, deaths in combat: the window opens, healers, tanks, damage",
		CC.deadFrame:IsShown() and table.concat(names, ",") == "Pr1/Healer,Pa1/Tank,Sh1/Damage", table.concat(names, ","))
	check("  how long each has been dead", (rows[2] and rows[2].name.__text or ""):find("0:02", 1, true) ~= nil, rows[2] and rows[2].name.__text)
	check("  the top row is marked", rows[1].hi.__shown and rows[1].edge.__shown and not rows[2].hi.__shown)
	check("  in a 5-player group anyone may call: Call on every row (not the leader here)",
		rows[1].call.__shown and rows[3].call.__shown)
	check("  heading: Dead (3), and 'in your order' only for the leader", CC.deadFrame.head.__text == "Dead (3)", CC.deadFrame.head.__text)
	check("  who would answer: the living druid's Rebirth, READY",
		(CC.deadFrame.foot.__text or ""):find("Answers:", 1, true) ~= nil and CC.deadFrame.foot.__text:find("Dr1", 1, true) ~= nil
		and CC.deadFrame.foot.__text:find("READY", 1, true) ~= nil, CC.deadFrame.foot.__text)

	local c0 = #CHATSENT
	rows[1].call.__scripts.OnClick(rows[1].call)
	local said = CHATSENT[c0 + 1]
	check("Call: names the rezzer and the dead player on /party", said ~= nil and said.chan == "PARTY"
		and said.msg:find("Dr1", 1, true) ~= nil and said.msg:find("Pr1", 1, true) ~= nil and #CHATSENT == c0 + 1,
		said and (said.chan .. " " .. said.msg))
	INSTANCE_GROUP = true
	c0 = #CHATSENT
	rows[2].call.__scripts.OnClick(rows[2].call)
	check("  in a finder group: instance chat (R16)", CHATSENT[c0 + 1] ~= nil and CHATSENT[c0 + 1].chan == "INSTANCE_CHAT"
		and CHATSENT[c0 + 1].msg:find("Pa1", 1, true) ~= nil)
	INSTANCE_GROUP = false
	c0 = #CHATSENT
	SlashCmdList["COOLDOWNCOLLABORATOR"]("rez")
	check("/cdc rez with nobody targeted calls the top of the list", CHATSENT[c0 + 1] ~= nil
		and CHATSENT[c0 + 1].msg:find("Pr1", 1, true) ~= nil, CHATSENT[c0 + 1] and CHATSENT[c0 + 1].msg)

	CC.rezCharges = { charges = 0, max = 2, nextAt = GetTime() + 75, from = full("Dr1"), heardAt = GetTime() }
	Advance(0.6)
	check("no charges: the foot says so, with the next in M:SS", (CC.deadFrame.foot.__text or ""):find("No Battle Rez charges; next in 1:1", 1, true) ~= nil,
		CC.deadFrame.foot.__text)
	c0 = #CHATSENT
	rows[1].call.__scripts.OnClick(rows[1].call)
	check("  and Call names nobody", #CHATSENT == c0 and PRINTS[#PRINTS]:find("No Battle Rez charges", 1, true) ~= nil, PRINTS[#PRINTS])
	CC.rezCharges = nil

	CC.deadFrame.closeButton.__scripts.OnClick(CC.deadFrame.closeButton)
	Advance(0.6)
	check("closed: it stays closed", not CC.deadFrame:IsShown())
	byName.Dr1.dead = true
	Advance(0.6)
	check("  another death in combat opens it again", CC.deadFrame:IsShown() and #DeadRows() == 4)
	check("  nobody living with a Battle Rez: the foot says so", (CC.deadFrame.foot.__text or ""):find("Nobody living", 1, true) ~= nil,
		CC.deadFrame.foot.__text)
	for _, n in ipairs({ "Dr1", "Pr1", "Pa1", "Sh1" }) do byName[n].dead = nil end
	Advance(0.6)
	check("everyone up: it closes", not CC.deadFrame:IsShown())

	-- a hidden answer (it throws) counts as alive, with no error
	local realDead = UnitIsDeadOrGhost
	UnitIsDeadOrGhost = function(u) if u == "party2" then error("secret boolean") end return realDead(u) end
	byName.Pa1.dead = true
	local e0 = #ERRORS
	Advance(0.6)
	check("a hidden dead-or-alive answer: no Lua error, that member counts as alive",
		#ERRORS == e0 and CC.deadFrame:IsShown() and #DeadRows() == 1)
	UnitIsDeadOrGhost = realDead
	byName.Pa1.dead = nil
	Advance(0.6)
	STUB_IS_LEADER = true
end

do
	-- raids: the leader or an assist may call, a plain member may not; a wipe of 40
	ResetState()
	SetGroup(20)
	STUB_IS_LEADER, STUB_IS_ASSIST = false, false
	CC.inEncounter = true
	byName.Pr1.dead, byName.Wa1.dead = true, true
	Advance(0.6)
	local rows = DeadRows()
	check("20 players, a plain raid member: the list, no Call buttons", CC.deadFrame:IsShown() and #rows == 2
		and not rows[1].call.__shown)
	STUB_IS_ASSIST = true
	Advance(0.6)
	local c0 = #CHATSENT
	rows[1].call.__scripts.OnClick(rows[1].call)
	local chans = {}
	for i = c0 + 1, #CHATSENT do chans[#chans + 1] = CHATSENT[i].chan end
	check("  an assist: Call on each, and the call goes to RAID and RAID_WARNING", rows[1].call.__shown
		and table.concat(chans, ",") == "RAID,RAID_WARNING", table.concat(chans, ","))
	STUB_IS_ASSIST, STUB_IS_LEADER = false, true
	Advance(0.6)
	check("  the leader: 'in your order'", CC.deadFrame.head.__text == "Dead (2), in your order", CC.deadFrame.head.__text)

	SetGroup(40)
	for _, m in ipairs(GROUP) do if m.name ~= PLAYER.name then m.dead = true end end
	PLAYER.dead = true
	Advance(0.6)
	check("40 players, a wipe: ten rows and +N more for the rest", #DeadRows() == 10
		and CC.deadFrame.more.__shown and CC.deadFrame.more.__text == "+30 more", CC.deadFrame.more.__text)
	for _, m in ipairs(GROUP) do m.dead = nil end
	PLAYER.dead = nil
	CC.inEncounter = false
	Advance(0.6)
	check("  all back up: closed", not CC.deadFrame:IsShown())
end

---------------------------------------------------------------- the externals strip (P32)
local function ShownTiles(f)
	local out = {}
	for _, t in ipairs(f.tiles) do if t.__shown then out[#out + 1] = t end end
	return out
end
local function ExternalCount()
	local n = 0
	for _, m in ipairs(GROUP) do
		if m.name ~= PLAYER.name then
			for _, d in pairs(CC.SpellData) do
				if d.kind == "external" and d.class == m.class and not d.spec then n = n + 1 end
			end
		end
	end
	return n
end
CC.db.externalsEnabled = true
for _, size in ipairs({ 5, 20, 40 }) do
	ResetState()
	SetGroup(size)
	Advance(0.6)
	local want = ExternalCount()
	local tiles = ShownTiles(CC.externalsFrame)
	local shown = math.min(want, 20)
	check(string.format("%d players: an icon per external an owner has (%d), names under them, 20 at most then +N", size, want),
		#tiles == shown and (want <= 20 and not CC.externalsFrame.more.__shown
			or CC.externalsFrame.more.__text == ("+" .. (want - 20) .. " more"))
		and CC.externalsFrame:IsShown() == (want > 0), #tiles .. " shown")
end
do
	ResetState()
	SetGroup(20)
	local ext = CC:SpellsOfKind("external")
	local paladinExt
	for _, id in ipairs(ext) do if CC.SpellData[id].class == "PALADIN" then paladinExt = id break end end
	Cast("Pa1", paladinExt, 10)
	Advance(0.6)
	local tiles = ShownTiles(CC.externalsFrame)
	local last = tiles[#tiles]
	local firstReady = tiles[1].icon.look.ring == "ready"
	check("ready ones first; a cooling one after them, greyed, with its time on it",
		firstReady and last.icon.look.owner == full("Pa1") and last.icon.look.dim and last.icon.timeText.__shown
		and last.icon.timeText.__text == CC:LookIconTime(CC.SpellData[paladinExt].duration - 10), last.icon.timeText.__text)
	check("  the owner's name under each", tiles[1].lines[1].__text ~= nil and last.lines[1].__text == "Pa1")
	if FLAVOR == "retail" then
		local bos = false
		for _, t in ipairs(tiles) do if t.icon.spellID == 6940 then bos = true end end
		check("Retail: Blessing of Sacrifice is on the strip", bos)
	end
	CC.externalsFrame.closeButton.__scripts.OnClick(CC.externalsFrame.closeButton)
	check("close button: the strip is off", not CC.db.externalsEnabled and not CC.externalsFrame:IsShown())
end

---------------------------------------------------------------- the mana strip with Ask (P24)
CC.db.manaEnabled = true
for _, size in ipairs({ 5, 20, 40 }) do
	ResetState()
	SetGroup(size)
	Advance(0.6)
	local mana = CC:SpellsOfKind("mana")
	local want = 0
	for _, id in ipairs(mana) do
		if COMPS[size][CC.SpellData[id].class] then want = want + 1 end
	end
	local tiles = ShownTiles(CC.manaFrame)
	local inn
	for _, t in ipairs(tiles) do if t.icon.spellID == INNERVATE then inn = t end end
	local druids = COMPS[size].DRUID
	check(string.format("%d players: an icon per mana spell someone has (%d); Innervate %d of %d", size, want, druids, druids),
		#tiles == want and inn ~= nil and inn.lines[1].__text == string.format("%d of %d", druids, druids)
		and inn.lines[2].__text == "Dr1" and CC.manaFrame.ask.__enabled, #tiles .. " " .. tostring(inn and inn.lines[1].__text))
end
do
	-- anyone may ask: not the leader, the one in need whispers the next ready owner
	ResetState()
	SetGroup(20)
	STUB_IS_LEADER = false
	Cast("Dr1", INNERVATE, 5)
	Advance(0.6)
	local w0 = #WHISPERS
	local first = CC:ManaTiles()[1]
	CC.manaFrame.ask.__scripts.OnClick(CC.manaFrame.ask)
	local w = WHISPERS[w0 + 1]
	local data = CC.SpellData[first.spellID]
	check("Ask (not the leader): whispers the first mana spell's next ready owner '<spell> on me please'",
		w ~= nil and first.ask ~= nil and w.msg == data.name .. " on me please" and w.target == first.ask.name
		and first.ask.name ~= full("Dr1") and #WHISPERS == w0 + 1, w and (w.target .. ": " .. w.msg))
	local innTile
	for _, t in ipairs(CC:ManaTiles()) do if t.spellID == INNERVATE then innTile = t end end
	check("  Innervate: one on cooldown, the next is the next druid", innTile.ready == COMPS[20].DRUID - 1
		and innTile.ask.name == full("Dr2"))
	-- nobody else ready: Ask is off and says so
	for _, id in ipairs(CC:SpellsOfKind("mana")) do
		for _, m in ipairs(GROUP) do
			if m.class == CC.SpellData[id].class and m.name ~= PLAYER.name then Cast(m.name, id, 5) end
		end
	end
	Advance(0.6)
	w0 = #WHISPERS
	check("  every mana spell on cooldown: Ask is off", not CC.manaFrame.ask.__enabled)
	CC:AskForMana()
	check("  and asking says nobody has one ready, whispering nobody", #WHISPERS == w0
		and PRINTS[#PRINTS]:find("Nobody else", 1, true) ~= nil)
	STUB_IS_LEADER = true
	Solo()
	Advance(0.6)
	check("leaving the group closes the strips and the dead list", not CC.manaFrame:IsShown()
		and not CC.externalsFrame:IsShown() and not CC.deadFrame:IsShown())
end

---------------------------------------------------------------- the burst line (P29)
do
	CC.db.burstEnabled = true
	ResetState()
	SetGroup(5)
	KNOWN[castID(TRANQ)] = true
	local si = idOf("Survival Instincts")
	if si then KNOWN[si] = true end
	local dur = CC.SpellData[TRANQ].duration
	-- our Tranquility back in 30 s (the game shows it); the group's lust in 42 s, PI ready
	FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-T", castID(TRANQ))
	SPELLCD[castID(TRANQ)] = { startTime = GetTime() - (dur - 30), duration = dur, isEnabled = true, isActive = true }
	local lust = CC.CAPABILITIES.BLOODLUST
	local lustID = lust and lust.classes.SHAMAN and lust.classes.SHAMAN[1]
	if lustID then Cast("Sh1", lustID, CC.SpellData[lustID].duration - 42) else Cast("Pr1", PI, CC.SpellData[PI].duration - 42) end
	Advance(0.6)
	local f = CC.burstFrame
	local own, group = {}, {}
	for _, w in ipairs(f.own) do if w.__shown then own[#own + 1] = w.spellID end end
	for _, w in ipairs(f.group) do if w.__shown then group[#group + 1] = w.spellID end end
	local wantOwn = si and 2 or 1
	check("5 players: your counted spells above the line (raid / personal, 90 s or more)", #own == wantOwn and f:IsShown(),
		table.concat(own, ","))
	check("  the group's lust and Power Infusion below", #group == (lustID and 2 or 1), table.concat(group, ","))
	check("  a gold band where they meet: 0:42", f.band.__shown and near(f.meet, 42, 0.6) and f.bandTime.__text == "0:42",
		tostring(f.meet) .. " " .. tostring(f.bandTime.__text))
	CC.db.burstSpells = { [TRANQ] = true }
	Advance(0.6)
	own = {}
	for _, w in ipairs(f.own) do if w.__shown then own[#own + 1] = w.spellID end end
	check("a saved list overrides which spells count", #own == 1 and own[1] == TRANQ)
	CC.db.burstSpells = {}
	-- the meet past two minutes: no band
	if lustID then Cast("Sh1", lustID, 10) else Cast("Pr1", PI, 1) end
	Advance(0.6)
	check("  they meet past 2:00: no band", not f.band.__shown)

	for _, size in ipairs({ 20, 40 }) do
		SetGroup(size)
		local e0 = #ERRORS
		Advance(0.6)
		local n = 0
		for _, w in ipairs(f.group) do if w.__shown then n = n + 1 end end
		check(string.format("%d players: one lust and one PI below (the soonest of each), no Lua error", size),
			#ERRORS == e0 and n == (lustID and 2 or 1), n)
	end
	if RETAILAPI then
		-- our cooldown hidden in combat: the place comes from the cast we saw, the hidden value only into the swipe
		local got = {}
		for _, w in ipairs(f.own) do
			rawset(w.cooldown, "SetCooldown", function(_, start, duration) got[#got + 1] = { start, duration } end)
		end
		SPELLCD[castID(TRANQ)] = { startTime = SECRET, duration = SECRET, isEnabled = true, isActive = true }
		local e0 = #ERRORS
		Advance(0.6)
		local secretIn = false
		for _, g in ipairs(got) do if g[1] == SECRET and g[2] == SECRET then secretIn = true end end
		check("hidden own cooldown: no Lua error, and it goes only into the icon's swipe", #ERRORS == e0 and secretIn
			and f.own[1].__shown, ERRORS[e0 + 1])
	end
	SPELLCD[castID(TRANQ)], KNOWN[castID(TRANQ)] = nil, nil
	if si then KNOWN[si] = nil end
	CC.db.burstEnabled = false
	Advance(0.6)
	check("burst line off: hidden", not f:IsShown())
end

---------------------------------------------------------------- the raid plan (P12)
do
	ResetState()
	SetGroup(20)
	local name = "Ner'zhul: 2nd; plan, 100% = go"
	CC.db.plans[name] = { rows = {
		{ timer = "2nd Tank Swap", player = ME, spellID = TRANQ },
		{ timer = "Big Wave", player = full("Dr1"), spellID = REBIRTH },
		{ at = 30, player = ME, spellID = INNERVATE },
	} }
	local text = CC:EncodePlan(name, CC.db.plans[name])
	local back, plan = CC:DecodePlan(text)
	check("a plan's text: escaped, and read back the same", back == name and #plan.rows == 3
		and plan.rows[1].timer == "2nd Tank Swap" and plan.rows[2].player == full("Dr1") and plan.rows[3].at == 30
		and not text:find(name, 1, true), text)
	check("  not a plan (a rotation order, another version): nil", CC:DecodePlan("1;k=order;n=x") == nil
		and CC:DecodePlan("2;k=plan;n=x") == nil)

	-- the leader shares it; the parts come back from the leader on the raid channel
	local big = { rows = {} }
	for i = 1, 30 do big.rows[i] = { timer = "Timer number " .. i, player = full("Dr" .. (i % 12 + 1)), spellID = REBIRTH } end
	CC.db.plans["Big"] = big
	local s0 = #SENT
	local ok = CC:SharePlan("Big")
	Advance(20)
	local parts, okLen = {}, true
	for i = s0 + 1, #SENT do
		if SENT[i].msg:match("^P:2:") then
			parts[#parts + 1] = SENT[i].msg
			if #SENT[i].msg > 255 then okLen = false end
		end
	end
	check("the leader shares a plan: P parts of 255 bytes at most on the raid channel", ok and #parts > 1 and okLen
		and SENT[#SENT].channel == "RAID", #parts .. " parts")
	CC.db.plans["Big"] = nil
	CC.db.activePlan = false
	local realLeader = UnitIsGroupLeader
	local leaderUnit = byName.Dr1.unit
	UnitIsGroupLeader = function(u) return u == leaderUnit end
	for _, msg in ipairs(parts) do FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", msg, "RAID", full("Dr1")) end
	Advance(1.2)
	local got = CC.db.plans["Big"]
	check("  a copy keeps a plan from its group's leader, and it becomes the active one",
		got ~= nil and #got.rows == 30 and got.from == full("Dr1") and CC.db.activePlan == "Big"
		and got.rows[30].timer == "Timer number 30", got and #got.rows)
	CC.db.plans["Big"], CC.db.activePlan = nil, false
	for _, msg in ipairs(parts) do FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", msg, "RAID", full("Pr1")) end
	Advance(1.2)
	local heard = CC.payloads.P[full("Pr1")]
	check("  one from a plain member is put together but not kept", heard ~= nil and next(heard) ~= nil
		and CC.db.plans["Big"] == nil)
	UnitIsGroupLeader = realLeader
	STUB_IS_LEADER = false
	check("  a plain member can't share", CC:SharePlan(name) == false)
	STUB_IS_LEADER = true

	-- the prompt: the assigned player's row, the last planLead seconds of its boss timer
	CC.db.activePlan = name
	BigWigs("BigWigs_StartBar", {}, 12345, "2nd Tank Swap", 20, 0)
	Advance(10)
	local bar = CC.planBars[1]
	check("our row's timer starts: no prompt yet with 10 s to go", not bar.__shown)
	Advance(5.5)
	check("  the last 5 s: a prompt bar like the boss mod's, '<spell>: <timer>' and the countdown",
		bar.__shown and bar.left.__text == CC.SpellData[TRANQ].name .. ": 2nd Tank Swap"
		and bar.right.__text == "0:05", tostring(bar.left.__text) .. " " .. tostring(bar.right.__text))
	Advance(5)
	check("  gone once its time has come", not bar.__shown)

	-- another player's planned spell that won't be back in time is late (for the main panel)
	Cast("Dr1", REBIRTH, 10)
	DBMFire("DBM_TimerStart", "Timer1", "Big Wave (3)", 15, 0, "cd")
	local late, dueIn = CC:PlannedSpellLate(full("Dr1"), REBIRTH)
	check("a planned Rebirth on cooldown past its DBM timer (Big Wave matches Big Wave (3)): late", late == true and near(dueIn, 15, 0.2))
	check("  nobody else's planned spell is late", CC:PlannedSpellLate(full("Dr2"), REBIRTH) == false)
	check("  and we see no prompt for another player's row", not CC.planBars[1].__shown)
	DBMFire("DBM_TimerStop", "Timer1")
	check("  its timer stopped: nothing planned, not late", CC:PlannedSpellLate(full("Dr1"), REBIRTH) == false)
	DBMFire("DBM_TimerStart", "Timer1", "Big Wave (3)", 15, 0, "cd")
	CC.state[full("Dr1")].spells[REBIRTH] = GetTime() - CC.SpellData[REBIRTH].duration
	check("  back in time: not late", CC:PlannedSpellLate(full("Dr1"), REBIRTH) == false)

	-- a row at a time into the fight
	FireEvent("ENCOUNTER_START", 1, "Boss", 16, 20)
	CC.inEncounter = true
	Advance(24)
	check("a row at 0:30 into the fight: no prompt at 0:24", not CC.planBars[1].__shown)
	Advance(1.5)
	check("  a prompt from 0:25", CC.planBars[1].__shown and CC.planBars[1].left.__text == CC.SpellData[INNERVATE].name .. ": 0:30",
		CC.planBars[1].left.__text)
	FireEvent("ENCOUNTER_END", 1, "Boss", 16, 20, 1)
	CC.inEncounter = false
	Advance(0.2)
	check("  the fight over: no prompts, nothing planned", not CC.planBars[1].__shown and next(CC.planPending) == nil)

	local e0 = #ERRORS
	BigWigs("BigWigs_StartBar", {}, 1, SECRET, 20, 0)
	BigWigs("BigWigs_StartBar", {}, 1, "2nd Tank Swap", SECRET, 0)
	DBMFire("DBM_TimerStart", "x", SECRET, SECRET, 0, "cd")
	Advance(0.5)
	check("hidden timer texts or lengths: no Lua error, they match nothing", #ERRORS == e0 and next(CC.planPending) == nil)
	CC.db.plans[name], CC.db.activePlan = nil, false
end

---------------------------------------------------------------- where the dead list, externals, mana and burst start
do
	local WINS = { { "dead", "deadFrame" }, { "externals", "externalsFrame" }, { "mana", "manaFrame" }, { "burst", "burstFrame" } }
	local BLOCKF = { "essentialsFrame", "frame", "laneFrame" }
	local function R(f) return STUB_RECT(f) end
	local function hit(a, b) return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5 end
	local function pct(r) return string.format("[%.0f%% across, %.0f%% down, %.0f x %.0f]", r[1] / SCREEN_W * 100, (SCREEN_H - r[4]) / SCREEN_H * 100, r[3] - r[1], r[4] - r[2]) end
	-- who is on the screen and clear of whom, among the four and the joined block
	local function clear(what)
		local items = {}
		for _, w in ipairs(WINS) do
			local f = CC[w[2]]
			if f:IsShown() then items[#items + 1] = { w[1], R(f) } end
		end
		for _, name in ipairs(BLOCKF) do
			if CC[name]:IsShown() then items[#items + 1] = { name, R(CC[name]) } end
		end
		for _, it in ipairs(items) do
			local r = it[2]
			if r[1] < -0.5 or r[2] < -0.5 or r[3] > SCREEN_W + 0.5 or r[4] > SCREEN_H + 0.5 then return false, what .. ": " .. it[1] .. " off screen " .. pct(r) end
		end
		for i = 1, #items do
			for j = i + 1, #items do
				if hit(items[i][2], items[j][2]) then return false, what .. ": " .. items[i][1] .. " " .. pct(items[i][2]) .. " on " .. items[j][1] .. " " .. pct(items[j][2]) end
			end
		end
		return true, #items .. " windows"
	end

	CC:ResetAllWindows()
	CC.db.laneEnabled, CC.db.essentialsEnabled, CC.db.panelClosed = true, true, false
	CC.db.deadListEnabled, CC.db.externalsEnabled, CC.db.manaEnabled, CC.db.burstEnabled = true, true, true, true
	ResetState()
	SetGroup(5)
	KNOWN[castID(TRANQ)] = true
	Advance(0.6)
	local d, e, m, b = R(CC.deadFrame), R(CC.externalsFrame), R(CC.manaFrame), R(CC.burstFrame)
	local first = CC.deadFrame:IsShown()
	CC.inEncounter = true
	byName.Pa1.dead = true
	Advance(1)
	d = R(CC.deadFrame)
	check("start places: the dead list's top-left is at about 13% across, 20% down (the party frames' side)",
		CC.deadFrame:IsShown() and near(d[1] / SCREEN_W, 0.13, 0.005) and near((SCREEN_H - d[4]) / SCREEN_H, 0.20, 0.005), pct(d))
	e, m, b = R(CC.externalsFrame), R(CC.manaFrame), R(CC.burstFrame)
	check("  externals under it at about 13%, 39%", CC.externalsFrame:IsShown() and near(e[1] / SCREEN_W, 0.13, 0.005) and near((SCREEN_H - e[4]) / SCREEN_H, 0.39, 0.005), pct(e))
	check("  mana under that at about 13%, 48% (lower when the externals above it are taller)", CC.manaFrame:IsShown() and near(m[1] / SCREEN_W, 0.13, 0.005) and (SCREEN_H - m[4]) / SCREEN_H >= 0.48 - 0.005
		and m[4] <= e[2] + 0.5 or false, pct(m))
	check("  burst centred across the screen, its top about 72% down",
		CC.burstFrame:IsShown() and near((b[1] + b[3]) / 2, SCREEN_W / 2, 1) and near((SCREEN_H - b[4]) / SCREEN_H, 0.72, 0.005), pct(b))
	byName.Pa1.dead = nil
	CC.inEncounter = false
	for _, size in ipairs({ 5, 20, 40 }) do
		ResetState()
		SetGroup(size)
		CC.inEncounter = true
		byName[size == 5 and "Pa1" or "Pr1"].dead = true
		if size > 5 then byName.Wa1.dead = true end
		if size == 40 then byName.Wl1.dead = true end
		Advance(1)
		local ok, why = clear(size .. " players")
		check(string.format("%d players, all four shown with the block (dead list with %d dead): each on the screen, none on another or on the block", size, size == 5 and 1 or (size == 20 and 2 or 3)), ok, why)
		for _, mm in ipairs(GROUP) do mm.dead = nil end
		CC.inEncounter = false
		Advance(1)
	end
	-- a dead list that fills (ten rows and "+N more") pushes the column down instead of lying on it
	SetGroup(40)
	CC.inEncounter = true
	for _, mm in ipairs(GROUP) do if mm.name ~= PLAYER.name then mm.dead = true end end
	Advance(1)
	local okw, whyw = clear("a wipe of 40")
	local dr, er = R(CC.deadFrame), R(CC.externalsFrame)
	check("a wipe of 40 (ten dead rows): the externals strip is moved clear below it", not hit(dr, er) and er[4] <= dr[2], pct(dr) .. " " .. pct(er))
	for _, mm in ipairs(GROUP) do mm.dead = nil end
	CC.inEncounter = false
	Advance(1)

	-- Reset puts each at its start place; a moved one stays where it was dropped
	local X = { dead = "deadListX", externals = "externalsX", mana = "manaX", burst = "burstX" }
	local Y = { dead = "deadListY", externals = "externalsY", mana = "manaY", burst = "burstY" }
	local atNew = true
	for key in pairs(X) do
		if not (near(CC.db[X[key]], CC.DEFAULTS[X[key]], 2) and near(CC.db[Y[key]], CC.DEFAULTS[Y[key]], 2)) then atNew = false end
	end
	check("their saved places are the new defaults, not the old ones", atNew and CC.DEFAULTS.deadListX ~= -300 and CC.DEFAULTS.burstX ~= 330)
	CC.db.manaX, CC.db.manaY = -100, -150
	CC:LayoutColumn()
	local c = { CC.manaFrame:GetCenter() }
	check("a window the player moved stays where he put it", near(c[1] - SCREEN_W / 2, -100, 0.5) and near(c[2] - SCREEN_H / 2, -150, 0.5))
	CC:ResetWindow(CC.WINDOWS[6])
	local mr = R(CC.manaFrame)
	check("  Reset brings it back to its place", near(mr[1] / SCREEN_W, 0.13, 0.005))

	-- saves from before: a place still at the old start moves, a moved one stays (live x / y, layouts, profiles)
	local function oldSave()
		return {
			deadListX = -300, deadListY = 60, externalsX = -300, externalsY = -60, manaX = -250, manaY = -170, burstX = 330, burstY = -60,
		}
	end
	local old = oldSave()
	local db = CC.db
	db.startPlacesV2 = nil
	for k, v in pairs(old) do db[k] = v end
	db.layouts = { raid = { dead = { -300, 60 }, mana = { -120, -90 }, burst = { 330, -60 } } }
	db.charPlaces = { ["Me-Realm"] = { externals = { -300, -60 } } }
	db.profiles = { Alt = { places = { burst = { 330, -60 }, dead = { 10, 10 } }, layouts = { party = { externals = { -300, -60 } } } } }
	CC:MoveOldPlaces()
	check("an old save: the windows still at the old defaults move to the new places",
		db.deadListX == CC.DEFAULTS.deadListX and db.deadListY == CC.DEFAULTS.deadListY
		and db.externalsX == CC.DEFAULTS.externalsX and db.externalsY == CC.DEFAULTS.externalsY
		and db.burstX == CC.DEFAULTS.burstX and db.burstY == CC.DEFAULTS.burstY)
	check("  the one the player moved (mana, -250) stays", db.manaX == -250 and db.manaY == -170)
	check("  the same inside layouts, characters' places and profiles; a moved one in them stays",
		db.layouts.raid.dead[1] == CC.DEFAULTS.deadListX and db.layouts.raid.dead[2] == CC.DEFAULTS.deadListY
		and db.layouts.raid.mana[1] == -120 and db.layouts.raid.burst[1] == CC.DEFAULTS.burstX
		and db.charPlaces["Me-Realm"].externals[1] == CC.DEFAULTS.externalsX
		and db.profiles.Alt.places.burst[1] == CC.DEFAULTS.burstX and db.profiles.Alt.places.dead[1] == 10
		and db.profiles.Alt.layouts.party.externals[2] == CC.DEFAULTS.externalsY)
	db.deadListX = -300
	CC:MoveOldPlaces()
	check("  it runs once (a window put back on the old spot later stays)", db.deadListX == -300)
	for k in pairs(old) do db[k] = nil end
	db.layouts, db.charPlaces, db.profiles = {}, {}, nil
	CC:ResetAllWindows()
	check("a screen of another size gets places in the same shares", (function()
		local x1, y1 = CC:StartPlaceFor("dead", 1000, 500)
		local x2, y2 = CC:StartPlaceFor("dead", 2000, 1000)
		return near(x1 + 500 - 120, 0.13 * 1000, 1) and near(y2, 500 - (0.2 * 1000 + 46), 1) and y1 ~= y2 and x1 ~= x2
	end)())
	KNOWN[castID(TRANQ)] = nil
	CC.db.deadListEnabled, CC.db.externalsEnabled, CC.db.manaEnabled, CC.db.burstEnabled = true, false, false, false
	CC.db.laneEnabled = true
	Solo()
	Advance(1)
end

check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT looks %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
