-- Classic Era (1.15.9): tracked spells, checked against the game data of build
-- 1.15.9.70576 (SpellName, SpellCooldowns, SpellMisc icons). Ranks lowest first;
-- variants = other IDs the same spell casts with, recorded under the base ID too.
-- No Bloodlust, Heroism or Time Warp on this client.
-- kind = what the spell is for (rez, lust, external, raid, personal, mana, utility).
-- effect = how long an external's or raid defensive's effect lasts, in seconds:
-- SpellMisc DurationIndex -> SpellDuration of this build, a ranked spell's from
-- its top rank (Blessing of Protection: 6, 8 and 10 s; Lay on Hands is instant).
CC.SpellData = {
    -- Warrior
    [871]   = { name = "Shield Wall",            duration = 1800, icon = 132362, class = "WARRIOR", kind = "personal" },
    [1161]  = { name = "Challenging Shout",      duration = 600,  icon = 132091, class = "WARRIOR", kind = "utility" },
    [12975] = { name = "Last Stand",             duration = 600,  icon = 135871, class = "WARRIOR", kind = "personal" },

    -- Paladin
    [633]   = { name = "Lay on Hands",           duration = 3600, icon = 135928, class = "PALADIN", ranks = { 633, 2800, 10310 }, kind = "external" },
    [19752] = { name = "Divine Intervention",    duration = 3600, icon = 136106, class = "PALADIN", kind = "rez" },
    [1022]  = { name = "Blessing of Protection", duration = 300,  icon = 135964, class = "PALADIN", ranks = { 1022, 5599, 10278 }, kind = "external", effect = 10 },

    -- Priest
    [10060] = { name = "Power Infusion",         duration = 180,  icon = 135939, class = "PRIEST", kind = "utility" },
    [724]   = { name = "Lightwell",              duration = 600,  icon = 135980, class = "PRIEST",  ranks = { 724, 27870, 27871 }, kind = "raid", effect = 180 },

    -- Shaman. Reincarnation: the spellbook has the passive 20608, the rez itself
    -- casts 21169 (same cooldown category), which records under 20608.
    [16190] = { name = "Mana Tide Totem",        duration = 300,  icon = 135861, class = "SHAMAN",  ranks = { 16190, 17354, 17359 }, kind = "mana" },
    [20608] = { name = "Reincarnation",          duration = 3600, icon = 136080, class = "SHAMAN",  variants = { 21169 }, kind = "rez" },

    -- Warlock. The cooldown sits on the soulstone item (these spells have no
    -- SpellCooldowns row), so the game can't say when it is ready again: 30 min
    -- (every soulstone item's ItemEffect category cooldown), and no "ready now"
    -- announcement.
    [20707] = { name = "Soulstone Resurrection", duration = 1800, icon = 136210, class = "WARLOCK", ranks = { 20707, 20762, 20763, 20764, 20765 }, itemCooldown = true, kind = "rez" },

    -- Druid
    [29166] = { name = "Innervate",              duration = 360,  icon = 136048, class = "DRUID", kind = "mana" },
    [20484] = { name = "Rebirth",                duration = 1800, icon = 136080, class = "DRUID",   ranks = { 20484, 20739, 20742, 20747, 20748 }, level = 20, kind = "rez" },
    [740]   = { name = "Tranquility",            duration = 300,  icon = 136107, class = "DRUID",   ranks = { 740, 8918, 9862, 9863 }, kind = "raid", effect = 10 },
    [5209]  = { name = "Challenging Roar",       duration = 600,  icon = 132117, class = "DRUID", kind = "utility" },

    -- Items (no class): Goblin Sapper Charge, item 10646. No SpellCooldowns row; the item's effect
    -- has a 300 s cooldown (ItemEffect 98888), so like a soulstone there is no ready-now watch.
    -- Settings lists it under "Items" so it can be unticked.
    [13241] = { name = "Goblin Sapper Charge",   duration = 300,  icon = 135826, class = "ITEMS", itemCooldown = true, kind = "utility" },
}

-- Who can provide each raid-wide capability (Roster.lua). No lust here.
CC.Providers = {
    BATTLEREZ = {
        DRUID = { 20484 },
    },
}

-- Built-in consumable buffs. Auras are readable here and one buff comes in many
-- IDs (dozens of "Well Fed"), so these match by aura NAME; the ID only names
-- the entry. Durations from SpellDuration (flasks 2 h, most Well Fed 15 min).
CC.ConsumableMatch = "name"
CC.BuiltinConsumables = {
    [17626] = { name = "Flask of the Titans",  duration = 7200, icon = 134842, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17627] = { name = "Distilled Wisdom",     duration = 7200, icon = 134877, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17628] = { name = "Supreme Power",        duration = 7200, icon = 134821, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17629] = { name = "Chromatic Resistance", duration = 7200, icon = 134828, class = "CONSUMABLE", consumable = true, category = "flask" },
    [19705] = { name = "Well Fed",             duration = 900,  icon = 136000, class = "CONSUMABLE", consumable = true, category = "food"  },
}
