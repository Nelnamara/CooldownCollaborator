-- Spell whitelist — tracked by CooldownCollaborator
-- duration = base cooldown in seconds (no talent reduction applied)
CC.SpellData = {
    -- Warrior
    [97462]  = { name = "Rallying Cry",              duration = 180, icon = 132351,  class = "WARRIOR"     },

    -- Paladin
    [31821]  = { name = "Aura Mastery",              duration = 180, icon = 135872,  class = "PALADIN"     },
    [633]    = { name = "Lay on Hands",              duration = 600, icon = 135928,  class = "PALADIN"     },
    [1022]   = { name = "Blessing of Protection",   duration = 300, icon = 135964,  class = "PALADIN"     },
    [47788]  = { name = "Guardian Spirit",           duration = 180, icon = 237542,  class = "PRIEST"      },

    -- Priest
    [33206]  = { name = "Pain Suppression",         duration = 90,  icon = 135936,  class = "PRIEST"      },
    [62618]  = { name = "Power Word: Barrier",       duration = 180, icon = 135940,  class = "PRIEST"      },
    [73325]  = { name = "Leap of Faith",             duration = 90,  icon = 463835,  class = "PRIEST"      },

    -- Death Knight
    [51052]  = { name = "Anti-Magic Zone",          duration = 120, icon = 135826,  class = "DEATHKNIGHT" },
    [61999]  = { name = "Raise Ally",                duration = 600, icon = 136144,  class = "DEATHKNIGHT" },

    -- Shaman
    [32182]  = { name = "Heroism",                   duration = 300, icon = 135978,  class = "SHAMAN"      },
    [2825]   = { name = "Bloodlust",                 duration = 300, icon = 136012,  class = "SHAMAN"      },
    [98008]  = { name = "Spirit Link Totem",         duration = 180, icon = 237586,  class = "SHAMAN"      },
    [207399] = { name = "Ancestral Prot. Totem",    duration = 300, icon = 1038468, class = "SHAMAN"      },
    [108280] = { name = "Healing Tide Totem",        duration = 120, icon = 538569,  class = "SHAMAN"      },

    -- Mage
    [80353]  = { name = "Time Warp",                 duration = 300, icon = 458223,  class = "MAGE"        },
    [45438]  = { name = "Ice Block",                 duration = 300, icon = 135841,  class = "MAGE"        },

    -- Warlock
    [111771] = { name = "Demonic Gateway",           duration = 90,  icon = 463286,  class = "WARLOCK"     },

    -- Monk
    [115310] = { name = "Revival",                   duration = 180, icon = 627485,  class = "MONK"        },
    [116849] = { name = "Life Cocoon",               duration = 120, icon = 627487,  class = "MONK"        },

    -- Druid
    [740]    = { name = "Tranquility",               duration = 180, icon = 136107,  class = "DRUID"       },
    [20484]  = { name = "Rebirth",                   duration = 600, icon = 136080,  class = "DRUID"       },
    [29166]  = { name = "Innervate",                 duration = 180, icon = 136048,  class = "DRUID"       },

    -- Demon Hunter
    [196718] = { name = "Darkness",                  duration = 180, icon = 1305149, class = "DEMONHUNTER" },

    -- Evoker
    [363534] = { name = "Rewind",                    duration = 240, icon = 4622462, class = "EVOKER"      },
    [370665] = { name = "Rescue",                    duration = 60,  icon = 4638349, class = "EVOKER"      },
    [374227] = { name = "Zephyr",                    duration = 120, icon = 4643463, class = "EVOKER"      },
    [357170] = { name = "Time Dilation",             duration = 90,  icon = 4622460, class = "EVOKER"      },
    [391215] = { name = "Fury of the Aspects",       duration = 300, icon = 3578226, class = "EVOKER"      },
}

-- Built-in consumable buffs — tracked automatically, no /cdc consumable needed.
-- Flask buff from Midnight cauldron: discover in-game via /cdc verbose, then
-- register with: /cdc consumable <id> 3600 <Flask Name>
CC.BuiltinConsumables = {
    -- Midnight feasts
    [1232585] = { name = "Well Fed",        duration = 3600, icon = 134052, class = "CONSUMABLE", consumable = true },
    [462187]  = { name = "Hearty Well Fed", duration = 3600, icon = 134052, class = "CONSUMABLE", consumable = true },
    -- Midnight flasks
    [1230876] = { name = "Flask of the Magisters",        duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true },
    [1230877] = { name = "Flask of the Blood Knights",    duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true },
    [1230878] = { name = "Flask of the Shattered Sun",    duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true },
    [1235057] = { name = "Flask of Thalassian Resistance",duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true },
}

-- Class display colors (r, g, b) matching Blizzard's RAID_CLASS_COLORS
CC.ClassColors = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    MAGE        = { 0.41, 0.80, 0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    MONK        = { 0.00, 1.00, 0.60 },
    DRUID       = { 1.00, 0.49, 0.04 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER      = { 0.20, 0.58, 0.50 },
    UNKNOWN     = { 0.50, 0.50, 0.50 },
}
