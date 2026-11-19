-- CooldownCollaborator Essentials bar checks for one TOC: the owner's picked
-- looks (19 Nov 2026, the Collaborator Looks board) in a party of 5 and raids of
-- 20 and 40 on each client: three providers a heading and "+N more", the count
-- on each heading, dead and offline lines, the guessed "?", "You're the ...",
-- the charge pips, the Defensives pips, the ready check and pull banner, the
-- Soulstones line, the icons for every way back, the lust and Sated bars, and
-- the buff counts with who lacks them; hidden values on Retail and Forever.
-- Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/essentials.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[essentials %s %s]", HARNESS_TOCFILE, FLAVOR))

local LUST = ({ retail = "MAGE", mop = "MAGE", tbc = "SHAMAN" })[FLAVOR]
local CLASSES = ({
	retail = { "MAGE", "DRUID", "WARLOCK", "PRIEST", "DEATHKNIGHT", "PALADIN", "SHAMAN", "WARRIOR" },
	mop    = { "MAGE", "DRUID", "WARLOCK", "PRIEST", "DEATHKNIGHT", "SHAMAN", "WARRIOR" },
	tbc    = { "SHAMAN", "DRUID", "WARLOCK", "PRIEST", "WARRIOR", "MAGE" },
})[FLAVOR] or { "DRUID", "WARLOCK", "PRIEST", "WARRIOR", "MAGE", "SHAMAN" }

PLAYER.class = "PRIEST"
LoadTOC(HARNESS_TOCFILE)
for id, d in pairs(CC.SpellData or {}) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
CooldownCollaboratorDB = nil
Login()
CC.db.essentialsEnabled = true

local READY, RED, AMBER, GREY = { 0.3, 1, 0.3 }, { 1, 0.3, 0.3 }, { 1, 0.6, 0 }, { 0.48, 0.48, 0.48 }
local function same(c, ref)
	if type(c) ~= "table" then return false end
	for i = 1, 3 do
		if math.abs((c[i] or -1) - ref[i]) > 0.01 then return false end
	end
	return true
end
local function full(name) return name .. "-Realm" end

