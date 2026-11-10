-- Tracked-spell data, per client.
--
-- Each client (retail Midnight, WoW: Forever) has its own spell list,
-- capability groups (the Essentials bar / Lane view rows) and built-in
-- consumables. The bottom of this file picks the set for the running client
-- (CC.isForever, set in CooldownCollaborator.lua) and builds:
--
--   CC.SpellData[canonicalID]  = { name, duration, icon, class, ranks?, talent? }
--   CC.SpellAlias[rankID]      = canonicalID   (every rank, canonical included)
--   CC.CAPABILITIES / CC.CAPABILITY_ORDER
--   CC.BuiltinConsumables[auraSpellID] = { name, duration, icon, class = "CONSUMABLE",
--                                          consumable = true, category = "flask"|"food" }
--
-- Spell entry fields:
--   duration = base cooldown in seconds (no talent reduction applied)
--   ranks    = every spell ID of the spell, canonical (lowest rank) first.
--              Forever only; omit when the spell has a single ID.
--   item     = true when the "spell" is an item's use effect (Soulstone): it is
--              never in the spellbook, so the class decides who has it, and its
--              cooldown is the item's (read from the observed use, not the API).
--   talent   = true when the spell comes from a talent, so a class alone
--              doesn't mean the player has it (capabilities then need the
--              player's addon to report it as known).
--
-- Capability fields:
--   label    = row header shown on the Essentials bar and Lane view
--   classes  = { CLASSTAG = { canonicalID, ... } }
--   talent   = true when providers must have reported the spell as known
--              (no class-only "READY" placeholder for players without the addon)
--   rez      = true for the battle-rez group Request Rez picks a provider from

-------------------------------------------------------------------------------
-- Retail (Midnight 12.x)
-------------------------------------------------------------------------------

local RETAIL_SPELLS = {
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
    [51052]  = { name = "Anti-Magic Zone",          duration = 240, icon = 135826,  class = "DEATHKNIGHT" },
    [61999]  = { name = "Raise Ally",                duration = 600, icon = 136144,  class = "DEATHKNIGHT" },

    -- Shaman
    [32182]  = { name = "Heroism",                   duration = 300, icon = 135978,  class = "SHAMAN"      },
    [2825]   = { name = "Bloodlust",                 duration = 300, icon = 136012,  class = "SHAMAN"      },
    [98008]  = { name = "Spirit Link Totem",         duration = 180, icon = 237586,  class = "SHAMAN"      },
    [207399] = { name = "Ancestral Prot. Totem",    duration = 300, icon = 1038468, class = "SHAMAN"      },
    [108280] = { name = "Healing Tide Totem",        duration = 180, icon = 538569,  class = "SHAMAN"      },

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
    [196718] = { name = "Darkness",                  duration = 300, icon = 1305149, class = "DEMONHUNTER" },

    -- Evoker
    [363534] = { name = "Rewind",                    duration = 240, icon = 4622462, class = "EVOKER"      },
    [370665] = { name = "Rescue",                    duration = 60,  icon = 4638349, class = "EVOKER"      },
    [374227] = { name = "Zephyr",                    duration = 120, icon = 4643463, class = "EVOKER"      },
    [357170] = { name = "Time Dilation",             duration = 90,  icon = 4622460, class = "EVOKER"      },
    [390386] = { name = "Fury of the Aspects",       duration = 300, icon = 4723908, class = "EVOKER"      },
}

local RETAIL_CAPABILITIES = {
    BLOODLUST = {
        label = "Bloodlust/Heroism",
        classes = {
            SHAMAN = { 2825, 32182 },
            MAGE   = { 80353 },
            EVOKER = { 390386 },
        },
    },
    BATTLEREZ = {
        label = "Battle Rez",
        rez = true,
        classes = {
            DRUID       = { 20484 },
            DEATHKNIGHT = { 61999 },
        },
    },
}
local RETAIL_CAPABILITY_ORDER = { "BLOODLUST", "BATTLEREZ" }

