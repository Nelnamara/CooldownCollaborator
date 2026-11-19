-- CooldownCollaborator group checks for one TOC: a /reload inside a big raid
-- (the raid is there before the addon loads), the Essentials bar in raids of
-- every size (three providers a heading, "+N more", the flask/food strip), one window's error
-- not stopping the others, and leaving the group closing the windows.
-- Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/groups.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[groups %s %s]", HARNESS_TOCFILE, FLAVOR))

-- Run f where errors are expected: returns the errors it raised (first lines)
-- and keeps them out of ERRORS and the output.
local function expectErrors(f)
	local e0, out = #ERRORS, OUT
	OUT = function() end
	f()
	OUT = out
	local got = {}
	for i = #ERRORS, e0 + 1, -1 do
		table.insert(got, 1, (ERRORS[i]:match("[^\n]+")))
		ERRORS[i] = nil
	end
	return got
end
local function allMatch(errs, n, text)
	if #errs ~= n then return false end
	for _, e in ipairs(errs) do
		if not e:find(text, 1, true) then return false end
	end
	return true
end

-- A raid of `lust` lust providers, `rez` druids and two priests, plus us (a
-- priest, never a provider) on the last raid token.
local LUST = ({ retail = "MAGE", mop = "MAGE", tbc = "SHAMAN" })[FLAVOR]
PLAYER.class = "PRIEST"
local function raid(lust, rez)
	GROUP = {}
	local function add(prefix, class, n)
		for i = 1, n do
			local k = #GROUP + 1
			GROUP[k] = { unit = "raid" .. k, name = prefix .. i, realm = "Realm", class = class, guid = "Player-1-1" .. k }
		end
	end
	if LUST then add("L", LUST, lust) end
	add("D", "DRUID", rez)
	add("P", "PRIEST", 2)
	GROUP[#GROUP + 1] = { unit = "raid" .. (#GROUP + 1), name = PLAYER.name, realm = PLAYER.realm, class = PLAYER.class, guid = PLAYER.guid }
	STUB_IN_RAID = true
end
local function party(classes)
	GROUP = {}
	for i, class in ipairs(classes) do
		GROUP[i] = { unit = "party" .. i, name = "G" .. i, realm = "Realm", class = class, guid = "Player-1-2" .. i }
	end
	STUB_IN_RAID = false
end
local function solo()
	GROUP = {}
	STUB_IN_RAID = false
end

-- The bar's shown lines, top down (CC.essentialsShown): headings, providers,
-- "+N more" and the flask/food strip, plus the other lines it may carry.
-- "Battle Rez: 3 +2 | strip" = the Battle Rez heading, three providers by name,
-- "+2 more", then the flask/food strip last. nil and a reason when it's malformed:
-- a line out of place, or lines not stacked one under the other.
local function readBar()
	local lines, y = {}, 16
	for i, line in ipairs(CC.essentialsShown or {}) do
		if not line.__shown then return nil, "line " .. i .. " hidden" end
		local p = line.__points[1]
		if not p or p[5] ~= -y then return nil, "line " .. i .. " not right under the one above" end
		y = y + line:GetHeight()
		local m = line.model
		local kind, text = m.kind, nil
		if kind == "heading" then
			text = line.label.__text
		elseif kind == "provider" then
			text = line.nameText.__text
		elseif kind == "text" and m.key == "more" then
			kind, text = "more", line.text.__text
		elseif kind == "strip" then
			text = line.parts[1].text.__text
		end
		lines[#lines + 1] = { kind = kind, text = text }
	end
	local sections, parts, cur = {}, {}, nil
	for i, l in ipairs(lines) do
		if l.kind == "heading" then
			cur = { label = l.text, named = 0 }
			sections[#sections + 1] = cur
		elseif l.kind == "provider" and cur and not cur.more then
			cur.named = cur.named + 1
		elseif l.kind == "more" and cur and not cur.more then
			cur.more = tonumber(l.text:match("^%+(%d+) more"))
			if not cur.more then return nil, "bad more line '" .. l.text .. "'" end
		elseif l.kind == "strip" and i ~= #lines then
			return nil, "the strip is not last"
		elseif l.kind == "provider" or l.kind == "more" then
			return nil, "line " .. i .. " (" .. l.kind .. ") out of place"
		end
	end
	for _, sec in ipairs(sections) do
		parts[#parts + 1] = sec.label .. ": " .. sec.named .. (sec.more and (" +" .. sec.more) or "")
	end
	if lines[#lines] and lines[#lines].kind == "strip" then parts[#parts + 1] = "strip" end
	return { lines = #lines, height = y + 2, sections = sections, text = table.concat(parts, " | ") }
end

-- Every capability the client has shows its heading (with no providers too),
-- and its named providers plus "+N more" add up to all of them: nobody
-- silently left off.
local function barAddsUp(bar)
	local k = 0
	for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
		local n = #CC:GetCapabilityStatus(capKey)
		k = k + 1
		local sec = bar.sections[k]
		if not sec or sec.label ~= CC.CAPABILITIES[capKey].label or sec.named + (sec.more or 0) ~= n then return false end
	end
	return k == #bar.sections
end

---------------------------------------------------------------- a /reload in a big raid
-- The raid is readable before the addon loads, so Init's first refresh sees it.
-- Init is wrapped to fail after its real work, as any start-up error would:
-- the addon must still hear its events.
local reloadLust, reloadRez = 7, 5
if not LUST then reloadLust, reloadRez = 0, 9 end
raid(reloadLust, reloadRez)
LoadTOC(HARNESS_TOCFILE)
for id, d in pairs(CC.SpellData or {}) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
CooldownCollaboratorDB = { laneEnabled = true }
local realInit = CC.Init
CC.Init = function(self)
	realInit(self)
	error("test: start-up error after Init")
end
local startErrors = expectErrors(Login)
CC.Init = realInit
check(string.format("reload in a raid of %d lust + %d Battle Rez providers: Init itself raises no Lua error", reloadLust, reloadRez),
	allMatch(startErrors, 1, "test: start-up error"),
	not allMatch(startErrors, 1, "test: start-up error") and table.concat(startErrors, " / ") or nil)

local missing = {}
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_LEVEL", "ENCOUNTER_START", "ENCOUNTER_END", "CHAT_MSG_ADDON",
	"PLAYER_LOGOUT", "PLAYER_LOGIN", FLAVOR == "retail" and "INSPECT_READY" or nil }) do
	if not IsEventRegisteredAnywhere(e) then missing[#missing + 1] = e end
end
check("  an error out of Init still leaves every event registered", #missing == 0, table.concat(missing, ","))
FireEvent("CHAT_MSG_ADDON", "CDCOLLAB", "20484:5.000:D1:DRUID", "RAID", "D1-Realm")
check("  and a raid member's sync is heard", CC.state["D1-Realm"] and CC.state["D1-Realm"].spells[20484] ~= nil)
CC.state["D1-Realm"] = nil
check("  the Essentials bar shows", CC.essentialsFrame:IsShown())
check("  the Lane view (on) shows too", CC.laneFrame:IsShown())
local bar, why = readBar()
local expectReload = LUST and "Bloodlust/Heroism: 3 +4 | Battle Rez: 3 +2 | strip" or "Battle Rez: 3 +6 | strip"
check("  bar: three providers a heading, '+N more' for the rest, flask/food strip last",
	bar and bar.text == expectReload and barAddsUp(bar), bar and bar.text or why)
check("  Request Rez sits after the Battle Rez icons (raid leader)", CC.essentialsRezBtn:IsShown()
	and CC.essentialsRezBtn.__points[1][2].lineKind == "icons")
local p0 = #PRINTS
SlashCmdList["COOLDOWNCOLLABORATOR"]("roster")
local members = 0
for _ in pairs(CC.roster or {}) do members = members + 1 end
check("  /cdc roster prints every member", members == reloadLust + reloadRez + 3 and #PRINTS == p0 + 1 + members,
	(#PRINTS - p0) .. " lines for " .. members)
check("no Lua errors so far", #ERRORS == 0, ERRORS[1])

---------------------------------------------------------------- raids of every size
-- lust and Battle Rez providers -> the bar; three a heading, the strip last
local sizes = LUST and {
	{ 4, 3,   "Bloodlust/Heroism: 3 +1 | Battle Rez: 3 | strip" },
	{ 4, 4,   "Bloodlust/Heroism: 3 +1 | Battle Rez: 3 +1 | strip" },
	{ 6, 6,   "Bloodlust/Heroism: 3 +3 | Battle Rez: 3 +3 | strip" },
	{ 1, 10,  "Bloodlust/Heroism: 1 | Battle Rez: 3 +7 | strip" },
	{ 0, 12,  "Bloodlust/Heroism: 0 | Battle Rez: 3 +9 | strip" },
	{ 25, 12, "Bloodlust/Heroism: 3 +22 | Battle Rez: 3 +9 | strip" },
} or {
	{ 0, 3,  "Battle Rez: 3 | strip" },
	{ 0, 8,  "Battle Rez: 3 +5 | strip" },
	{ 0, 12, "Battle Rez: 3 +9 | strip" },
	{ 0, 37, "Battle Rez: 3 +34 | strip" },
}
for _, s in ipairs(sizes) do
	raid(s[1], s[2])
	CC.essentialsFrame:Hide()
	local e0 = #ERRORS
	FireEvent("GROUP_ROSTER_UPDATE")
	Advance(1)   -- the bar's own ticker refreshes it again
	bar, why = readBar()
	local ok = #ERRORS == e0 and CC.essentialsFrame:IsShown() and bar and bar.text == s[3] and barAddsUp(bar)
		and CC.essentialsFrame:GetHeight() == bar.height
	check(string.format("raid, %d lust + %d Battle Rez providers: no Lua error, bar shown, %s", s[1], s[2], s[3]),
		ok, not ok and (bar and bar.text or why) or nil)
end

---------------------------------------------------------------- one window's error doesn't stop the others
raid(2, 2)
FireEvent("GROUP_ROSTER_UPDATE")
local function hideAll()
	CC.frame:Hide(); CC.essentialsFrame:Hide(); CC.laneFrame:Hide()
end
local realEss, realRows = CC.RefreshEssentials, CC.RefreshRows
CC.RefreshEssentials = function() error("test: Essentials refresh fails") end
hideAll()
raid(2, 3)
local errs = expectErrors(function() FireEvent("GROUP_ROSTER_UPDATE") end)
check("an Essentials error on a roster change: reported, and the Lane view, main panel and roster still update",
	allMatch(errs, 1, "test: Essentials refresh fails") and CC.laneFrame:IsShown() and CC.frame:IsShown()
	and CC.roster["D3-Realm"] ~= nil, table.concat(errs, " / "))
CC.RefreshEssentials = realEss
CC.RefreshRows = function() error("test: main panel refresh fails") end
hideAll()
raid(2, 4)
errs = expectErrors(function() FireEvent("GROUP_ROSTER_UPDATE") end)
check("a main panel error on a roster change: the roster scan, Essentials bar and Lane view still run",
	allMatch(errs, 1, "test: main panel refresh fails") and CC.roster["D4-Realm"] ~= nil
	and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown(), table.concat(errs, " / "))
hideAll()
errs = expectErrors(function() CC:RefreshAllViews() end)
check("  and on a cast or sync (RefreshAllViews)", allMatch(errs, 1, "test: main panel refresh fails")
	and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown(), table.concat(errs, " / "))
CC.RefreshRows = realRows

---------------------------------------------------------------- leaving the group closes the windows
FireEvent("GROUP_ROSTER_UPDATE")
check("in a raid: main panel, Essentials bar and Lane view open",
	CC.frame:IsShown() and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown())
solo()
FireEvent("GROUP_ROSTER_UPDATE")
check("leaving the raid closes all three", not CC.frame:IsShown() and not CC.essentialsFrame:IsShown() and not CC.laneFrame:IsShown())
Advance(2)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20484)
check("  they stay closed solo (timers, an own cast)", not CC.frame:IsShown() and not CC.essentialsFrame:IsShown()
	and not CC.laneFrame:IsShown())

SlashCmdList["COOLDOWNCOLLABORATOR"]("")
check("/cdc while solo shows the main panel", CC.frame:IsShown())
Advance(2)
FireEvent("GROUP_ROSTER_UPDATE")
check("  and it stays (its timer, a roster change while solo)", CC.frame:IsShown())
SlashCmdList["COOLDOWNCOLLABORATOR"]("")
check("  /cdc again closes it", not CC.frame:IsShown())
SlashCmdList["COOLDOWNCOLLABORATOR"]("essentials")
local essOff = not CC.db.essentialsEnabled and PRINTS[#PRINTS]:find("Essentials bar: OFF", 1, true)
SlashCmdList["COOLDOWNCOLLABORATOR"]("essentials")
local essOn = CC.db.essentialsEnabled and PRINTS[#PRINTS]:find("Essentials bar: ON", 1, true)
check("/cdc essentials while solo: OFF, ON, the bar waits for a group", essOff and essOn and not CC.essentialsFrame:IsShown())
SlashCmdList["COOLDOWNCOLLABORATOR"]("lanes")
local lanesOff = not CC.db.laneEnabled and PRINTS[#PRINTS]:find("Lane view: OFF", 1, true)
SlashCmdList["COOLDOWNCOLLABORATOR"]("lanes")
local lanesOn = CC.db.laneEnabled and PRINTS[#PRINTS]:find("Lane view: ON (it shows when you're in a group)", 1, true)
check("/cdc lanes while solo: OFF, then ON with the solo hint, the view waits for a group",
	lanesOff and lanesOn and not CC.laneFrame:IsShown(), PRINTS[#PRINTS])

party({ "DRUID", LUST or "DRUID" })
FireEvent("GROUP_ROSTER_UPDATE")
check("joining a party opens all three again", CC.frame:IsShown() and CC.essentialsFrame:IsShown() and CC.laneFrame:IsShown())
solo()
FireEvent("GROUP_ROSTER_UPDATE")
check("leaving the party closes them", not CC.frame:IsShown() and not CC.essentialsFrame:IsShown() and not CC.laneFrame:IsShown())
check("no Lua errors", #ERRORS == 0, ERRORS[1])

OUT(string.format("RESULT groups %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
