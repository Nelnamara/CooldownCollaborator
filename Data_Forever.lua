-- WoW: Forever (1.60.1): tracked spells, checked against the game data of build
-- 1.60.1.70888 (SpellName, SpellCooldowns, SpellMisc icons). Classic Era's list
-- with Forever's own changes: Lay on Hands 20 min, Shield Wall 15 min, and a
-- fourth Mana Tide Totem ID. Ranks lowest first. No Bloodlust, Heroism or Time
-- Warp on this client.
-- Forever's new priest spells (Dark Sacrifice, Divine Grace, Contingency Plan,
-- Chastise) wait until someone reads their tooltips.
CC.SpellData = {
    -- Warrior
    [871]   = { name = "Shield Wall",            duration = 900,  icon = 132362, class = "WARRIOR" },
    [1161]  = { name = "Challenging Shout",      duration = 600,  icon = 132091, class = "WARRIOR" },

    -- Paladin
    [633]   = { name = "Lay on Hands",           duration = 1200, icon = 135928, class = "PALADIN", ranks = { 633, 2800, 10310 } },
    [19752] = { name = "Divine Intervention",    duration = 3600, icon = 136106, class = "PALADIN" },
    [1022]  = { name = "Blessing of Protection", duration = 300,  icon = 135964, class = "PALADIN", ranks = { 1022, 5599, 10278 } },

    -- Priest
    [10060] = { name = "Power Infusion",         duration = 180,  icon = 135939, class = "PRIEST" },
    [724]   = { name = "Lightwell",              duration = 600,  icon = 135980, class = "PRIEST",  ranks = { 724, 27870, 27871 } },

    -- Shaman
    [16190] = { name = "Mana Tide Totem",        duration = 300,  icon = 135861, class = "SHAMAN",  ranks = { 16190, 17354, 17359, 1325256 } },

    -- Warlock. The cooldown sits on the soulstone item (these spells have no
    -- SpellCooldowns row), so the game can't say when it is ready again: 30 min
    -- as CooldownTimeline3 has it, and no "ready now" announcement.
    [20707] = { name = "Soulstone Resurrection", duration = 1800, icon = 136210, class = "WARLOCK", ranks = { 20707, 20762, 20763, 20764, 20765 }, itemCooldown = true },

    -- Druid
    [29166] = { name = "Innervate",              duration = 360,  icon = 136048, class = "DRUID" },
    [20484] = { name = "Rebirth",                duration = 1800, icon = 136080, class = "DRUID",   ranks = { 20484, 20739, 20742, 20747, 20748 }, level = 20 },
    [740]   = { name = "Tranquility",            duration = 300,  icon = 136107, class = "DRUID",   ranks = { 740, 8918, 9862, 9863 } },
}

-- Who can provide each raid-wide capability (Roster.lua). No lust here.
CC.Providers = {
    BATTLEREZ = {
        DRUID = { 20484 },
    },
}

-- Built-in consumable buffs. Auras are secret here (modern engine), so each one
-- is looked up by spell ID: the four Classic flasks (2 h) and every "Well Fed"
-- ID in the Forever game data (durations from SpellDuration).
CC.ConsumableMatch = "id"
CC.BuiltinConsumables = {
    [17626] = { name = "Flask of the Titans",  duration = 7200, icon = 134842, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17627] = { name = "Distilled Wisdom",     duration = 7200, icon = 134877, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17628] = { name = "Supreme Power",        duration = 7200, icon = 134821, class = "CONSUMABLE", consumable = true, category = "flask" },
    [17629] = { name = "Chromatic Resistance", duration = 7200, icon = 134828, class = "CONSUMABLE", consumable = true, category = "flask" },
}
do
    local WELL_FED = {
        [19705] = 900, [19706] = 900, [19708] = 900, [19709] = 900, [19710] = 900,
        [19711] = 900, [24799] = 900, [24870] = 900, [25694] = 900, [25941] = 900,
        [1225778] = 900, [1225779] = 900, [1225780] = 900, [1225782] = 2700, [1248406] = 900,
        [1248420] = 900, [1248421] = 900, [1248422] = 900, [1248688] = 900, [1249519] = 900,
        [1249520] = 900, [1249521] = 900, [1249523] = 900, [1249907] = 900, [1249926] = 900,
        [1249927] = 900, [1283082] = 120, [1294007] = 900, [1302064] = 900, [1319310] = 900,
    }
    for id, duration in pairs(WELL_FED) do
        CC.BuiltinConsumables[id] = { name = "Well Fed", duration = duration, icon = id < 1000000 and 136000 or 133943,
            class = "CONSUMABLE", consumable = true, category = "food" }
    end
end
