-- MoP Classic (5.5.4): tracked spells, checked against the game data of build
-- 5.5.4.70631 (SpellName, SpellCooldowns, SpellMisc icons). No ranks on this
-- client. The hunter pet lust (Primal Rage) is cast by the pet and is not
-- tracked. variants = the other IDs the same spell casts with (Stampeding Roar
-- in Bear and Cat Form): like ranks they record under, and are sent as, the
-- base ID.
-- kind = what the spell is for (rez, lust, external, raid, personal, mana, utility).
-- effect = how long an external's or raid defensive's effect lasts, in seconds:
-- SpellMisc DurationIndex -> SpellDuration of this build (Rallying Cry's from its
-- buff 97463; Lay on Hands and Revival are instant and have none).
CC.SpellData = {
    -- Warrior
    [97462]  = { name = "Rallying Cry",         duration = 180, icon = 463829, class = "WARRIOR", kind = "raid", effect = 10 },
    [114207] = { name = "Skull Banner",         duration = 180, icon = 603532, class = "WARRIOR", kind = "utility" },
    [114203] = { name = "Demoralizing Banner",  duration = 180, icon = 604449, class = "WARRIOR", kind = "raid", effect = 15 },
    [114192] = { name = "Mocking Banner",       duration = 180, icon = 604450, class = "WARRIOR", kind = "utility" },
    [871]    = { name = "Shield Wall",          duration = 180, icon = 132362, class = "WARRIOR", kind = "personal" },
    [12975]  = { name = "Last Stand",           duration = 180, icon = 135871, class = "WARRIOR", kind = "personal" },

    -- Paladin
    [633]    = { name = "Lay on Hands",         duration = 600, icon = 135928, class = "PALADIN", kind = "external" },
    [1022]   = { name = "Hand of Protection",   duration = 300, icon = 135964, class = "PALADIN", kind = "external", effect = 10 },
    [6940]   = { name = "Hand of Sacrifice",    duration = 120, icon = 135966, class = "PALADIN", kind = "external", effect = 12 },
    [1038]   = { name = "Hand of Salvation",    duration = 120, icon = 135967, class = "PALADIN", kind = "utility" },
    [31821]  = { name = "Devotion Aura",        duration = 180, icon = 135872, class = "PALADIN", kind = "raid", effect = 6 },
    [86659]  = { name = "Guardian of Ancient Kings", duration = 180, icon = 135919, class = "PALADIN", kind = "personal" },
    [31850]  = { name = "Ardent Defender",      duration = 180, icon = 135870, class = "PALADIN", kind = "personal" },

    -- Priest
    [62618]  = { name = "Power Word: Barrier",  duration = 180, icon = 253400, class = "PRIEST", kind = "raid", effect = 10 },
    [64843]  = { name = "Divine Hymn",          duration = 180, icon = 237540, class = "PRIEST", kind = "raid", effect = 8 },
    [64901]  = { name = "Hymn of Hope",         duration = 360, icon = 135982, class = "PRIEST", kind = "mana" },
    [15286]  = { name = "Vampiric Embrace",     duration = 180, icon = 136230, class = "PRIEST", kind = "raid", effect = 15 },
    [47788]  = { name = "Guardian Spirit",      duration = 180, icon = 237542, class = "PRIEST", kind = "external", effect = 10 },
    [33206]  = { name = "Pain Suppression",     duration = 180, icon = 135936, class = "PRIEST", kind = "external", effect = 8 },
    [10060]  = { name = "Power Infusion",       duration = 120, icon = 135939, class = "PRIEST", kind = "utility" },

    -- Death Knight
    [51052]  = { name = "Anti-Magic Zone",      duration = 120, icon = 237510, class = "DEATHKNIGHT", kind = "raid", effect = 3 },
    [61999]  = { name = "Raise Ally",           duration = 600, icon = 136143, class = "DEATHKNIGHT", level = 72, kind = "rez" },
    [48792]  = { name = "Icebound Fortitude",   duration = 180, icon = 237525, class = "DEATHKNIGHT", kind = "personal" },
    [55233]  = { name = "Vampiric Blood",       duration = 60,  icon = 136168, class = "DEATHKNIGHT", kind = "personal" },

    -- Shaman
    [2825]   = { name = "Bloodlust",            duration = 300, icon = 136012, class = "SHAMAN",      level = 70, kind = "lust" },
    [32182]  = { name = "Heroism",              duration = 300, icon = 132313, class = "SHAMAN",      level = 70, kind = "lust" },
    [98008]  = { name = "Spirit Link Totem",    duration = 180, icon = 237586, class = "SHAMAN", kind = "raid", effect = 6 },
    [108280] = { name = "Healing Tide Totem",   duration = 180, icon = 538569, class = "SHAMAN", kind = "raid", effect = 11 },
    [120668] = { name = "Stormlash Totem",      duration = 300, icon = 538575, class = "SHAMAN", kind = "utility" },

    -- Mage
    [80353]  = { name = "Time Warp",            duration = 300, icon = 458224, class = "MAGE",        level = 84, kind = "lust" },

    -- Warlock. Soulstone can also be cast on a dead player: a Battle Rez provider
    -- (owner, 19 Nov 2026). Category 831 "Soulstone", 10 min; level = BaseLevel 18.
    [20707]  = { name = "Soulstone",            duration = 600, icon = 136210, class = "WARLOCK",     level = 18, kind = "rez" },

    -- Monk
    [115310] = { name = "Revival",              duration = 180, icon = 237573, class = "MONK", kind = "raid" },
    [116849] = { name = "Life Cocoon",          duration = 120, icon = 627485, class = "MONK", kind = "external", effect = 12 },
    [115213] = { name = "Avert Harm",           duration = 180, icon = 627605, class = "MONK", kind = "raid", effect = 6 },
    [115203] = { name = "Fortifying Brew",      duration = 180, icon = 615341, class = "MONK", kind = "personal" },

    -- Druid
    [740]    = { name = "Tranquility",          duration = 480, icon = 136107, class = "DRUID", kind = "raid", effect = 8 },
    [102342] = { name = "Ironbark",             duration = 60,  icon = 572025, class = "DRUID", kind = "external", effect = 12 },
    [29166]  = { name = "Innervate",            duration = 180, icon = 136048, class = "DRUID", kind = "mana" },
    [20484]  = { name = "Rebirth",              duration = 600, icon = 136080, class = "DRUID",       level = 56, kind = "rez" },
    [106898] = { name = "Stampeding Roar",      duration = 120, icon = 464343, class = "DRUID",       variants = { 77761, 77764 }, kind = "utility" },
    [61336]  = { name = "Survival Instincts",   duration = 180, icon = 236169, class = "DRUID", kind = "personal" },
}

