-- CooldownCollaborator final-review fixes (19 Nov 2026), one scenario at a time, each in its own
-- stubbed client (wow.lua in a fresh Lua environment). Prints ok / FAIL per check and one RESULT line.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/final.lua <toc file>

local OUTPUT = print
local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUTPUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end

local all = {}
local FLAVOR, RETAILAPI
-- a fresh client; prep(env) runs after the stub loads and before the addon's files do
local function Fresh(prep, db)
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.loadfile = function(path, mode) return loadfile(path, mode or "t", env) end
	assert(loadfile(HARNESS_DIR .. "/wow.lua", "t", env))()
	FLAVOR, RETAILAPI = env.FLAVOR, env.RETAILAPI
	env.CooldownCollaboratorDB = db
	if prep then prep(env) end
	env.LoadTOC(HARNESS_TOCFILE)
	for id, d in pairs(env.CC.SpellData) do
		env.SPELLINFO[id] = { d.name, d.icon }
		for _, r in ipairs(d.ranks or {}) do env.SPELLINFO[r] = { d.name, d.icon } end
	end
	all[#all + 1] = env
	return env
end
local function Errors()
	local n = 0
	for _, c in ipairs(all) do n = n + #c.ERRORS end
	return n
end
local function FirstError()
	for _, c in ipairs(all) do if c.ERRORS[1] then return c.ERRORS[1] end end
end
local function From(env, msg, channel, who, prefix)
	env.FireEvent("CHAT_MSG_ADDON", prefix or "CDCOLLAB", msg, channel or "PARTY", who .. "-Realm")
end

---------------------------------------------------------------- F1: the profile is applied once the realm is known
do
	local loggedIn = false
	local c = Fresh(function(env)
		-- the game: the player's realm is unreadable until PLAYER_LOGIN
		local realUnitFullName, realRealm = env.UnitFullName, env.GetNormalizedRealmName
		env.GetNormalizedRealmName = function() if loggedIn then return realRealm() end return nil end
		env.UnitFullName = function(u)
			local n, r = realUnitFullName(u)
			if u == "player" and not loggedIn then return n, nil end
			return n, r
		end
		env.PLAYER.name = "Bee"
	end, {
		disabledSpells = { [11111] = true },
		customSpells = {},
		profiles = {
			Heal = { disabled = { 11111 }, custom = {}, alerts = {}, places = {} },
			Tank = { disabled = { 22222 }, custom = {}, alerts = {}, places = {} },
		},
		charProfile = { ["Bee-Realm"] = "Tank", ["Tester-Realm"] = "Heal" },
	})
	c.FireEvent("ADDON_LOADED", "CooldownCollaborator")
	-- a logout before the character's profile is in must save nothing
	loggedIn = true
	c.FireEvent("PLAYER_LOGIN")
	c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	local db = c.CC.db
	check("F1: at login this character's own profile is applied (its list, not the last character's)",
		db.disabledSpells[22222] == true and db.disabledSpells[11111] == nil)
	c.FireEvent("PLAYER_LOGOUT")
	check("  logout leaves the other character's profile as it was and saves this one's",
		db.profiles.Heal.disabled[1] == 11111 and db.profiles.Tank.disabled[1] == 22222)
	-- a session that never reached login writes into no profile
	local d = Fresh(function(env) env.PLAYER.name = "Bee" end, {
		disabledSpells = { [11111] = true }, customSpells = {},
		profiles = { Tank = { disabled = { 22222 }, custom = {}, alerts = {}, places = {} } },
		charProfile = { ["Bee-Realm"] = "Tank" },
	})
	d.FireEvent("ADDON_LOADED", "CooldownCollaborator")
	d.FireEvent("PLAYER_LOGOUT")
	check("  a logout before the profile went in writes no profile", d.CC.db.profiles.Tank.disabled[1] == 22222)
end

---------------------------------------------------------------- F2: boss end, 1.x lines unless everyone is known to run format 2
do
	local function bossEnd(hello)
		local c = Fresh(function(env)
			env.PLAYER.class = "DRUID"
			env.GROUP = { { unit = "party1", name = "Old", realm = "Realm", class = "PRIEST", guid = "Player-1-51" } }
		end)
		c.KNOWN[20484] = true
		c.Login()
		c.FireEvent("GROUP_ROSTER_UPDATE")
		c.Advance(5)
		if hello then From(c, "H:2:1.2.0:retail", "PARTY", "Old") end
		c.FireEvent("ENCOUNTER_START", 1, "Boss", 16, 20)
		local lockdown = true
		c.SendResult = function() if lockdown then return 11 end return c.RETAILAPI and 0 or true end
		c.SPELLCD[20484] = { startTime = c.NOW, duration = 600, isEnabled = true, isActive = true }
		c.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20484)
		c.Advance(120)
		lockdown = false
		c.FireEvent("ENCOUNTER_END", 1, "Boss", 16, 20, 1)
		local before = #c.SENT
		c.Advance(10)
		local line, s = false, false
		for i = before + 1, #c.SENT do
			local m = c.SENT[i]
			if m.prefix == "CDCOLLAB" and not m.refused then
				if m.msg:match("^%d+:") then line = true end
				if m.msg:match("^S:2:") then s = true end
			end
		end
		return line, s
	end
	local line, s = bossEnd(false)
	check("F2: a boss end sends the 1.x line when a member hasn't been heard (it may be a 1.x copy)", line and s)
	line, s = bossEnd(true)
	check("  and only the S state when every member has said a format 2 hello", s and not line)
