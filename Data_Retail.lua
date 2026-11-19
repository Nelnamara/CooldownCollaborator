-- Retail (12.1.5): tracked spells, checked against the game data of build
-- 12.1.5.70783 (SpellName, SpellCooldowns, SpellCategory, SpellMisc icons). No
-- ranks on this client.
-- duration = base cooldown in seconds (no talent reduction applied). A spell
-- that holds one charge (Pain Suppression, Ice Block, Shield Wall and others:
-- docs/port-research.md B7, B8) is as long as the charge's recharge
-- (SpellCategory ChargeRecoveryTime); its own RecoveryTime is only the gap
-- between uses.
-- spec = the one specialization (ChrSpecialization ID) that has the spell
-- (Roster.lua: a groupmate counts only once we know they are that spec).
-- kind = what the spell is for (rez, lust, external, raid, personal, mana, utility).
-- effect = how long an external's or raid defensive's effect lasts, in seconds:
-- SpellMisc DurationIndex -> SpellDuration of this build (Rallying Cry's from its
-- buff 97463; Lay on Hands and Revival are instant and have none).
CC.SpellData = {
    -- Warrior
    [97462]  = { name = "Rallying Cry",              duration = 180, icon = 132351,  class = "WARRIOR", kind = "raid", effect = 10 },
    [871]    = { name = "Shield Wall",               duration = 180, icon = 132362,  class = "WARRIOR", kind = "personal" },
    [12975]  = { name = "Last Stand",                duration = 180, icon = 135871,  class = "WARRIOR", kind = "personal" },
    [1161]   = { name = "Challenging Shout",         duration = 120, icon = 132091,  class = "WARRIOR", kind = "utility" },

    -- Paladin
    [31821]  = { name = "Aura Mastery",              duration = 180, icon = 135872,  class = "PALADIN", kind = "raid", effect = 8 },
    [633]    = { name = "Lay on Hands",              duration = 600, icon = 135928,  class = "PALADIN", kind = "external" },
    [1022]   = { name = "Blessing of Protection",   duration = 300, icon = 135964,  class = "PALADIN", kind = "external", effect = 10 },
    [6940]   = { name = "Blessing of Sacrifice",     duration = 120, icon = 135966,  class = "PALADIN", kind = "external", effect = 12 },
    [391054] = { name = "Intercession",              duration = 600, icon = 4726195, class = "PALADIN",     level = 19, kind = "rez" },
    [86659]  = { name = "Guardian of Ancient Kings", duration = 180, icon = 135919,  class = "PALADIN", kind = "personal" },
    [31850]  = { name = "Ardent Defender",           duration = 90,  icon = 135870,  class = "PALADIN", kind = "personal" },
    [47788]  = { name = "Guardian Spirit",           duration = 180, icon = 237542,  class = "PRIEST", kind = "external", effect = 10 },

    -- Priest
    [33206]  = { name = "Pain Suppression",         duration = 180, icon = 135936,  class = "PRIEST", kind = "external", effect = 8 },
    [62618]  = { name = "Power Word: Barrier",       duration = 180, icon = 253400,  class = "PRIEST", kind = "raid", effect = 10 },
    [73325]  = { name = "Leap of Faith",             duration = 90,  icon = 463835,  class = "PRIEST", kind = "utility" },
    [10060]  = { name = "Power Infusion",            duration = 120, icon = 135939,  class = "PRIEST", kind = "utility" },

    -- Death Knight
    [51052]  = { name = "Anti-Magic Zone",          duration = 240, icon = 237510,  class = "DEATHKNIGHT", kind = "raid", effect = 6 },
    [61999]  = { name = "Raise Ally",                duration = 600, icon = 136143,  class = "DEATHKNIGHT", level = 19, kind = "rez" },
    [48792]  = { name = "Icebound Fortitude",        duration = 120, icon = 237525,  class = "DEATHKNIGHT", kind = "personal" },
    [55233]  = { name = "Vampiric Blood",            duration = 90,  icon = 136168,  class = "DEATHKNIGHT", kind = "personal" },

    -- Hunter (Marksmanship's lust)
    [466904] = { name = "Harrier's Cry",             duration = 360, icon = 6352455, class = "HUNTER",      level = 48, spec = 254, kind = "lust" },

    -- Shaman
    [32182]  = { name = "Heroism",                   duration = 300, icon = 132313,  class = "SHAMAN",      level = 48, kind = "lust" },
    [2825]   = { name = "Bloodlust",                 duration = 300, icon = 136012,  class = "SHAMAN",      level = 48, kind = "lust" },
    [98008]  = { name = "Spirit Link Totem",         duration = 180, icon = 237586,  class = "SHAMAN", kind = "raid", effect = 6 },
    [207399] = { name = "Ancestral Prot. Totem",    duration = 300, icon = 136080,  class = "SHAMAN", kind = "raid", effect = 30 },
    [108280] = { name = "Healing Tide Totem",        duration = 180, icon = 538569,  class = "SHAMAN", kind = "raid", effect = 10 },

    -- Mage
    [80353]  = { name = "Time Warp",                 duration = 300, icon = 458224,  class = "MAGE",        level = 49, kind = "lust" },
    [45438]  = { name = "Ice Block",                 duration = 240, icon = 135841,  class = "MAGE", kind = "personal" },

    -- Warlock. Soulstone is a Battle Rez provider here (Providers below). In 12.1.5
    -- it has its own cooldown category (831 "Soulstone", 10 min), not Rebirth's and
    -- Intercession's 26 "Resurrection (Full)"; level = its SpellLevels BaseLevel.
    [20707]  = { name = "Soulstone",                 duration = 600, icon = 136210,  class = "WARLOCK",     level = 14, kind = "rez" },

    -- Monk
    [115310] = { name = "Revival",                   duration = 180, icon = 1020466, class = "MONK", kind = "raid" },
    [116849] = { name = "Life Cocoon",               duration = 120, icon = 627485,  class = "MONK", kind = "external", effect = 12 },
    [115203] = { name = "Fortifying Brew",           duration = 360, icon = 615341,  class = "MONK", kind = "personal" },

    -- Druid
    [740]    = { name = "Tranquility",               duration = 180, icon = 136107,  class = "DRUID", kind = "raid", effect = 6 },
    [20484]  = { name = "Rebirth",                   duration = 600, icon = 136080,  class = "DRUID",       level = 19, kind = "rez" },
    [29166]  = { name = "Innervate",                 duration = 180, icon = 136048,  class = "DRUID", kind = "mana" },
    [61336]  = { name = "Survival Instincts",        duration = 180, icon = 236169,  class = "DRUID", kind = "personal" },

    -- Demon Hunter
    [196718] = { name = "Darkness",                  duration = 300, icon = 1305154, class = "DEMONHUNTER", kind = "raid", effect = 8 },
    [187827] = { name = "Metamorphosis",             duration = 120, icon = 1247263, class = "DEMONHUNTER", kind = "personal" },

    -- Evoker
    [363534] = { name = "Rewind",                    duration = 240, icon = 4622474, class = "EVOKER", kind = "raid", effect = 4 },
    [370665] = { name = "Rescue",                    duration = 60,  icon = 4622460, class = "EVOKER", kind = "utility" },
    [374227] = { name = "Zephyr",                    duration = 120, icon = 4630449, class = "EVOKER", kind = "raid", effect = 8 },
    [357170] = { name = "Time Dilation",             duration = 60,  icon = 4622478, class = "EVOKER", kind = "external", effect = 8 },
    [390386] = { name = "Fury of the Aspects",       duration = 300, icon = 4723908, class = "EVOKER",      level = 48, kind = "lust" },
}

-- Who can provide each raid-wide capability (Roster.lua). A hunter's pet lust
-- (Primal Rage) is cast by the pet and is not tracked.
CC.Providers = {
    BLOODLUST = {
        SHAMAN = { 2825, 32182 },
        MAGE   = { 80353 },
        EVOKER = { 390386 },
        HUNTER = { 466904 },
    },
    BATTLEREZ = {
        DRUID       = { 20484 },
        DEATHKNIGHT = { 61999 },
        PALADIN     = { 391054 },
        -- Retail's Soulstone can be cast on a dead player in combat and uses a Battle Rez charge
        -- (owner, 19 Nov 2026: "a soul stone and raise ally still count as a combat rez"); MoP's
        -- too. On Era, TBC and Forever it's a stone placed beforehand, so it stays tracked only there
        WARLOCK     = { 20707 },
    },
}

-- Built-in consumable buffs — tracked automatically, no /cdc consumable needed.
-- Auras are secret here, so each one is looked up by its spell ID.
-- Flask buff from Midnight cauldron: discover in-game via /cdc verbose, then
-- register with: /cdc consumable <id> 3600 <Flask Name>
CC.ConsumableMatch = "id"
CC.BuiltinConsumables = {
    -- Midnight feasts
    [1232585] = { name = "Well Fed",        duration = 3600, icon = 134052, class = "CONSUMABLE", consumable = true, category = "food"  },
    [462187]  = { name = "Hearty Well Fed", duration = 3600, icon = 134052, class = "CONSUMABLE", consumable = true, category = "food"  },
    -- Midnight flasks
    [1230876] = { name = "Flask of the Magisters",        duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1230877] = { name = "Flask of the Blood Knights",    duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1230878] = { name = "Flask of the Shattered Sun",    duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
    [1235057] = { name = "Flask of Thalassian Resistance",duration = 3600, icon = 134823, class = "CONSUMABLE", consumable = true, category = "flask" },
}
