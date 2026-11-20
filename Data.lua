-- Shared data. The tracked spells are per client: each TOC also loads exactly
-- one Data_<client>.lua (Data_Retail, Data_Mists, Data_TBC, Data_Era,
-- Data_Forever), which sets:
--
--   CC.SpellData[baseID] = { name, duration, icon, class, ranks = { ... } }
--       duration = base cooldown in seconds (no talent reduction applied)
--       ranks    = Era, TBC and Forever: every rank's spell ID, lowest first.
--                  Each rank casts with its own ID; all of them record under
--                  the base ID, and only base IDs go on the wire, so players
--                  with different ranks agree.
--       variants = other IDs the same spell casts with (MoP Stampeding Roar
--                  in Bear or Cat Form, Classic Reincarnation's rez). They
--                  record under, and are sent as, the base ID like ranks, but
--                  are never in the spellbook, so KnownRank doesn't read them.
--       level    = provider spells: the level the spell is learned at.
--       spec     = a provider only one specialization has (its ChrSpecialization
--                  ID): a groupmate counts once we know their spec (Roster.lua).
--       itemCooldown = the cooldown sits on an item (no ready-now watch).
--       kind     = what it is for: rez, lust, external, raid, personal, mana or
--                  utility (the tooltip's line, the views' groupings).
--       effect   = externals and raid defensives: the effect's length in
--                  seconds (SpellDuration), for the panel's effect bar.
--   CC.Providers[capability][CLASS] = { baseID, ... }  (Roster.lua)
--   CC.BuiltinConsumables[spellID] = { ..., consumable = true, category }
--   CC.ConsumableMatch = "id" (Retail, Forever) or "name" (Era, TBC, MoP)
CC.SpellData          = {}
CC.Providers          = {}
CC.BuiltinConsumables = {}
CC.ConsumableMatch    = "id"

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
    ITEMS       = { 1.00, 0.82, 0.00 },   -- no class: items such as the Goblin Sapper Charge
}

-- Built at Init from the client's list (before custom spells and consumables
-- are merged in):
--   CC.RankToBase[spellID] = baseID   every rank and variant of every tracked spell
--   CC.SpellByName[name]   = baseID   the English name and the client's own
--                                      (combat-log casts match by name too)
CC.RankToBase  = {}
CC.SpellByName = {}

function CC:BuildSpellIndex()
    self.RankToBase, self.SpellByName = {}, {}
    for baseID, data in pairs(self.SpellData) do
        if not data.consumable then
            self.RankToBase[baseID] = baseID
            for _, ids in ipairs({ data.ranks or {}, data.variants or {} }) do
                for _, id in ipairs(ids) do
                    self.RankToBase[id] = baseID
                end
            end
            self.SpellByName[data.name] = baseID
            local ok, localName = pcall(self.Compat.GetSpellInfo, baseID)
            if ok and type(localName) == "string" and localName ~= "" then
                self.SpellByName[localName] = baseID
            end
        end
    end
end

-- The base ID a cast records under (a rank's or variant's ID, or the ID itself).
function CC:BaseSpellID(spellID)
    return self.RankToBase[spellID] or spellID
end
