-- CooldownCollaborator
-- Group and raid cooldown coordinator for World of Warcraft: Retail (Midnight
-- 12.x), MoP Classic, TBC Anniversary, Classic Era and WoW: Forever.
-- Author: Nelnamara

CooldownCollaborator = {}
CC = CooldownCollaborator

CC.version = "1.1.0"
CC.PREFIX   = "CDCOLLAB"

-------------------------------------------------------------------------------
-- Client detection (the same rules as CooldownTimeline3). WoW: Forever runs
-- the modern engine and API (the old spell globals are gone, values can be
-- secret, no combat log) but reports a vanilla-era interface number (16xxx).
-- So tocversion only picks CONTENT (the TOCs load each client's spell list);
-- retailAPI picks which API calls exist. Never pick an API by tocversion alone.
-------------------------------------------------------------------------------

local _, _, _, tocversion = GetBuildInfo()
CC.tocversion = tocversion
CC.isForever = (tocversion >= 16000 and tocversion < 17000)
    or (WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and tocversion < 110000)
CC.retailAPI = tocversion >= 110000 or CC.isForever
-- Specs (and the inspect pipeline that reads them) are used on Retail only.
CC.isRetail = tocversion >= 110000

-- Frames with a backdrop take the template only where the client has it.
CC.BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Globals that don't exist on every client, resolved per call. WoW: Forever
-- ships no deprecation fallbacks: no IsSpellKnown / IsSpellKnownOrOverridesKnown
-- and no GetSpellInfo globals there.
local function PlayerSpellBank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
end

CC.Compat = {
    IsSpellKnown = function(spellID)
        if IsSpellKnownOrOverridesKnown or IsSpellKnown then
            return (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID))
                or (IsSpellKnown and IsSpellKnown(spellID)) or false
        end
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            return C_SpellBook.IsSpellKnown(spellID, PlayerSpellBank()) or false
        end
        return false
    end,
    -- name, icon, spellID of a spell (an ID, or a name where the client takes one)
    GetSpellInfo = function(spell)
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spell)
            if info and info.name then return info.name, info.iconID, info.spellID end
        end
        if GetSpellInfo then
            local name, _, icon, _, _, _, spellID = GetSpellInfo(spell)
            if name then return name, icon, spellID end
        end
    end,
}

-- state["Name-Realm"] = { class = "WARRIOR", spells = { [spellID] = usedAtTimestamp } }
CC.state = {}

CC.inEncounter = false

-- Local player's own tracked spells that were used and have not yet been
-- announced as ready: [spellID] = usedAt (local GetTime()).
CC.localActive = {}

-------------------------------------------------------------------------------
-- Player identity: "Name-Realm" so same-named players from different realms
-- never clash. Display code uses CC:ShortName().
-------------------------------------------------------------------------------

function CC:FullName(unit)
    local name, realm = UnitFullName(unit)
    if not name or name == "" then return nil end
    if not realm or realm == "" then realm = GetNormalizedRealmName() end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function CC:ShortName(full)
    if not full then return full end
    return full:match("^([^-]+)") or full
end

-- Addon-message senders normally carry a realm; add ours if one is missing.
function CC:NormalizeSender(sender)
    if not sender or sender == "" then return nil end
    if sender:find("-", 1, true) then return sender end
    local realm = GetNormalizedRealmName()
    if realm and realm ~= "" then return sender .. "-" .. realm end
    return sender
end

-- Turn a bare name (old-format message body) into a group member's full name.
function CC:ResolveBareName(bare)
    local function check(unit)
        if UnitExists(unit) and UnitName(unit) == bare then return self:FullName(unit) end
    end
    local found = check("player")
    if found then return found end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            found = check("raid" .. i)
            if found then return found end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            found = check("party" .. i)
            if found then return found end
        end
    end
    return self:NormalizeSender(bare)
end

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

    showOnCDTL3 = true,   -- feed group cooldowns to CDTL3's lanes (if CDTL3 is loaded)
}

