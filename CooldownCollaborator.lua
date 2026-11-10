-- CooldownCollaborator
-- Group and raid cooldown coordinator for WoW Midnight (12.x) and WoW: Forever (1.60.x)
-- Author: Nelnamara

CooldownCollaborator = {}
CC = CooldownCollaborator

CC.version = "1.1.0"
CC.PREFIX   = "CDCOLLAB"

-- Which client we're on. Forever runs the modern (retail) API with Midnight's
-- restrictions but a vanilla-era interface number (16xxx), so detect it by that
-- band, never by WOW_PROJECT_ID (it changed during the Forever beta).
local _, _, _, tocversion = GetBuildInfo()
CC.tocversion = tocversion or 0
CC.isForever  = CC.tocversion >= 16000 and CC.tocversion < 17000

-- Spell ranks (Forever keeps them: every rank has its own spell ID). Data.lua
-- keys each tracked spell by ONE canonical ID and fills CC.SpellAlias with
-- [anyRankID] = canonicalID. Everything stored, sent or displayed uses the
-- canonical ID. On retail there are no ranks, so canonical == cast ID.
CC.SpellAlias = CC.SpellAlias or {}
function CC:CanonicalSpellID(spellID)
    return CC.SpellAlias[spellID] or spellID
end

-- All rank IDs of a tracked spell (canonical first). Falls back to { id }.
function CC:SpellRanks(spellID)
    local data = CC.SpellData and CC.SpellData[spellID]
    return (data and data.ranks) or { spellID }
end

-- Does the local player know this spell (any rank)? pcall-guarded: these
-- calls take secret-sensitive arguments on Midnight/Forever.
function CC:KnowsSpell(spellID)
    -- Item use effects (Soulstone) are never in the spellbook: the class decides.
    local data = CC.SpellData and CC.SpellData[spellID]
    if data and data.item then
        local _, classTag = UnitClass("player")
        return classTag == data.class, spellID
    end
    for _, id in ipairs(self:SpellRanks(spellID)) do
        local known = false
        pcall(function()
            if C_SpellBook and C_SpellBook.IsSpellKnown then
                known = C_SpellBook.IsSpellKnown(id)
            elseif IsSpellKnownOrOverridesKnown then
                known = IsSpellKnownOrOverridesKnown(id)
            elseif IsSpellKnown then
                known = IsSpellKnown(id)
            end
        end)
        if known then return true, id end
    end
    return false
end

-- Addon-message senders arrive as "Name-Realm"; the rest of the addon keys
-- players by UnitName() (no realm). Normalize to that.
function CC:ShortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:match("^([^-]+)")) or name
end

-- state[playerName] = { class = "WARRIOR", spells = { [canonicalSpellID] = usedAt (local GetTime()) } }
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

    -- Merge built-in consumables, then user's custom/registered ones
    for id, data in pairs(CC.BuiltinConsumables or {}) do
        CC.SpellData[id] = data
    end
    self:LoadCustomSpells()
    self:LoadConsumableBuffs()

    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix("CDCBUFF")
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

    -- Any rank of a built-in spell is already tracked (casts map to its
    -- canonical ID, so a custom entry for another rank would never fill).
    local canonical = CC.SpellAlias[spellID]
    if canonical and CC.SpellData[canonical] and not CC.SpellData[canonical].custom then
        print(string.format("|cFF54a3ffCooldownCollaborator|r %s is already tracked.",
            CC.SpellData[canonical].name or tostring(spellID)))
        return false
    end

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

-- usedAt is optional (local GetTime() of the cast); defaults to now. Consumables
-- pass the real start when an aura was already up (login, /reload).
function CC:RecordCooldown(unitToken, spellID, usedAt)
    spellID = self:CanonicalSpellID(spellID)
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
    local now = usedAt or GetTime()
    self.state[name].spells[spellID] = now

    -- Sync.lua saves our own cooldowns so a /reload or relog keeps them.
    if unitToken == "player" and CC.OnOwnCooldown then CC:OnOwnCooldown(spellID, now) end

    self:SendCooldownSync(spellID, name, now)
    self:RefreshAllViews()
end

function CC:RecordCooldownFromComm(playerName, spellID, usedAt, classTag)
    spellID = self:CanonicalSpellID(spellID)
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

-- Resolve a player's name back to a live unit token, so we can check things
-- (alive/dead) that GetCapabilityStatus's name-only entries cannot.
local function FindUnitToken(name)
    if UnitName("player") == name then return "player" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local token = "raid" .. i
            if UnitName(token) == name then return token end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local token = "party" .. i
            if UnitName(token) == name then return token end
        end
    end
    return nil
end