-- A group of n with us: a party up to 5, else a raid; classes in turn ("Mage01", "Druid02", ...).
local function Group(n, classes, extra)
	GROUP = {}
	classes = classes or CLASSES
	local raid = n > 5
	for i = 1, n - 1 do
		local class = classes[(i - 1) % #classes + 1]
		GROUP[i] = { unit = (raid and "raid" or "party") .. i, realm = "Realm", class = class,
			name = string.format("%s%02d", class:sub(1, 1) .. class:sub(2):lower(), i), guid = "Player-1-3" .. i }
		if extra then extra(GROUP[i], i) end
	end
	if raid then
		GROUP[n] = { unit = "raid" .. n, name = PLAYER.name, realm = PLAYER.realm, class = PLAYER.class, guid = PLAYER.guid }
	end
	STUB_IN_RAID = raid
	wipe(CC.state)
	FireEvent("GROUP_ROSTER_UPDATE")
end
local function Member(name)
	for _, m in ipairs(GROUP) do if m.name == name then return m end end
end

-- the bar's lines now, top down
local function Bar()
	CC:RefreshEssentials()
	return CC.essentialsShown
end
-- every line stacked right under the one above, the frame as tall as its lines
local function Stacked()
	local y = 16
	for _, line in ipairs(CC.essentialsShown) do
		local p = line.__points[1]
		if not line.__shown or not p or p[5] ~= -y then return false end
		y = y + line:GetHeight()
	end
	return CC.essentialsFrame:GetHeight() == y + 2
end
-- one capability's lines: its heading, provider lines, "+N more", lust bars, icons
local function Section(cap)
	local sec
	for _, line in ipairs(Bar()) do
		local m = line.model
		if m.kind == "heading" then
			if m.cap == cap then
				sec = { heading = line, providers = {} }
			elseif sec then
				break
			end
		elseif sec then
			if m.kind == "provider" then sec.providers[#sec.providers + 1] = line
			elseif m.kind == "text" and m.key == "more" then sec.more = line
			elseif m.kind == "bars" then sec.bars = line
			elseif m.kind == "icons" then sec.icons = line
			else break end
		end
	end
	return sec
end
local function Find(kind, key)
	local out = {}
	for _, line in ipairs(Bar()) do
		if line.model.kind == kind and (key == nil or line.model.key == key) then out[#out + 1] = line end
	end
	return out
end
local function Status(cap)
	local s = CC:GetCapabilityStatus(cap)
	table.sort(s, function(a, b) return a.name < b.name end)
	return s
end
-- a remote cast `ago` seconds back
local function Cast(name, id, ago)
	local m = Member(name)
	CC.state[full(name)] = CC.state[full(name)] or { class = m and m.class or "DRUID", spells = {} }
	CC.state[full(name)].spells[id] = NOW - ago
end
local function SetGroupState(fn)
	for _, m in ipairs(GROUP) do fn(m) end
	FireEvent("GROUP_ROSTER_UPDATE")
end

-- Fixture kinds for the Defensives line (the panel lane adds `kind` to the Data rows): one
-- priest spell "external", one druid spell "raid"; neither a provider, spec- or level-gated.
local providerID = {}
for _, cap in pairs(CC.CAPABILITIES) do
	for _, list in pairs(cap.classes) do for _, id in ipairs(list) do providerID[id] = true end end
end
local function pick(class)
	local ids = {}
	for id, d in pairs(CC.SpellData) do
		if d.class == class and not d.consumable and not providerID[id] and not d.spec and not d.level then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids[1]
end
local EXT, RAIDCD = pick("PRIEST"), pick("DRUID")
for id, d in pairs(CC.SpellData) do d.kind = nil end
if EXT then CC.SpellData[EXT].kind = "external" end
if RAIDCD then CC.SpellData[RAIDCD].kind = "raid" end
local function knowOwn(id, yes)
	local d = CC.SpellData[id]
	for _, r in ipairs(d and d.ranks or { id }) do KNOWN[r] = yes or nil end
end
if EXT then knowOwn(EXT, true) end

local GROUPS = { 5, 20, 40 }

---------------------------------------------------------------- per group size
for _, n in ipairs(GROUPS) do
	OUT(string.format(" -- %d players", n))
	Group(n)
	local e0 = #ERRORS
	Bar()
	check(n .. ": the bar shows, no Lua error, lines stacked", CC.essentialsFrame:IsShown() and #ERRORS == e0 and Stacked())

	-- [win-essentials] three providers a heading (ready first), one line for the rest
	for _, cap in ipairs(CC.CAPABILITY_ORDER) do
		local status = Status(cap)
		local sec = Section(cap)
		local named = sec and #sec.providers or -1
		local moreOK = (#status > 3) == (sec and sec.more ~= nil)
			and (not sec.more or sec.more.model.count == #status - 3)
		check(string.format("%d [win-essentials] %s: heading, %d of %d named, the rest on one line", n, cap,
			math.min(3, #status), #status), sec ~= nil and named == math.min(3, #status) and moreOK,
			sec and sec.more and sec.more.text.__text)
		if #status > 3 then
			check(string.format("%d   '+%d more, %d ready' while all are ready", n, #status - 3, #status - 3),
				sec.more.text.__text == string.format("+%d more, %d ready", #status - 3, #status - 3), sec.more.text.__text)
			-- the alphabetically first one cools: it leaves the top three, ready first
			local first = status[1]
			local data = CC.SpellData[first.spellID]
			Cast(first.name:match("^[^-]+"), first.spellID, data.duration - 300)
			sec = Section(cap)
			local inTop = false
			for _, l in ipairs(sec.providers) do if l.model.entry.name == first.name then inTop = true end end
			local wantMore = #status > 4 and string.format("+%d more, %d ready", #status - 3, #status - 4)
				or "+1 more, next 5:00"
			check(string.format("%d   a cooling provider goes below the ready ones: '%s'", n, wantMore), not inTop and
				sec.more.text.__text == wantMore, sec.more.text.__text)
			-- everyone cools; the soonest back is 4:02
			for i, e in ipairs(status) do
				local d = CC.SpellData[e.spellID]
				Cast(e.name:match("^[^-]+"), e.spellID, d.duration - (242 + i * 10))
			end
			sec = Section(cap)
			local restSoonest = 242 + 4 * 10
			check(string.format("%d   all cooling: '+%d more, next %s'", n, #status - 3,
				string.format("%d:%02d", math.floor(restSoonest / 60), restSoonest % 60)),
				sec.more.text.__text == string.format("+%d more, next %d:%02d", #status - 3, math.floor(restSoonest / 60),
					restSoonest % 60), sec.more.text.__text)
			wipe(CC.state)
		end
	end

	-- [missing-warning] the count on each heading: live providers, red at none, amber at one
	for _, cap in ipairs(CC.CAPABILITY_ORDER) do
		local live = #Status(cap)
		local sec = Section(cap)
		local want = live == 0 and RED or (live == 1 and AMBER or READY)
		check(string.format("%d [missing-warning] %s count %d in %s", n, cap, live,
			live == 0 and "red" or (live == 1 and "amber" or "green")),
			sec.heading.pill.text.__text == tostring(live) and same(sec.heading.pill.bg.__color, want), sec.heading.pill.text.__text)
	end

	-- [dead-owner] the first three Battle Rez providers dead or offline: greyed with a mark,
	-- never READY, and the next live one is named
	local rez = Status("BATTLEREZ")
	local downed = {}
	for i = 1, math.min(3, #rez) do downed[rez[i].name:match("^[^-]+")] = (i == 2) and "offline" or "dead" end
	SetGroupState(function(m)
		m.dead = downed[m.name] == "dead" or nil
		m.offline = downed[m.name] == "offline" or nil
	end)
	local sec = Section("BATTLEREZ")
	local marks, live, readyDead = {}, 0, false
	for _, l in ipairs(sec.providers) do
		local t = l.timeText.__text
		marks[#marks + 1] = t
		if t ~= "DEAD" and t ~= "OFFLINE" then live = live + 1 end
		if downed[l.model.entry.name:match("^[^-]+")] and t == "READY" then readyDead = true end
	end
	local greyOK = true
	for _, l in ipairs(sec.providers) do
		local t = l.timeText.__text
		if t == "DEAD" or t == "OFFLINE" then
			greyOK = greyOK and same(l.nameText.__textColor, GREY) and same(l.timeText.__textColor, GREY)
				and l.icon.__desat == true and same(l.classBar.__color, GREY)
		end
	end
	local liveLeft = #rez - math.min(3, #rez)
	check(string.format("%d [dead-owner] DEAD / OFFLINE greyed in the timer's place, never READY", n),
		greyOK and not readyDead and #sec.providers == math.min(3, #rez), table.concat(marks, ","))
	check(string.format("%d   the next live provider is named (%s)", n, liveLeft > 0 and "one live line" or "none left"),
		(liveLeft > 0) == (live >= 1), table.concat(marks, ","))
	local count = sec.heading.pill.text.__text
	check(string.format("%d   the heading counts only the live ones (%d)", n, liveLeft), count == tostring(liveLeft), count)
	if liveLeft == 0 then
		check(string.format("%d   none live: the count is red", n), same(sec.heading.pill.bg.__color, RED))
	end
	SetGroupState(function(m) m.dead, m.offline = nil, nil end)

	-- [guessed] a "?" after READY on Retail and Forever for a provider who doesn't run the
	-- addon and wasn't seen casting; none once they say hello, none on Era, TBC and MoP
	sec = Section("BATTLEREZ")
	local q = sec.providers[1] and sec.providers[1].qmark.__shown
	check(string.format("%d [guessed] a provider with no hello: '?' %s", n, RETAILAPI and "after READY" or "not shown here"),
		sec.providers[1] ~= nil and (q == RETAILAPI) and sec.providers[1].timeText.__text == "READY")
	for _, e in ipairs(Status("BATTLEREZ")) do CC.peers[e.name] = { proto = 2, version = CC.version, heardAt = NOW } end
	sec = Section("BATTLEREZ")
	local anyQ = false
	for _, l in ipairs(sec.providers) do if l.qmark.__shown then anyQ = true end end
	check(string.format("%d   their hello takes it away", n), not anyQ)
	wipe(CC.peers)

	-- [charges] a pip per charge, lit when banked, the next filling; the time to it
	CC.rezCharges = { charges = 1, max = 3, nextAt = NOW + 252, from = "Someone-Realm", heardAt = NOW }
	sec = Section("BATTLEREZ")
	local pips = sec.heading.pipHolder.pips
	check(string.format("%d [charges] 1 of 3 banked: three pips, one lit, '4:12'", n), sec.heading.pipHolder.count == 3
		and pips[1].lit and not pips[2].lit and not pips[3].lit and sec.heading.timeText.__text == "4:12",
		sec.heading.timeText.__text)
	CC.rezCharges = { charges = 0, max = 2, nextAt = NOW + 65, from = "Someone-Realm", heardAt = NOW }
	sec = Section("BATTLEREZ")
	check(string.format("%d   no charges: dark pips, 'no charges 1:05' in red", n), sec.heading.pipHolder.count == 2
		and not sec.heading.pipHolder.pips[1].lit and sec.heading.timeText.__text == "no charges 1:05"
		and same(sec.heading.timeText.__textColor, RED), sec.heading.timeText.__text)
	CC.rezCharges = nil
	sec = Section("BATTLEREZ")
	check(string.format("%d   no pool known: no pips", n), sec.heading.pipHolder.count == 0 and not sec.heading.timeText.__shown)

	-- [defensives-tile] one pip per counted cooldown, lit when ready, dark while cooling
	if EXT or RAIDCD then
		local function want()
			local k = 0
			if EXT then k = k + 1 end   -- ours
			for _, m in ipairs(GROUP) do
				if m.name ~= PLAYER.name and ((EXT and m.class == "PRIEST") or (RAIDCD and m.class == "DRUID")) then
					if not RETAILAPI or CC.peers[full(m.name)] then k = k + 1 end
				end
			end
			return k
		end
		if RETAILAPI then
			for _, m in ipairs(GROUP) do
				if m.class == "PRIEST" or m.class == "DRUID" then CC.peers[full(m.name)] = { proto = 2, heardAt = NOW } end
			end
		end
		local def = Find("defensives")[1]
		local k = want()
		check(string.format("%d [defensives-tile] %d pips, all lit", n, k), def ~= nil and def.pipHolder.count == k
			and def.model.ready == k, def and def.pipHolder.count)
		local target
		for _, m in ipairs(GROUP) do
			if not target and m.class == (EXT and "PRIEST" or "DRUID") then target = m end
		end
		if target then
			Cast(target.name, EXT or RAIDCD, 5)
			def = Find("defensives")[1]
			local lit = 0
			for i = 1, def.pipHolder.count do if def.pipHolder.pips[i].lit then lit = lit + 1 end end
			check(string.format("%d   one cooling: %d lit, its pip dark", n, k - 1), lit == k - 1 and def.model.ready == k - 1)
			local perRow = math.floor((212 - 78) / 13)
			check(string.format("%d   %s", n, k > perRow and "more than a row: the line grows" or "one row of pips"),
				def:GetHeight() == 22 + (math.ceil(k / perRow) - 1) * 13, def:GetHeight())
			-- hover: who and what
			local tipLines = 0
			local saveDouble = GameTooltip.AddDoubleLine
			rawset(GameTooltip, "AddDoubleLine", function() tipLines = tipLines + 1 end)
			def.__scripts.OnEnter(def)
			rawset(GameTooltip, "AddDoubleLine", saveDouble)
			check(string.format("%d   hovering lists who and what (%d lines)", n, k), tipLines == k, tipLines)
			wipe(CC.state)
		end
		if RETAILAPI then
			wipe(CC.peers)
			def = Find("defensives")[1]
			check(string.format("%d   Retail and Forever: only players who run it count (just ours now)", n),
				def ~= nil and def.pipHolder.count == (EXT and 1 or 0))
		end
	end

	-- [ready-check] a banner across the top for the countdown
	FireEvent("READY_CHECK", "Leader", 35)
	local first = Bar()[1]
	check(string.format("%d [ready-check] a ready check: the banner is the bar's first line", n), first.model.kind == "banner"
		and first.first.__text:find("Ready check", 1, true) ~= nil and first.first.__text:find("rez", 1, true) ~= nil
		and ((LUST ~= nil) == (first.first.__text:find("lust", 1, true) ~= nil)), first.first.__text)
	FireEvent("START_PLAYER_COUNTDOWN", "Leader", 8, 10, true, "Leader")
	first = Bar()[1]
	check(string.format("%d   a pull countdown: 'Pull in 8'", n), first.model.kind == "banner"
		and first.first.__text:find("Pull in 8", 1, true) ~= nil, first.first.__text)
	Advance(3)
	first = Bar()[1]
	check(string.format("%d   three seconds on: 'Pull in 5'", n), first.first.__text:find("Pull in 5", 1, true) ~= nil,
		first.first.__text)
	Advance(6)
	check(string.format("%d   and gone at the pull", n), Bar()[1].model.kind ~= "banner")
	FireEvent("READY_CHECK_FINISHED")
	check(string.format("%d   no Lua errors", n), #ERRORS == e0, ERRORS[e0 + 1])
end

---------------------------------------------------------------- [ready-check] what's still cooling, hidden and boss-mod timers
do
	Group(20)
	if EXT then
		local priest
		for _, m in ipairs(GROUP) do if not priest and m.class == "PRIEST" then priest = m end end
		if RETAILAPI then CC.peers[full(priest.name)] = { proto = 2, heardAt = NOW } end
		Cast(priest.name, EXT, CC.SpellData[EXT].duration - 41)
	end
	FireEvent("START_PLAYER_COUNTDOWN", "Leader", 8, 10, true, "Leader")
	local b = Bar()[1]
	if EXT then
		check("[ready-check] the banner names what is still cooling: '" .. CC.SpellData[EXT].name .. " 0:41'",
			b.second.__shown and b.second.__text:find(CC.SpellData[EXT].name .. " 0:41", 1, true) ~= nil
			and b.first.__text:find("externals", 1, true) ~= nil, b.second.__text)
	end
	FireEvent("CANCEL_PLAYER_COUNTDOWN", "Leader")
	check("  a cancelled countdown takes the banner away", Bar()[1].model.kind ~= "banner")
	if RETAILAPI then
		FireEvent("START_PLAYER_COUNTDOWN", "Leader", SECRET, SECRET, true, "Leader")
		b = Bar()[1]
		check("  hidden countdown seconds: 'Pull timer', no Lua error", b.model.kind == "banner"
			and b.first.__text:find("Pull timer", 1, true) ~= nil, b.first.__text)
		Advance(10.5)
		check("    gone after ten seconds", Bar()[1].model.kind ~= "banner")
	end
	-- DBM and BigWigs, through their public callbacks once loaded
	local dbmCallbacks = {}
	DBM = { RegisterCallback = function(_, event, f) dbmCallbacks[event] = f end }
	local bwMessages = {}
	BigWigsLoader = { RegisterMessage = function(_, msg, f) bwMessages[msg] = f end }
	FireEvent("ADDON_LOADED", "DBM-Core")
	check("  DBM and BigWigs: their pull callbacks registered once they load",
		dbmCallbacks.DBM_TimerBegin ~= nil and bwMessages.BigWigs_StartPull ~= nil)
	dbmCallbacks.DBM_TimerBegin("DBM_TimerBegin", "DBMRespawnTimer", "Respawn", 30, "237538", "extratimer")
	check("    a DBM timer that isn't the pull: no banner", Bar()[1].model.kind ~= "banner")
	dbmCallbacks.DBM_TimerBegin("DBM_TimerBegin", "pull", "Pull in", 10, "132349", "pull")
	b = Bar()[1]
	check("    DBM's pull: 'Pull in 10'", b.model.kind == "banner" and b.first.__text:find("Pull in 10", 1, true) ~= nil,
		b.first.__text)
	bwMessages.BigWigs_StartPull("BigWigs_StartPull", {}, 12)
	b = Bar()[1]
	check("    BigWigs' pull: 'Pull in 12'", b.first.__text:find("Pull in 12", 1, true) ~= nil, b.first.__text)
	bwMessages.BigWigs_StopPull("BigWigs_StopPull")
	check("    BigWigs' stop takes it away", Bar()[1].model.kind ~= "banner")
	DBM, BigWigsLoader = nil, nil
	wipe(CC.state); wipe(CC.peers)
end

---------------------------------------------------------------- [youre-the-rez] a line at the top
do
	PLAYER.class = "DRUID"
	for _, id in ipairs(CC.CAPABILITIES.BATTLEREZ.classes.DRUID) do knowOwn(id, true) end
	for _, n in ipairs(GROUPS) do
		-- no other druid: the only one
		local others = {}
		for _, c in ipairs(CLASSES) do
			if not (CC.CAPABILITIES.BATTLEREZ.classes[c]) then others[#others + 1] = c end
		end
		Group(n, others)
		local you = Find("text", "you")
		check(string.format("%d [youre-the-rez] the only Battle Rez: amber line at the top", n), #you == 1
			and you[1].text.__text == "You're the Battle Rez, the only one" and same(you[1].text.__textColor, AMBER)
			and Bar()[1].model.key == "you", you[1] and you[1].text.__text)
		Group(n, { "DRUID", "PRIEST" })
		local live = #Status("BATTLEREZ")
		you = Find("text", "you")
		check(string.format("%d   one of %d: a plain line", n, live), #you == 1 and (live == 1 or
			(you[1].text.__text == string.format("You're a Battle Rez, one of %d", live)
			and not same(you[1].text.__textColor, AMBER))), you[1] and you[1].text.__text)
		SetGroupState(function(m) if m.name ~= PLAYER.name and m.class == "DRUID" then m.dead = true end end)
		you = Find("text", "you")
		check(string.format("%d   the others dead: the only one again", n), #you == 1
			and you[1].text.__text == "You're the Battle Rez, the only one")
		SetGroupState(function(m) m.dead = nil end)
		-- in a raid our own raid token is dead too
		PLAYER.dead = true
		SetGroupState(function(m) if m.name == PLAYER.name then m.dead = true end end)
		check(string.format("%d   dead yourself: no line", n), #Find("text", "you") == 0)
		PLAYER.dead = nil
		SetGroupState(function(m) m.dead = nil end)
	end
	for _, id in ipairs(CC.CAPABILITIES.BATTLEREZ.classes.DRUID) do knowOwn(id, false) end
	if LUST then
		PLAYER.class = LUST
		for _, id in ipairs(CC.CAPABILITIES.BLOODLUST.classes[LUST]) do knowOwn(id, true) end
		Group(5, { "DRUID", "PRIEST", "WARRIOR", "WARRIOR" })
		local you = Find("text", "you")
		check("[youre-the-rez] the only lust: 'You're the lust, the only one'", #you == 1
			and you[1].text.__text == "You're the lust, the only one", you[1] and you[1].text.__text)
		for _, id in ipairs(CC.CAPABILITIES.BLOODLUST.classes[LUST]) do knowOwn(id, false) end
	end
	PLAYER.class = "PRIEST"
	Group(5)
	check("  a priest: no line", #Find("text", "you") == 0)
end

---------------------------------------------------------------- [charges] filling, hidden own pool
do
	Group(20)
	CC.rezCharges = { charges = 1, max = 3, nextAt = NOW + 240, from = "Someone-Realm", heardAt = NOW }
	Section("BATTLEREZ")
	Advance(120)
	local sec = Section("BATTLEREZ")
	local pip = sec.heading.pipHolder.pips[2]
	check("[charges] half way to the next charge: its pip half filled", pip.part.__shown and pip.part:GetHeight() == 5
		and sec.heading.timeText.__text == "2:00", sec.heading.timeText.__text)
	CC.rezCharges = nil
	if FLAVOR == "retail" then
		PLAYER.class = "DRUID"
		knowOwn(20484, true)
		SPELLCHARGES[20484] = { currentCharges = SECRET, maxCharges = SECRET, cooldownStartTime = SECRET, cooldownDuration = SECRET }
		Group(20)
		local e0 = #ERRORS
		Advance(2)
		sec = Section("BATTLEREZ")
		check("  Retail, our pool hidden: no Lua error, no pips", #ERRORS == e0 and sec.heading.pipHolder.count == 0)
		SPELLCHARGES[20484] = nil
		knowOwn(20484, false)
		PLAYER.class = "PRIEST"
	end
end

---------------------------------------------------------------- [defensives-tile] the saved list
if EXT and RAIDCD then
	Group(20)
	if RETAILAPI then
		for _, m in ipairs(GROUP) do CC.peers[full(m.name)] = { proto = 2, heardAt = NOW } end
	end
	CC.db.essentialsDefensives = { RAIDCD }
	local def = Find("defensives")[1]
	local druids = 0
	for _, m in ipairs(GROUP) do if m.class == "DRUID" then druids = druids + 1 end end
	check("[defensives-tile] a saved list of spell IDs overrides the kinds", def ~= nil and def.pipHolder.count == druids,
		def and def.pipHolder.count)
	CC.db.essentialsDefensives = {}
	for id, d in pairs(CC.SpellData) do if d.kind then d.kind = nil end end
	check("  no kinds and no list: no Defensives line", #Find("defensives") == 0)
	CC.SpellData[EXT].kind = "external"
	CC.SpellData[RAIDCD].kind = "raid"
	wipe(CC.peers)
end

---------------------------------------------------------------- [soulstones] the line on the bar
do
	local hasStone = CC.SpellData[CC.SOULSTONE_ID] ~= nil
	for _, n in ipairs(GROUPS) do
		Group(n)
		local wl, a, b
		for _, m in ipairs(GROUP) do
			if m.name ~= PLAYER.name then
				if not wl and m.class == "WARLOCK" then wl = m
				elseif m.class ~= "WARLOCK" and not a then a = m
				elseif m.class ~= "WARLOCK" and not b then b = m end
			end
		end
		wipe(CC.stones)
		local line = Find("text", "stones")[1]
		check(string.format("%d [soulstones] a warlock in the group, no stones out: 'Soulstones 0'", n),
			line ~= nil and line.text.__text:find("Soulstones 0", 1, true) ~= nil, line and line.text.__text)
		CC:PlaceStone(full(wl.name), full(a.name), NOW - 60)
		CC:PlaceStone(full(wl.name) .. "x", full(b.name), NOW - (CC:StoneDuration() - 220))
		a.role, b.role = "TANK", "HEALER"
		UnitGroupRolesAssigned = function(u)
			for _, m in ipairs(GROUP) do if m.unit == u then return m.role or "DAMAGER" end end
			return "NONE"
		end
		line = Find("text", "stones")[1]
		check(string.format("%d   two out, by tank and healer: 'Soulstones 2  tank 1 · healer 1'", n),
			line.model.count == 2 and line.model.tank == 1 and line.model.healer == 1
			and line.text.__text:find("tank 1", 1, true) ~= nil and line.text.__text:find("healer 1", 1, true) ~= nil,
			line.text.__text)
		local warn = Find("text", "stonewarn")
		check(string.format("%d   one about to run out: '%s's runs out in 3:40'", n, b.name), #warn == 1
			and warn[1].text.__text == b.name .. "'s runs out in 3:40" and same(warn[1].text.__textColor, AMBER),
			warn[1] and warn[1].text.__text)
		UnitGroupRolesAssigned = nil
		a.role, b.role = nil, nil
		line = Find("text", "stones")[1]
		check(string.format("%d   no roles known: who has them", n), line.text.__text:find("on " .. b.name, 1, true) ~= nil,
			line.text.__text)
		wipe(CC.stones)
	end
	if hasStone and not RETAILAPI then
		-- Era, TBC and MoP: a stone read on the member's buffs, gone when the buff is
		Group(20)
		local wl, target
		for _, m in ipairs(GROUP) do
			if not wl and m.class == "WARLOCK" then wl = m end
			if not target and m.class == "WARRIOR" then target = m end
		end
		local stoneID = (CC.SpellData[CC.SOULSTONE_ID].ranks or { CC.SOULSTONE_ID })[2] or CC.SOULSTONE_ID
		local len = CC:StoneDuration()
		UNIT_AURAS[target.name] = { HELPFUL = { { name = CC.SpellData[CC.SOULSTONE_ID].name, spellId = stoneID,
			expirationTime = NOW + 600, duration = len, sourceUnit = wl.unit } } }
		CC:PollConsumables()
		local st = CC.stones[full(target.name)]
		check("[soulstones] Era, TBC, MoP: a Soulstone read on a member's buffs, with who placed it",
			st ~= nil and st.from == full(wl.name) and math.abs(st.placedAt - (NOW + 600 - len)) < 0.01,
			st and (tostring(st.from) .. " " .. tostring(st.placedAt)))
		UNIT_AURAS[target.name] = nil
		CC:PollConsumables()
		check("  and gone when the buff is", CC.stones[full(target.name)] == nil)
	end
end

---------------------------------------------------------------- [rez-row] icons by kind, the Rez button after them
do
	local order = { 20484, 61999, 391054, CC.SOULSTONE_ID }
	for _, n in ipairs(GROUPS) do
		Group(n)
		local sec = Section("BATTLEREZ")
		local want = {}
		for _, id in ipairs(order) do
			local k = 0
			for _, e in ipairs(Status("BATTLEREZ")) do if e.spellID == id then k = k + 1 end end
			if k > 0 then want[#want + 1] = { key = "spell:" .. id, count = k } end
		end
		if CC.SpellData[CC.SOULSTONE_ID] then want[#want + 1] = { key = "stones", count = 0 } end
		local got, ok = {}, sec.icons ~= nil
		for i, w in ipairs(want) do
			local slot = sec.icons and sec.icons.slots[i]
			got[#got + 1] = slot and (slot.kindKey .. "=" .. slot.count) or "-"
			ok = ok and slot ~= nil and slot.__shown and slot.kindKey == w.key and slot.count == w.count
				and slot.badge.text.__text == tostring(w.count)
		end
		check(string.format("%d [rez-row] one icon per way back with its ready count", n), ok, table.concat(got, " "))
		check(string.format("%d   the Rez button after them (party or raid leader)", n), CC.essentialsRezBtn:IsShown()
			and CC.essentialsRezBtn.__points[1][2] == sec.icons and CC.essentialsRezBtn.__points[1][1] == "RIGHT")
		-- one rezzer used theirs: one fewer ready
		local first = Status("BATTLEREZ")[1]
		Cast(first.name:match("^[^-]+"), first.spellID, 5)
		sec = Section("BATTLEREZ")
		local slot, before
		for i, w in ipairs(want) do
			if w.key == "spell:" .. first.spellID then slot, before = sec.icons.slots[i], w.count end
		end
		check(string.format("%d   one used: its icon counts one fewer", n), slot ~= nil and slot.count == before - 1)
		wipe(CC.state)
	end
	if CC.SpellData[20608] and not CC.isRetail then
		PLAYER.class = "SHAMAN"
		knowOwn(20608, true)
		Group(5)
		local slots = Section("BATTLEREZ").icons.slots
		local reinc
		for _, s in ipairs(slots) do if s.__shown and s.kindKey == "reincarnation" then reinc = s end end
		check("[rez-row] Reincarnation for the shaman himself: ready", reinc ~= nil and reinc.count == 1)
		if RETAILAPI then
			SPELLCD[20608] = { startTime = SECRET, duration = SECRET, isEnabled = true, isActive = SECRET }
		else
			SPELLCD[20608] = { startTime = NOW - 60, duration = 3600, isEnabled = true, isActive = true }
		end
		local e0 = #ERRORS
		slots = Section("BATTLEREZ").icons.slots
		reinc = nil
		for _, s in ipairs(slots) do if s.__shown and s.kindKey == "reincarnation" then reinc = s end end
		check(RETAILAPI and "  its cooldown hidden: no Lua error, still shown" or "  on cooldown: 0",
			#ERRORS == e0 and reinc ~= nil and reinc.count == (RETAILAPI and 1 or 0), reinc and reinc.count)
		SPELLCD[20608] = nil
		knowOwn(20608, false)
		PLAYER.class = "PRIEST"
		Group(5)
	end
	local anyReinc = false
	for _, s in ipairs(Section("BATTLEREZ").icons.slots) do if s.__shown and s.kindKey == "reincarnation" then anyReinc = true end end
	check("  a priest has no Reincarnation icon", not anyReinc)
end

---------------------------------------------------------------- [lust-sated] two bars under the lust heading
if LUST then
	for _, n in ipairs(GROUPS) do
		Group(n)
		if RETAILAPI then
			PLAYER_AURA_IDS[2825] = { expirationTime = NOW + 28, duration = 40 }
			PLAYER_AURA_IDS[57724] = { expirationTime = NOW + 588, duration = 600 }
		else
			AURAS.HELPFUL = { { name = "Bloodlust", spellId = 2825, expirationTime = NOW + 28, duration = 40 } }
			AURAS.HARMFUL = { { name = "Sated", spellId = 57724, expirationTime = NOW + 588, duration = 600 } }
		end
		local sec = Section("BLOODLUST")
		local b1, b2 = sec.bars and sec.bars.bars[1], sec.bars and sec.bars.bars[2]
		check(string.format("%d [lust-sated] the lust bar: 'Bloodlust 28s', 28 of 40", n), b1 ~= nil and b1.__shown
			and b1.label.__text == "Bloodlust" and b1.timeText.__text == "28s" and b1.__value == 28 and b1.__max == 40,
			b1 and (tostring(b1.label.__text) .. " " .. tostring(b1.timeText.__text)))
		check(string.format("%d   the grey Sated bar: 'Sated 9:48'", n), b2 ~= nil and b2.__shown and b2.label.__text == "Sated"
			and b2.timeText.__text == "9:48" and same(b2.__barColor, { 0.42, 0.42, 0.5 }), b2 and b2.timeText.__text)
		check(string.format("%d   right under the heading, lines stacked", n), Bar()[1].model.kind == "heading"
			and Bar()[2].model.kind == "bars" and Stacked())
		PLAYER_AURA_IDS = {}
		AURAS.HELPFUL, AURAS.HARMFUL = {}, {}
		check(string.format("%d   gone when the auras are", n), Section("BLOODLUST").bars == nil)
	end
	if RETAILAPI then
		-- hidden fields: the time counts from when we saw it come on
		Group(20)
		Bar()
		PLAYER_AURA_IDS[2825] = true
		local e0 = #ERRORS
		local b1 = Section("BLOODLUST").bars.bars[1]
		check("[lust-sated] Retail, hidden aura values: no Lua error, the bar shows '40s'", #ERRORS == e0
			and b1.__shown and b1.timeText.__text == "40s" and b1.hidden == true, b1.timeText.__text)
		Advance(12)
		b1 = Section("BLOODLUST").bars.bars[1]
		check("  twelve seconds on: '28s'", b1.timeText.__text == "28s" and #ERRORS == e0, b1.timeText.__text)
		PLAYER_AURA_IDS = {}
	end
else
	Group(20)
	check("[lust-sated] no lust on this client: no lust heading and no bars", Section("BLOODLUST") == nil
		and #Find("bars") == 0)
end

---------------------------------------------------------------- [world-buffs] who lacks it
do
	local cats = {}
	for _, c in ipairs(CC.BuffCategories) do cats[#cats + 1] = c.key end
	local wantKeys = ({ retail = "", mists = "el", tbc = "ds,zg,sf,wb,dm,pp,el" })[CC:ClientTag()] or "ds,zg,sf,wb,dm,pp,el"
	check("[world-buffs] this client's extra counts: " .. (wantKeys == "" and "none" or wantKeys), table.concat(cats, ",") == wantKeys,
		table.concat(cats, ","))
	Group(5)
	CC:PollConsumables()
	Advance(4)
	local sent
	for i = #SENT, 1, -1 do if SENT[i].prefix == "CDCBUFF" then sent = SENT[i].msg break end end
	local pattern = "^flask:%d:food:%d"
	for _, k in ipairs(cats) do pattern = pattern .. ":" .. k .. ":%d" end
	check("  our CDCBUFF: flask and food first, then one field per extra count", sent ~= nil and sent:find(pattern .. "$") ~= nil,
		sent)
	check("  flask and food alone: the one strip, last", Bar()[#CC.essentialsShown].model.kind == "strip")

	local key = cats[3] or cats[1] or "flask"   -- Songflower where the world buffs are, else the elixir, else flask
	local count = CC.BuffCounts[key]
	local buffID = count.ids and count.ids[1]
	for _, n in ipairs(GROUPS) do
		Group(n)
		CC.db.essentialsBuffCounts = key == "flask" and { "flask", "food" } or { "flask", "food", key }
		-- every third member has it
		local have, lacking = 0, {}
		local others = {}
		for i, m in ipairs(GROUP) do
			if m.name ~= PLAYER.name then
				others[#others + 1] = m
				-- on Retail and Forever the last one is an old copy: flask and food only, nothing else known
				local old = RETAILAPI and i == #GROUP - (STUB_IN_RAID and 1 or 0)
				local yes = i % 3 == 0 and not old
				if yes then have = have + 1 end
				if RETAILAPI then
					local parts = { "flask:" .. (key == "flask" and (yes and 1 or 0) or 0) .. ":food:0" }
					for _, k in ipairs(cats) do parts[#parts + 1] = k .. ":" .. ((k == key and yes) and 1 or 0) end
					local msg = old and "flask:0:food:0" or table.concat(parts, ":")
					FireEvent("CHAT_MSG_ADDON", "CDCBUFF", msg, STUB_IN_RAID and "RAID" or "PARTY", m.name)
				elseif buffID then
					UNIT_AURAS[m.name] = { HELPFUL = yes and { { name = count.name, spellId = buffID } } or {} }
				end
			end
		end
		CC:PollConsumables()
		-- the count: its own line where there are extra counts, else the flask part of the strip
		local function counter()
			for _, l in ipairs(Find("count")) do
				if l.model.item.key == key then return l.button, l.label, l.right.__text end
			end
			for _, l in ipairs(Find("strip")) do
				for _, part in ipairs(l.parts) do
					if part.__shown and part.countKey == key then
						return part, part.text, part.text.__text:match("(%d+/%d+)")
					end
				end
			end
		end
		local button, label, figures = counter()
		local total = n
		check(string.format("%d [world-buffs] the %s count: %d/%d%s", n, count.label, have, total,
			key == "flask" and " (the strip)" or ", its own line"), button ~= nil
			and figures == string.format("%d/%d", have, total) and label.__text:find(count.label, 1, true) == 1
			and same(label.__textColor, { 1, 0.4, 0.4 }), figures)
		CC.db.essentialsBuffAim = have
		button, label = counter()
		check(string.format("%d   at the aim (%d): green", n, have), same(label.__textColor, { 0.4, 1, 0.4 }))
		CC.db.essentialsBuffAim = 0
		-- click: who lacks it
		local line = { button = button }
		line.button.__scripts.OnClick(line.button)
		local f = CC.buffMissingFrame
		local st = CC:GetGroupBuffStatus().counts[key]
		local missing, unknown = #st.missing, #st.unknown
		check(string.format("%d   clicking it opens '%s: %d missing'", n, count.name, missing), f:IsShown()
			and f.title.__text == string.format("%s: %d missing", count.name, missing), f.title.__text)
		local more = missing > 6 and string.format("and %d more", missing - 6) or nil
		check(string.format("%d   names listed%s", n, more and (", then '" .. more .. "'") or ""),
			(more == nil) == (f.names.__text:find("more", 1, true) == nil) and (not more or f.names.__text:find(more, 1, true) ~= nil),
			f.names.__text)
		check(string.format("%d   %s", n, RETAILAPI and "players without the addon show as not known" or "everyone read directly: nobody unknown"),
			(unknown > 0) == f.unknown.__shown and (RETAILAPI or unknown == 0), unknown)
		local c0 = #CHATSENT
		f.post.__scripts.OnClick(f.post)
		local names, longest, headOK = 0, 0, CHATSENT[c0 + 1] ~= nil
			and CHATSENT[c0 + 1].msg:find("Missing " .. count.name .. " (" .. missing .. "): ", 1, true) == 1
		for i = c0 + 1, #CHATSENT do
			local msg = CHATSENT[i].msg:gsub("^Missing [^:]*: ", ""):gsub("; %d+ not known$", "")
			for name in msg:gmatch("[^,]+") do if name:find("%S") then names = names + 1 end end
			longest = math.max(longest, #CHATSENT[i].msg)
		end
		check(string.format("%d   'Post' sends every name to %s chat, in messages under 255", n, STUB_IN_RAID and "raid" or "party"),
			headOK and names == missing and longest <= 255 and CHATSENT[#CHATSENT].chan == (STUB_IN_RAID and "RAID" or "PARTY"),
			(#CHATSENT - c0) .. " messages, " .. names .. " names, longest " .. longest)
		line.button.__scripts.OnClick(line.button)
		check(string.format("%d   clicking again closes it", n), not f:IsShown())
		for _, m in ipairs(GROUP) do UNIT_AURAS[m.name] = nil end
		wipe(CC.buffRoster)
	end
	CC.db.essentialsBuffCounts = { "flask", "food" }
	if FLAVOR == "forever" then
		-- our own world buff, its aura's fields hidden: found by ID, sent as sf:1
		PLAYER_AURA_IDS[15366] = true
		Group(5)
		CC:PollConsumables()
		Advance(4)
		local msg
		for i = #SENT, 1, -1 do if SENT[i].prefix == "CDCBUFF" then msg = SENT[i].msg break end end
		check("[world-buffs] Forever, our Songflower (hidden fields): sent as sf:1", msg ~= nil and msg:find(":sf:1:", 1, true) ~= nil, msg)
		PLAYER_AURA_IDS = {}
	end
end

---------------------------------------------------------------- [dead-owner] FlashEssentialsFor
do
	Group(20)
	local first = Section("BATTLEREZ").providers[1]
	CC:FlashEssentialsFor(first.model.entry.name, first.model.entry.spellID)
	first = Section("BATTLEREZ").providers[1]
	local on = first.flash.__shown
	Advance(0.35)
	local off = not Section("BATTLEREZ").providers[1].flash.__shown
	Advance(0.3)
	local again = Section("BATTLEREZ").providers[1].flash.__shown
	Advance(1)
	local done = not Section("BATTLEREZ").providers[1].flash.__shown and CC.essentialsFlash == nil
	check("FlashEssentialsFor: that provider's line flashes green twice, then stops", on and off and again and done)
end

check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT essentials %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
