-- CooldownCollaborator group sync, copy against copy, for one TOC: up to three
-- copies of the addon, each loaded into its own stubbed client (wow.lua, one
-- Lua environment each, with its own GetTime() clock), joined by a fake group
-- channel that carries every addon message exactly as sent (and back to the
-- sender, as the game does). An old 1.x copy, a player with no copy and
-- outsiders are hand-written lines on the same channel.
-- Covers docs/MESSAGE_FORMAT_2.md: hello, state request and answer, the send
-- queue, sender-owns-it, saved timers, and the 18 Nov review's sync cards.
-- Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/sync.lua <toc file>

local OUTPUT = print
local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUTPUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
local function near(a, b, tol) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tol or 1) end

local REALM = "Realm"
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local all, live = {}, {}   -- every client made (for the error count); the ones running now
local wall = 1800000000.0  -- the real clock (time()) every client shares
local world = {}           -- name -> member record, shared by every client's GROUP
local group = {}           -- names in the group, in order
local WIRE = {}            -- every message delivered: { from, prefix, msg, channel, wall }
local FLAVOR, RETAILAPI
local guidN = 100

local function full(name) return name .. "-" .. REALM end
local function Member(name, class, extra)
	guidN = guidN + 1
	local m = { name = name, realm = REALM, class = class, guid = "Player-1-" .. string.format("%07d", guidN) }
	for k, v in pairs(extra or {}) do m[k] = v end
	world[name] = m
	return m
end
local function InGroup(name)
	for _, n in ipairs(group) do if n == name then return true end end
	return false
end
local function Errors()
	local n = 0
	for _, c in ipairs(all) do n = n + #c.ERRORS end
	return n
end
local function FirstError()
	for _, c in ipairs(all) do if c.ERRORS[1] then return c.ERRORS[1] end end
end