end

---------------------------------------------------------------- F3 and F4: an empty rez pool, and who may report one
do
	local c = Fresh(function(env)
		env.PLAYER.class = "PRIEST"
		env.GROUP = {
			{ unit = "party1", name = "Dru", realm = "Realm", class = "DRUID", guid = "Player-1-21" },
			{ unit = "party2", name = "Pri", realm = "Realm", class = "PRIEST", guid = "Player-1-22" },
			{ unit = "party3", name = "War", realm = "Realm", class = "WARRIOR", guid = "Player-1-24" },
		}
	end)
	c.Login()
	c.CC.db.laneEnabled = true
	c.FireEvent("GROUP_ROSTER_UPDATE")
	c.Advance(5)
	From(c, "H:2:1.2.0:retail", "PARTY", "Dru")
	-- F4: a priest can't read a pool; nor can anyone outside the group
	From(c, "C:2:0:5:0", "PARTY", "Pri")
	From(c, "C:2:0:2:100", "PARTY", "Stranger")
	check("F4: a C from a member who isn't a Battle Rez provider is dropped", c.CC.rezCharges == nil and c.CC:NoRezChargesText() == nil)
	-- a provider's C: clamped, the newest wins
	From(c, "C:2:9:99:99999", "PARTY", "Dru")
	local p = c.CC.rezCharges
	check("  a provider's values are clamped (charges 0..max, max 1..5, wait 0..1800 s)",
		p and p.max == 5 and p.charges == 5 and p.nextAt and p.nextAt - c.GetTime() <= 1800.01)
	From(c, "C:2:0:3:99999", "PARTY", "Dru")
	p = c.CC.rezCharges
	check("  max 3, wait capped at 30 minutes", p and p.charges == 0 and p.max == 3 and p.nextAt and p.nextAt - c.GetTime() <= 1800.01
		and p.nextAt - c.GetTime() > 1799)
	From(c, "C:2:0:2:120", "PARTY", "Dru")
	-- F3: nothing says READY while the pool is empty
	local states = {}
	for _, m in ipairs(c.CC:EssentialsModel()) do
		if m.kind == "provider" and m.cap == "BATTLEREZ" then states[#states + 1] = m.state end
		if m.kind == "text" and m.key == "you" and m.cap == "BATTLEREZ" then states[#states + 1] = "you" end
	end
	check("F3: Essentials names the rez providers NO CHARGE, not ready", #states >= 1 and states[1] == "nocharge", table.concat(states, ","))
	local readyIcons = 0
	for _, m in ipairs(c.CC:EssentialsModel()) do
		if m.kind == "icons" then for _, ic in ipairs(m.icons) do readyIcons = readyIcons + ic.count end end
	end
	check("  the rez icons count none ready", readyIcons == 0, readyIcons)
	c.CC:RefreshLanes()
	local lane = c.CC.lanes.BATTLEREZ
	local row = lane.readyRow
	local greyed = false
	for _, w in ipairs(row.icons) do if w.__shown and w.look and w.look.state == "nocharge" then greyed = true end end
	check("  the Lane view greys them and its row says No charge", greyed and row.label.__text == "No charge", row.label.__text)
	local post = table.concat(c.CC:PostLines(), " | ")
	check("  /cdc post says no charge for Rebirth", post:find("Dru no charge", 1, true) ~= nil and not post:find("Dru ready", 1, true), post)
	-- it lapses 10 minutes after it was last heard
	c.Advance(130)
	check("  at its own time to the next charge the pool counts it back", c.CC:NoRezChargesText() == nil)
	From(c, "C:2:0:5:0", "PARTY", "Dru")
	check("  an empty pool with no known next charge blocks", c.CC:NoRezChargesText() ~= nil)
	c.Advance(601)
	check("F4: and lapses after 10 minutes without a refresh", c.CC:NoRezChargesText() == nil and c.CC.rezCharges == nil)
end

---------------------------------------------------------------- the whole run
check("no Lua errors in any copy", Errors() == 0, FirstError())
OUTPUT(string.format("RESULT final %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, Errors()))
