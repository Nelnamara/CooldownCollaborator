-- TBC Anniversary (2.5.6): tracked spells, checked against the game data of
-- build 2.5.6.70577 (SpellName, SpellCooldowns, SpellMisc icons). Ranks lowest
-- first. Bloodlust and Heroism are Shaman only on this client. variants = other
-- IDs the same spell casts with; like ranks they record under the base ID.
CC.SpellData = {
    -- Warrior
    [871]   = { name = "Shield Wall",            duration = 1800, icon = 132362, class = "WARRIOR" },
    [1161]  = { name = "Challenging Shout",      duration = 600,  icon = 132091, class = "WARRIOR" },
    [12975] = { name = "Last Stand",             duration = 480,  icon = 135871, class = "WARRIOR" },

    -- Paladin
    [633]   = { name = "Lay on Hands",           duration = 3600, icon = 135928, class = "PALADIN", ranks = { 633, 2800, 10310, 27154 } },
    [19752] = { name = "Divine Intervention",    duration = 3600, icon = 136106, class = "PALADIN" },
    [1022]  = { name = "Blessing of Protection", duration = 300,  icon = 135964, class = "PALADIN", ranks = { 1022, 5599, 10278 } },

    -- Priest
    [10060] = { name = "Power Infusion",         duration = 180,  icon = 135939, class = "PRIEST" },
    [33206] = { name = "Pain Suppression",       duration = 120,  icon = 135936, class = "PRIEST" },
    [34433] = { name = "Shadowfiend",            duration = 300,  icon = 136199, class = "PRIEST" },
    [724]   = { name = "Lightwell",              duration = 360,  icon = 135980, class = "PRIEST",  ranks = { 724, 27870, 27871, 28275 } },
    [6346]  = { name = "Fear Ward",              duration = 180,  icon = 135902, class = "PRIEST" },

    -- Shaman. Reincarnation: the spellbook has the passive 20608, the rez itself
    -- casts 21169 (same cooldown category), which records under 20608.
    [2825]  = { name = "Bloodlust",              duration = 600,  icon = 136012, class = "SHAMAN", level = 70 },
    [32182] = { name = "Heroism",                duration = 600,  icon = 132313, class = "SHAMAN", level = 70 },
    [16190] = { name = "Mana Tide Totem",        duration = 300,  icon = 135861, class = "SHAMAN" },
    [2062]  = { name = "Earth Elemental Totem",  duration = 1200, icon = 136024, class = "SHAMAN" },
    [20608] = { name = "Reincarnation",          duration = 3600, icon = 136080, class = "SHAMAN",  variants = { 21169 } },

    -- Hunter
    [34477] = { name = "Misdirection",           duration = 120,  icon = 132180, class = "HUNTER" },

    -- Warlock. The cooldown sits on the soulstone item (these spells have no
    -- SpellCooldowns row), so the game can't say when it is ready again: 30 min
    -- (every soulstone item's ItemEffect category cooldown), and no "ready now"
    -- announcement.
    [20707] = { name = "Soulstone Resurrection", duration = 1800, icon = 136210, class = "WARLOCK", ranks = { 20707, 20762, 20763, 20764, 20765, 27239 }, itemCooldown = true },

    -- Druid
    [29166] = { name = "Innervate",              duration = 360,  icon = 136048, class = "DRUID" },
    [20484] = { name = "Rebirth",                duration = 1200, icon = 136080, class = "DRUID",   ranks = { 20484, 20739, 20742, 20747, 20748, 26994 }, level = 20 },
    [740]   = { name = "Tranquility",            duration = 600,  icon = 136107, class = "DRUID",   ranks = { 740, 8918, 9862, 9863, 26983 } },
    [5209]  = { name = "Challenging Roar",       duration = 600,  icon = 132117, class = "DRUID" },
}

-- Who can provide each raid-wide capability (Roster.lua).
CC.Providers = {
    BLOODLUST = {
        SHAMAN = { 2825, 32182 },
    },
    BATTLEREZ = {
        DRUID = { 20484 },
    },
}

-- Built-in consumable buffs. Auras are readable here and one buff comes in many
-- IDs (dozens of "Well Fed"), so these match by aura NAME; the ID only names
-- the entry. Durations from SpellDuration (flasks 2 h, most Well Fed 30 min).
CC.ConsumableMatch = "name"
CC.BuiltinConsumables = {
    [17626] = { name = "Flask of the Titans",         duration = 7200, icon = 134842, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17627] = { name = "Distilled Wisdom",            duration = 7200, icon = 134877, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17628] = { name = "Supreme Power",               duration = 7200, icon = 134821, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17629] = { name = "Chromatic Resistance",        duration = 7200, icon = 134828, class = "CONSUMABLE", consumable = true, category = "flask" },
    [28518] = { name = "Flask of Fortification",      duration = 7200, icon = 134742, class = "CONSUMABLE", consumable = true, category = "flask" },
    [28519] = { name = "Flask of Mighty Restoration", duration = 7200, icon = 134741, class = "CONSUMABLE", consumable = true, category = "flask" },
    [28520] = { name = "Flask of Relentless Assault", duration = 7200, icon = 134740, class = "CONSUMABLE", consumable = true, category = "flask" },
    [28521] = { name = "Flask of Blinding Light",     duration = 7200, icon = 134739, class = "CONSUMABLE", consumable = true, category = "flask" },
    [28540] = { name = "Flask of Pure Death",         duration = 7200, icon = 134738, class = "CONSUMABLE", consumable = true, category = "flask" },
    [42735] = { name = "Chromatic Wonder",            duration = 7200, icon = 134828, class = "CONSUMABLE", consumable = true, category = "flask" },
    [19705] = { name = "Well Fed",                    duration = 1800, icon = 136000, class = "CONSUMABLE", consumable = true, category = "food"  },
}