---------------------------------------------------------------- the channel
local delivered = {}
local function Deliver()
	local again = true
	while again do
		again = false
		for _, c in ipairs(live) do
			local n = delivered[c] or 0
			while n < #c.SENT do
				n = n + 1
				delivered[c] = n
				local m = c.SENT[n]
				if not m.refused and GROUP_CHANNELS[m.channel] and InGroup(c.cname) then
					WIRE[#WIRE + 1] = { from = c.cname, prefix = m.prefix, msg = m.msg, channel = m.channel, wall = wall }
					for _, d in ipairs(live) do
						if InGroup(d.cname) then d.FireEvent("CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, full(c.cname)) end
					end
				end
				again = true
			end
		end
	end
end

-- a hand-written line from someone without a live client (to `only`, or to every client in the group)
local function Inject(msg, channel, fromName, only, prefix)
	for _, c in ipairs(live) do
		if (not only or c == only) and (channel ~= "PARTY" or InGroup(c.cname)) then
			c.FireEvent("CHAT_MSG_ADDON", prefix or "CDCOLLAB", msg, channel, full(fromName))
		end
	end
	Deliver()
end

-- the inspect server: a NotifyInspect is answered with INSPECT_READY(guid) 0.5 s later
local inspectSeen, inFlight, maxInFlight = {}, {}, 0
local function InspectServer(c)
	local seen = inspectSeen[c] or 0
	while seen < #c.INSPECTED do
		seen = seen + 1
		local unit = c.INSPECTED[seen]
		inFlight[c] = (inFlight[c] or 0) + 1
		if inFlight[c] > maxInFlight then maxInFlight = inFlight[c] end
		local guid = c.UnitGUID(unit)
		c.C_Timer.After(0.5, function()
			inFlight[c] = inFlight[c] - 1
			c.FireEvent("INSPECT_READY", guid)
		end)
	end
	inspectSeen[c] = seen
end

local function Step(dt)
	wall = wall + dt
	for _, c in ipairs(live) do
		c.Advance(dt)
		InspectServer(c)
	end
	Deliver()
end
local function Run(seconds)
	for _ = 1, math.floor(seconds / 0.05 + 0.5) do Step(0.05) end
end

local function WireSince(mark, from, pattern)
	local out = {}
	for i = mark + 1, #WIRE do
		local w = WIRE[i]
		if (not from or w.from == from) and (not pattern or w.msg:match(pattern)) then out[#out + 1] = w end
	end
	return out
end

---------------------------------------------------------------- clients
local function SetGroupFor(c)
	local g = {}
	if InGroup(c.cname) then
		for _, n in ipairs(group) do
			if n ~= c.cname then
				g[#g + 1] = setmetatable({ unit = "party" .. (#g + 1) }, { __index = world[n] })
			end
		end
	end
	c.GROUP = g
end
local function SetGroup(names)
	group = names
	for _, c in ipairs(live) do
		SetGroupFor(c)
		c.FireEvent("GROUP_ROSTER_UPDATE")
	end
	Deliver()
end

-- a copy of the addon logged in as `name`, its process clock at `start`, with
-- saved data `db` (nil = a fresh install); prep(env) runs just before login
local function NewClient(name, start, db, prep)
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.loadfile = function(path, mode) return loadfile(path, mode or "t", env) end
	assert(loadfile(HARNESS_DIR .. "/wow.lua", "t", env))()
	FLAVOR, RETAILAPI = env.FLAVOR, env.RETAILAPI
	env.NOW = start
	env.WALL_OFFSET = wall - start
	local w = world[name]
	env.PLAYER = { guid = w.guid, name = name, realm = REALM, class = w.class, unit = "player" }
	env.CooldownCollaboratorDB = db
	env.bridge = { started = {}, stopped = {} }
	env.CDTL3 = {
		RegisterTimerType = function() return true end,
		StartTimer = function(_, _, id, t) env.bridge.started[#env.bridge.started + 1] = { id = id, t = t } end,
		StopTimer = function(_, _, id) env.bridge.stopped[#env.bridge.stopped + 1] = id end,
	}
	env.defaultSend = env.SendResult
	env.cname = name
	env.LoadTOC(HARNESS_TOCFILE)
	for id, d in pairs(env.CC.SpellData) do
		env.SPELLINFO[id] = { d.name, d.icon }
		for _, r in ipairs(d.ranks or {}) do env.SPELLINFO[r] = { d.name, d.icon } end
	end
	for id, d in pairs(env.CC.BuiltinConsumables) do env.SPELLINFO[id] = { d.name, d.icon } end
	all[#all + 1] = env
	live[#live + 1] = env
	SetGroupFor(env)
	if prep then prep(env) end
	env.Login()
	Deliver()
	return env
end

local function Drop(c)
	for i, x in ipairs(live) do if x == c then table.remove(live, i) break end end
end

-- the game's own state (spellbook, cooldowns, auras) carried from one session of
-- a character into the next, on the new session's clock, `away` seconds later
local function CarryGame(old, new, away)
	local shift = new.NOW - old.NOW - (away or 0)
	for k, v in pairs(old.KNOWN) do new.KNOWN[k] = v end
	for k, v in pairs(old.SPELLCD) do
		new.SPELLCD[k] = { startTime = v.startTime + shift, duration = v.duration, isEnabled = v.isEnabled, isActive = v.isActive }
	end
	new.AURAS.HELPFUL = {}
	for i, a in ipairs(old.AURAS.HELPFUL) do
		new.AURAS.HELPFUL[i] = { name = a.name, spellId = a.spellId, expirationTime = a.expirationTime and a.expirationTime + shift }
	end
	for k, v in pairs(old.PLAYER_AURA_IDS) do new.PLAYER_AURA_IDS[k] = v end
end

-- the saved variables file: what PLAYER_LOGOUT left, read back fresh
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = DeepCopy(v) end
	return c
end
local function Logout(c)
	c.FireEvent("PLAYER_LOGOUT")
	Drop(c)
	return DeepCopy(c.CooldownCollaboratorDB)
end

local function CastID(c, base)
	local d = c.CC.SpellData[base]
	return d.ranks and d.ranks[#d.ranks] or base
end
-- our own cast; the game's cooldown runs its full length until ComesBack
local function Cast(c, base)
	local d = c.CC.SpellData[base]
	local id = CastID(c, base)
	c.KNOWN[id] = true
	c.SPELLCD[id] = { startTime = c.NOW, duration = d.duration, isEnabled = true, isActive = true }
	c.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. id, id)
	Deliver()
end
local function ComesBack(c, base) c.SPELLCD[CastID(c, base)] = nil end
local function Rem(c, owner, id) return c.CC:GetRemaining(full(owner), id) end
local function Status(c, capKey, who)
	for _, s in ipairs(c.CC:GetCapabilityStatus(capKey)) do
		if s.name == full(who) then return s end
	end
end
local function Refuse(c, on)
	c.SendResult = on and function() return RETAILAPI and 11 or false end or c.defaultSend
end
local function RosterLine(c, who)
	local p0 = #c.PRINTS
	c.SlashCmdList["COOLDOWNCOLLABORATOR"]("roster")
	for i = p0 + 1, #c.PRINTS do
		if c.PRINTS[i]:find("    " .. who .. " [", 1, true) then return c.PRINTS[i] end
	end
	return ""
end

-- run fn with a dead friendly player "Fallen" (outside the group) as c's target; returns
-- the chat lines sent and the last line printed
local function WithDeadTarget(c, fn)
	local keep = { UnitExists = c.UnitExists, UnitIsPlayer = c.UnitIsPlayer, UnitIsFriend = c.UnitIsFriend,
		UnitIsDeadOrGhost = c.UnitIsDeadOrGhost, UnitFullName = c.UnitFullName }
	c.UnitExists = function(u) if u == "target" then return true end return keep.UnitExists(u) end
	c.UnitIsPlayer = function(u) if u == "target" then return true end return keep.UnitIsPlayer(u) end
	c.UnitIsFriend = function(a, b) if b == "target" then return true end return keep.UnitIsFriend(a, b) end
	c.UnitIsDeadOrGhost = function(u) if u == "target" then return true end return keep.UnitIsDeadOrGhost(u) end
	c.UnitFullName = function(u) if u == "target" then return "Fallen", REALM end return keep.UnitFullName(u) end
	local c0, p0 = #c.CHATSENT, #c.PRINTS
	fn()
	for k, v in pairs(keep) do c[k] = v end
	local said = {}
	for i = c0 + 1, #c.CHATSENT do said[#said + 1] = c.CHATSENT[i] end
	return said, (#c.PRINTS > p0) and c.PRINTS[#c.PRINTS] or nil
end

---------------------------------------------------------------- the players
Member("Ayla", "DRUID")
Member("Bram", "DRUID", { spec = 105 })
Member("Cyr", "PRIEST", { spec = 257 })
Member("Olde", "DRUID")    -- runs an old 1.x copy: hand-written lines
Member("Quiet", "DRUID")   -- runs no copy at all

local A = NewClient("Ayla", 1000)
local B = NewClient("Bram", 52000)
OUTPUT(string.format("[sync %s %s]", HARNESS_TOCFILE, FLAVOR))
check("two copies load, each in its own client, with no Lua errors", Errors() == 0 and A.CC ~= B.CC, FirstError())

local FLASK = ({ retail = 1230876, mop = 105694, tbc = 28520, era = 17626, forever = 17626 })[FLAVOR]
local flaskData = A.CC.SpellData[FLASK]
local byName = A.CC.ConsumableMatch == "name"
-- a flask with `left` seconds to go: its end readable on Era, TBC and MoP, hidden on Retail and Forever
local function PutFlask(c, left)
	if byName then
		c.AURAS.HELPFUL = { { name = flaskData.name, spellId = 99001, expirationTime = c.NOW + left } }
	else
		c.PLAYER_AURA_IDS[FLASK] = true
	end
end
local function DropFlask(c)
	c.AURAS.HELPFUL = {}
	c.PLAYER_AURA_IDS[FLASK] = nil
end

---------------------------------------------------------------- joining: hello, state, flask status
PutFlask(A, 600)
local flaskOnAt = A.NOW
Run(3)
check("solo: nothing is sent", #A.SENT == 0 and #B.SENT == 0, #A.SENT .. "/" .. #B.SENT)
SetGroup({ "Ayla", "Bram" })
Run(8)
local pb = A.CC.peers[full("Bram")]
check("hello: each copy knows the other's version and client (P13)",
	pb ~= nil and pb.proto == 2 and pb.version == B.CC.version and pb.client == A.CC:ClientTag()
	and A.CC:ClientTag() == ({ retail = "retail", mop = "mists", tbc = "tbc", era = "era", forever = "forever" })[FLAVOR]
	and B.CC.peers[full("Ayla")] ~= nil and B.CC.peers[full("Ayla")].proto == 2,
	pb and (tostring(pb.version) .. " " .. tostring(pb.client)))
check("R7: a flask put on while solo reaches the group on joining",
	B.CC.buffRoster[full("Ayla")] ~= nil and B.CC.buffRoster[full("Ayla")].flask == true)
local flaskWant = byName and (600 - (A.NOW - flaskOnAt)) or (flaskData.duration - (A.NOW - flaskOnAt - 2))
check("R8: our flask's timer " .. (byName and "runs to the aura's own end" or "starts when first seen (its end is hidden here)"),
	near(Rem(A, "Ayla", FLASK), flaskWant, 2.5), tostring(Rem(A, "Ayla", FLASK)) .. " want " .. flaskWant)
check("  and the group sees the same time (from our state message on joining)",
	near(Rem(B, "Ayla", FLASK), Rem(A, "Ayla", FLASK), 1), tostring(Rem(B, "Ayla", FLASK)))

---------------------------------------------------------------- R5: our filters never stop our casts
A.CC.db.disabledSpells[29166] = true
A.CC.db.minDuration = 99999
Cast(A, 29166)
Run(1)
local innervate = A.CC.SpellData[29166]
check("R5: an unticked spell, below our minimum length, still reaches the group",
	near(Rem(B, "Ayla", 29166), innervate.duration - 1, 1), tostring(Rem(B, "Ayla", 29166)))
local shownOwn = false
for _, row in ipairs(A.CC:BuildRowData()) do if row.spellID == 29166 then shownOwn = true end end
check("  while our own list still hides it", not shownOwn)
A.CC.db.disabledSpells[29166] = nil
A.CC.db.minDuration = 60

---------------------------------------------------------------- R12: CDTL3 follows our untick and minimum
local function startedFor(c, id) local n = 0; for _, s in ipairs(c.bridge.started) do if s.id == id then n = n + 1 end end return n end
local function stoppedFor(c, id) local n = 0; for _, s in ipairs(c.bridge.stopped) do if s == id then n = n + 1 end end return n end
local inID = full("Ayla") .. ":29166"
check("R12: a groupmate's cast goes to CDTL3", startedFor(B, inID) >= 1)
local stops0 = stoppedFor(B, inID)
B.CC.db.disabledSpells[29166] = true
Run(1.5)
check("  unticking it here takes it off CDTL3", stoppedFor(B, inID) > stops0)
local tranq = A.CC.SpellData[740]
B.CC.db.minDuration = tranq.duration + 1
Run(1.5)
local tqID = full("Ayla") .. ":740"
Cast(A, 740)
Run(1)
check("  a groupmate's spell below our minimum never reaches it", startedFor(B, tqID) == 0 and Rem(B, "Ayla", 740) ~= nil)
local starts0 = startedFor(B, inID)
B.CC.db.disabledSpells[29166] = nil
B.CC.db.minDuration = 60
Run(1.5)
check("  ticking it again puts the running timers back", startedFor(B, inID) > starts0 and startedFor(B, tqID) >= 1)

---------------------------------------------------------------- R4, P16: a joiner is filled in at once
Cast(A, 20484)
Cast(B, 740)
Run(12)
local C = NewClient("Cyr", 300)
check("a third copy (the joiner) loads", Errors() == 0, FirstError())
local cMark = #WIRE
SetGroup({ "Ayla", "Bram", "Cyr" })
Run(8)
local rebirth = A.CC.SpellData[20484]
check("R4: the joiner sees Ayla's Rebirth cooling, as Ayla does",
	near(Rem(C, "Ayla", 20484), Rem(A, "Ayla", 20484), 1) and Rem(C, "Ayla", 20484) > 0,
	tostring(Rem(C, "Ayla", 20484)) .. " / " .. tostring(Rem(A, "Ayla", 20484)))
check("  and Bram's Tranquility, as Bram does", near(Rem(C, "Bram", 740), Rem(B, "Bram", 740), 1), tostring(Rem(C, "Bram", 740)))
local ar = Status(C, "BATTLEREZ", "Ayla")
check("  Ayla is not a ready Battle Rez provider there", ar ~= nil and ar.ready == false and ar.guessed == false)
check("R7: the joiner hears the flask status in answer to its state request",
	C.CC.buffRoster[full("Ayla")] ~= nil and C.CC.buffRoster[full("Ayla")].flask == true)
check("  and every copy's version", C.CC.peers[full("Ayla")] ~= nil and C.CC.peers[full("Bram")] ~= nil
	and C.CC.peers[full("Ayla")].version == A.CC.version)
local qs = WireSince(cMark, "Cyr", "^Q:2$")
check("the joiner asked once (Q:2)", #qs == 1, #qs)

---------------------------------------------------------------- Q: one answer per 10 s, after a random wait
Run(12)
local qMark, qAt = #WIRE, wall
Inject("Q:2", "PARTY", "Cyr", A)
Run(1)
Inject("Q:2", "PARTY", "Cyr", A)
Run(3.5)
local answers = WireSince(qMark, "Ayla", "^S:2:")
local hellos = WireSince(qMark, "Ayla", "^H:2:")
local buffs = WireSince(qMark, "Ayla", "^flask:")
check("Q: two requests within the wait get one answer: hello, state and flask/food",
	#answers == 1 and #hellos == 1 and #buffs == 1, #answers .. " " .. #hellos .. " " .. #buffs)
local answerAt = answers[1] and answers[1].wall or 0
check("  sent 0 to 3 s after the request (and the queue's spacing)", answerAt - qAt >= 0 and answerAt - qAt <= 3.8,
	string.format("%.2f s", answerAt - qAt))
Inject("Q:2", "PARTY", "Cyr", A)
local q2 = wall
Run(math.max(0, answerAt + 9.8 - wall))
local early = #WireSince(qMark, "Ayla", "^S:2:")
Run(4)
local later = WireSince(qMark, "Ayla", "^S:2:")
check("  a request inside the 10 s is answered when they are up, not before",
	early == 1 and #later == 2 and later[2].wall >= answerAt + 10 - 0.05,
	string.format("%d then %d, %.2f s after the first answer (asked %.2f s after)", early, #later,
		later[2] and later[2].wall - answerAt or -1, q2 - answerAt))

---------------------------------------------------------------- the queue: spacing and repeats
Run(12)
local h0 = #WireSince(0, "Ayla", "^H:2:")
A.CC:SendHello(); A.CC:SendHello()
Run(0.5)
A.CC:SendHello()
Run(0.3)
local h1 = #WireSince(0, "Ayla", "^H:2:")
Run(1)
A.CC:SendHello()
Run(0.3)
local h2 = #WireSince(0, "Ayla", "^H:2:")
check("queue: the same message again within 1 s is dropped, and goes out after", h1 == h0 + 1 and h2 == h0 + 2,
	h0 .. " " .. h1 .. " " .. h2)
local mark = #WIRE
for _, id in ipairs({ 20484, 740, 29166 }) do A.CC:SendCooldownSync(id, full("Ayla"), A.CC.state[full("Ayla")].spells[id]) end
A.CC:SendHello(); A.CC:SendStateRequest()
Run(2)
local burst = WireSince(mark, "Ayla")
local gapsOK = #burst == 5
for i = 2, #burst do
	if burst[i].wall - burst[i - 1].wall < 0.25 - 1e-6 then gapsOK = false end
end
check("  a burst of five goes out one every 0.25 s or more (P35)", gapsOK, #burst .. " sent")

---------------------------------------------------------------- an old 1.x copy, relays and forgeries (R10, R11)
SetGroup({ "Ayla", "Bram", "Cyr", "Olde" })
Run(1)
Inject("20484:30.000:Olde:DRUID", "PARTY", "Olde")
check("an old 1.x copy's own cast line is still read",
	near(Rem(A, "Olde", 20484), rebirth.duration - 30, 0.5) and near(Rem(C, "Olde", 20484), rebirth.duration - 30, 0.5),
	tostring(Rem(A, "Olde", 20484)))
local po = A.CC.peers[full("Olde")]
check("  and marks it as an old copy (heard, no hello)", po ~= nil and po.proto == 1)
local bTq = Rem(A, "Bram", 740)
Inject("29166:5.000:Bram:DRUID", "PARTY", "Olde")
Inject("740:5.000:Ayla:DRUID", "PARTY", "Olde")
check("R10, R11: a relay naming someone else is dropped (another player, or us)",
	Rem(A, "Bram", 29166) == nil and near(Rem(A, "Bram", 740), bTq, 0.1) and near(Rem(A, "Ayla", 740), Rem(B, "Ayla", 740), 1))
Inject("740:1.000:Bram:DRUID", "WHISPER", "Bram")
Inject("740:1.000:Bram:DRUID", "GUILD", "Bram")
Inject("740:1.000:Stranger:DRUID", "PARTY", "Stranger")
check("  a whisper, a guild line and a non-member's line are dropped",
	near(Rem(A, "Bram", 740), bTq, 0.1) and A.CC.state[full("Stranger")] == nil)
Inject("740:-50.000:Olde:DRUID", "PARTY", "Olde")
Inject("740:99999:Olde:DRUID", "PARTY", "Olde")
Inject("740:nan:Olde:DRUID", "PARTY", "Olde")
check("  secondsAgo below 0 or past the spell's length is dropped, not stored", Rem(A, "Olde", 740) == nil)
Inject("S:2:DRUID:29166,12.0;740,-5.0;20739,99999.0", "PARTY", "Olde", A)
check("  the same inside a state list: the good entry kept, the bad ones dropped",
	near(Rem(A, "Olde", 29166), innervate.duration - 12, 0.5) and Rem(A, "Olde", 740) == nil
	and near(Rem(A, "Olde", 20484), 0, 0.01), tostring(Rem(A, "Olde", 20484)))
A.CC.state[full("Olde")].spells[29166] = nil
Inject("20484:30.000:Olde:DRUID", "PARTY", "Olde", A)
Inject("R:20484", "PARTY", "Olde")
check("  an old copy's ready-now is read from its owner", Rem(A, "Olde", 20484) == 0 and Rem(C, "Olde", 20484) == 0, tostring(Rem(A, "Olde", 20484)) .. " " .. tostring(Rem(C, "Olde", 20484)))

---------------------------------------------------------------- R9 and the boss end in a mixed group
Run(12)
mark = #WIRE
for _, c in ipairs(live) do c.FireEvent("ENCOUNTER_START", 1, "Boss", 15, 20) end
Refuse(A, true)
ComesBack(A, 29166)    -- talented Innervate comes back during the fight
Cast(A, 740)           -- and a cast inside the fight
Run(34)                -- past the 15 tries of each
local inFight = #WireSince(mark, "Ayla")
for _, c in ipairs(live) do c.FireEvent("ENCOUNTER_END", 1, "Boss", 15, 20, 1) end
Refuse(A, false)
Run(6)
local after = WireSince(mark, "Ayla")
local function count(list, pattern) local n = 0; for _, w in ipairs(list) do if w.msg:match(pattern) then n = n + 1 end end return n end
check("R9: nothing gets out during the fight; its refused ready-now goes out once at the boss end",
	inFight == 0 and count(after, "^R:29166$") == 1, inFight .. " / " .. count(after, "^R:29166$"))
check("  the group shows it ready", Rem(B, "Ayla", 29166) == 0 and Rem(C, "Ayla", 29166) == 0)
check("boss end with a 1.x copy in the group: our state (S) and the per-spell 1.x lines",
	count(after, "^S:2:DRUID:") == 1 and count(after, "^740:") == 1, count(after, "^S:2:") .. " S, " .. count(after, "^740:") .. " lines")
check("  the cast held back in the fight reaches the group", near(Rem(B, "Ayla", 740), Rem(A, "Ayla", 740), 1))
SetGroup({ "Ayla", "Bram", "Cyr" })
Run(12)
mark = #WIRE
for _, c in ipairs(live) do c.FireEvent("ENCOUNTER_START", 2, "Boss 2", 15, 20) end
Refuse(A, true)
Cast(A, 740)
Run(34)
for _, c in ipairs(live) do c.FireEvent("ENCOUNTER_END", 2, "Boss 2", 15, 20, 1) end
Refuse(A, false)
Run(6)
after = WireSince(mark, "Ayla")
check("boss end with only format 2 copies: S alone, no 1.x lines",
	count(after, "^S:2:") == 1 and count(after, "^%d+:") == 0, count(after, "^S:2:") .. " S, " .. count(after, "^%d+:") .. " lines")
check("  and the fight's cast still reaches the group", near(Rem(B, "Ayla", 740), Rem(A, "Ayla", 740), 1))

---------------------------------------------------------------- R6: offline and dead providers; P44 guessed; P13 roster
SetGroup({ "Ayla", "Bram", "Cyr", "Olde", "Quiet" })
-- Olde, back in the group, casts a Rebirth that is just over
Inject(string.format("20484:%.3f:Olde:DRUID", rebirth.duration - 0.5), "PARTY", "Olde")
Run(1)
world.Bram.offline = true
local sb = Status(C, "BATTLEREZ", "Bram")
check("R6: an offline provider isn't ready (online = false)", sb ~= nil and sb.online == false and sb.ready == false)
local so, sq = Status(C, "BATTLEREZ", "Olde"), Status(C, "BATTLEREZ", "Quiet")
check("  a living, online one is (online, alive)", so ~= nil and so.ready and so.online and so.alive)
do
	local keep = { UnitExists = C.UnitExists, UnitIsPlayer = C.UnitIsPlayer, UnitIsFriend = C.UnitIsFriend,
		UnitIsDeadOrGhost = C.UnitIsDeadOrGhost, UnitFullName = C.UnitFullName }
	C.UnitExists = function(u) if u == "target" then return true end return keep.UnitExists(u) end
	C.UnitIsPlayer = function(u) if u == "target" then return true end return keep.UnitIsPlayer(u) end
	C.UnitIsFriend = function(a, b) if b == "target" then return true end return keep.UnitIsFriend(a, b) end
	C.UnitIsDeadOrGhost = function(u) if u == "target" then return true end return keep.UnitIsDeadOrGhost(u) end
	C.UnitFullName = function(u) if u == "target" then return "Fallen", REALM end return keep.UnitFullName(u) end
	-- Quiet sorts ahead of nobody: make Olde the only one, by putting Quiet on cooldown
	Inject("20484:10.000:Quiet:DRUID", "PARTY", "Quiet", C)
	local c0 = #C.CHATSENT
	C.CC:RequestRez()
	local said = C.CHATSENT[c0 + 1]
	check("  Request Rez skips the offline rezzer and names the living one",
		said ~= nil and said.msg:find("Olde", 1, true) ~= nil and said.msg:find("Bram", 1, true) == nil, said and said.msg)
	world.Olde.dead = true
	local sd = Status(C, "BATTLEREZ", "Olde")
	c0 = #C.CHATSENT
	C.CC:RequestRez()
	check("  a dead rezzer: alive = false, and Request Rez finds nobody", sd ~= nil and sd.alive == false
		and #C.CHATSENT == c0 and C.PRINTS[#C.PRINTS]:find("No living", 1, true) ~= nil, C.PRINTS[#C.PRINTS])
	world.Olde.dead, world.Bram.offline = nil, nil
	for k, v in pairs(keep) do C[k] = v end
	C.CC.state[full("Quiet")], C.CC.peers[full("Quiet")] = nil, nil
end
sq = Status(C, "BATTLEREZ", "Quiet")
so = Status(C, "BATTLEREZ", "Olde")
sb = Status(C, "BATTLEREZ", "Bram")
check("P44: guessed only for a provider with no copy and no cast seen",
	sq ~= nil and sq.guessed == true and so.guessed == false and sb.guessed == false
	and Status(A, "BATTLEREZ", "Ayla").guessed == false)
local lb, lo, lq, lc = RosterLine(C, "Bram"), RosterLine(C, "Olde"), RosterLine(C, "Quiet"), RosterLine(C, "Cyr")
check("P13: /cdc roster says who runs it: a version, an old 1.x copy, no hello, you",
	lb:find(B.CC.version, 1, true) and not lb:find("old", 1, true) and lo:find("1.x (old version", 1, true)
	and lq:find("no hello", 1, true) and lc:find("you, " .. C.CC.version, 1, true) and true or false,
	lo .. " | " .. lq)
Inject("H:2:0.9.0:" .. A.CC:ClientTag(), "PARTY", "Olde", C)
check("  an older version's hello is marked old", RosterLine(C, "Olde"):find("0.9.0 (old version)", 1, true) ~= nil,
	RosterLine(C, "Olde"))
SetGroup({ "Ayla", "Bram", "Cyr" })
Run(1)

---------------------------------------------------------------- P11: the battle rez charge pool
local bRez = CastID(B, 20484)
B.KNOWN[bRez] = true
B.SPELLCHARGES[bRez] = { currentCharges = 1, maxCharges = 2, cooldownStartTime = B.NOW - 100, cooldownDuration = 600 }
mark = #WIRE
Run(4)
local rc = C.CC.rezCharges
check("P11: the pool one copy reads reaches the others (charges, max, next, from)",
	rc ~= nil and rc.charges == 1 and rc.max == 2 and rc.from == full("Bram") and B.CC.rezCharges ~= nil
	and near(rc.nextAt - C.NOW, B.CC.rezCharges.nextAt - B.NOW, 1.5)
	and A.CC.rezCharges ~= nil and A.CC.rezCharges.charges == 1 and B.CC.rezCharges ~= nil,
	rc and (rc.charges .. "/" .. rc.max .. " " .. tostring(rc.nextAt and rc.nextAt - C.NOW)) or "none")
check("  sent by the copy that can read it, once", #WireSince(mark, "Bram", "^C:2:") == 1 and #WireSince(mark, "Ayla", "^C:2:") == 0
	and #WireSince(mark, "Cyr", "^C:2:") == 0)
B.SPELLCHARGES[bRez].currentCharges = 0
Run(4)
check("  a charge used: the new count goes out", C.CC.rezCharges ~= nil and C.CC.rezCharges.charges == 0)
local rs = Status(C, "BATTLEREZ", "Ayla")
check("  the pool known empty: the Battle Rez entries carry noCharges", rs ~= nil and rs.noCharges == true)
local nextIn = B.CC.rezCharges.nextAt - B.NOW
local said, printed = WithDeadTarget(C, function() C.CC:RequestRez() end)
local m, sec = (printed or ""):match("No Battle Rez charges; next in (%d+):(%d%d)$")
check("  Request Rez says no charges and when the next comes (M:SS), and names nobody",
	#said == 0 and m ~= nil and near(tonumber(m) * 60 + tonumber(sec), nextIn, 2),
	tostring(printed) .. " (next in " .. string.format("%.1f", nextIn) .. " s)")
local keepNext = C.CC.rezCharges.nextAt
C.CC.rezCharges.nextAt = C.NOW - 1
check("  a recharge that has come due counts as a charge", Status(C, "BATTLEREZ", "Ayla").noCharges == false)
C.CC.rezCharges.nextAt = keepNext
B.SPELLCHARGES[bRez].currentCharges = 1
Run(4)
check("  a charge back: noCharges clears", Status(C, "BATTLEREZ", "Ayla").noCharges == false)
B.SPELLCHARGES[bRez] = nil
Run(4)
check("  the pool ending clears it everywhere", C.CC.rezCharges == nil and A.CC.rezCharges == nil and B.CC.rezCharges == nil)

---------------------------------------------------------------- P and O: chunked payloads, stored once complete
Inject("P:2:plan1:1/2:abc", "PARTY", "Bram", A)
local partial = A.CC.payloads.P[full("Bram")]
Inject("P:2:plan1:2/2:def", "PARTY", "Bram", A)
local whole = A.CC.payloads.P[full("Bram")]
check("P: parts are kept until all are in, then the whole text is stored",
	partial == nil and whole ~= nil and whole.plan1 ~= nil and whole.plan1.data == "abcdef")
Inject("O:2:set1:1/1:xyz", "PARTY", "Bram", A)
Inject("O:2:set1:1/1:xyz", "GUILD", "Guildie", A)
Inject("P:2:p2:1/1:zzz", "GUILD", "Guildie", A)
check("O: only from the guild channel, and P never from it",
	A.CC.payloads.O[full("Bram")] == nil and A.CC.payloads.O[full("Guildie")] ~= nil
	and A.CC.payloads.O[full("Guildie")].set1.data == "xyz" and A.CC.payloads.P[full("Guildie")] == nil)
Inject("P:2:p3:1/2:aa", "PARTY", "Bram", A)
Run(32)
Inject("P:2:p3:2/2:bb", "PARTY", "Bram", A)
check("  a part older than 30 s is let go", A.CC.payloads.P[full("Bram")].p3 == nil)

---------------------------------------------------------------- Soulstone placements: T on Retail and Forever, the combat log elsewhere
Member("Wren", "WARLOCK")
local W = NewClient("Wren", 7000)
-- review-build's Retail row (the data lane adds it), until it lands in this tree
local stoneRow = { name = "Soulstone", duration = 600, icon = 136210, class = "WARLOCK" }
for _, c in ipairs(live) do
	if not c.CC.SpellData[20707] then c.CC.SpellData[20707] = stoneRow end
end
SetGroup({ "Ayla", "Bram", "Cyr", "Wren" })
Run(8)
local STONE_LEN = (FLAVOR == "retail" or FLAVOR == "mop") and 900 or 1800
local sendsT = RETAILAPI
local nStone = 0
local function StoneOn(targetName)
	nStone = nStone + 1
	local id = CastID(W, 20707)
	W.KNOWN[id] = true
	W.SPELLCD[id] = { startTime = W.NOW, duration = W.CC.SpellData[20707].duration, isEnabled = true, isActive = true }
	local guid = "Cast-SS" .. nStone
	W.FireEvent("UNIT_SPELLCAST_SENT", "player", targetName, guid, id)
	W.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
	Deliver()
	return id
end
-- what the combat log shows another copy on Era, TBC and MoP
local function StoneLog(c, id, targetName)
	if RETAILAPI then return end
	local t = world[targetName]
	c.CLEU_ARGS = { c.NOW, "SPELL_CAST_SUCCESS", false, world.Wren.guid, "Wren", 0x0512, 0, t.guid, targetName, 0x0512, 0,
		id, W.CC.SpellData[20707].name, 1 }
	c.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
	c.CLEU_ARGS = nil
end
mark = #WIRE
local ssID = StoneOn("Cyr")
StoneLog(A, ssID, "Cyr")
Run(1)
local ws, as = W.CC.stones[full("Cyr")], A.CC.stones[full("Cyr")]
check("Soulstone on a living groupmate: the warlock's copy keeps it, with the buff's length (" .. STONE_LEN .. " s)",
	ws ~= nil and ws.from == full("Wren") and ws.duration == STONE_LEN, ws and ws.duration)
check(sendsT and "  and tells the group (T:2), which keeps it too" or "  the others see it in the combat log; nothing is sent",
	as ~= nil and as.from == full("Wren") and near(A.NOW - as.placedAt, 1, 0.5)
	and #WireSince(mark, "Wren", "^T:2:") == (sendsT and 1 or 0), #WireSince(mark, "Wren", "^T:2:"))
ssID = StoneOn("Bram")
StoneLog(A, ssID, "Bram")
Run(1)
check("  a new stone by the same warlock moves it (one per warlock)",
	W.CC.stones[full("Cyr")] == nil and A.CC.stones[full("Cyr")] == nil and A.CC.stones[full("Bram")] ~= nil)
world.Ayla.dead = true
StoneOn("Ayla")
Run(1)
world.Ayla.dead = nil
check("  a Soulstone on the dead is a rez, not a placement", W.CC.stones[full("Ayla")] == nil and W.CC.stones[full("Bram")] ~= nil)
StoneOn("Stranger")
Run(1)
check("  nor is one on someone outside the group", W.CC.stones[full("Stranger")] == nil and W.CC.stones[full("Bram")] ~= nil)
StoneOn("")
Run(1)
check("  with no target named it goes on the warlock", W.CC.stones[full("Wren")] ~= nil and W.CC.stones[full("Bram")] == nil)
ssID = StoneOn("Bram")
StoneLog(A, ssID, "Bram")
Run(1)
if sendsT then
	Inject("T:2:Cyr-Realm:5.0", "WHISPER", "Wren", A)
	Inject("T:2:Stranger-Realm:5.0", "PARTY", "Wren", A)
	Inject("T:2:Cyr-Realm:-5.0", "PARTY", "Wren", A)
	Inject("T:2:Cyr-Realm:99999", "PARTY", "Wren", A)
	check("  a whispered T, one naming an outsider, or an impossible time is dropped",
		A.CC.stones[full("Cyr")] == nil and A.CC.stones[full("Stranger")] == nil and A.CC.stones[full("Bram")] ~= nil)
	for k in pairs(A.CC.stones) do A.CC.stones[k] = nil end
	Inject("Q:2", "PARTY", "Ayla", W)
	Run(4.5)
	check("  a state request gets the warlock's stones again",
		A.CC.stones[full("Bram")] ~= nil and A.CC.stones[full("Bram")].from == full("Wren"))
end
if FLAVOR == "retail" or FLAVOR == "mop" then
	W.SPELLCHARGES[ssID] = { currentCharges = 1, maxCharges = 2, cooldownStartTime = W.NOW - 50, cooldownDuration = 600 }
	mark = #WIRE
	Run(4)
	check("Retail and MoP: a warlock reads the shared rez pool through Soulstone",
		A.CC.rezCharges ~= nil and A.CC.rezCharges.from == full("Wren") and #WireSince(mark, "Wren", "^C:2:1:2:") == 1)
	W.SPELLCHARGES[ssID] = nil
	Run(4)
end

---------------------------------------------------------------- R4, P16, R8: /reload and relog keep timers
Cast(B, 20484)
Cast(B, 29166)
Run(2)
local before = {
	ownRebirth = Rem(A, "Ayla", 20484), bramRebirth = Rem(A, "Bram", 20484), bramInnervate = Rem(A, "Bram", 29166),
	flask = Rem(A, "Ayla", FLASK), flaskAtB = Rem(B, "Ayla", FLASK),
}
local saved = Logout(A)
local sp = type(saved.timers) == "table" and saved.timers.players or {}
check("logout saves running timers as real clock times", sp[full("Ayla")] ~= nil and sp[full("Bram")] ~= nil
	and near(sp[full("Bram")].spells[20484], wall - (B.CC.SpellData[20484].duration - Rem(B, "Bram", 20484)), 1.5))
-- a /reload: the same game, its clock goes on
local A2 = NewClient("Ayla", A.NOW, saved, function(env) CarryGame(A, env) end)
check("/reload: our own and the group's running timers are back at once",
	near(Rem(A2, "Ayla", 20484), before.ownRebirth, 1) and near(Rem(A2, "Bram", 20484), before.bramRebirth, 1)
	and before.bramInnervate > 0 and near(Rem(A2, "Bram", 29166), before.bramInnervate, 1),
	string.format("%s %s %s", tostring(Rem(A2, "Ayla", 20484)), tostring(Rem(A2, "Bram", 20484)), tostring(Rem(A2, "Bram", 29166))))
check("  and the Soulstone it knew of", A2.CC.stones[full("Bram")] ~= nil and A2.CC.stones[full("Bram")].from == full("Wren"))
Run(8)
check("  and still agree with their owners after the group's answers",
	near(Rem(A2, "Bram", 20484), Rem(B, "Bram", 20484), 1) and near(Rem(A2, "Ayla", 20484), Rem(B, "Ayla", 20484), 1),
	string.format("%s/%s %s/%s", tostring(Rem(A2, "Bram", 20484)), tostring(Rem(B, "Bram", 20484)),
		tostring(Rem(A2, "Ayla", 20484)), tostring(Rem(B, "Ayla", 20484))))
check("R8: our flask didn't restart, for us or the group",
	near(Rem(A2, "Ayla", FLASK), before.flask - 8, 2) and near(Rem(B, "Ayla", FLASK), before.flaskAtB - 8, 2),
	string.format("%s (was %s), at Bram %s (was %s)", tostring(Rem(A2, "Ayla", FLASK)), tostring(before.flask),
		tostring(Rem(B, "Ayla", FLASK)), tostring(before.flaskAtB)))
-- a relog after the game closed: a new process (GetTime() starts again), 30 s later by the real clock
local beforeOwn = Rem(A2, "Ayla", 20484)
saved = Logout(A2)
ComesBack(B, 29166)      -- Bram's Innervate comes back while Ayla is away: its ready-now never reaches her
Run(30)
local A3 = NewClient("Ayla", 50, saved, function(env) CarryGame(A2, env, 30) end)
check("relog: our timers are restored by the real clock (30 s less)",
	near(Rem(A3, "Ayla", 20484), beforeOwn - 30, 1.5), tostring(Rem(A3, "Ayla", 20484)) .. " want " .. (beforeOwn - 30))
check("  Bram's Innervate comes back as saved (running)", (Rem(A3, "Bram", 29166) or 0) > 0)
Run(8)
check("  and gives way to his newer word: his state list leaves it out, so it is ready",
	Rem(A3, "Bram", 29166) == 0 and near(Rem(A3, "Bram", 20484), Rem(B, "Bram", 20484), 1),
	string.format("%s %s/%s", tostring(Rem(A3, "Bram", 29166)), tostring(Rem(A3, "Bram", 20484)), tostring(Rem(B, "Bram", 20484))))
check("R8: the flask still didn't restart after the relog",
	near(Rem(A3, "Ayla", FLASK), Rem(B, "Ayla", FLASK), 1.5) and Rem(A3, "Ayla", FLASK) < before.flask - 30,
	tostring(Rem(A3, "Ayla", FLASK)))
local DropFlaskMark = #WIRE
DropFlask(A3)
Refuse(A3, true)
Run(2.2)
Refuse(A3, false)
Run(3)
check("R7: a refused flask/food send is tried again", B.CC.buffRoster[full("Ayla")].flask == false
	and #WireSince(DropFlaskMark, "Ayla", "^flask:0") >= 1)

---------------------------------------------------------------- R15: Retail inspect
if FLAVOR == "retail" then
	Member("Hunt", "HUNTER", { spec = 254 })
	local i0 = #A3.INSPECTED
	maxInFlight = 0
	SetGroup({ "Ayla", "Bram", "Cyr", "Hunt" })
	Run(0.2)
	-- someone else's inspect result (the Inspect window, another addon) arrives first
	local pendingBefore = A3.CC.inspectPending
	A3.FireEvent("INSPECT_READY", "Player-9-0000999")
	check("R15: someone else's inspect result doesn't move our queue on",
		pendingBefore ~= nil and A3.CC.inspectPending == pendingBefore and #A3.INSPECTED == i0 + 1)
	Run(15)
	check("  the groupmate's spec is stored as its ID (Marksmanship 254)", A3.CC.rosterSpecs[full("Hunt")] == 254,
		tostring(A3.CC.rosterSpecs[full("Hunt")]))
	local hl = Status(A3, "BLOODLUST", "Hunt")
	check("  and the Marksmanship hunter now counts as lust (Harrier's Cry)", hl ~= nil and hl.spellID == 466904)
	local units, only = {}, true
	for i = i0 + 1, #A3.INSPECTED do
		local u = A3.INSPECTED[i]
		units[#units + 1] = u
		if not u:match("^party%d$") then only = false end
	end
	check("  one inspect at a time, group members only, each once (the others' specs were read before)",
		only and maxInFlight == 1 and #units == 1,
		table.concat(units, ",") .. " in flight " .. maxInFlight)
	check("  /cdc roster shows the groupmate's spec", RosterLine(A3, "Hunt"):find("Marksmanship HUNTER", 1, true) ~= nil,
		RosterLine(A3, "Hunt"))
else
	check("no inspects off Retail", #A3.INSPECTED == 0 and #B.INSPECTED == 0)
end

---------------------------------------------------------------- the whole run
local spaced = true
for _, c in ipairs(all) do
	local last = {}
	for _, m in ipairs(c.SENT) do
		local l = last[m.channel]
		if l and m.at - l < 0.25 - 1e-6 then spaced = false end
		last[m.channel] = m.at
	end
end
check("queue: no copy ever sent two messages on one channel within 0.25 s", spaced)
check("no Lua errors in any copy", Errors() == 0, FirstError())

OUTPUT(string.format("RESULT sync %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, Errors()))
