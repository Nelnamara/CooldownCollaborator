-- Translations: the English text is the key (Locales/enUS.lua), CC.L answers the key itself for a phrase
-- without a translation.
--   node run.js <addon> <toc number> locale.lua <toc file> [pseudo]
-- Always: every L["..."] in the addon's files is a key of enUS.lua and no enUS key goes unused, an unknown key
--   comes back as itself, and no visible string literal is handed to a SetText / AddLine / print / chat call
--   without L[] (a debug or verbose line carries "-- debug", a block sits between "debug begin" and "debug end").
-- pseudo: a fake deDE client where every key is translated to a marker plus the key; the windows, tooltips,
--   Options, slash commands and chat lines are driven, and every text with letters that shows up must carry the
--   marker (or be data: a spell name, a player name, a time).
dofile(HARNESS_DIR .. "/wow.lua")
local PSEUDO = HARNESS_ARG == "pseudo"
PLAYER.class = "MAGE"

local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[locale %s %s%s]", HARNESS_TOCFILE, FLAVOR, PSEUDO and " pseudo" or ""))

local MARK = "\194\167"   -- the section sign, as UTF-8
if PSEUDO then
	GAME_LOCALE = "deDE"
	STUB_FILES = STUB_FILES or {}
	STUB_FILES["locales/dede.lua"] = function()
		local L = CooldownCollaborator.NewLocale("deDE")
		for key in pairs(CooldownCollaborator.localeKeys) do L[key] = MARK .. key end
	end
	TEXT_LOG = {}
end

local files = LoadTOC(HARNESS_TOCFILE)
for id, d in pairs(CC.SpellData) do
	SPELLINFO[id] = { d.name, d.icon }
	for _, r in ipairs(d.ranks or {}) do SPELLINFO[r] = { d.name, d.icon } end
