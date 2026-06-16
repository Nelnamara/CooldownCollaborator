-- Cauldron/Feast tracking — structurally different from a personal cooldown:
-- it's a shared buff applied to everyone nearby from one cast, not something
-- only the caster has. That means no cross-client sync is needed at all -
-- everyone who has the buff can detect it on themselves directly, and
-- everyone who has the addon already has the buff if they're standing in it.
--
-- Detection constraint: aura .name and .spellId are SECRET even on your own
-- "player" buffs (confirmed by the Eclipse/DoT crashes earlier tonight) - we
-- cannot enumerate your buffs and discover what an unknown one is. The only
-- safe lookup is C_UnitAuras.GetPlayerAuraBySpellID(knownID), so consumables
-- have to be registered by ID up front (same flow as a custom spell), not
-- auto-discovered.

CC.consumableActive = CC.consumableActive or {}

function CC:LoadConsumableBuffs()
    for idStr, data in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID and data.duration and data.duration > 0 then
            CC.SpellData[spellID] = {
                name       = data.name or ("Consumable " .. spellID),
                duration   = data.duration,
                icon       = data.icon or 134400,
                class      = "UNKNOWN",
                consumable = true,
            }
        end
    end
end

function CC:AddConsumableBuff(spellID, duration, name)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end
    name = name or ("Consumable " .. spellID)

    self.db.consumableBuffs[tostring(spellID)] = {
        name     = name,
        duration = duration,
        icon     = 134400,
    }
    CC.SpellData[spellID] = {
        name       = name,
        duration   = duration,
        icon       = 134400,
        class      = "UNKNOWN",
        consumable = true,
    }
    print(string.format("|cFF54a3ffCooldownCollaborator|r tracking consumable buff: %s (%ds)", name, duration))
    return true
end

function CC:RemoveConsumableBuff(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    self.db.consumableBuffs[tostring(spellID)] = nil
    if CC.SpellData[spellID] and CC.SpellData[spellID].consumable then
        CC.SpellData[spellID] = nil
    end
    self.consumableActive[spellID] = nil
    self:RefreshAllViews()
end

-- Only react to the buff *appearing* (not present last poll, present now) so
-- an already-active buff doesn't get treated as freshly cast on every poll,
-- which would continuously reset its displayed remaining time to full.
function CC:PollConsumables()
    for idStr in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID then
            local present   = C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
            local wasActive = self.consumableActive[spellID]

            if present and not wasActive then
                CC:RecordCooldown("player", spellID)
            end
            self.consumableActive[spellID] = present
        end
    end
end

C_Timer.NewTicker(2, function() CC:PollConsumables() end)
