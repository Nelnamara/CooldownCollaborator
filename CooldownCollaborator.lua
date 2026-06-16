-- CooldownCollaborator
-- Group and raid cooldown coordinator for WoW Midnight (12.x)
-- Author: Nelnamara

CooldownCollaborator = {}
CC = CooldownCollaborator

CC.version = "1.0.0"
CC.PREFIX   = "CDCOLLAB"

-- state[playerName] = { class = "WARRIOR", spells = { [spellID] = usedAtTimestamp } }
CC.state = {}

CC.inEncounter = false

local DEFAULTS = {
    x              = 0,
    y              = 200,
    scale          = 1.0,
    locked         = false,
    minDuration    = 60,
    showReady      = true,
    alpha          = 0.9,
    minimapAngle   = 225,
    minimapHide    = false,
    customSpells     = {},    -- [spellID] = { name, duration, icon }
    disabledSpells   = {},    -- [spellID] = true when user unchecks a default spell
    consumableBuffs  = {},    -- [spellID] = { name, duration, icon } -- Cauldron/Feast etc

    essentialsEnabled = true,
    essentialsX       = 220,
    essentialsY        = 200,
    essentialsScale   = 1.0,
    essentialsLocked  = false,

    laneEnabled = false,
    laneX       = 0,
    laneY       = -200,
    laneScale   = 1.0,
    laneLocked  = false,
}

function CC:Init()
    if not CooldownCollaboratorDB then
        CooldownCollaboratorDB = CopyTable(DEFAULTS)
    end
    self.db = CooldownCollaboratorDB
    for k, v in pairs(DEFAULTS) do
        if self.db[k] == nil then self.db[k] = v end
    end

    -- Merge user's custom spells into the live SpellData table
    self:LoadCustomSpells()
    self:LoadConsumableBuffs()

    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    self:RegisterGroupEvents()
    self:BuildOptionsPanel()
    self:BuildMinimapButton()
    self:BuildUI()
    self:BuildEssentialsBar()
    self:BuildLaneView()
    self:ScanRoster()
end

function CC:LoadCustomSpells()
    for idStr, data in pairs(self.db.customSpells) do
        local spellID = tonumber(idStr)
        if spellID and data.duration and data.duration > 0 then
            CC.SpellData[spellID] = {
                name     = data.name or ("Spell " .. spellID),
                duration = data.duration,
                icon     = data.icon or 134400,
                class    = "UNKNOWN",
                custom   = true,
            }
        end
    end
end

function CC:AddCustomSpell(spellID, duration)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end

    local name, icon
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info then
        name = info.name
        icon = info.iconID
    else
        name = GetSpellInfo and select(1, GetSpellInfo(spellID)) or ("Spell " .. spellID)
        icon = GetSpellInfo and select(3, GetSpellInfo(spellID)) or 134400
    end

    if not name then
        print("|cFF54a3ffCooldownCollaborator|r Unknown spell ID: " .. spellID)
        return false
    end

    self.db.customSpells[tostring(spellID)] = {
        name     = name,
        duration = duration,
        icon     = icon or 134400,
    }
    CC.SpellData[spellID] = {
        name     = name,
        duration = duration,
        icon     = icon or 134400,
        class    = "UNKNOWN",
        custom   = true,
    }
    print(string.format("|cFF54a3ffCooldownCollaborator|r Added: %s (%ds)", name, duration))
    return true
end

function CC:RemoveCustomSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    self.db.customSpells[tostring(spellID)] = nil
    if CC.SpellData[spellID] and CC.SpellData[spellID].custom then
        CC.SpellData[spellID] = nil
    end
    self:RefreshRows()
    self:RefreshSpellList()
end

function CC:RecordCooldown(unitToken, spellID)
    local data = CC.SpellData[spellID]
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r cast seen: unit=%s spellID=%s known=%s",
            tostring(unitToken), tostring(spellID), tostring(data ~= nil)))
    end
    if not data then return end
    if data.duration < (self.db.minDuration or 60) then return end
    if self.db.disabledSpells and self.db.disabledSpells[spellID] then return end

    local name = UnitName(unitToken)
    if not name or name == "" then return end

    if not self.state[name] then
        local _, classTag = UnitClass(unitToken)
        self.state[name] = { class = classTag or "UNKNOWN", spells = {} }
    end
    self.state[name].spells[spellID] = GetTime()

    self:SendCooldownSync(spellID, name, GetTime())
    self:RefreshAllViews()
end

function CC:RecordCooldownFromComm(playerName, spellID, usedAt, classTag)
    local data = CC.SpellData[spellID]
    if not data then return end

    if not self.state[playerName] then
        self.state[playerName] = { class = classTag or "UNKNOWN", spells = {} }
    end
    local cur = self.state[playerName].spells[spellID]
    if not cur or usedAt > cur then
        self.state[playerName].spells[spellID] = usedAt
        self:RefreshAllViews()
    end
end

function CC:RefreshAllViews()
    self:RefreshRows()
    if CC.RefreshEssentials then CC:RefreshEssentials() end
    if CC.RefreshLanes then CC:RefreshLanes() end
end

