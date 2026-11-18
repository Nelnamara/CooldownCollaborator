-- CooldownCollaborator checks for one TOC: loads every file the TOC lists, in
-- order, under the stubbed client of that TOC's game version (wow.lua), logs
-- in a druid with a party of three, then checks the TOC, the client's spell
-- data and capabilities, rank IDs, the combat log path, addon messages, local
-- cooldown readers, consumables, the CDTL3 bridge and the options window.
-- Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/checks.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
local function near(a, b, tol) return type(a) == "number" and math.abs(a - b) <= (tol or 0.01) end
local function keys(t)
	local out = {}
	for k in pairs(t or {}) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return table.concat(out, ",")
end
local function lastSent(prefix)
	for i = #SENT, 1, -1 do
		if SENT[i].prefix == prefix then return SENT[i], i end
	end
end
local function countSent(prefix, pattern)
	local n = 0
	for _, s in ipairs(SENT) do
		if s.prefix == prefix and (not pattern or s.msg:match(pattern)) then n = n + 1 end
	end
	return n
end

local EXPECT = {
	retail  = { data = "Data_Retail.lua",  spells = 29, lust = "EVOKER,MAGE,SHAMAN", rez = "DEATHKNIGHT,DRUID", log = false },
	mop     = { data = "Data_Mists.lua",   spells = 32, lust = "MAGE,SHAMAN",        rez = "DEATHKNIGHT,DRUID", log = true  },
	tbc     = { data = "Data_TBC.lua",     spells = 17, lust = "SHAMAN",             rez = "DRUID",             log = true  },
	era     = { data = "Data_Era.lua",     spells = 12, lust = nil,                  rez = "DRUID",             log = true  },
	forever = { data = "Data_Forever.lua", spells = 12, lust = nil,                  rez = "DRUID",             log = false },
}
local E = EXPECT[FLAVOR]
local CURSE_TOCS = { ["CooldownCollaborator.toc"] = true, ["CooldownCollaborator_Camelot.toc"] = true,
	["CooldownCollaborator_Mainline.toc"] = true }
OUT(string.format("[%s %s]", HARNESS_TOCFILE, FLAVOR))

---------------------------------------------------------------- TOC and packaging
local tocText = ReadTOC(HARNESS_TOCFILE) or ""
local function tag(name) return tocText:match("## " .. name .. ":%s*([^\r\n]-)%s*[\r\n]") end
check("TOC: one Interface number, this client's", tag("Interface") == tostring(HARNESS_TOC), tag("Interface"))
check("TOC: Version 1.1.1", tag("Version") == "1.1.1", tag("Version"))
check("TOC: SavedVariables CooldownCollaboratorDB", tag("SavedVariables") == "CooldownCollaboratorDB", tag("SavedVariables"))
check("TOC: CurseForge project 1577127 in the plain, _Camelot and _Mainline TOCs only",
	(tag("X%-Curse%-Project%-ID") == "1577127") == (CURSE_TOCS[HARNESS_TOCFILE] == true), tag("X%-Curse%-Project%-ID"))
local pkgmeta = HARNESS_READ(HARNESS_SRC .. "/.pkgmeta") or ""
check(".pkgmeta keeps tools, CLAUDE.md and the PNG source art out of the package",
	pkgmeta:find("- tools", 1, true) and pkgmeta:find("- CLAUDE.md", 1, true) and pkgmeta:find("- Media/icon.png", 1, true)
	and pkgmeta:find("- Media/minimap.png", 1, true) and true or false)