-- Who can provide each raid-wide capability (Roster.lua).
CC.Providers = {
    BLOODLUST = {
        SHAMAN = { 2825, 32182 },
        MAGE   = { 80353 },
    },
    BATTLEREZ = {
        DRUID       = { 20484 },
        DEATHKNIGHT = { 61999 },
        WARLOCK     = { 20707 },
    },
}

-- Built-in consumable buffs. Auras are readable here and one buff comes in many
-- IDs (170 "Well Fed"), so these match by aura NAME; the ID only names the
-- entry. Durations from SpellDuration (flasks 1 h, most Well Fed 1 h).
CC.ConsumableMatch = "name"
CC.BuiltinConsumables = {
    [105689] = { name = "Flask of Spring Blossoms", duration = 3600, icon = 609900, class = "CONSUMABLE", consumable = true, category = "flask" },
    [105693] = { name = "Flask of Falling Leaves",  duration = 3600, icon = 609899, class = "CONSUMABLE", consumable = true, category = "flask" },
    [105694] = { name = "Flask of the Earth",       duration = 3600, icon = 609903, class = "CONSUMABLE", consumable = true, category = "flask" },
    [105696] = { name = "Flask of Winter's Bite",   duration = 3600, icon = 609901, class = "CONSUMABLE", consumable = true, category = "flask" },
    [105691] = { name = "Flask of the Warm Sun",    duration = 3600, icon = 609902, class = "CONSUMABLE", consumable = true, category = "flask" },
    [19705]  = { name = "Well Fed",                 duration = 3600, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food"  },
}