function CC:GetRemaining(playerName, spellID)
    local entry = self.state[playerName]
    if not entry then return nil end
    local usedAt = entry.spells[spellID]
    if not usedAt then return nil end
    local data = CC.SpellData[spellID]
    if not data then return nil end
    local rem = (usedAt + data.duration) - GetTime()
    return rem > 0 and rem or 0
end

-- Event frame
local ef = CreateFrame("Frame", "CCEventFrame")
CC.eventFrame = ef

ef:RegisterEvent("ADDON_LOADED")
ef:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "CooldownCollaborator" then
            CC:Init()
            self:RegisterEvent("GROUP_ROSTER_UPDATE")
            self:RegisterEvent("ENCOUNTER_START")
            self:RegisterEvent("ENCOUNTER_END")
            self:RegisterEvent("CHAT_MSG_ADDON")
            self:RegisterEvent("PLAYER_LOGOUT")
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        CC:PruneState()
        CC:RefreshRows()
        CC:ScanRoster()
    elseif event == "ENCOUNTER_START" then
        CC.inEncounter = true
    elseif event == "ENCOUNTER_END" then
        CC.inEncounter = false
        C_Timer.After(1, function() CC:BroadcastState() end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- spellID is SECRET for party/raid tokens — confirmed by live crash
        -- ("attempted to index a table that cannot be indexed with secret
        -- keys") when a party member's cast fired this event. Only "player"
        -- gives a safe, indexable spellID. Other players' cooldowns must
        -- arrive exclusively via the addon-message sync (OnAddonMessage),
        -- never by reading this event for their unit token directly.
        local unitToken, _, spellID = ...
        if unitToken == "player" then
            CC:RecordCooldown(unitToken, spellID)
        end
    elseif event == "CHAT_MSG_ADDON" then
        CC:OnAddonMessage(...)
    elseif event == "PLAYER_LOGOUT" then
        CC:SavePosition()
    end
end)

SLASH_COOLDOWNCOLLABORATOR1 = "/cdc"
SlashCmdList["COOLDOWNCOLLABORATOR"] = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    if cmd == "lock" then
        CC.db.locked = true
        CC:UpdateLock()
        print("|cFF54a3ffCooldownCollaborator|r locked.")
    elseif cmd == "unlock" then
        CC.db.locked = false
        CC:UpdateLock()
        print("|cFF54a3ffCooldownCollaborator|r unlocked.")
    elseif cmd == "reset" then
        CC.db.x, CC.db.y = 0, 200
        CC.frame:ClearAllPoints()
        CC.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        print("|cFF54a3ffCooldownCollaborator|r position reset.")
    elseif cmd == "settings" then
        CC:OpenOptions()
    elseif cmd == "verbose" then
        CC.verbose = not CC.verbose
        print("|cFF54a3ffCooldownCollaborator|r verbose cast logging: " .. (CC.verbose and "ON" or "OFF"))
    elseif cmd == "essentials" then
        CC.db.essentialsEnabled = not CC.db.essentialsEnabled
        CC:RefreshEssentials()
        print("|cFF54a3ffCooldownCollaborator|r Essentials bar: " .. (CC.db.essentialsEnabled and "ON" or "OFF"))
    elseif cmd == "lanes" then
        CC.db.laneEnabled = not CC.db.laneEnabled
        CC:RefreshLanes()
        print("|cFF54a3ffCooldownCollaborator|r Lane view: " .. (CC.db.laneEnabled and "ON" or "OFF"))
    elseif cmd == "consumable" then
        -- /cdc consumable <spellID> <duration> <name...>
        local rest = msg:match("^%S+%s+(.*)$") or ""
        local spellIDStr, durStr, name = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
        local spellID = tonumber(spellIDStr)
        local dur = tonumber(durStr)
        if not spellID or not dur then
            print("|cFF54a3ffCooldownCollaborator|r usage: /cdc consumable <spellID> <durationSeconds> <name>")
        else
            CC:AddConsumableBuff(spellID, dur, name ~= "" and name or nil)
        end
    elseif cmd == "roster" then
        CC:ScanRoster()
        print("|cFF54a3ffCooldownCollaborator|r roster:")
        for name, info in pairs(CC.roster or {}) do
            local caps = {}
            for key in pairs(info.capabilities) do caps[#caps + 1] = key end
            print(string.format("    %s [%s] capabilities: %s",
                name, info.class, #caps > 0 and table.concat(caps, ", ") or "none"))
        end
    elseif cmd == "debug" then
        print("|cFF54a3ffCooldownCollaborator|r " .. CC.version)
        print("  In group:", tostring(IsInGroup()), " In raid:", tostring(IsInRaid()))
        print("  In encounter:", tostring(CC.inEncounter))
        print("  Min duration filter:", CC.db.minDuration)
        local any = false
        for name, entry in pairs(CC.state) do
            for sid, _ in pairs(entry.spells) do
                any = true
                local rem = CC:GetRemaining(name, sid)
                local spell = CC.SpellData[sid]
                print(string.format("    %s [%s] %s = %.0fs",
                    name, entry.class, spell and spell.name or tostring(sid), rem or 0))
            end
        end
        if not any then
            print("  (no cooldowns recorded yet — try /cdc verbose, then use a tracked CD)")
        end
    else
        if CC.frame then
            CC.frame:SetShown(not CC.frame:IsShown())
        end
    end
end