-- Raid lead / assist only: target a dead player and announce who should
-- rez them, naming the specific provider whose Battle Rez is ready right
-- now rather than a generic "someone rez" callout.
function CC:CanRequestRez()
    -- IsRaidLeader/IsRaidOfficer were removed from the game long ago (absent from
    -- both the retail and Forever API docs); calling them errored inside raids.
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    elseif IsInGroup() then
        return UnitIsGroupLeader("player")
    end
    return false
end

function CC:RequestRez()
    if not self:CanRequestRez() then
        print("|cFF54a3ffCDC|r Only the raid leader/assist (or party leader) can request a rez.")
        return
    end
    if not UnitExists("target") or not UnitIsDeadOrGhost("target") then
        print("|cFF54a3ffCDC|r Target a dead player first.")
        return
    end

    local targetName = UnitName("target")
    local rezKey = "BATTLEREZ"
    for key, cap in pairs(CC.CAPABILITIES or {}) do
        if cap.rez then rezKey = key break end
    end
    local status = CC:GetCapabilityStatus(rezKey)
    local provider = nil
    for _, entry in ipairs(status) do
        -- A dead player can't rez anyone, including themselves - skip the
        -- target and skip anyone else who is also currently dead/ghost.
        if entry.ready and entry.name ~= targetName then
            local token = FindUnitToken(entry.name)
            if not token or not UnitIsDeadOrGhost(token) then
                provider = entry
                break
            end
        end
    end

    if not provider then
        print("|cFF54a3ffCDC|r No living Battle Rez provider available right now.")
        return
    end

    local data = CC.SpellData[provider.spellID]
    local spellName = data and data.name or "Battle Rez"
    local msg = string.format("%s, please %s %s!", provider.name, spellName, targetName)

    local chatType = CC.GroupChatType and CC:GroupChatType() or (IsInRaid() and "RAID" or "PARTY")
    SendChatMessage(msg, chatType)
    if chatType == "RAID" then SendChatMessage(msg, "RAID_WARNING") end
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

-- Live readiness for the LOCAL player's own spell, in seconds (0 = ready), or nil
-- if we can't read it (spell unknown, or a value is still secret in this context).
--
-- Midnight 12.0.7 un-secreted combat-res (and other whitelisted) cooldowns AND
-- charge counts, so for our own capability spells we can show true readiness
-- immediately — even right after /reload or before we've observed a cast — and
-- respect the raid-wide Battle Rez charge pool. Remote players are still learned
-- only via the CDCOLLAB sync (their values remain secret to us).
--
-- pcall-guarded: a bare read of a secret value doesn't error, but comparing/using
-- one does. If any field is still secret here the compare throws, ok is false, and
-- we return nil so the caller falls back to the observed-cast model (GetRemaining).
function CC:GetLocalReadiness(spellID)
    if not C_Spell then return nil end
    -- An item's cooldown isn't the use spell's cooldown; use the observed use.
    local itemData = CC.SpellData and CC.SpellData[spellID]
    if itemData and itemData.item then return nil end

    -- Read the rank the player actually knows (Forever has ranks).
    local known, knownID = self:KnowsSpell(spellID)
    if not known then return nil end
    spellID = knownID or spellID

    local remaining
    local ok = pcall(function()
        -- Charge-based (raid Battle Rez pool): ready while >=1 charge is banked,
        -- otherwise count down to the next charge.
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
        if ch and ch.maxCharges and ch.maxCharges > 1 then
            if (ch.currentCharges or 0) >= 1 then
                remaining = 0
            else
                local rem = (ch.cooldownStart or 0) + (ch.cooldownDuration or 0) - GetTime()
                remaining = rem > 0 and rem or 0
            end
            return
        end
        -- Plain cooldown. duration <= 1.5 is just the GCD → treat as ready.
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
        if cd and cd.isEnabled ~= false and cd.isActive and cd.duration and cd.duration > 1.5 then
            local rem = (cd.startTime + cd.duration) - GetTime()
            remaining = rem > 0 and rem or 0
        else
            remaining = 0  -- known and not on a real cooldown → ready
        end
    end)
    if not ok then return nil end
    return remaining
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
            self:RegisterEvent("INSPECT_READY")
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
    elseif event == "INSPECT_READY" then
        CC:OnInspectReady(...)
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
    elseif cmd == "rez" then
        CC:RequestRez()
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
        print("|cFF54a3ffCooldownCollaborator|r roster (spec refinement queued):")
        for name, info in pairs(CC.roster or {}) do
            local caps = {}
            for key in pairs(info.capabilities) do caps[#caps + 1] = key end
            local specName = CC:GetSpecName(name)
            local classStr = specName and (specName .. " " .. info.class) or info.class
            local ver = CC.addonVersions and CC.addonVersions[name]
            print(string.format("    %s [%s] capabilities: %s  |cFF888888%s|r",
                name, classStr, #caps > 0 and table.concat(caps, ", ") or "none",
                ver and ("addon " .. ver) or "no addon seen"))
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
