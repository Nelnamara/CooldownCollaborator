-- WoW: Forever surnames (seen in game 19 and 20 Nov 2026): a chat or addon-message sender "Name Surname"
-- belongs to the group member named either "Name" or "Name Surname", and CDC's Ask whispers the full name.
-- node tools/tests/run.js <addon folder> <interface> tools/tests/surnames.lua <toc file>
dofile(HARNESS_DIR .. "/wow.lua")
local checks, fails = 0, 0
local function check(label, ok, detail)
	checks = checks + 1
	if not ok then fails = fails + 1 end
	OUT(string.format("  %-4s %s %s", ok and "ok" or "FAIL", label, detail ~= nil and tostring(detail) or ""))
end
OUT(string.format("[surnames %s %s]", HARNESS_TOCFILE, FLAVOR))
LoadTOC(HARNESS_TOCFILE)
Login()
local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
local function full(n) return realm and (n .. "-" .. realm) or n end
local members
CC.GetActiveGroupNames = function() return members end
IsInGroup = function() return true end
if CC.isForever then
	members = { [full("Devilin")] = true }
	check("sender with surname, roster without: same player", CC:NormalizeSender("Devilin Nyx") == full("Devilin"), CC:NormalizeSender("Devilin Nyx"))
	check("its whisper name is the full \"Devilin Nyx\"", CC:WhisperName(full("Devilin")) == "Devilin Nyx", CC:WhisperName(full("Devilin")))
	members = { [full("Marykatherin Gallagher")] = true }
	check("sender with surname, roster with it too: same player", CC:NormalizeSender("Marykatherin Gallagher") == full("Marykatherin Gallagher"), CC:NormalizeSender("Marykatherin Gallagher"))
	check("a roster name with its surname whispers as is", CC:WhisperName(full("Marykatherin Gallagher")) ~= nil)
	check("never seen in chat: the name as given", CC:WhisperName(full("Brannoc")) == full("Brannoc"))
else
	members = {}
	check("not Forever: whisper name unchanged", CC:WhisperName("Brannoc") == "Brannoc")
	CC:NormalizeSender("Devilin Nyx")
	check("not Forever: no surname memory", next(CC.chatNames) == nil)
end
check("no Lua errors", #ERRORS == 0, ERRORS[1])
OUT(string.format("RESULT surnames %s %s: checks %d, fails %d, lua errors %d", HARNESS_TOCFILE, FLAVOR, checks, fails, #ERRORS))
