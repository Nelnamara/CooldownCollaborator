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
-- let the send queue (one message every 0.25 s per channel) catch up
local function Settle(seconds) Advance(seconds or 0.3) end
local function countSent(prefix, pattern)
	local n = 0
	for _, s in ipairs(SENT) do
		if s.prefix == prefix and (not pattern or s.msg:match(pattern)) then n = n + 1 end
	end
	return n
end

local EXPECT = {
	retail  = { data = "Data_Retail.lua",  spells = 43, lust = "EVOKER,HUNTER,MAGE,SHAMAN", rez = "DEATHKNIGHT,DRUID,PALADIN,WARLOCK", log = false },
	mop     = { data = "Data_Mists.lua",   spells = 41, lust = "MAGE,SHAMAN",               rez = "DEATHKNIGHT,DRUID,WARLOCK", log = true  },
	tbc     = { data = "Data_TBC.lua",     spells = 23, lust = "SHAMAN",                    rez = "DRUID",                     log = true  },
	era     = { data = "Data_Era.lua",     spells = 16, lust = nil,                         rez = "DRUID",                     log = true  },
	forever = { data = "Data_Forever.lua", spells = 17, lust = nil,                         rez = "DRUID",                     log = false },
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
		for _, v in ipairs(d.variants or {}) do
			if CC.RankToBase[v] ~= id or CC.SpellData[v] ~= nil then badRow = v end
		end
	end
end
check(string.format("%d tracked spells (%d expected)", tracked, E.spells), tracked == E.spells)
check("every tracked spell: name, icon, class, base cooldown >= 60 s; each rank and variant maps to its base", badRow == nil, badRow)
check("ranks only on Era, TBC and Forever", rankless == (FLAVOR == "mop" or FLAVOR == "retail"))
if FLAVOR == "retail" then
	check("Fury of the Aspects is 390386 (391215 is Initiative)",
		CC.SpellData[390386] and CC.SpellData[390386].name == "Fury of the Aspects" and CC.SpellData[391215] == nil)
	check("Anti-Magic Zone 240 s", CC.SpellData[51052].duration == 240)
	-- older rows set to the 12.1.5 data (one-charge spells: the charge's recharge)
	local RETAIL_FIXED = {
		[33206]  = { 180, 135936 },    -- Pain Suppression, one charge (was 90 s)
		[45438]  = { 240, 135841 },    -- Ice Block, one charge (was 300 s)
		[108280] = { 180, 538569 },    -- Healing Tide Totem (was 120 s)
		[196718] = { 300, 1305154 },   -- Darkness (was 180 s)
		[357170] = { 60, 4622478 },    -- Time Dilation, one charge (was 90 s)
		[32182]  = { 300, 132313 },    -- Heroism's icon
	}
	local fixedBad = {}
	for id, want in pairs(RETAIL_FIXED) do
		local d = CC.SpellData[id]
		if not d or d.duration ~= want[1] or d.icon ~= want[2] then fixedBad[#fixedBad + 1] = id end
	end
	check("Retail: corrected rows have the 12.1.5 cooldown and icon", #fixedBad == 0, table.concat(fixedBad, ","))
	check("Retail: no Demonic Gateway row (10 s in 12.1.5, not a group cooldown)", CC.SpellData[111771] == nil)
end
if CC.SpellData[20707] then
	local ss = CC.SpellData[20707]
	check("Soulstone tracked; no ready-now poll where its cooldown is the item's (Era, TBC, Forever)",
		(ss.itemCooldown == true) == (FLAVOR ~= "mop" and FLAVOR ~= "retail"))
end

-- rows from the 18 Nov review (R3, R13, P18, P28, P32): base ID -> its base cooldown on each client
-- whose game data has it (docs/port-research.md B); on a client not named it must not be listed
local NEW_ROWS = {
	[391054] = { "Intercession", retail = 600 },
	[466904] = { "Harrier's Cry", retail = 360 },
	[10060]  = { "Power Infusion", retail = 120, mop = 120, tbc = 180, era = 180, forever = 180 },
	[6940]   = { "Blessing (MoP: Hand) of Sacrifice", retail = 120, mop = 120 },
	[871]    = { "Shield Wall", retail = 180, mop = 180, tbc = 1800, era = 1800, forever = 900 },
	[12975]  = { "Last Stand", retail = 180, mop = 180, tbc = 480, era = 600, forever = 180 },
	[1161]   = { "Challenging Shout", retail = 120, tbc = 600, era = 600, forever = 600 },
	[5209]   = { "Challenging Roar", tbc = 600, era = 600, forever = 600 },
	[114192] = { "Mocking Banner", mop = 180 },
	[86659]  = { "Guardian of Ancient Kings", retail = 180, mop = 180 },
	[31850]  = { "Ardent Defender", retail = 90, mop = 180 },
	[48792]  = { "Icebound Fortitude", retail = 120, mop = 180 },
	[55233]  = { "Vampiric Blood", retail = 90, mop = 60 },
	[61336]  = { "Survival Instincts", retail = 180, mop = 180 },
	[115203] = { "Fortifying Brew", retail = 360, mop = 180 },
	[187827] = { "Metamorphosis (Vengeance)", retail = 120 },
	[2062]   = { "Earth Elemental Totem", tbc = 1200 },
	[6346]   = { "Fear Ward", tbc = 180, forever = 180 },         -- Era's is 30 s
	[20608]  = { "Reincarnation", tbc = 3600, era = 3600, forever = 3600 },
	[20707]  = { "Soulstone", retail = 600, mop = 600, tbc = 1800, era = 1800, forever = 1800 },
	[19801]  = { "Tranquilizing Shot (20 s on Era, TBC and Forever)" },
	[605]    = { "Mind Control (no cooldown)" },
}
local newBad = {}
for id, row in pairs(NEW_ROWS) do
	local want, d = row[FLAVOR], CC.SpellData[id]
	if (want == nil) ~= (d == nil) or (d and d.duration ~= want) then
		newBad[#newBad + 1] = row[1] .. " " .. id .. "=" .. tostring(d and d.duration)
	end
end
table.sort(newBad)
check("new rows: each on the clients whose game data has it, with that client's cooldown, and nowhere else",
	#newBad == 0, table.concat(newBad, ", "))
local specRows = {}
for id, d in pairs(CC.SpellData) do if d.spec then specRows[#specRows + 1] = id .. ":" .. d.spec end end
check("spec markers: only Retail's Harrier's Cry (Marksmanship, 254)",
	table.concat(specRows, ",") == (FLAVOR == "retail" and "466904:254" or ""), table.concat(specRows, ","))
local VARIANTS = ({
	mop = { [77761] = 106898, [77764] = 106898 },   -- Stampeding Roar in Bear and Cat Form
	tbc = { [21169] = 20608 }, era = { [21169] = 20608 }, forever = { [21169] = 20608 },   -- Reincarnation's rez
})[FLAVOR] or {}
local variantBad
for v, base in pairs(VARIANTS) do
	if CC:BaseSpellID(v) ~= base then variantBad = v end
end
check("variant IDs record under their base", variantBad == nil, variantBad)

-- kind on every tracked row; effect (seconds) only on externals and raid defensives
local KINDS = { rez = true, lust = true, external = true, raid = true, personal = true, mana = true, utility = true }
local kindBad, effects = {}, {}
for id, d in pairs(CC.SpellData) do
	if not d.consumable and not d.custom then
		if not KINDS[d.kind] then kindBad[#kindBad + 1] = id .. ":kind" end
		if d.effect ~= nil then
			if (d.kind ~= "external" and d.kind ~= "raid") or type(d.effect) ~= "number" or d.effect <= 0
				or d.effect >= d.duration then
				kindBad[#kindBad + 1] = id .. ":effect"
			end
			effects[#effects + 1] = id .. "=" .. d.effect
		end
	end
end
table.sort(effects)
check("every tracked spell has a kind; effects only on externals and raid defensives, shorter than the cooldown",
	#kindBad == 0, table.concat(kindBad, ","))
-- the Providers' spells are their own kind (Rebirth "rez", Bloodlust "lust")
local provBad
for capKey, kind in pairs({ BLOODLUST = "lust", BATTLEREZ = "rez" }) do
	for _, ids in pairs(CC.Providers[capKey] or {}) do
		for _, id in ipairs(ids) do
			if CC.SpellData[id].kind ~= kind then provBad = id end
		end
	end
end
check("lust and Battle Rez providers carry kind lust and rez", provBad == nil, provBad)
local EFFECTS = ({
	retail = "1022=10,108280=10,116849=12,196718=8,207399=30,33206=8,357170=8,363534=4,374227=8,47788=10,51052=6,6940=12,62618=10,740=6,97462=10,98008=6,31821=8",
	mop = "102342=12,1022=10,108280=11,114203=15,115213=6,116849=12,15286=15,31821=6,33206=8,47788=10,51052=3,62618=10,64843=8,6940=12,740=8,97462=10,98008=6",
	tbc = "1022=10,33206=8,724=180,740=8",
	era = "1022=10,724=180,740=10",
	forever = "1022=10,724=180,740=10",
})[FLAVOR]
local expected = {}
for item in EFFECTS:gmatch("[^,]+") do expected[#expected + 1] = item end
table.sort(expected)
check("effect lengths as the game data has them (SpellDuration)", table.concat(effects, ",") == table.concat(expected, ","),
	table.concat(effects, ","))

---------------------------------------------------------------- capabilities
local lust, rez = CC.CAPABILITIES.BLOODLUST, CC.CAPABILITIES.BATTLEREZ
check("lust providers", (lust and keys(lust.classes) or nil) == E.lust, lust and keys(lust.classes) or "none")
check("Battle Rez providers", rez and keys(rez.classes) == E.rez, rez and keys(rez.classes))
check("capability order", table.concat(CC.CAPABILITY_ORDER, ",") == (E.lust and "BLOODLUST,BATTLEREZ" or "BATTLEREZ"),
	table.concat(CC.CAPABILITY_ORDER, ","))
check("lanes: one per capability, no lust lane without lust", (CC.lanes.BLOODLUST ~= nil) == (E.lust ~= nil) and CC.lanes.BATTLEREZ ~= nil)
-- title 20, each lane 28 with its 1 + 20 ready row under it, 15 for the next lane's name, 5 below
check("lane frame sized for its lanes and their ready rows",
	CC.laneFrame:GetHeight() == 20 + 49 * #CC.CAPABILITY_ORDER + 15 * (#CC.CAPABILITY_ORDER - 1) + 5, CC.laneFrame:GetHeight())
local providerBad
for _, cap in pairs(CC.CAPABILITIES) do
	for _, ids in pairs(cap.classes) do
		for _, id in ipairs(ids) do
			if not CC.SpellData[id] or CC.SpellData[id].consumable
				or (id == 20707 and FLAVOR ~= "retail" and FLAVOR ~= "mop") then providerBad = id end
		end
	end
end
check("every provider spell is a tracked spell; Soulstone a Battle Rez provider on Retail and MoP only", providerBad == nil, providerBad)

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
for _, line in ipairs(CC.essentialsShown) do
	if line.__shown and line.lineKind == "heading" and line.label.__text == "Bloodlust/Heroism" then lustHeader = true end
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
if FLAVOR == "retail" then
	-- R3: Intercession is a paladin's Battle Rez. Harrier's Cry is Marksmanship's lust: a hunter
	-- groupmate counts only once their spec is known to be Marksmanship (254); ourselves by spellbook.
	GROUP[4] = { unit = "party4", name = "Aldren", realm = "Realm", class = "PALADIN", guid = "Player-1-0000005" }
	FireEvent("GROUP_ROSTER_UPDATE")
	local a = listed("BATTLEREZ", "Aldren-Realm")
	check("Retail: a paladin groupmate at the level cap is a Battle Rez provider (Intercession)", a ~= nil and a.spellID == 391054)
	GROUP[4].level = 18
	FireEvent("UNIT_LEVEL", "party4")
	check("  one below 19 is not", listed("BATTLEREZ", "Aldren-Realm") == nil)
	GROUP[4] = { unit = "party4", name = "Vessa", realm = "Realm", class = "HUNTER", guid = "Player-1-0000006" }
	FireEvent("GROUP_ROSTER_UPDATE")
	check("a hunter groupmate whose spec we don't know is not a lust provider",
		CC.roster["Vessa-Realm"] ~= nil and CC.roster["Vessa-Realm"].capabilities.BLOODLUST == nil and listed("BLOODLUST", "Vessa-Realm") == nil)
	CC.rosterSpecs["Vessa-Realm"] = 253
	FireEvent("GROUP_ROSTER_UPDATE")
	check("  nor a known Beast Mastery one (253)", listed("BLOODLUST", "Vessa-Realm") == nil)
	CC.rosterSpecs["Vessa-Realm"] = 254
	FireEvent("GROUP_ROSTER_UPDATE")
	local v = listed("BLOODLUST", "Vessa-Realm")
	check("  a known Marksmanship one (254) is, with Harrier's Cry", v ~= nil and v.spellID == 466904 and v.ready)
	GROUP[4].level = 47
	FireEvent("UNIT_LEVEL", "party4")
	check("  but not below level 48", listed("BLOODLUST", "Vessa-Realm") == nil)
	CC.rosterSpecs["Vessa-Realm"] = nil
	table.remove(GROUP, 4)
	FireEvent("GROUP_ROSTER_UPDATE")
	-- ourselves as a hunter: our own roster spec is our own spec's ID (a druid's here), never matched; the spellbook decides
	local keep = CC.roster[ME]
	CC.roster[ME] = { class = "HUNTER", capabilities = CC:CapabilitiesFor("player", "HUNTER") }
	check("we as a hunter: Harrier's Cry is left for our spellbook to decide", CC.roster[ME].capabilities.BLOODLUST ~= nil)
	check("  not in our spellbook (another spec): not a lust provider", listed("BLOODLUST", ME) == nil)
	KNOWN[466904] = true
	check("  in our spellbook (Marksmanship): a lust provider", listed("BLOODLUST", ME) ~= nil)
	KNOWN[466904] = nil
	CC.roster[ME] = keep
	GROUP[#GROUP + 1] = { unit = "raid9", name = PLAYER.name, realm = PLAYER.realm, class = "HUNTER" }
	local raidSelf = CC:CapabilitiesFor("raid9", "HUNTER")
	GROUP[#GROUP] = nil
	check("  the same when we are read as a raid unit", raidSelf.BLOODLUST ~= nil)
end
if CC.SpellData[20707] then
	-- owner, 19 Nov: Soulstone cast on a dead player is a combat rez on Retail and MoP; on Era,
	-- TBC and Forever it is a stone placed beforehand, tracked only
	GROUP[4] = { unit = "party4", name = "Morwen", realm = "Realm", class = "WARLOCK", guid = "Player-1-0000007" }
	FireEvent("GROUP_ROSTER_UPDATE")
	local w = listed("BATTLEREZ", "Morwen-Realm")
	if FLAVOR == "retail" or FLAVOR == "mop" then
		local need = CC.SpellData[20707].level
		check("a warlock groupmate at the level cap is a Battle Rez provider (Soulstone)", w ~= nil and w.spellID == 20707)
		GROUP[4].level = need - 1
		FireEvent("UNIT_LEVEL", "party4")
		check("  one below " .. need .. " is not", listed("BATTLEREZ", "Morwen-Realm") == nil)
	else
		check("a warlock groupmate is not a Battle Rez provider (Soulstone is tracked only)",
			CC.roster["Morwen-Realm"] ~= nil and CC.roster["Morwen-Realm"].capabilities.BATTLEREZ == nil and w == nil)
	end
	table.remove(GROUP, 4)
	FireEvent("GROUP_ROSTER_UPDATE")
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
Settle()
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
Settle()
local w2 = lastSent("CDCBUFF")
check("  cooldown sync and buff status go to INSTANCE_CHAT", w1.channel == "INSTANCE_CHAT" and w2.channel == "INSTANCE_CHAT")
INSTANCE_GROUP = false

-- round trip: what Brannoc's own client sends, received here
local shamanSpell = CC.SpellData[2825] and 2825 or 16190
CC.state["Brannoc-Realm"] = { class = "SHAMAN", spells = {} }
Settle()
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

---------------------------------------------------------------- variants: other IDs of one spell
Settle()
if FLAVOR == "mop" then
	-- R14: Stampeding Roar cast in Cat or Bear Form has its own ID; it records and goes out as 106898
	for i, form in ipairs({ 77764, 77761 }) do
		Advance(10)
		local sent0 = #SENT
		FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-SR" .. i, form)
		local me, w = CC.state[ME], lastSent("CDCOLLAB")
		check("own Stampeding Roar in a form (" .. form .. "): recorded and sent as 106898",
			me.spells[106898] == NOW and me.spells[form] == nil and #SENT == sent0 + 1 and w.msg:match("^106898:") ~= nil,
			w and w.msg)
	end
	cleu("SPELL_CAST_SUCCESS", TANIA.guid, "Tania", PARTY, 77761, "Stampeding Roar")
	check("  a party member's Bear Form one, from the combat log, records under 106898",
		CC.state["Tania-Realm"].spells[106898] == NOW and CC.state["Tania-Realm"].spells[77761] == nil)
elseif CC.SpellData[20608] then
	FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-RI", 21169)
	local w = lastSent("CDCOLLAB")
	check("own Reincarnation rez (21169): recorded and sent as 20608", CC.state[ME].spells[20608] == NOW
		and CC.state[ME].spells[21169] == nil and w.msg:match("^20608:") ~= nil, w and w.msg)
	if E.log then
		cleu("SPELL_CAST_SUCCESS", GROUP[2].guid, "Brannoc", PARTY, 21169, "Reincarnation")
		local b2 = CC.state["Brannoc-Realm"]
		check("  a party shaman's, from the combat log, records under 20608", b2 ~= nil and b2.spells[20608] == NOW and b2.spells[21169] == nil)
	end
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
Settle(1)
local br = CC.buffRoster[ME]
check("own flask and Well Fed found (" .. (CC.ConsumableMatch == "name" and "by name" or "by ID") .. ")", br and br.flask and br.food)
check("  status sent", lastSent("CDCBUFF").msg:find("^flask:1:food:1") ~= nil, lastSent("CDCBUFF").msg)
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
Settle(1)
check("  and nothing once the buffs drop", not CC.buffRoster[ME].flask and lastSent("CDCBUFF").msg:find("^flask:0:food:0") ~= nil)
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
-- Blizzard's link-insert calls (newer and older name), there when the options window is built
ChatFrameUtil = { InsertLink = function() return false end }
ChatEdit_InsertLink = function() return false end
CC.db.laneEnabled = true
CC:RefreshLanes()
CC:RefreshEssentials()
CC:RefreshRows()
CC:OpenOptions()
local insertNew, insertOld = ChatFrameUtil.InsertLink, ChatEdit_InsertLink
ChatFrameUtil, ChatEdit_InsertLink = nil, nil
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
-- the longer lists: one row per tracked spell, A to Z within its class, each class's rows together,
-- nothing overlapping, and the scroll child as tall as everything on it
do
	local content, realCreateFrame = CC.defaultSpellContent, CreateFrame
	local function fontStringsInto(list)
		return function(self)
			local fs = realCreateFrame("FontString", nil, self)
			list[#list + 1] = fs
			return fs
		end
	end
	local hdrs, items = {}, {}
	rawset(content, "CreateFontString", fontStringsInto(hdrs))
	CreateFrame = function(otype, name, parent, template)
		local f = realCreateFrame(otype, name, parent, template)
		if parent == content and otype == "Frame" then
			local texts = {}
			items[#items + 1] = { row = f, texts = texts }
			rawset(f, "CreateFontString", fontStringsInto(texts))
		end
		return f
	end
	local ok, err = pcall(CC.RefreshDefaultSpellList, CC)
	CreateFrame = realCreateFrame
	rawset(content, "CreateFontString", nil)
	local placed, bad = {}, nil
	for _, h in ipairs(hdrs) do placed[#placed + 1] = { y = -h.__points[1][5], h = 20, header = h.__text } end
	for _, it in ipairs(items) do
		local name = it.texts[1] and it.texts[1].__text
		local id = name and CC.SpellByName[name]
		placed[#placed + 1] = { y = -it.row.__points[1][5], h = 22, name = name, class = id and CC.SpellData[id].class }
		if not id then bad = bad or ("row without a tracked spell: " .. tostring(name)) end
	end
	table.sort(placed, function(a, b) return a.y < b.y end)
	local seen, cur, prevName = {}, nil, nil
	for i, p in ipairs(placed) do
		local nextItem = placed[i + 1]
		if nextItem and nextItem.y < p.y + p.h then bad = bad or ("overlap at " .. p.y) end
		if p.header then
			cur, prevName = p.header, nil
		elseif p.class then
			if seen[p.class] and seen[p.class] ~= cur then bad = bad or (p.class .. " rows split") end
			seen[p.class] = cur
			if prevName and p.name < prevName then bad = bad or (p.name .. " after " .. prevName) end
			prevName = p.name
		end
	end
	local last = placed[#placed]
	check("  Default Spells: one row per tracked spell, A to Z per class, none overlapping or past the list's end",
		ok and #items == tracked and bad == nil and last ~= nil and content:GetHeight() >= last.y + last.h,
		ok and (#items .. "/" .. tracked .. " rows, list " .. content:GetHeight() .. " px, " .. tostring(bad)) or tostring(err))
end
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
		GetCapabilityStatus = CC.GetCapabilityStatus, UnitIsPlayer = UnitIsPlayer, UnitIsFriend = UnitIsFriend }
	UnitIsPlayer = function(u) return u == "target" or saved.UnitIsPlayer(u) end
	UnitIsFriend = function() return true end
	UnitExists = function(u) if u == "target" then return true end return saved.UnitExists(u) end
	UnitIsDeadOrGhost = function(u) return u == "target" end
	UnitFullName = function(u) if u == "target" then return "Odrin", "Other" end return saved.UnitFullName(u) end
	CC.GetCapabilityStatus = function() return { { ready = true, name = "Tania-Realm" } } end
	local c0 = #CHATSENT
	local okReq, errReq = pcall(CC.RequestRez, CC)
	UnitExists, UnitIsDeadOrGhost, UnitFullName, CC.GetCapabilityStatus =
		saved.UnitExists, saved.UnitIsDeadOrGhost, saved.UnitFullName, saved.GetCapabilityStatus
	UnitIsPlayer, UnitIsFriend = saved.UnitIsPlayer, saved.UnitIsFriend
	local a, b = CHATSENT[c0 + 1], CHATSENT[c0 + 2]
	check("  Request Rez in a raid: RAID and RAID_WARNING through C_ChatInfo.SendChatMessage",
		okReq and #CHATSENT == c0 + 2 and a.chan == "RAID" and b.chan == "RAID_WARNING"
			and a.via == "C_ChatInfo" and b.via == "C_ChatInfo"
			and a.msg:find("Tania", 1, true) ~= nil and a.msg:find("Odrin", 1, true) ~= nil,
		okReq and (a and (a.chan .. " " .. a.via .. " " .. a.msg) or "nothing sent") or tostring(errReq))
	STUB_IN_RAID, STUB_IS_LEADER, STUB_IS_ASSIST = false, true, false
	pcall(CC.RefreshEssentials, CC)
end

---------------------------------------------------------------- review fixes: rez, custom spells, locks, consumables, options, minimap
do
	local function sentSince(n) local out = {}; for i = n + 1, #CHATSENT do out[#out + 1] = CHATSENT[i] end return out end
	local function chans(list) local o = {}; for _, m in ipairs(list) do o[#o + 1] = m.chan end return table.concat(o, ",") end
	local saved = { UnitExists = UnitExists, UnitIsDeadOrGhost = UnitIsDeadOrGhost, UnitFullName = UnitFullName,
		UnitIsPlayer = UnitIsPlayer, UnitIsFriend = UnitIsFriend, GetCapabilityStatus = CC.GetCapabilityStatus }
	local target = { exists = true, dead = true, player = true, friend = true, hidden = false }
	UnitExists = function(u) if u == "target" then return target.exists end return saved.UnitExists(u) end
	UnitIsDeadOrGhost = function(u) if u == "target" then return target.dead end return false end
	UnitIsPlayer = function(u) if u == "target" then return target.player end return saved.UnitIsPlayer(u) end
	UnitIsFriend = function(a, b) if b == "target" then return target.friend end return saved.UnitIsFriend(a, b) end
	UnitFullName = function(u)
		if u == "target" then
			if target.hidden then return SECRET, "x" end
			return "Odrin", "Other"
		end
		return saved.UnitFullName(u)
	end
	CC.GetCapabilityStatus = function() return { { ready = true, name = "Tania-Realm" } } end
	local function ask()
		local n = #CHATSENT
		local ok, err = pcall(CC.RequestRez, CC)
		return ok, err, sentSince(n)
	end

	-- R16: the channel that reaches the whole group
	STUB_IN_RAID, STUB_IS_LEADER, STUB_IS_ASSIST = false, true, false
	local ok, err, sent = ask()
	check("rez request in a party: /party only", ok and chans(sent) == "PARTY", chans(sent) .. " " .. tostring(err))
	INSTANCE_GROUP = true
	ok, err, sent = ask()
	check("  in an instance group (Dungeon Finder, battleground): INSTANCE_CHAT",
		ok and chans(sent) == "INSTANCE_CHAT", chans(sent) .. " " .. tostring(err))
	STUB_IN_RAID = true
	ok, err, sent = ask()
	check("  in an instance raid (Raid Finder): INSTANCE_CHAT and no raid warning",
		ok and chans(sent) == "INSTANCE_CHAT", chans(sent) .. " " .. tostring(err))
	INSTANCE_GROUP = false
	STUB_IS_LEADER, STUB_IS_ASSIST = false, true
	ok, err, sent = ask()
	check("  in a normal raid as an assistant: RAID and RAID_WARNING", ok and chans(sent) == "RAID,RAID_WARNING", chans(sent))
	STUB_IN_RAID, STUB_IS_LEADER, STUB_IS_ASSIST = false, true, false

	-- R17: only a dead friendly player
	target.player = false
	ok, err, sent = ask()
	check("rez request: a dead monster is refused", ok and #sent == 0, chans(sent) .. " " .. tostring(err))
	target.player, target.friend = true, false
	ok, err, sent = ask()
	check("  a dead enemy player is refused", ok and #sent == 0, chans(sent))
	target.friend, target.dead = true, false
	ok, err, sent = ask()
	check("  a living friendly player is refused", ok and #sent == 0, chans(sent))
	target.dead = true
	ok, err, sent = ask()
	check("  a dead friendly player outside the group is named", ok and #sent == 1 and sent[1].msg:find("Odrin", 1, true) ~= nil,
		chans(sent) .. " " .. tostring(err))
	target.hidden = true
	ok, err, sent = ask()
	check("  a hidden target name raises no error and sends nothing", ok and #sent == 0, tostring(err))
	UnitExists, UnitIsDeadOrGhost, UnitFullName = saved.UnitExists, saved.UnitIsDeadOrGhost, saved.UnitFullName
	UnitIsPlayer, UnitIsFriend, CC.GetCapabilityStatus = saved.UnitIsPlayer, saved.UnitIsFriend, saved.GetCapabilityStatus
end

do
	-- R23: a custom spell with a built-in's ID overrides the cooldown length only
	local bid, b
	for id, d in pairs(CC.SpellData) do
		if not d.custom and not d.consumable and d.class ~= "UNKNOWN" and (not bid or id < bid) then bid, b = id, d end
	end
	local origDur, origClass, origName = b.duration, b.class, b.name
	check("custom spell with a built-in's ID: added", CC:AddCustomSpell(bid, origDur + 100))
	local d = CC.SpellData[bid]
	check("  keeps the built-in's class, name and listing, with the new length",
		d and d.duration == origDur + 100 and d.class == origClass and d.name == origName and not d.custom,
		d and (d.class .. " " .. tostring(d.custom)))
	CC:RemoveCustomSpell(bid)
	d = CC.SpellData[bid]
	check("  Remove brings the built-in back as it was", d == b and d.duration == origDur and CC.db.customSpells[tostring(bid)] == nil)
	-- saved across a reload: LoadCustomSpells applies it the same way
	CC.db.customSpells[tostring(bid)] = { name = origName, duration = origDur + 7, icon = 1 }
	CC:LoadCustomSpells()
	d = CC.SpellData[bid]
	check("  a saved override is applied at load, built-in kept", d and d.duration == origDur + 7 and d.class == origClass)
	CC:RemoveCustomSpell(bid)
	check("  and removed again", CC.SpellData[bid] == b)
	-- an ordinary custom spell still comes and goes
	SPELLINFO[777001] = { "Odd Spell", 5 }
	CC:AddCustomSpell(777001, 90)
	check("an ordinary custom spell is added", CC.SpellData[777001] and CC.SpellData[777001].custom == true)
	local fsNote = CC.noCustomFS
	CC:RefreshSpellList()
	check("  custom list: 'No custom spells added yet.' hidden while a spell is listed", fsNote == nil or CC.noCustomFS:IsShown() == false,
		tostring(CC.noCustomFS and CC.noCustomFS:IsShown()))
	CC:RemoveCustomSpell(777001)
	check("  removed: nothing left behind", CC.SpellData[777001] == nil)
	local anyCustom = next(CC.db.customSpells) ~= nil
	check("  and the note is shown again once the list is empty", anyCustom or CC.noCustomFS:IsShown() == true)
end

do
	-- R24: you in a raid are counted once
	local groupWas = GROUP
	GROUP = {
		{ unit = "raid1", name = PLAYER.name, realm = PLAYER.realm, class = "DRUID", guid = PLAYER.guid },
		{ unit = "raid2", name = "Brannoc", realm = PLAYER.realm, class = "WARRIOR", guid = "Player-1-0000009" },
	}
	STUB_IN_RAID = true
	local st = CC:GetGroupBuffStatus()
	check("group buff line in a raid counts you once", st and st.total == 2, st and st.total)
	STUB_IN_RAID = false
	GROUP = groupWas
end

do
	-- R26, R29: one lock for all three windows; the Settings tick follows it
	CC:SetWindowsLocked(false)
	SlashCmdList["COOLDOWNCOLLABORATOR"]("lock")
	check("/cdc lock locks the panel, the Essentials bar and the Lane view",
		CC.db.locked and CC.db.essentialsLocked and CC.db.laneLocked and CC:AreWindowsLocked())
	local box = CC.lockCheck
	local f = CC.optionsFrame
	check("Settings: the box says Lock windows", f ~= nil and _G["CCOptionsFrame"] == f and box ~= nil)
	f.__scripts.OnShow(f)
	check("  its tick follows /cdc lock when the window is shown", box:GetChecked() == true)
	SlashCmdList["COOLDOWNCOLLABORATOR"]("unlock")
	check("/cdc unlock frees all three",
		not CC.db.locked and not CC.db.essentialsLocked and not CC.db.laneLocked)
	f.__scripts.OnShow(f)
	check("  and the tick clears on the next show", box:GetChecked() == false)
	box.__scripts.OnClick(setmetatable({}, { __index = function(_, k) if k == "GetChecked" then return function() return true end end end }))
	check("  the box locks all three", CC.db.locked and CC.db.essentialsLocked and CC.db.laneLocked)
	CC:SetWindowsLocked(false)
end

do
	-- R27, R28: consumables get an explicit category, can be listed and removed
	local function slash(m) SlashCmdList["COOLDOWNCOLLABORATOR"](m) end
	slash("consumable 555001 3600 flask Haste Brew")
	check("/cdc consumable <id> <sec> flask <name>: category flask, name kept",
		CC.SpellData[555001] and CC.SpellData[555001].category == "flask" and CC.SpellData[555001].name == "Haste Brew")
	slash("consumable 555002 3600 food Roast Thing")
	check("  food", CC.SpellData[555002] and CC.SpellData[555002].category == "food" and CC.SpellData[555002].name == "Roast Thing")
	slash("consumable 555003 3600 other Mystery Feast")
	check("  other: tracked, in neither count", CC.SpellData[555003] and CC.SpellData[555003].category == nil
		and CC.SpellData[555003].name == "Mystery Feast")
	slash("consumable 555004 3600 Flask of Odd Power")
	check("old form guesses a flask from the name, case-insensitive, as a word anywhere",
		CC.SpellData[555004] and CC.SpellData[555004].category == "flask" and CC.SpellData[555004].name == "Flask of Odd Power")
	slash("consumable 555005 3600 Hearty Meal FOOD Bowl")
	check("  and food", CC.SpellData[555005] and CC.SpellData[555005].category == "food")
	slash("consumable 555006 3600 Haste Flask flask")
	check("  the old trailing flag still works", CC.SpellData[555006] and CC.SpellData[555006].category == "flask"
		and CC.SpellData[555006].name == "Haste Flask")
	slash("consumable 555007 3600 Cauldron")
	check("  a name with neither word is tracked, uncounted", CC.SpellData[555007] and CC.SpellData[555007].category == nil)
	local p0 = #PRINTS
	slash("consumable 12")
	check("  the usage line names the category", PRINTS[p0 + 1] and PRINTS[p0 + 1]:find("flask|food|other", 1, true) ~= nil, PRINTS[p0 + 1])

	CC:RefreshSpellList()
	check("Settings lists the registered consumables under their own heading", CC.consumableHdrFS and CC.consumableHdrFS:IsShown() == true)
	slash("consumable remove 555001")
	check("/cdc consumable remove <id> forgets it", CC.SpellData[555001] == nil and CC.db.consumableBuffs["555001"] == nil
		and CC.consumableActive[555001] == nil)
	local p1 = #PRINTS
	slash("consumable remove 555001")
	check("  removing one that isn't there says so", #PRINTS == p1 + 1)
	for id = 555002, 555007 do slash("consumable remove " .. id) end
	slash("consumable remove 424242")
	CC:RefreshSpellList()
	check("  with none left the heading is hidden", next(CC.db.consumableBuffs) ~= nil or CC.consumableHdrFS:IsShown() == false)
end

do
	-- R31: a shift-clicked spell link goes into the Custom Spells box while it has focus
	local box = _G["CCSpellInput"]
	local link = "|cff71d5ff|Hspell:29166:0|h[Innervate]|h|r"
	local focused = false
	rawset(box, "HasFocus", function() return focused end)
	insertNew(link); insertOld(link)
	check("shift-click a spell link with the box unfocused: box untouched", box:GetText() == nil or box:GetText() == "")
	focused = true
	local e = #ERRORS
	insertNew(link); insertOld(link)
	check("  with the box focused: it takes the spell (both link-insert calls, once over)", box:GetText() == "29166", box:GetText())
	check("  no Lua error, and the original calls still return as before", #ERRORS == e and insertNew("x") == false)
end

do
	-- R33: the minimap drag compares the cursor and the centre in the minimap's own scale
	local btn = _G["CCMinimapButton"]
	local saveCenter, saveScale, saveCursor = Minimap.GetCenter, Minimap.GetEffectiveScale, GetCursorPosition
	rawset(Minimap, "GetCenter", function() return 50, 50 end)
	rawset(Minimap, "GetEffectiveScale", function() return 2 end)
	GetCursorPosition = function() return 150, 50 end
	btn.__scripts.OnDragStart(btn)
	local ok, err = pcall(btn.__scripts.OnUpdate, btn)
	btn.__scripts.OnDragStop(btn)
	-- cursor 150,50 at scale 2 is 75,25; from the centre 50,50 that is down and right: -45 degrees
	check("minimap drag at scale 2: angle from the cursor in the minimap's scale", ok and near(CC.db.minimapAngle, -45, 0.01),
		tostring(CC.db.minimapAngle) .. " " .. tostring(err))
	rawset(Minimap, "GetCenter", saveCenter); rawset(Minimap, "GetEffectiveScale", saveScale)
	GetCursorPosition = saveCursor
end

local allowed = { CooldownCollaborator = true, CC = true, CooldownCollaboratorDB = true, SLASH_COOLDOWNCOLLABORATOR1 = true,
	CCEventFrame = true, CCMainFrame = true, CCEssentialsFrame = true, CCLaneFrame = true, CCMinimapButton = true,
	CCBuffMissingFrame = true, CCAlertOptions = true, CCCopyBox = true, CCSetupDialog = true, CooldownCollaboratorAPI = true,
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