function CC:Init()
    if not CooldownCollaboratorDB then
        CooldownCollaboratorDB = CopyTable(DEFAULTS)
    end
    self.db = CooldownCollaboratorDB
    for k, v in pairs(DEFAULTS) do
        if self.db[k] == nil then self.db[k] = v end
    end

    -- Rank map and name index from this client's own list (Data_<client>.lua)
    self:BuildSpellIndex()

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
    -- Every rank records under (and is sent as) its base ID.
    local castID = spellID
    spellID = self:BaseSpellID(spellID)
    local data = CC.SpellData[spellID]
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r cast seen: unit=%s spellID=%s known=%s",
            tostring(unitToken), tostring(castID), tostring(data ~= nil)))
    end
    if not data then return end
    if data.duration < (self.db.minDuration or 60) then return end
    if self.db.disabledSpells and self.db.disabledSpells[spellID] then return end

    local name = self:FullName(unitToken)
    if not name then return end

    if not self.state[name] then
        local _, classTag = UnitClass(unitToken)
        self.state[name] = { class = classTag or "UNKNOWN", spells = {} }
    end
    local now = GetTime()
    self.state[name].spells[spellID] = now

    -- Watch our own spell so we can announce "ready now" (talents shorten
    -- the real cooldown below the base length everyone else assumes). Not
    -- for a spell whose cooldown sits on an item: its own cooldown reads 0.
    if unitToken == "player" and not data.consumable and not data.itemCooldown then
        self.localActive[spellID] = now
    end

    self:SendCooldownSync(spellID, name, now)
    self:BridgeStart(name, spellID, now, self.state[name].class)
    self:RefreshAllViews()
end

-- A remote player's spell is ready now (their "ready now" announcement).
function CC:RecordReadyFromComm(playerName, spellID)
    spellID = self:BaseSpellID(spellID)
    local data = CC.SpellData[spellID]
    local entry = self.state[playerName]
    if not data or not entry or not entry.spells[spellID] then return end
    entry.spells[spellID] = GetTime() - data.duration
    self:BridgeStop(playerName, spellID)
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
        self:BridgeStart(playerName, spellID, usedAt, self.state[playerName].class)
        self:RefreshAllViews()
    end
end

-- Resolve a player's name back to a live unit token, so we can check things
-- (alive/dead) that GetCapabilityStatus's name-only entries cannot.
local function FindUnitToken(name)
    if CC:FullName("player") == name then return "player" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local token = "raid" .. i
            if CC:FullName(token) == name then return token end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local token = "party" .. i
            if CC:FullName(token) == name then return token end
        end
    end
    return nil
end

-- Raid lead / assist only: target a dead player and announce who should
-- rez them, naming the specific provider whose Battle Rez is ready right
-- now rather than a generic "someone rez" callout.
function CC:CanRequestRez()
    if IsInRaid() then
        return IsRaidLeader() or IsRaidOfficer()
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

    local targetName = self:FullName("target")
    local status = CC:GetCapabilityStatus("BATTLEREZ")
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
    local msg = string.format("%s, please %s %s!", self:ShortName(provider.name), spellName, self:ShortName(targetName))

    if IsInRaid() then
        SendChatMessage(msg, "RAID")
        SendChatMessage(msg, "RAID_WARNING")
    else
        SendChatMessage(msg, "PARTY")
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

    local known = false
    pcall(function()
        known = (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID))
             or (IsSpellKnown and IsSpellKnown(spellID))
    end)
    if not known then return nil end

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

-- Is our own spell off cooldown right now? Returns true / false, or nil when
-- it can't be read. cd.isActive is never secret; reads are pcall-guarded.
local function LocalSpellIsReady(spellID)
    local ready
    local ok = pcall(function()
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
        if ch and ch.maxCharges and ch.maxCharges > 1 then
            ready = (ch.currentCharges or 0) >= 1
            return
        end
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
        if not cd then return end
        ready = not cd.isActive
    end)
    if not ok then return nil end
    return ready
end

-- Cheap poll: only the spells we've used and not yet announced. Skipped
-- entirely (one next() call) when nothing is outstanding.
function CC:PollLocalReady()
    if not next(self.localActive) then return end
    local now = GetTime()
    for spellID, usedAt in pairs(self.localActive) do
        -- Grace so the cooldown has actually started before we judge it.
        if now - usedAt > 3 and LocalSpellIsReady(spellID) == true then
            self.localActive[spellID] = nil
            local me = self:FullName("player")
            local data = CC.SpellData[spellID]
            local entry = me and self.state[me]
            if entry and data and entry.spells[spellID] then
                entry.spells[spellID] = now - data.duration
            end
            if me then self:BridgeStop(me, spellID) end
            self:SendReadySync(spellID)
            self:RefreshAllViews()
        end
    end
end

C_Timer.NewTicker(1, function() CC:PollLocalReady() end)

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
            self:RegisterEvent("PLAYER_LOGIN")
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
    elseif event == "PLAYER_LOGIN" then
        -- Every addon is loaded by now, so CDTL3 (if present) is ready.
        CC:BridgeRegister()
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
            print(string.format("    %s [%s] capabilities: %s",
                CC:ShortName(name), classStr, #caps > 0 and table.concat(caps, ", ") or "none"))
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
                    CC:ShortName(name), entry.class, spell and spell.name or tostring(sid), rem or 0))
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