---------------------------------------------------------------- load and log in
-- a stub CDTL3 timer-type API, there before CooldownCollaborator loads (OptionalDeps)
local bridge = { registered = {}, started = {}, stopped = {} }
CDTL3 = {
	RegisterTimerType = function(self, key, info) bridge.registered[key] = info; return true end,
	StartTimer = function(self, key, id, t) bridge.started[#bridge.started + 1] = { key = key, id = id, t = t } end,
	StopTimer = function(self, key, id) bridge.stopped[#bridge.stopped + 1] = { key = key, id = id } end,
}
local function lastStarted(id)
	for i = #bridge.started, 1, -1 do
		if bridge.started[i].id == id then return bridge.started[i] end
	end
end
local function countStarted(id)
	local n = 0
	for _, s in ipairs(bridge.started) do if s.id == id then n = n + 1 end end
	return n
end
local function stopped(id)
	for _, s in ipairs(bridge.stopped) do if s.id == id then return true end end
	return false
end

local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

local files = LoadTOC(HARNESS_TOCFILE)
local dataFiles = {}
for _, f in ipairs(files) do if f:match("^Data_") then dataFiles[#dataFiles + 1] = f end end
check("TOC lists only this client's spell data file", #dataFiles == 1 and dataFiles[1] == E.data, table.concat(dataFiles, ","))
check("every file the TOC lists loaded", #LOADED_FILES == #files, #LOADED_FILES .. "/" .. #files)
check("CC.version 1.1.1", CC.version == "1.1.1", CC.version)
check("client detection: retailAPI, isForever, isRetail",
	CC.retailAPI == RETAILAPI and CC.isForever == (FLAVOR == "forever") and CC.isRetail == (FLAVOR == "retail"))
check("stub: no GetSpecialization on Era, TBC and Forever", (GetSpecialization ~= nil) == (FLAVOR == "retail" or FLAVOR == "mop"))
check("stub: no IsSpellKnown globals on Forever", (IsSpellKnown == nil) == (FLAVOR == "forever"))

-- the game knows every listed spell by the list's own (English) name
for id, d in pairs(CC.SpellData) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
for id, d in pairs(CC.BuiltinConsumables) do SPELLINFO[id] = { d.name, d.icon } end

Login()
check("load + ADDON_LOADED + PLAYER_LOGIN: no Lua errors", #ERRORS == 0, ERRORS[1])
if RETAILAPI then
	check("options entry in the Settings panel", SETTINGS_CATEGORY ~= nil)
else
	check("options entry in the Interface Options list (no Settings panel in this stub)", INTERFACE_OPTIONS_PANEL ~= nil)
end
check("every backdrop frame got BackdropTemplate", BACKDROP_FRAMES >= 3, BACKDROP_FRAMES)

---------------------------------------------------------------- spell data
local tracked, rankless, badRow = 0, true, nil
for id, d in pairs(CC.SpellData) do
	if not d.consumable and not d.custom then
		tracked = tracked + 1
		if d.ranks then rankless = false end
		if type(d.name) ~= "string" or type(d.duration) ~= "number" or d.duration < 60 or type(d.icon) ~= "number"
			or not CC.ClassColors[d.class] or CC.RankToBase[id] ~= id or CC.SpellByName[d.name] ~= id then
			badRow = id
		end
		if d.ranks and d.ranks[1] ~= id then badRow = id end
		for _, r in ipairs(d.ranks or {}) do
			if CC.RankToBase[r] ~= id then badRow = r end
		end
	end
end
check(string.format("%d tracked spells (%d expected)", tracked, E.spells), tracked == E.spells)
check("every tracked spell: name, icon, class, base cooldown >= 60 s; each rank maps to its base", badRow == nil, badRow)
check("ranks only on Era, TBC and Forever", rankless == (FLAVOR == "mop" or FLAVOR == "retail"))
if FLAVOR == "retail" then
	check("Fury of the Aspects is 390386 (391215 is Initiative)",
		CC.SpellData[390386] and CC.SpellData[390386].name == "Fury of the Aspects" and CC.SpellData[391215] == nil)
	check("Anti-Magic Zone 240 s", CC.SpellData[51052].duration == 240)
end
if CC.SpellData[20707] then
	local ss = CC.SpellData[20707]
	check("Soulstone tracked; no ready-now poll where its cooldown is the item's", (ss.itemCooldown == true) == (FLAVOR ~= "mop"))
end

---------------------------------------------------------------- capabilities
local lust, rez = CC.CAPABILITIES.BLOODLUST, CC.CAPABILITIES.BATTLEREZ
check("lust providers", (lust and keys(lust.classes) or nil) == E.lust, lust and keys(lust.classes) or "none")
check("Battle Rez providers", rez and keys(rez.classes) == E.rez, rez and keys(rez.classes))
check("capability order", table.concat(CC.CAPABILITY_ORDER, ",") == (E.lust and "BLOODLUST,BATTLEREZ" or "BATTLEREZ"),
	table.concat(CC.CAPABILITY_ORDER, ","))
check("lanes: one per capability, no lust lane without lust", (CC.lanes.BLOODLUST ~= nil) == (E.lust ~= nil) and CC.lanes.BATTLEREZ ~= nil)
check("lane frame sized for its lanes", CC.laneFrame:GetHeight() == 28 * #CC.CAPABILITY_ORDER + 6 * (#CC.CAPABILITY_ORDER - 1) + 30,
	CC.laneFrame:GetHeight())
local providerBad
for _, cap in pairs(CC.CAPABILITIES) do
	for _, ids in pairs(cap.classes) do
		for _, id in ipairs(ids) do
			if not CC.SpellData[id] or CC.SpellData[id].consumable or id == 20707 then providerBad = id end
		end
	end
end
check("every provider spell is a tracked spell; Soulstone never a Battle Rez provider", providerBad == nil, providerBad)

---------------------------------------------------------------- group, roster, specs
local laneWas = CC.db.laneEnabled
CC.db.laneEnabled = true
CC:RefreshLanes()
check("lane view on while solo: stays hidden", not CC.laneFrame:IsShown())
GROUP = {
	{ unit = "party1", name = "Tania",   realm = "Realm", class = "DRUID",  guid = "Player-1-0000002" },
	{ unit = "party2", name = "Brannoc", realm = "Realm", class = "SHAMAN", guid = "Player-1-0000003" },
	{ unit = "party3", name = "Odrin",   realm = "Other", class = "PRIEST", guid = "Player-2-0000004" },
}
local ME = "Tester-Realm"
FireEvent("GROUP_ROSTER_UPDATE")
check("joining a group with the lane view on opens it", CC.laneFrame:IsShown())
CC.db.laneEnabled = laneWas
CC:RefreshLanes()
check("roster: player and three party members", CC.roster and CC.roster[ME] and CC.roster["Tania-Realm"] and CC.roster["Odrin-Other"] ~= nil)
check("inspect (spec labels) on Retail only", (INSPECTS > 0) == (FLAVOR == "retail") and IsEventRegisteredAnywhere("INSPECT_READY") == (FLAVOR == "retail"),
	"NotifyInspect calls " .. INSPECTS)
CC.db.essentialsEnabled = true
CC:RefreshEssentials()
local lustHeader = false
for _, row in ipairs(CC.essentialsRows) do
	if row.__shown and row.isHeader and row.headerText.__text == "Bloodlust/Heroism" then lustHeader = true end
end
check("Essentials: a lust header only where lust exists (a shaman is in the party)", lustHeader == (E.lust ~= nil))
check("CDTL3 bridge registered its type at login", CC.bridgeRegistered and bridge.registered.cdcGroup ~= nil and CC:BridgeActive())

---------------------------------------------------------------- providers: learned levels and our own spellbook
local function listed(capKey, who)
	for _, s in ipairs(CC:GetCapabilityStatus(capKey)) do
		if s.name == who then return s end
	end
end
local rebirthData = CC.SpellData[20484]
local levelBad
for _, cap in pairs(CC.CAPABILITIES) do
	for _, ids in pairs(cap.classes) do
		for _, id in ipairs(ids) do
			if type(CC.SpellData[id].level) ~= "number" then levelBad = id end
		end
	end
end
check("every provider spell has the level it is learned at", levelBad == nil, levelBad)
check("we (a druid) don't know Rebirth yet: not a Battle Rez provider", listed("BATTLEREZ", ME) == nil)
check("  a druid in the party at the level cap is", listed("BATTLEREZ", "Tania-Realm") ~= nil
	and listed("BATTLEREZ", "Tania-Realm").ready)
local rebirthRank1 = rebirthData.ranks and rebirthData.ranks[1] or 20484
KNOWN[rebirthRank1] = true
check("  once we learn it (rank " .. rebirthRank1 .. "), we are, and ready", listed("BATTLEREZ", ME) ~= nil and listed("BATTLEREZ", ME).ready)
KNOWN[rebirthRank1] = nil
GROUP[1].level = rebirthData.level - 1
FireEvent("UNIT_LEVEL", "party1")
check("  a druid one level short of " .. rebirthData.level .. " is not", CC.roster["Tania-Realm"].capabilities.BATTLEREZ == nil
	and listed("BATTLEREZ", "Tania-Realm") == nil)
GROUP[1].level = rebirthData.level
FireEvent("UNIT_LEVEL", "party1")
check("  and is once they level up to it", listed("BATTLEREZ", "Tania-Realm") ~= nil)
GROUP[1].level = rebirthData.level - 1
FireEvent("GROUP_ROSTER_UPDATE")
check("  a roster rescan uses the level too", listed("BATTLEREZ", "Tania-Realm") == nil)
GROUP[1].level = 0
FireEvent("GROUP_ROSTER_UPDATE")
check("  a level we can't read (0) counts as learned", listed("BATTLEREZ", "Tania-Realm") ~= nil)
GROUP[1].level = nil
FireEvent("GROUP_ROSTER_UPDATE")
local e0 = #ERRORS
FireEvent("UNIT_LEVEL", "target")
FireEvent("UNIT_LEVEL", "nameplate4")
check("  UNIT_LEVEL for someone outside the group changes nothing", #ERRORS == e0 and listed("BATTLEREZ", "Tania-Realm") ~= nil)
if E.lust then
	local shamanLust = CC.CAPABILITIES.BLOODLUST.classes.SHAMAN
	local need = CC.SpellData[shamanLust[1]].level
	GROUP[2].level = need - 1
	FireEvent("UNIT_LEVEL", "party2")
	check("a shaman below " .. need .. " is not a lust provider", listed("BLOODLUST", "Brannoc-Realm") == nil)
	GROUP[2].level = nil
	FireEvent("UNIT_LEVEL", "party2")
	check("  and at the level cap is", listed("BLOODLUST", "Brannoc-Realm") ~= nil)
end

---------------------------------------------------------------- own cast: ranks, wire, bridge
local rebirth = CC.SpellData[20484]
local rebirthCast = rebirth.ranks and rebirth.ranks[#rebirth.ranks] or 20484
KNOWN[rebirthCast] = true
SPELLCD[rebirthCast] = { startTime = NOW, duration = rebirth.duration, isEnabled = true, isActive = true }
local sent0 = #SENT
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", rebirthCast)
local mine = CC.state[ME]
check("own cast of " .. rebirthCast .. " records under the base ID 20484",
	mine and mine.spells[20484] == NOW and (rebirthCast == 20484 or mine.spells[rebirthCast] == nil))
local wire = lastSent("CDCOLLAB")
check("one message, base ID on the wire, PARTY", #SENT == sent0 + 1 and wire.msg:match("^20484:") ~= nil and wire.channel == "PARTY",
	wire and wire.msg)
check("a sent message (result " .. tostring(SendResult()) .. ") is not queued again", #CC.pendingSyncs == 0, #CC.pendingSyncs)
local st = lastStarted(ME .. ":20484")
check("bridge: StartTimer with duration, start, owner and class", st and st.key == "cdcGroup" and st.t.duration == rebirth.duration
	and st.t.startedAt == NOW and st.t.owner == ME and st.t.class == "DRUID" and st.t.name == rebirth.name)

---------------------------------------------------------------- local readiness (legacy readers, ranks, charges, secrets)
local r = CC:GetLocalReadiness(20484)
check("Battle Rez readiness reads the rank the player knows", near(r, rebirth.duration), r)
Advance(100)
r = CC:GetLocalReadiness(20484)
check("  and counts down", near(r, rebirth.duration - 100), r)
SPELLCD[rebirthCast] = nil
check("  0 once off cooldown", CC:GetLocalReadiness(20484) == 0)
SPELLCD[rebirthCast] = { startTime = NOW, duration = 1.5, isEnabled = true, isActive = true }
check("  the GCD alone reads ready", CC:GetLocalReadiness(20484) == 0)
SPELLCD[rebirthCast] = nil
KNOWN[rebirthCast] = nil
check("  nil when no rank is known", CC:GetLocalReadiness(20484) == nil)
KNOWN[rebirthCast] = true
if FLAVOR == "retail" then
	SPELLCHARGES[20484] = { currentCharges = 0, maxCharges = 2, cooldownStartTime = NOW - 100, cooldownDuration = 600 }
	r = CC:GetLocalReadiness(20484)
	check("Battle Rez charge pool counts from cooldownStartTime", near(r, 500), r)
	SPELLCHARGES[20484].currentCharges = 1
	check("  a banked charge reads ready", CC:GetLocalReadiness(20484) == 0)
	SPELLCHARGES[20484] = nil
end
if RETAILAPI then
	local e0 = #ERRORS
	SPELLCD[rebirthCast] = { startTime = SECRET, duration = SECRET, isEnabled = true, isActive = true }
	check("secret cooldown values: nil, never compared outside a pcall", CC:GetLocalReadiness(20484) == nil and #ERRORS == e0)
	local status = CC:GetCapabilityStatus("BATTLEREZ")
	CC:RefreshAllViews()
	check("  Battle Rez status falls back to the observed cast", #status >= 2 and #ERRORS == e0)
	SPELLCD[rebirthCast] = nil
end

-- "ready now": a spell still cooling is not announced; announced once it's ready
local innervate = CC.SpellData[29166]
KNOWN[29166] = true
SPELLCD[29166] = { startTime = NOW, duration = innervate.duration, isEnabled = true, isActive = true }
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 29166)
Advance(4)
check("own Innervate still cooling: no ready-now message (Classic tables have no isActive)",
	countSent("CDCOLLAB", "^R:29166$") == 0 and CC.localActive[29166] ~= nil)
SPELLCD[29166] = nil
Advance(1.1)
check("  off cooldown: one ready-now message, bridge timer stopped",
	countSent("CDCOLLAB", "^R:29166$") == 1 and CC.localActive[29166] == nil and stopped(ME .. ":29166"))
Advance(2.1)
check("  sent once", countSent("CDCOLLAB", "^R:29166$") == 1)
if CC.SpellData[20707] and CC.SpellData[20707].itemCooldown then
	FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 20707)
	check("own Soulstone use: recorded, no ready-now watch (the cooldown is the item's)",
		CC.state[ME].spells[20707] == NOW and CC.localActive[20707] == nil)
end

---------------------------------------------------------------- addon messages
check("send results: nil, true, 0 and Success are sent; 3, 11 and false are not",
	CC:AddonMessageSent(nil) and CC:AddonMessageSent(true) and CC:AddonMessageSent(0)
	and CC:AddonMessageSent(Enum.SendAddonMessageResult.Success)
	and not CC:AddonMessageSent(3) and not CC:AddonMessageSent(11) and not CC:AddonMessageSent(false))
local keepResult = SendResult
SendResult = function() return 3 end
CC:SendCooldownSync(20484, ME, NOW - 5)
check("a throttled send is queued once", #CC.pendingSyncs == 1, #CC.pendingSyncs)
SendResult = keepResult
local before = countSent("CDCOLLAB", "^20484:")
Advance(2.1)
check("  the retry goes out and the queue empties", #CC.pendingSyncs == 0 and countSent("CDCOLLAB", "^20484:") == before + 1)
Advance(2.1)
check("  and is not sent again", countSent("CDCOLLAB", "^20484:") == before + 1)

INSTANCE_GROUP = true
check("instance group: INSTANCE_CHAT", CC:GroupChannel() == "INSTANCE_CHAT")
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 29166)
local w1 = lastSent("CDCOLLAB")
CC:BroadcastBuffStatus(ME, false, false)
local w2 = lastSent("CDCBUFF")
check("  cooldown sync and buff status go to INSTANCE_CHAT", w1.channel == "INSTANCE_CHAT" and w2.channel == "INSTANCE_CHAT")
INSTANCE_GROUP = false

-- round trip: what Brannoc's own client sends, received here
local shamanSpell = CC.SpellData[2825] and 2825 or 16190
CC.state["Brannoc-Realm"] = { class = "SHAMAN", spells = {} }
CC:SendCooldownSync(shamanSpell, "Brannoc-Realm", NOW - 10)
local out = lastSent("CDCOLLAB")
CC.state["Brannoc-Realm"] = nil
local startedBefore = countStarted("Brannoc-Realm:" .. shamanSpell)
FireEvent("CHAT_MSG_ADDON", out.prefix, out.msg, out.channel, "Brannoc")
local b = CC.state["Brannoc-Realm"]
check("addon message round trip: " .. out.msg, b and near(b.spells[shamanSpell], NOW - 10) and b.class == "SHAMAN"
	and countStarted("Brannoc-Realm:" .. shamanSpell) == startedBefore + 1)
FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "R:" .. shamanSpell, "PARTY", "Brannoc-Realm")
check("  ready-now message: ready, bridge timer stopped", CC:GetRemaining("Brannoc-Realm", shamanSpell) == 0
	and stopped("Brannoc-Realm:" .. shamanSpell))
if rebirth.ranks then
	FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", rebirthCast .. ":5.000:Tania:DRUID", "PARTY", "Tania-Realm")
	local t = CC.state["Tania-Realm"]
	check("  a rank ID received records under its base", t and near(t.spells[20484], NOW - 5) and t.spells[rebirthCast] == nil)
	CC.state["Tania-Realm"] = nil
end

---------------------------------------------------------------- combat log
local PARTY, RAID = 0x0512, 0x0514
local OUTSIDER, PARTY_PET = 0x0548, 0x1112
local function cleu(sub, guid, name, flags, spellID, spellName)
	CLEU_ARGS = { NOW, sub, false, guid, name, flags, 0, "", "", 0, 0, spellID, spellName, 1 }
	local n = FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
	CLEU_ARGS = nil
	return n
end
local tranq = CC.SpellData[740]
local tranqCast = tranq.ranks and tranq.ranks[#tranq.ranks] or 740
local TANIA = GROUP[1]
if E.log then
	check("combat log registered", CC.combatLogRegistered == true and IsEventRegisteredAnywhere("COMBAT_LOG_EVENT_UNFILTERED"))
	local sentBefore = #SENT
	local castAt = NOW
	cleu("SPELL_CAST_SUCCESS", TANIA.guid, "Tania", PARTY, tranqCast, tranq.name)
	local t = CC.state["Tania-Realm"]
	check("a party member's cast (" .. tranqCast .. ") records under its base, with their class",
		t and t.spells[740] == castAt and t.class == "DRUID" and countStarted("Tania-Realm:740") == 1)
	check("  nothing is sent for another player's cast", #SENT == sentBefore)
	Advance(0.5)
	FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "740:0.400:Tania:DRUID", "PARTY", "Tania-Realm")
	check("  the same cast heard again from their addon is recorded once",
		CC.state["Tania-Realm"].spells[740] == castAt and countStarted("Tania-Realm:740") == 1)
	cleu("SPELL_CAST_SUCCESS", GROUP[3].guid, "Odrin-Other", RAID, 10060, "Power Infusion")
	local o = CC.state["Odrin-Other"]
	check("a raid member from another realm", o and o.spells[10060] == NOW and o.class == "PRIEST")
	cleu("SPELL_CAST_SUCCESS", TANIA.guid, "Tania", PARTY, 999999, innervate.name)
	check("an unknown ID matches by name", CC.state["Tania-Realm"].spells[29166] == NOW)
	cleu("SPELL_CAST_SUCCESS", "Player-9-0000009", "Stranger", OUTSIDER, tranqCast, tranq.name)
	cleu("SPELL_CAST_SUCCESS", "Pet-1-0000010", "Wolf", PARTY_PET, tranqCast, tranq.name)
	cleu("SPELL_CAST_SUCCESS", PLAYER.guid, "Tester", PARTY, tranqCast, tranq.name)
	cleu("SPELL_AURA_APPLIED", TANIA.guid, "Tania", PARTY, 871, "Shield Wall")
	cleu("SPELL_CAST_SUCCESS", TANIA.guid, "Tania", PARTY, 133, "Fireball")
	check("ignored: outsiders, pets, my own casts, other sub-events, untracked spells",
		CC.state["Stranger-Realm"] == nil and CC.state["Wolf-Realm"] == nil and CC.state[ME].spells[740] == nil
		and CC.state["Tania-Realm"].spells[871] == nil and CC.state["Tania-Realm"].spells[133] == nil)
else
	check("combat log not registered (closed on this client)", CC.combatLogRegistered == false
		and not IsEventRegisteredAnywhere("COMBAT_LOG_EVENT_UNFILTERED"))
	local n = cleu("SPELL_CAST_SUCCESS", TANIA.guid, "Tania", PARTY, tranqCast, tranq.name)
	check("  a party member's combat-log cast is ignored", n == 0 and CC.state["Tania-Realm"] == nil)
end
check("no Lua errors so far", #ERRORS == 0, ERRORS[1])

---------------------------------------------------------------- consumables
local flaskName = ({ era = "Flask of the Titans", tbc = "Flask of Relentless Assault", mop = "Flask of the Earth" })[FLAVOR]
if FLAVOR == "retail" then
	PLAYER_AURA_IDS[1230876], PLAYER_AURA_IDS[1232585] = true, true
elseif FLAVOR == "forever" then
	PLAYER_AURA_IDS[17626], PLAYER_AURA_IDS[1248406] = true, true
else
	check("stub: no GetPlayerAuraBySpellID on the Classic clients", C_UnitAuras.GetPlayerAuraBySpellID == nil)
	-- other IDs than the list's: matched by name
	AURAS.HELPFUL = { { name = "Arcane Intellect", spellId = 10157 }, { name = flaskName, spellId = 99001 },
		{ name = "Well Fed", spellId = 24799 } }
end
CC:PollConsumables()
local br = CC.buffRoster[ME]
check("own flask and Well Fed found (" .. (CC.ConsumableMatch == "name" and "by name" or "by ID") .. ")", br and br.flask and br.food)
check("  status sent", lastSent("CDCBUFF").msg == "flask:1:food:1")
CC:AddConsumableBuff(424242, 3600, "Test Elixir")
CC.SpellData[424242].category = "flask"
if RETAILAPI then
	PLAYER_AURA_IDS = { [424242] = true }
else
	AURAS.HELPFUL = { { name = "Test Elixir", spellId = 424242 } }
end
CC:PollConsumables()
br = CC.buffRoster[ME]
check("a /cdc consumable entry matches its spell ID; the built-ins are gone", CC.consumableActive[424242] == true and br.flask and not br.food)
PLAYER_AURA_IDS = {}
AURAS.HELPFUL = {}
CC:PollConsumables()
check("  and nothing once the buffs drop", not CC.buffRoster[ME].flask and lastSent("CDCBUFF").msg == "flask:0:food:0")
check("CDCBUFF from a party member", (function()
	FireEvent("CHAT_MSG_ADDON", "CDCBUFF", "flask:1:food:0", "PARTY", "Tania")
	local s = CC.buffRoster["Tania-Realm"]
	return s and s.flask and not s.food
end)())

---------------------------------------------------------------- bridge switch, views, options, slash
local stops0 = #bridge.stopped
CC:SetShowOnCDTL3(false)
check("bridge off: running timers stopped, no new ones", #bridge.stopped > stops0 and not CC:BridgeActive())
local starts0 = #bridge.started
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 29166)
check("  a cast while off starts nothing", #bridge.started == starts0)
CC:SetShowOnCDTL3(true)
check("bridge on again: timers resent", #bridge.started > starts0 and CC:BridgeActive())

local e0 = #ERRORS
CC.db.laneEnabled = true
CC:RefreshLanes()
CC:RefreshEssentials()
CC:RefreshRows()
CC:OpenOptions()
local headers = 0
rawset(CC.defaultSpellContent, "CreateFontString", function(self)
	local fs = CreateFrame("FontString")
	rawset(fs, "SetText", function(s, text) headers = headers + 1 end)
	return fs
end)
CC:RefreshDefaultSpellList()
local classes = {}
for _, d in pairs(CC.SpellData) do if not d.consumable and not d.custom then classes[d.class] = true end end
local nClasses = 0
for _ in pairs(classes) do nClasses = nClasses + 1 end
check("options: Default Spells shows every class with tracked spells", headers == nClasses, headers .. "/" .. nClasses)
for _, cmd in ipairs({ "verbose", "roster", "debug", "lanes", "essentials", "", "", "verbose" }) do
	SlashCmdList["COOLDOWNCOLLABORATOR"](cmd)
end
CC.verbose = true
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 29166)
if E.log then cleu("SPELL_CAST_SUCCESS", GROUP[2].guid, "Brannoc", PARTY, 871, "Shield Wall") end
CC.verbose = false
Advance(10)
check("views, options, slash commands and verbose output: no Lua errors", #ERRORS == e0, ERRORS[e0 + 1])

-- the minimap button rides the rim of a minimap of any size (Forever's is larger than the old one)
do
	local btn = _G["CCMinimapButton"]
	local hook = Minimap.__hooks and Minimap.__hooks.OnSizeChanged
	local function dist()
		local p = btn and btn.__points[#btn.__points]
		if not p then return nil end
		return math.sqrt((p[4] or 0) ^ 2 + (p[5] or 0) ^ 2)
	end
	local sizes = {}
	for _, w in ipairs({ 140, 200 }) do
		Minimap:SetSize(w, w)
		if hook then hook(Minimap) end
		sizes[#sizes + 1] = dist()
	end
	check("minimap button: just past the rim, and follows the minimap's size",
		hook ~= nil and sizes[1] and sizes[2] and math.abs(sizes[1] - 74) < 0.01 and math.abs(sizes[2] - 104) < 0.01,
		tostring(sizes[1]) .. "/" .. tostring(sizes[2]))
	-- Forever: the map grows with no size event reaching the hook; login places the button again
	Minimap:SetSize(182, 182)
	local bridge = CC.BridgeRegister
	CC.BridgeRegister = function() end
	FireEvent("PLAYER_LOGIN")
	CC.BridgeRegister = bridge
	local atLogin = dist()
	check("minimap button: placed again at login, for a map that grew without a size event",
		atLogin ~= nil and math.abs(atLogin - 95) < 0.01, tostring(atLogin))
end

---------------------------------------------------------------- Request Rez in a raid
-- raid leader or assist may ask (UnitIsGroupLeader / UnitIsGroupAssistant: IsRaidLeader and
-- IsRaidOfficer are gone on every client), a plain raid member may not, the party leader may;
-- the Essentials bar refreshes in a raid with no Lua error; the request goes out through
-- C_ChatInfo.SendChatMessage
do
	local function can()
		local ok, res = pcall(CC.CanRequestRez, CC)
		if not ok then return "error", tostring(res) end
		return res and true or false, ""
	end
	local party, e1 = can()
	STUB_IN_RAID, STUB_IS_LEADER, STUB_IS_ASSIST = true, false, false
	local member, e2 = can()
	STUB_IS_ASSIST = true
	local assist, e3 = can()
	STUB_IS_ASSIST, STUB_IS_LEADER = false, true
	local lead, e4 = can()
	check("request rez: party leader yes; in a raid, leader yes, assist yes, plain member no",
		party == true and lead == true and assist == true and member == false,
		table.concat({ tostring(party), tostring(lead), tostring(assist), tostring(member), e1, e2, e3, e4 }, " "))

	local essWas = CC.db.essentialsEnabled
	CC.db.essentialsEnabled = true
	if CC.essentialsRezBtn then CC.essentialsRezBtn:Hide() end
	local okRefresh, errRefresh = pcall(CC.RefreshEssentials, CC)
	check("  Essentials bar in a raid (leader): refreshes with no Lua error and shows Request Rez",
		okRefresh and CC.essentialsRezBtn ~= nil and CC.essentialsRezBtn:IsShown(), tostring(errRefresh))
	CC.db.essentialsEnabled = essWas

	local saved = { UnitExists = UnitExists, UnitIsDeadOrGhost = UnitIsDeadOrGhost, UnitFullName = UnitFullName,
		GetCapabilityStatus = CC.GetCapabilityStatus }
	UnitExists = function(u) if u == "target" then return true end return saved.UnitExists(u) end
	UnitIsDeadOrGhost = function(u) return u == "target" end
	UnitFullName = function(u) if u == "target" then return "Odrin", "Other" end return saved.UnitFullName(u) end
	CC.GetCapabilityStatus = function() return { { ready = true, name = "Tania-Realm" } } end
	local c0 = #CHATSENT
	local okReq, errReq = pcall(CC.RequestRez, CC)
	UnitExists, UnitIsDeadOrGhost, UnitFullName, CC.GetCapabilityStatus =
		saved.UnitExists, saved.UnitIsDeadOrGhost, saved.UnitFullName, saved.GetCapabilityStatus
	local a, b = CHATSENT[c0 + 1], CHATSENT[c0 + 2]
	check("  Request Rez in a raid: RAID and RAID_WARNING through C_ChatInfo.SendChatMessage",
		okReq and #CHATSENT == c0 + 2 and a.chan == "RAID" and b.chan == "RAID_WARNING"
			and a.via == "C_ChatInfo" and b.via == "C_ChatInfo"
			and a.msg:find("Tania", 1, true) ~= nil and a.msg:find("Odrin", 1, true) ~= nil,
		okReq and (a and (a.chan .. " " .. a.via .. " " .. a.msg) or "nothing sent") or tostring(errReq))
	STUB_IN_RAID, STUB_IS_LEADER, STUB_IS_ASSIST = false, true, false
	pcall(CC.RefreshEssentials, CC)
end

local allowed = { CooldownCollaborator = true, CC = true, CooldownCollaboratorDB = true, SLASH_COOLDOWNCOLLABORATOR1 = true,
	CCEventFrame = true, CCMainFrame = true, CCEssentialsFrame = true, CCLaneFrame = true, CCMinimapButton = true,
	CCOptionsFrame = true, CCDefScroll = true, CCSpellInput = true, CCDurInput = true, CCCustScroll = true,
	SETTINGS_CATEGORY = true, INTERFACE_OPTIONS_PANEL = true }
local leaked = {}
for k in pairs(_G) do
	if not globalsBefore[k] and not allowed[k] then leaked[#leaked + 1] = tostring(k) end
end
table.sort(leaked)
check("no new globals besides the addon's own", #leaked == 0, table.concat(leaked, ","))

OUT(string.format("RESULT %s %s: tracked spells %d, checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, tracked, checks, fails, #ERRORS))
