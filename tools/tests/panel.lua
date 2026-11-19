-- CooldownCollaborator main panel checks for one TOC (the 19 Nov look picks):
-- running cooldowns first with ready ones folded, one column in a party and two
-- from 10 players, 28 lines then "+N more", no flask or food (R2), the close
-- button staying shut (R19), guessed / dead / offline marks, who-runs dots and
-- counts, the empty panel's reason, the tooltip's lines, the effect bar, the
-- next lust in the title, rotation numbers, team tabs, the icon style, ready
-- alerts (sound, flash, mid-screen icon, warning) and click to ask.
-- Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/panel.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[panel %s %s]", HARNESS_TOCFILE, FLAVOR))

LoadTOC(HARNESS_TOCFILE)
for id, d in pairs(CC.SpellData) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
Login()
check("loads with Tooltip.lua and Alerts.lua: no Lua errors", #ERRORS == 0, ERRORS[1])

-- the client's tracked spells by class, base IDs low to high
local byClass, classes = {}, {}
for id, d in pairs(CC.SpellData) do
	if not d.consumable and not d.spec then
		if not byClass[d.class] then byClass[d.class] = {}; classes[#classes + 1] = d.class end
		table.insert(byClass[d.class], id)
	end
end
for _, list in pairs(byClass) do table.sort(list) end
table.sort(classes)

local function full(name) return name .. "-Realm" end
-- a group of n (us included): M1 .. M(n-1), classes from classOf(i); a raid from 6
local function Group(n, classOf)
	GROUP = {}
	STUB_IN_RAID = n > 5
	for i = 1, n - 1 do
		GROUP[i] = { unit = (STUB_IN_RAID and "raid" or "party") .. i, name = "M" .. i, realm = "Realm",
			class = classOf and classOf(i) or classes[(i - 1) % #classes + 1], guid = string.format("Player-1-5%05d", i) }
	end
	FireEvent("GROUP_ROSTER_UPDATE")
end
local function Solo()
	GROUP = {}
	STUB_IN_RAID = false
	FireEvent("GROUP_ROSTER_UPDATE")
end
local function Reset()
	wipe(CC.state)
	wipe(CC.peers)
	wipe(CC.rotations)
	CC.db.panelClosed = false
	CC.db.panelStyle = "text"
	CC.db.panelTab = "all"
	CC.db.teams = {}
	CC.db.alerts = {}
	CC.db.showReady = true
end
local function M(i) return GROUP[i] end
-- M<i> used a spell `ago` seconds back (as their cast message or the combat log would say)
local function Use(i, id, ago, how)
	local m = M(i)
	CC:SetRemoteCooldown(full(m.name), id, GetTime() - (ago or 0), m.class, how)
end
local function Hello(i, version)
	FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "H:2:" .. (version or CC.version) .. ":" .. CC:ClientTag(),
		STUB_IN_RAID and "RAID" or "PARTY", full(M(i).name))
end
local function Plain(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
-- the panel's shown lines in layout order: { kind = run / rot / grey / fold / head / more, x, y, w, h, ... }
local function Lines()
	local out = {}
	for _, line in ipairs(CC.rows) do
		if line.__shown then
			local p = line.__points[#line.__points]
			local info = line.info
			local kind
			if not info then
				kind = line.divider.__shown and "head" or "more"
			elseif info.owners then
				kind = "fold"
			elseif line.greyed then
				kind = "grey"
			elseif info.place then
				kind = "rot"
			else
				kind = "run"
			end
			out[#out + 1] = { kind = kind, x = p[4], y = -p[5], w = line.__w, h = line.__h, info = info, line = line,
				name = line.nameText.__shown and Plain(line.nameText.__text) or nil,
				rawName = line.nameText.__shown and line.nameText.__text or nil,
				time = line.timeText.__shown and Plain(line.timeText.__text) or nil,
				rawTime = line.timeText.__shown and line.timeText.__text or nil,
				owners = line.ownersText.__shown and Plain(line.ownersText.__text) or nil,
				rawOwners = line.ownersText.__shown and line.ownersText.__text or nil,
				text = line.headText.__shown and Plain(line.headText.__text) or nil }
		end
	end
	return out
end
local function Count(lines, kind)
	local n = 0
	for _, l in ipairs(lines) do if l.kind == kind then n = n + 1 end end
	return n
end
local function Find(lines, pred)
	for _, l in ipairs(lines) do if pred(l) then return l end end
end
local function Refresh() CC:RefreshRows() end

---------------------------------------------------------------- 5 players: running first, ready folded, one column
Reset()
Group(5, function(i) return classes[1] end)
local A = byClass[classes[1]]
-- every groupmate has the class's first spell; M1 and M2 cool, M3 and M4 ready
Use(1, A[1], 30)
Use(2, A[1], 10)
Use(3, A[1], CC.SpellData[A[1]].duration)
Use(4, A[1], CC.SpellData[A[1]].duration)
if A[2] then Use(1, A[2], 5) end
Refresh()
local L = Lines()
local runs, folds = Count(L, "run"), Count(L, "fold")
local first, second = L[1], L[2]
check("party: one column (320 wide), running rows first", CC.frame.__w == 320 and first.kind == "run" and second.kind == "run"
	and runs == (A[2] and 3 or 2), runs .. " running")
local okOrder = true
for i = 2, runs do
	if L[i].info.remaining < L[i - 1].info.remaining then okOrder = false end
end
check("  soonest at the top", okOrder)
local head = L[runs + 1]
local fold = L[runs + 2]
check("  then a Ready heading and one folded line for the ready spell, its owners and a count",
	head and head.kind == "head" and head.text == "Ready" and fold and fold.kind == "fold" and folds == 1
	and fold.owners == "M3, M4" and fold.time == "\195\1512", fold and (tostring(fold.owners) .. " " .. tostring(fold.time)))
check("  rows are 28 px and folded lines 20 px, one under the other", first.h == 28 and fold.h == 20
	and second.y == first.y + 28 and fold.y == head.y + 17)

-- R2: flask and food never show here
local consumable
for id, d in pairs(CC.SpellData) do if d.consumable then consumable = id break end end
if consumable then
	CC:SetRemoteCooldown(full("M1"), consumable, GetTime() - 10, M(1).class)
	Refresh()
	local seen = false
	for _, r in ipairs(CC:BuildRowData()) do if r.spellID == consumable then seen = true end end
	check("R2: a flask or food timer is not on the panel", not seen)
end

---------------------------------------------------------------- 20 and 40 players: two columns, 28 cells, +N
Reset()
Group(20)
local nRunning = 0
for i = 1, 19 do
	local list = byClass[M(i).class]
	Use(i, list[1], i)          -- running, M1 soonest... no: M19 used it longest ago
	nRunning = nRunning + 1
	if list[2] then Use(i, list[2], CC.SpellData[list[2]].duration) end   -- ready
end
Refresh()
L = Lines()
local cells = {}
for _, l in ipairs(L) do if l.kind == "run" then cells[#cells + 1] = l end end
local perColumn = math.ceil(math.min(nRunning, 28) / 2)
local colOk = #cells > 1
for i, c in ipairs(cells) do
	local col = i <= perColumn and 0 or 1
	if c.h ~= 22 or (col == 0 and c.x ~= 6) or (col == 1 and c.x <= 6) then colOk = false end
	if i > 1 and i ~= perColumn + 1 and c.y ~= cells[i - 1].y + 22 then colOk = false end
end
check("20 players: two columns (380 wide) of 22 px cells, the first column filled first",
	CC.frame.__w == 380 and colOk and cells[perColumn + 1] and cells[perColumn + 1].y == cells[1].y, #cells .. " cells")
okOrder = true
for i = 2, #cells do
	if cells[i].info.remaining < cells[i - 1].info.remaining then okOrder = false end
end
check("  running first, soonest at the top of the first column", okOrder and L[1].kind == "run")
local shownCount = 0
for _, l in ipairs(L) do if l.kind ~= "head" and l.kind ~= "more" then shownCount = shownCount + 1 end end
check("  at most 28 cells", shownCount <= 28, shownCount)
check("  cells: icon, name and time (no spell name)", cells[1].name ~= nil and cells[1].line.spellText.__shown == false
	and cells[1].time ~= nil)

Reset()
Group(40)
local total = 0
for i = 1, 39 do
	for _, id in ipairs(byClass[M(i).class]) do
		Use(i, id, 1 + i * 0.1)
		total = total + 1
	end
end
CC:RecordReadyFromComm(full("M1"), byClass[M(1).class][1])   -- one ready
total = total - 1
Refresh()
L = Lines()
local more = L[#L]
check("40 players: 28 cells, then +N more for the rest",
	Count(L, "run") == 28 and more.kind == "more" and more.text == string.format("+%d more running, 1 spell ready", total - 28),
	more.text)
check("  the panel stays two columns", CC.frame.__w == 380)

---------------------------------------------------------------- R19: the close button stays shut
Reset()
Group(5)
Use(1, byClass[M(1).class][1], 5)
Refresh()
check("in a group with a cooldown the panel opens", CC.frame.__shown)
CC.closeButton.__scripts.OnClick(CC.closeButton, "LeftButton")
check("the close button closes it", not CC.frame.__shown and CC.db.panelClosed == true)
Use(2, byClass[M(2).class][1], 1)
CC:RefreshAllViews()
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", byClass[PLAYER.class][1])
Group(6)
Advance(2)
check("  and it stays shut through casts, syncs, roster changes and its timer", not CC.frame.__shown)
SlashCmdList["COOLDOWNCOLLABORATOR"]("")
check("/cdc opens it", CC.frame.__shown and CC.db.panelClosed == false)
CC.minimapBtn.__scripts.OnClick(CC.minimapBtn, "LeftButton")
check("the minimap button closes it, and that lasts too", not CC.frame.__shown and CC.db.panelClosed == true)
Advance(1)
CC:RefreshAllViews()
check("  (a refresh later)", not CC.frame.__shown)
CC.minimapBtn.__scripts.OnClick(CC.minimapBtn, "LeftButton")
check("  and opens it again", CC.frame.__shown and CC.db.panelClosed == false)

---------------------------------------------------------------- guessed, dead and offline
Reset()
Group(5)
local G = byClass[M(1).class][1]
local dur = CC.SpellData[G].duration
Use(1, G, dur, "log")                    -- from the combat log, ran out: as far as we know
Use(2, G, dur)                            -- their own word
Hello(2)
Refresh()
L = Lines()
fold = Find(L, function(l) return l.kind == "fold" and l.info.spellID == G end)
local rawM1 = fold and fold.rawOwners or ""
check("guessed: a ready timer nobody confirmed gets a ? after its owner", fold and fold.owners == "M1?, M2"
	and CC:IsGuessedReady(full("M1"), G) and not CC:IsGuessedReady(full("M2"), G), fold and fold.owners)
Hello(1)
check("  a hello from their copy takes it away", not CC:IsGuessedReady(full("M1"), G))
check("  our own cooldowns are never guessed", not CC:IsGuessedReady(CC:FullName("player"), G))

Reset()
Group(5)
M(1).dead = true
M(2).offline = true
Use(1, G, dur)
Use(2, G, dur)
Use(3, G, dur)
local other = byClass[M(4).class][1]
M(4).dead = true
Use(4, other, 10)
Refresh()
L = Lines()
local dead = Find(L, function(l) return l.kind == "grey" and l.info.name == full("M1") end)
local off = Find(L, function(l) return l.kind == "grey" and l.info.name == full("M2") end)
fold = Find(L, function(l) return l.kind == "fold" and l.info.spellID == G end)
check("dead: greyed, DEAD where the timer would be", dead and dead.time == "DEAD" and dead.line.greyed)
check("offline: greyed, OFFLINE", off and off.time == "OFFLINE")
check("  the folded line keeps only the live owner", fold and fold.owners == "M3" and fold.time == "", fold and fold.owners)
local run4 = Find(L, function(l) return l.kind == "run" and l.info.name == full("M4") end)
check("  a running cooldown of a dead owner keeps its timer", run4 and run4.time ~= "DEAD" and run4.time ~= "READY")
M(1).dead, M(2).offline, M(4).dead = nil, nil, nil

---------------------------------------------------------------- who runs it: dots, the count, the empty panel
Reset()
Group(5)
Refresh()
check("empty, nobody else runs it: says so", Plain(CC.emptyLabel.__text):find("Nobody else here runs CooldownCollaborator", 1, true)
	~= nil and CC.emptyLabel.__shown, CC.emptyLabel.__text)
Hello(1)
Hello(2, "1.0.3")
Refresh()
check("empty, two others run it: how many and who, and that nothing was used yet",
	CC.emptyLabel.__text == "3 of 5 here run CooldownCollaborator (M1, M2 and you). Nothing has been used yet; cooldowns show once someone uses one.",
	CC.emptyLabel.__text)
check("the title counts who runs it", CC.runsText.__text == "3 of 5", CC.runsText.__text)
Use(1, G, 20)
Use(2, byClass[M(2).class][1], 25)
Use(3, byClass[M(3).class][1], 30)
Refresh()
L = Lines()
local r1 = Find(L, function(l) return l.info and l.info.name == full("M1") end)
local r2 = Find(L, function(l) return l.info and l.info.name == full("M2") end)
local r3 = Find(L, function(l) return l.info and l.info.name == full("M3") end)
check("dots: green for the current version, amber for an old one, none without a copy",
	r1 and r1.rawName:find("77:255:77", 1, true) and r2 and r2.rawName:find("255:153:0", 1, true)
	and r3 and not r3.rawName:find("|T", 1, true), r1 and r1.rawName)
check("  the empty text goes once there is something", not CC.emptyLabel.__shown)
Solo()
wipe(CC.state)
Refresh()
check("solo and empty: nothing used yet", Plain(CC.emptyLabel.__text):find("^Nothing used yet") ~= nil, CC.emptyLabel.__text)

---------------------------------------------------------------- the tooltip: the game's, then the line on when it matters
Reset()
Group(5)
Hello(1, "1.0.3")
local E
for id, d in pairs(CC.SpellData) do
	if d.effect and not d.consumable and not d.spec and (not E or id < E) then E = id end
end
local edata = CC.SpellData[E]
M(1).class = edata.class
FireEvent("GROUP_ROSTER_UPDATE")
Use(1, E, 2)
Refresh()
local tip = {}
rawset(GameTooltip, "AddLine", function(_, text) tip[#tip + 1] = text end)
rawset(GameTooltip, "SetSpellByID", function(_, id) tip.spell = id end)
rawset(GameTooltip, "NumLines", function() return 1 end)
L = Lines()
local er = Find(L, function(l) return l.kind == "run" and l.info.spellID == E end)
er.line.__scripts.OnEnter(er.line)
local WHEN = { external = "For one player about to take a big hit.", raid = "For a big hit on the whole group." }
check("hover: the game's own spell tooltip, then when it matters (from kind)",
	tip.spell == (edata.ranks and edata.ranks[#edata.ranks] or E) and tip[1] == WHEN[edata.kind], tostring(tip[1]))
check("  the owner and the time left", tip[2] == "M1 \194\183 back in " .. CC:FormatTime(edata.duration - 2), tip[2])
check("  the effect still running", tip[3] == "Its effect: " .. CC:FormatTime(edata.effect - 2) .. " left", tip[3])
check("  an old copy says so", tip[4] == "Runs 1.0.3; the current version is " .. CC.version .. "." and tip[5] ~= nil, tip[4])
local lines = CC:CooldownTooltipLines(full("M2"), G)
check("  a never-seen owner: ready as far as we know, and why",
	lines[2] and lines[2].text == "M2 \194\183 ready as far as we know" and lines[3].text == "Ready as far as we know."
	and lines[4].text == "Doesn't run CooldownCollaborator and hasn't been seen casting.", lines[2] and lines[2].text)
for _, k in ipairs({ "AddLine", "SetSpellByID", "NumLines" }) do rawset(GameTooltip, k, nil) end
check("every kind has its line", (function()
	for id, d in pairs(CC.SpellData) do
		if not d.consumable and not d.custom and not CC:CooldownWhen(id) then return false end
	end
	return true
end)())

---------------------------------------------------------------- the effect bar
L = Lines()
er = Find(L, function(l) return l.kind == "run" and l.info.spellID == E end)
check("effect bar: shown on the row while the effect runs, ending with it",
	er.line.fx.__shown and math.abs(er.line.fxEnd - (GetTime() + edata.effect - 2)) < 0.01)
Advance(edata.effect - 2 + 0.6)
CC:AnimatePanel()
L = Lines()
er = Find(L, function(l) return l.kind == "run" and l.info.spellID == E end)
check("  gone when the effect ends, while the cooldown timer still runs", er and not er.line.fx.__shown
	and er.info.remaining > 0)

---------------------------------------------------------------- next lust in the title
if CC.CAPABILITIES.BLOODLUST then
	local lustClass, lustID
	for _, c in ipairs(classes) do
		local ids = CC.Providers.BLOODLUST[c]
		if ids and not lustClass then
			for _, id in ipairs(ids) do if not CC.SpellData[id].spec then lustClass, lustID = c, id break end end
		end
	end
	Reset()
	Group(5, function(i) return i <= 2 and lustClass or classes[1] end)
	Hello(1)
	Hello(2)
	Refresh()
	check("next lust: the title names a ready one", Plain(CC.lustText.__text) == "Lust M1 READY", Plain(CC.lustText.__text))
	Use(1, lustID, 10)
	Refresh()
	check("  the next ready one once it's used", Plain(CC.lustText.__text) == "Lust M2 READY", Plain(CC.lustText.__text))
	Use(2, lustID, 5)
	Refresh()
	check("  all cooling: the soonest, with its timer",
		Plain(CC.lustText.__text) == "Lust M1 " .. CC:FormatTime(CC:GetRemaining(full("M1"), lustID)), Plain(CC.lustText.__text))
	CC:RecordReadyFromComm(full("M2"), lustID)
	M(2).dead = true
	Refresh()
	check("  a dead holder is skipped", Plain(CC.lustText.__text):find("^Lust M1") ~= nil, Plain(CC.lustText.__text))
	M(2).dead = nil
else
	Refresh()
	check("no lust on this client: nothing in the title", (CC.lustText.__text or "") == "")
end

---------------------------------------------------------------- rotation numbers
Reset()
Group(6, function(i) return classes[1] end)
local R = byClass[classes[1]][1]
Use(1, R, 20)
Hello(3)
CC:SetRotation(R, { full("M1"), full("M2"), full("M3") })
L = Lines()
local rot = {}
for _, l in ipairs(L) do if l.kind == "rot" then rot[#rot + 1] = l end end
check("rotation: its rows come first, in order, numbered", #rot == 3 and L[1].kind == "rot"
	and rot[1].line.badgeText.__text == "1" and rot[2].line.badgeText.__text == "2" and rot[3].line.badgeText.__text == "3"
	and rot[1].info.name == full("M1"), #rot)
check("  the next ready one reads NEXT, the one after it READY", rot[1].time ~= "READY" and rot[2].time == "NEXT"
	and rot[3].time == "READY", tostring(rot[2] and rot[2].time) .. " " .. tostring(rot[3] and rot[3].time))
Use(2, R, 1)
Refresh()
L = Lines()
rot = {}
for _, l in ipairs(L) do if l.kind == "rot" then rot[#rot + 1] = l end end
check("  it moves on when the next one uses it", rot[2] and rot[2].time ~= "NEXT" and rot[3].time == "NEXT")
check("  our own order is saved", CC.db.rotations[R] and CC.db.rotations[R][2] == full("M2"))
-- the leader shares an order: P:2:rot-<id>
STUB_IS_LEADER = false
M(4).leader = true
local data = CC:EncodeRotation(R, { full("M3"), full("M1") })
local spellBack, namesBack = CC:DecodeRotation(data)
check("  an order encodes and decodes", spellBack == R and namesBack[1] == full("M3") and namesBack[2] == full("M1"), data)
Advance(1)
FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "P:2:rot-" .. R .. ":1/1:" .. CC:EncodeRotation(R, { full("M5") }), "RAID", full("M5"))
Refresh()
check("  a plain member's order is ignored", CC.rotations[R] and CC.rotations[R][1] == full("M1"))
FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "P:2:rot-" .. R .. ":1/1:" .. data, "RAID", full("M4"))
Refresh()
check("  the leader's order is taken (P:2:rot-<spellID>)", CC.rotations[R] and CC.rotations[R][1] == full("M3")
	and #CC.rotations[R] == 2)
M(4).leader = nil
STUB_IS_LEADER = true
local s0 = #SENT
CC:SetRotation(R, { full("M2"), full("M1") })
Advance(1)
local sentP
for i = s0 + 1, #SENT do if SENT[i].msg:match("^P:2:rot%-" .. R .. ":1/1:") then sentP = SENT[i] end end
check("  ours, as the leader, goes to the group", sentP ~= nil and sentP.channel == "RAID"
	and select(2, CC:DecodeRotation(sentP.msg:match("^P:2:[^:]+:1/1:(.*)$")))[1] == full("M2"))
CC:SetRotation(R, {})

---------------------------------------------------------------- team tabs
Reset()
Group(6)
for i = 1, 5 do Use(i, byClass[M(i).class][1], 10 + i) end
CC.db.teams = { Tuesday = { full("M1"), "M2" } }
Refresh()
local tabs = {}
for _, t in ipairs(CC.tabs) do if t.__shown then tabs[#tabs + 1] = t end end
check("team tabs: All, then one per saved team", #tabs == 2 and tabs[1].text.__text == "All" and tabs[2].text.__text == "Tuesday"
	and tabs[1].current)
tabs[2].__scripts.OnClick(tabs[2])
L = Lines()
local names = {}
for _, l in ipairs(L) do if l.info then names[#names + 1] = l.info.name end end
table.sort(names)
check("  a team's tab shows only its members (full or short names)", table.concat(names, ",") == "M1-Realm,M2-Realm"
	and CC.db.panelTab == "team:Tuesday", table.concat(names, ","))
tabs[1].__scripts.OnClick(tabs[1])
check("  All shows everyone again", Count(Lines(), "run") == 5)
CC.db.teams = {}
Refresh()
check("  no teams, no tabs", not CC.tabs[1].__shown)

---------------------------------------------------------------- the icon style
Reset()
Group(5)
Use(1, byClass[M(1).class][1], 10)
Use(2, byClass[M(2).class][1], CC.SpellData[byClass[M(2).class][1]].duration)
CC.db.panelStyle = "icons"
Refresh()
local icons = {}
for _, b in ipairs(CC.icons) do if b.__shown then icons[#icons + 1] = b end end
check("icon style: an icon per cooldown, running first, no text rows", #icons == 2 and icons[1].state == "cool"
	and icons[2].state == "ready" and #Lines() == 0)
check("  cooling: the sweep from its cast and the time on top", icons[1].cdStart ~= nil and icons[1].time.__text ~= "")
check("  ready: a green edge, no time", icons[2].edge.__shown and icons[2].time.__text == "")
check("  26 px icons", icons[1].__w == 26)
CC.db.panelStyle = "text"

---------------------------------------------------------------- ready alerts (P1)
Reset()
Group(5)
local AL = byClass[M(1).class][1]
local alDur = CC.SpellData[AL].duration
CC.db.alerts[AL] = { sound = true, flash = true, midscreen = true, warn = 5 }
local flashed = {}
CC.FlashEssentialsFor = function(_, owner, id) flashed[#flashed + 1] = owner .. ":" .. id end
SOUNDS = {}
CC.lastAlert = nil
Use(1, AL, 0)
Advance(alDur - 7)
check("alerts: nothing while it cools", #SOUNDS == 0 and CC.lastAlert == nil)
Advance(2.2)
check("  the warning N s before, once", #SOUNDS == 1 and CC.lastAlert and CC.lastAlert.secondsLeft
	and CC.lastAlert.secondsLeft <= 5, #SOUNDS)
local function Until(cond, limit)
	for _ = 1, math.floor((limit or 10) / 0.1) do
		if cond() then return true end
		Advance(0.1)
	end
	return cond()
end
local readyAt = Until(function() return #SOUNDS >= 2 end, 8)
check("  and when it's ready: the sound, once", readyAt and #SOUNDS == 2 and CC.lastAlert.secondsLeft == nil
	and SOUNDS[2].id == 8959)
check("  its Essentials line flashes too", flashed[#flashed] == full("M1") .. ":" .. AL, flashed[#flashed])
Refresh()
Advance(0.15)
CC:AnimatePanel()
fold = Find(Lines(), function(l) return l.kind == "fold" and l.info.spellID == AL end)
check("  its row flashes green", fold and (fold.line.flashAlpha or 0) > 0 and fold.line.flash.__shown)
check("  the mid-screen icon pops up with its name and owner",
	CC.midscreenFrame and CC.midscreenFrame.__shown and CC.midscreenFrame.nameText.__text == CC.SpellData[AL].name
	and CC.midscreenFrame.ownerText.__text == "M1")
Advance(1.4)
CC:AnimatePanel()
check("  the flash is over after two pulses", not fold.line.flash.__shown)
Advance(1.2)
check("  the icon is gone after 2 s and its fade", not CC.midscreenFrame.__shown)
Advance(5)
check("  nothing fires twice for one ready", #SOUNDS == 2)
-- a ready-now from their copy
Use(2, AL, 1)
Advance(0.5)
FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "R:" .. AL, "PARTY", full("M2"))
Advance(0.5)
check("  a ready-now fires it once", #SOUNDS == 3 and CC.lastAlert.owner == full("M2"))
Advance(2)
check("  and only once", #SOUNDS == 3)
-- our own spell turning ready
local mine = byClass[PLAYER.class][1]
CC.db.alerts[mine] = { sound = 12345, flash = false }
KNOWN[mine] = true
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", mine)
Advance(4)
check("  ours too (its own sound, no flash)", SOUNDS[#SOUNDS].id == 12345 and CC.lastAlert.owner == CC:FullName("player"))
CC.db.alerts = {}
CC.FlashEssentialsFor = nil

---------------------------------------------------------------- click to ask (P8)
Reset()
Group(5)
local ASK = byClass[M(1).class][1]
Use(1, ASK, CC.SpellData[ASK].duration)
Use(2, byClass[M(2).class][1], 10)
Refresh()
L = Lines()
fold = Find(L, function(l) return l.kind == "fold" and l.info.spellID == ASK end)
local runRow = Find(L, function(l) return l.kind == "run" end)
local function Click(line, shift)
	STUB_SHIFT = shift or false
	line.__scripts.OnMouseDown(line, "LeftButton")
	line.__scripts.OnMouseUp(line, "LeftButton")
	STUB_SHIFT = false
end
local c0 = #CHATSENT
Click(fold.line)
local said = CHATSENT[c0 + 1]
check("click a ready line: whispers its owner", said and said.chan == "WHISPER" and said.target == full("M1")
	and said.msg == CC.SpellData[ASK].name .. " on me please", said and said.msg)
Click(fold.line, true)
said = CHATSENT[c0 + 2]
check("  Shift-click asks in the group channel", said and said.chan == "PARTY"
	and said.msg == "M1, " .. CC.SpellData[ASK].name .. " on me please", said and said.msg)
Click(runRow.line)
check("  a running cooldown asks nothing", #CHATSENT == c0 + 2)
M(1).dead = true
Refresh()
local greyLine = Find(Lines(), function(l) return l.kind == "grey" end)
Click(greyLine.line)
check("  nor one whose owner is dead", #CHATSENT == c0 + 2)
M(1).dead = nil

check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT panel %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