-- Built-in consumable buffs — tracked automatically, no /cdc consumable needed.
local RETAIL_CONSUMABLES = {
    -- Midnight feasts
    [1232585] = { name = "Well Fed",        duration = 3600, icon = 134052, class = "CONSUMABLE", consumable = true, category = "food" },
    [462187]  = { name = "Hearty Well Fed", duration = 3600, icon = 134052, class = "CONSUMABLE", consumable = true, category = "food" },
    -- Midnight flasks
    [1230876] = { name = "Flask of the Magisters",        duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1230877] = { name = "Flask of the Blood Knights",    duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1230878] = { name = "Flask of the Shattered Sun",    duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1235057] = { name = "Flask of Thalassian Resistance",duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
}

-------------------------------------------------------------------------------
-- WoW: Forever (1.60.x)
-------------------------------------------------------------------------------
-- Vanilla-era raid cooldowns with Forever's own timings. Checked against
-- Forever's game data with tools/spell-check (run it after every patch).

local FOREVER_SPELLS = {
    -- Druid
    [20484] = { name = "Rebirth", duration = 1800, icon = 136080, class = "DRUID", ranks = { 20484, 20739, 20742, 20747, 20748 } },
    [29166] = { name = "Innervate", duration = 360, icon = 136048, class = "DRUID" },
    [740] = { name = "Tranquility", duration = 300, icon = 136107, class = "DRUID", ranks = { 740, 8918, 9862, 9863 } },
    [5209] = { name = "Challenging Roar", duration = 600, icon = 132117, class = "DRUID" },

    -- Paladin
    [633] = { name = "Lay on Hands", duration = 1200, icon = 135928, class = "PALADIN", ranks = { 633, 2800, 10310 } },
    [19752] = { name = "Divine Intervention", duration = 3600, icon = 136106, class = "PALADIN" },
    [1022] = { name = "Blessing of Protection", duration = 300, icon = 135964, class = "PALADIN", ranks = { 1022, 5599, 10278 } },
    [642] = { name = "Divine Shield", duration = 300, icon = 135896, class = "PALADIN", ranks = { 642, 1020 } },

    -- Priest
    [10060] = { name = "Power Infusion", duration = 180, icon = 135939, class = "PRIEST", talent = true },
    [6346] = { name = "Fear Ward", duration = 180, icon = 135902, class = "PRIEST" },
    [724] = { name = "Lightwell", duration = 600, icon = 135980, class = "PRIEST", ranks = { 724, 27870, 27871 }, talent = true },
    [14751] = { name = "Inner Focus", duration = 180, icon = 135863, class = "PRIEST", talent = true },

    -- Warrior
    [871] = { name = "Shield Wall", duration = 900, icon = 132362, class = "WARRIOR" },
    [20230] = { name = "Retaliation", duration = 900, icon = 132336, class = "WARRIOR" },
    [1719] = { name = "Recklessness", duration = 1800, icon = 132109, class = "WARRIOR" },
    [12975] = { name = "Last Stand", duration = 180, icon = 135871, class = "WARRIOR", talent = true },
    [1161] = { name = "Challenging Shout", duration = 600, icon = 132091, class = "WARRIOR" },

    -- Mage
    [11958] = { name = "Ice Block", duration = 300, icon = 135841, class = "MAGE", talent = true },
    [12051] = { name = "Evocation", duration = 480, icon = 136075, class = "MAGE" },

    -- Shaman
    [16190] = { name = "Mana Tide Totem", duration = 300, icon = 135861, class = "SHAMAN", ranks = { 16190, 17354, 17359, 1325256 }, talent = true },
    [20608] = { name = "Reincarnation", duration = 3600, icon = 136080, class = "SHAMAN", ranks = { 20608, 21169 } },

    -- Warlock
    -- The stone is an item: the warlock makes it, then USES it on a target. These are the
    -- item-use spell IDs (Minor, Lesser, normal, Greater, Major Soulstone); the 30 min
    -- cooldown is the items' shared category cooldown.
    [20707] = { name = "Soulstone Resurrection", duration = 1800, icon = 136210, class = "WARLOCK", item = true, ranks = { 20707, 20762, 20763, 20764, 20765 } },
}

local FOREVER_CAPABILITIES = {
    BATTLEREZ = {
        label = "Battle Rez",
        rez = true,
        classes = {
            DRUID = { 20484 },          -- Rebirth
        },
    },
    SOULSTONE = {
        label = "Soulstone",
        classes = {
            WARLOCK = { 20707 },        -- Soulstone Resurrection (item use)
        },
    },
    INNERVATE = {
        label = "Innervate",
        classes = {
            DRUID = { 29166 },
        },
    },
    POWERINFUSION = {
        label = "Power Infusion",
        talent = true,
        classes = {
            PRIEST = { 10060 },
        },
    },
    GROUPTAUNT = {
        label = "Group Taunts",
        classes = {
            WARRIOR = { 1161 },         -- Challenging Shout
            DRUID   = { 5209 },         -- Challenging Roar
        },
    },
}
local FOREVER_CAPABILITY_ORDER = { "BATTLEREZ", "SOULSTONE", "INNERVATE", "POWERINFUSION", "GROUPTAUNT" }

local FOREVER_CONSUMABLES = {
    -- Flasks (the aura IDs; the game names some of these without "Flask of")
    [17626] = { name = "Flask of the Titans", duration = 7200, icon = 134842, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17627] = { name = "Flask of Distilled Wisdom", duration = 7200, icon = 134877, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17628] = { name = "Flask of Supreme Power", duration = 7200, icon = 134821, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17629] = { name = "Flask of Chromatic Resistance", duration = 7200, icon = 134828, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1293740] = { name = "Flask of Natural Accuracy", duration = 7200, icon = 463902, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1293741] = { name = "Flask of Natural Aggression", duration = 7200, icon = 463898, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1293742] = { name = "Flask of Natural Precision", duration = 7200, icon = 463900, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1293743] = { name = "Flask of Natural Swiftness", duration = 7200, icon = 463901, class = "CONSUMABLE", consumable = true, category = "flask" },
    -- 1293743 is the Flask of Natural Swiftness; the game names its aura "Flask of Natural Accuracy".

    -- Food: every "Well Fed" aura (food items trigger one of these), then the named buffs
    [19705] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [19706] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [19708] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [19709] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [19710] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [19711] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [24799] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [24870] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [25694] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [25941] = { name = "Well Fed", duration = 900, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food" },
    [1225778] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1225779] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1225780] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1225782] = { name = "Well Fed", duration = 2700, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1248406] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1248420] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1248421] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1248422] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1248688] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249519] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249520] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249521] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249523] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249907] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249926] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1249927] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1294007] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1302064] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [1319310] = { name = "Well Fed", duration = 900, icon = 133943, class = "CONSUMABLE", consumable = true, category = "food" },
    [18125] = { name = "Blessed Sunfruit", duration = 600, icon = 135892, class = "CONSUMABLE", consumable = true, category = "food" },
    [25661] = { name = "Increased Stamina", duration = 900, icon = 132584, class = "CONSUMABLE", consumable = true, category = "food" },
}

-------------------------------------------------------------------------------
-- Pick this client's set
-------------------------------------------------------------------------------

local spells, consumables
if CC.isForever then
    spells, consumables = FOREVER_SPELLS, FOREVER_CONSUMABLES
    CC.CAPABILITIES, CC.CAPABILITY_ORDER = FOREVER_CAPABILITIES, FOREVER_CAPABILITY_ORDER
else
    spells, consumables = RETAIL_SPELLS, RETAIL_CONSUMABLES
    CC.CAPABILITIES, CC.CAPABILITY_ORDER = RETAIL_CAPABILITIES, RETAIL_CAPABILITY_ORDER
end

CC.SpellData = {}
CC.SpellAlias = CC.SpellAlias or {}
for id, data in pairs(spells) do
    CC.SpellData[id] = data
    CC.SpellAlias[id] = id
    for _, rankID in ipairs(data.ranks or {}) do
        CC.SpellAlias[rankID] = id
    end
end
CC.BuiltinConsumables = consumables

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
