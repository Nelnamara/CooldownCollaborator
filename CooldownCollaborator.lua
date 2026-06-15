-- CooldownCollaborator
-- Group and raid cooldown coordinator for WoW Midnight (12.x)
-- Author: Nelnamara

CooldownCollaborator = {}
local CC = CooldownCollaborator

CC.version = "1.0.0"
CC.PREFIX   = "CDCOLLAB"

-- state[playerName] = { class = "WARRIOR", spells = { [spellID] = usedAtTimestamp } }
CC.state = {}

CC.inEncounter = false

local DEFAULTS = {
    x           = 0,
    y           = 200,
    scale       = 1.0,
    locked      = false,
    minDuration = 60,
    showReady   = true,
    alpha       = 0.9,
}

function CC:Init()
    if not CooldownCollaboratorDB then
        CooldownCollaboratorDB = CopyTable(DEFAULTS)
    end
    self.db = CooldownCollaboratorDB
    for k, v in pairs(DEFAULTS) do
        if self.db[k] == nil then self.db[k] = v end
    end

    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    self:RegisterGroupEvents()
    self:BuildUI()
end

function CC:RecordCooldown(unitToken, spellID)
    local data = CC.SpellData[spellID]
    if not data then return end
    if data.duration < (self.db.minDuration or 60) then return end

    local name = UnitName(unitToken)
    if not name or name == "" then return end

    if not self.state[name] then
        local _, classTag = UnitClass(unitToken)
        self.state[name] = { class = classTag or "UNKNOWN", spells = {} }
    end
    self.state[name].spells[spellID] = GetTime()

    self:SendCooldownSync(spellID, name, GetTime())
    self:RefreshRows()
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
        self:RefreshRows()
    end
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

-- Event frame — created once, methods added by other files before first event fires
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
    elseif event == "ENCOUNTER_START" then
        CC.inEncounter = true
    elseif event == "ENCOUNTER_END" then
        CC.inEncounter = false
        -- Wait 1 frame for lockdown to release before broadcasting
        C_Timer.After(1, function() CC:BroadcastState() end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitToken, _, spellID = ...
        CC:RecordCooldown(unitToken, spellID)
    elseif event == "CHAT_MSG_ADDON" then
        CC:OnAddonMessage(...)
    elseif event == "PLAYER_LOGOUT" then
        CC:SavePosition()
    end
end)

SLASH_COOLDOWNCOLLABORATOR1 = "/cc"
SLASH_COOLDOWNCOLLABORATOR2 = "/collab"
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
    elseif cmd == "debug" then
        print("|cFF54a3ffCooldownCollaborator|r " .. CC.version)
        print("  In encounter:", tostring(CC.inEncounter))
        print("  Tracked players:")
        for name, entry in pairs(CC.state) do
            for sid, usedAt in pairs(entry.spells) do
                local rem = CC:GetRemaining(name, sid)
                local spell = CC.SpellData[sid]
                print(string.format("    %s [%s] %s = %.0fs remaining",
                    name, entry.class, spell and spell.name or tostring(sid), rem or 0))
            end
        end
    else
        -- Toggle visibility
        if CC.frame then
            CC.frame:SetShown(not CC.frame:IsShown())
        end
    end
end
