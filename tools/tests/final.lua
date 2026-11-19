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

---------------------------------------------------------------- the whole run
check("no Lua errors in any copy", Errors() == 0, FirstError())
OUTPUT(string.format("RESULT final %s %s: checks %d, fails %d, lua errors %d",
	HARNESS_TOCFILE, FLAVOR, checks, fails, Errors()))
