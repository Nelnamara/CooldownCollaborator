-- Translations. The English text is the key, so a phrase with no translation shows in English.
-- CC.L is the lookup table (L["Some phrase"]). Each Locales/xxXX.lua gets a table to fill from
-- CC.NewLocale; only the client's own language (and enUS, the base) is taken, the rest return nil.
-- The language files are filled from the CurseForge translation tool when a release is packaged.
local CC = CooldownCollaborator
local locale = GetLocale()

local L = setmetatable({}, { __index = function(_, key) return key end })
CC.L = L
CC.localeKeys = {}   -- every phrase enUS.lua lists (tools/tests/locale.lua checks the code against it)

function CC.NewLocale(name)
    if name ~= "enUS" and name ~= locale then return nil end
    return setmetatable({}, { __newindex = function(_, key, value)
        if name == "enUS" then CC.localeKeys[key] = true end
        if value == true then value = key end   -- same-key-is-true: the English text is the phrase
        rawset(L, key, value)
    end })
end