end
Login()
check("loads and logs in without errors", #ERRORS == 0, ERRORS[1])

local L = CC.L
local keys = CC.localeKeys

---------------------------------------------------------------- every L["..."] is a key
local function literals(src)
	local found = {}
	local i = 1
	while true do
		local s, e = src:find('L%["', i)
		if not s then break end
		i = e + 1
		local before = s > 1 and src:sub(s - 1, s - 1) or " "
		if not before:match("[%w_:%.]") then
			local j = e + 1
			while j <= #src do
				local c = src:sub(j, j)
				if c == "\\" then j = j + 2
				elseif c == '"' then break
				else j = j + 1 end
			end
			if src:sub(j + 1, j + 1) == "]" then
				local fn = load("return " .. src:sub(e, j))
				if fn then found[#found + 1] = fn() end
				i = j + 1
			end
		end
	end
	return found
end

local used, missing, total = {}, {}, 0
local sources = {}
for _, f in ipairs(files) do
	if f:match("%.lua$") and not f:lower():match("^locales/") then
		local src = HARNESS_READ(HARNESS_SRC .. "/" .. f)
		if src then
			src = src:gsub("\r\n", "\n")
			sources[f] = src
			for _, key in ipairs(literals(src)) do
				total = total + 1
				used[key] = true
				if not keys[key] then missing[key] = f end
			end
		end
	end
end
local nMissing = 0
for k, f in pairs(missing) do
	nMissing = nMissing + 1
	if nMissing <= 8 then OUT("    missing from enUS (" .. f .. "): " .. k) end
end
check("every L[\"...\"] in the code is a key of enUS.lua", nMissing == 0, string.format("%d lookups, %d missing", total, nMissing))
local unused = 0
for k in pairs(keys) do
	if not used[k] then
		unused = unused + 1
		if unused <= 8 then OUT("    unused enUS key: " .. k) end
	end
end
check("enUS.lua lists no phrase the code never uses", unused == 0, unused .. " unused")
check("an unknown key comes back as itself", L["No such phrase \1"] == "No such phrase \1")
local nkeys = 0
for _ in pairs(keys) do nkeys = nkeys + 1 end
check("enUS.lua has phrases", nkeys > 100, nkeys)
if not PSEUDO then
	local same = true
	for k in pairs(keys) do if L[k] ~= k then same = false end end
	check("an English client shows every key as written", same)
end

---------------------------------------------------------------- no visible literal without L[]
-- Calls whose text a player sees. A string literal in their arguments must sit inside L[...].
local CALLS = { "SetText", "SetTitle", "AddLine", "AddDoubleLine", "print", "SendChat", "SendChatLine",
	"SendChatMessage", "ShowCopyBox", "CreateFontString" }
local ALLOWED = { "CDC", "CooldownCollaborator", "CooldownTimeline3", "CD Collab" }
-- words the code compares or passes on (a state, a chat channel, a unit token), never shown as they are
local CODES = { DEAD = true, OFFLINE = true, RAID_WARNING = true, WHISPER = true, old = true, ok = true,
	player = true, never = true, last = true }

local function clean(s)
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cff", ""):gsub("|r", ""):gsub("|T.-|t", "")
	s = s:gsub("%%[%-%d%.]*%a", ""):gsub("\\[%d]+", ""):gsub("\\n", " ")
	for _, w in ipairs(ALLOWED) do s = s:gsub(w, "") end
	return s
end

-- the text of the call's arguments starting after the "(" at position p, and where it ends
local function argsFrom(src, p)
	local depth, i = 1, p
	while i <= #src do
		local c = src:sub(i, i)
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= #src and src:sub(j, j) ~= c do
				if src:sub(j, j) == "\\" then j = j + 1 end
				j = j + 1
			end
			i = j
		elseif c == "(" then depth = depth + 1
		elseif c == ")" then
			depth = depth - 1
			if depth == 0 then return src:sub(p, i - 1), i end
		end
		i = i + 1
	end
	return src:sub(p), #src
end

local function stringsOf(args)
	local out = {}
	local i = 1
	while i <= #args do
		local c = args:sub(i, i)
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= #args and args:sub(j, j) ~= c do
				if args:sub(j, j) == "\\" then j = j + 1 end
				j = j + 1
			end
			local before = args:sub(math.max(1, i - 2), i - 1)
			local lit = args:sub(i + 1, j - 1)
			if before ~= "L[" and not CODES[lit] then out[#out + 1] = lit end
			i = j
		end
		i = i + 1
	end
	return out
end

local bare, nBare = {}, 0
for f, src in pairs(sources) do
	if not f:match("^Data") then
		-- which lines are debug output
		local lineOf, debugLine = {}, {}
		local n, inDebug = 1, false
		for line in (src .. "\n"):gmatch("([^\n]*)\n") do
			if line:find("debug begin", 1, true) then inDebug = true end
			debugLine[n] = inDebug or line:find("-- debug", 1, true) ~= nil
			if line:find("debug end", 1, true) then inDebug = false end
			n = n + 1
		end
		local function lineAt(pos)
			local _, c = src:sub(1, pos):gsub("\n", "")
			return c + 1
		end
		for _, name in ipairs(CALLS) do
			local from = 1
			while true do
				local s, e = src:find("%f[%w_]" .. name .. "%(", from)
				if not s then break end
				from = e + 1
				local ln = lineAt(s)
				local commentStart = src:sub(1, s):match("[^\n]*$"):find("%-%-")
				if not commentStart and not debugLine[ln] then
					local args = argsFrom(src, e + 1)
					if name ~= "CreateFontString" then
						for _, lit in ipairs(stringsOf(args)) do
							if clean(lit):find("%a%a") then
								nBare = nBare + 1
								if nBare <= 12 then OUT(string.format("    bare string (%s:%d, %s): %s", f, ln, name, lit)) end
								bare[#bare + 1] = lit
							end
						end
					end
				end
			end
		end
	end
end
check("no visible string literal skips L[]", nBare == 0, nBare .. " found")

if not PSEUDO then
	OUT(string.format("RESULT %s %s: phrases %d, checks %d, fails %d, lua errors %d", "locale " .. HARNESS_TOCFILE, FLAVOR, nkeys, checks, fails, #ERRORS))
	return
end

---------------------------------------------------------------- pseudo: drive the windows
local TIPS, PRINTS, CHATS = {}, {}, {}
local function tip(_, t) if type(t) == "string" then TIPS[#TIPS + 1] = t end end
GameTooltip.SetText = tip
GameTooltip.AddLine = tip
GameTooltip.AddDoubleLine = function(_, a, b) tip(nil, a); tip(nil, b) end
print = function(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	PRINTS[#PRINTS + 1] = table.concat(t, " ")
end
if C_ChatInfo then C_ChatInfo.SendChatMessage = function(msg) CHATS[#CHATS + 1] = msg; return true end end

local function try(label, fn, ...)
	local e0 = #ERRORS
	local ok, err = pcall(fn, ...)
	if not ok then check("drive: " .. label, false, err) end
	if #ERRORS > e0 then check("drive: " .. label, false, ERRORS[#ERRORS]) end
end

local classes = {}
for _, d in pairs(CC.SpellData) do if not d.consumable then classes[d.class] = true end end
local classList = {}
for c in pairs(classes) do classList[#classList + 1] = c end
table.sort(classList)
GROUP = {}
STUB_IN_RAID = true
for i = 1, 8 do
	GROUP[i] = { unit = "raid" .. i, name = "M" .. i, realm = "Realm", class = classList[(i - 1) % #classList + 1],
		guid = string.format("Player-1-5%05d", i) }
end
FireEvent("GROUP_ROSTER_UPDATE")
Advance(2)
local me = CC:FullName("player")
local n = 0
for id, d in pairs(CC.SpellData) do
	if not d.consumable and n < 12 then
		n = n + 1
		local who = n % 2 == 0 and me or ("M" .. (n % 8 + 1) .. "-Realm")
		try("cast", CC.RecordCooldownFromComm, CC, who, id, GetTime(), d.class, "comm")
	end
end
Advance(1)

try("refresh all views", CC.RefreshAllViews, CC)
for _, key in ipairs({ "panelStyle" }) do CC.db[key] = "icons"; try("icons style", CC.RefreshRows, CC); CC.db[key] = "text" end
CC.db.teams = { Alpha = { "M1", "M2" } }
CC.db.guildSync = true
try("team and guild tabs", CC.RefreshRows, CC)
CC.db.panelTab = "guild"
try("guild tab", CC.RefreshRows, CC)
CC.db.panelTab = "team:Alpha"
try("team tab", CC.RefreshRows, CC)
CC.db.panelTab = "all"
CC.db.guildSync = false
CC.db.teams = {}
try("refresh", CC.RefreshRows, CC)
Solo = function() GROUP = {}; STUB_IN_RAID = false; FireEvent("GROUP_ROSTER_UPDATE") end

-- tooltips
for id in pairs(CC.SpellData) do
	try("tooltip", CC.CooldownTooltipLines, CC, me, id)
	try("tooltip names", CC.CooldownTooltipLines, CC, { "M1-Realm", "M2-Realm" }, id)
end
if CC.frame then try("tooltip show", CC.ShowCooldownTooltip, CC, CC.frame, "M1-Realm", next(CC.SpellData)) end

-- the windows
CC.db.essentialsEnabled, CC.db.laneEnabled, CC.db.deadListEnabled = true, true, true
CC.db.externalsEnabled, CC.db.manaEnabled, CC.db.burstEnabled = true, true, true
Advance(2)
try("refresh again", CC.RefreshAllViews, CC)
Advance(2)
if CC.minimapBtn and CC.minimapBtn.__scripts and CC.minimapBtn.__scripts.OnEnter then
	try("minimap tooltip", CC.minimapBtn.__scripts.OnEnter, CC.minimapBtn)
end
try("alert", CC.ShowMidscreenAlert, CC, "M1-Realm", next(CC.SpellData), 5)
try("rez call", CC.CallRez, CC, "M3-Realm")
try("request rez", CC.RequestRez, CC)
try("ask mana", CC.AskForMana, CC)
try("no charges text", CC.NoRezChargesText, CC)
CC.rezCharges = { charges = 0, nextAt = GetTime() + 70, at = GetTime() }
try("no charges text 0", CC.NoRezChargesText, CC)
try("share plan", CC.SharePlan, CC, "nope")
try("last pull", CC.PrintLastPull, CC)
try("post ready", CC.PostReady, CC)
try("next hit", CC.NextHitCommand, CC, "30")
try("next hit off", CC.NextHitCommand, CC, "off")
try("next hit bad", CC.NextHitCommand, CC, "x")
try("buff missing", function()
	if CC.BuildBuffMissing and not CC.buffMissingFrame then CC:BuildBuffMissing() end
	if CC.buffMissingFrame then
		CC.buffMissingFrame.countKey = "flask"
		CC:FillBuffMissing()
	end
end)
try("consumable add", CC.AddConsumableBuff, CC, 99901, 60, nil, nil)
try("consumable remove", CC.RemoveConsumableBuff, CC, 99901, true)
try("consumable remove bad", CC.RemoveConsumableBuff, CC, 5, true)
try("custom spell bad", CC.AddCustomSpell, CC, 99999999, 60)
try("setup", function()
	local s = CC:SnapshotSetup()
	s.disabled = { 1, 2, 3 }
	CC:DescribeSetup(s)
	CC:ShowImportBox()
end)
try("support", CC.SupportText, CC)

local slash = SlashCmdList["COOLDOWNCOLLABORATOR"]
for _, cmd in ipairs({ "lock", "unlock", "reset", "essentials", "essentials", "lanes", "lanes", "consumable", "nexthit",
	"lastpull", "post", "settings", "" }) do
	try("/cdc " .. cmd, slash, cmd)
end

-- the Settings window, every page, and the alert window
try("options", CC.OpenOptions, CC)
try("alert options", CC.OpenAlertOptions, CC, next(CC.SpellData), nil)
if CC.optionsFrame and CC.optionsFrame.__scripts and CC.optionsFrame.__scripts.OnShow then
	try("options onshow", CC.optionsFrame.__scripts.OnShow, CC.optionsFrame)
end
try("spell lists", function() CC.db.spellGroupBy = "kind"; CC:RefreshDefaultSpellList(); CC.db.spellGroupBy = "class"; CC:RefreshDefaultSpellList() end)
try("profile status", function() if CC.RefreshProfileStatus then CC:RefreshProfileStatus() end end)
Advance(2)

-- what the player saw must carry the marker, or be data
local dataWords = {}
for _, d in pairs(CC.SpellData) do if d.name then dataWords[#dataWords + 1] = d.name end end
for _, w in ipairs({ "M%d+", "Realm", PLAYER.name or "Player", "Alpha", "nope", "Warrior", "Mage", "Priest" }) do dataWords[#dataWords + 1] = w end
local function isData(s)
	local t = clean(s):gsub("%d+[ms]", "")   -- 1m 30s: the time units stay as they are
	for _, w in ipairs(dataWords) do
		local pat = w:find("%%d") and w or w:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
		t = t:gsub(pat, "")
	end
	t = t:gsub("[%d%s,:;%.%(%)%+%-/>%%x\194\183]", "")
	return not t:find("%a%a")
end
local seen, badCount, badList = {}, 0, {}
local function audit(list, where)
	for _, s in ipairs(list) do
		if type(s) == "string" and not seen[s] then
			seen[s] = true
			if not s:find(MARK, 1, true) and not isData(s) then
				badCount = badCount + 1
				if badCount <= 15 then badList[#badList + 1] = where .. ": " .. s end
			end
		end
	end
end
audit(TEXT_LOG, "window text")
audit(TIPS, "tooltip")
audit(PRINTS, "chat line")
audit(CHATS, "message")
for _, s in ipairs(badList) do OUT("    unmarked " .. s) end
check("every text shown is translated or data", badCount == 0, string.format("%d texts seen, %d unmarked", #TEXT_LOG + #TIPS + #PRINTS + #CHATS, badCount))
check("windows showed marked text", (function()
	local c = 0
	for _, s in ipairs(TEXT_LOG) do if type(s) == "string" and s:find(MARK, 1, true) then c = c + 1 end end
	return c > 20
end)())

OUT(string.format("RESULT %s %s pseudo: phrases %d, checks %d, fails %d, lua errors %d", "locale " .. HARNESS_TOCFILE, FLAVOR, nkeys, checks, fails, #ERRORS))
