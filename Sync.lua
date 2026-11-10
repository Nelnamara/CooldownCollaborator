-- State sync: known-spells reporting, state requests/replies, and saved own
-- cooldowns (per-character CooldownCollaboratorCharDB). Wire formats are
-- documented in Comms.lua.

CC.knownSpells   = CC.knownSpells   or {}
CC.addonVersions = CC.addonVersions or {}

local MAX_MSG_BYTES = 230      -- payload budget per known-spells part (limit is 255)
local lastSentSig              -- signature of the last known set we broadcast
local wasInGroup = false
local replyPending = false
local debounceToken = 0

local function Log(fmt, ...)
    if CC.verbose then print("|cFF54a3ffCDC|r " .. string.format(fmt, ...)) end
end

-------------------------------------------------------------------------------
-- Known spells
-------------------------------------------------------------------------------

-- Sorted list of canonical IDs of built-in tracked spells the player knows.
local function ComputeKnownList()
    local list = {}
    for id, data in pairs(CC.SpellData or {}) do
        if not data.consumable and not data.custom and data.class ~= "CONSUMABLE"
           and CC:KnowsSpell(id) then
            list[#list + 1] = id
        end
    end
    table.sort(list)
    return list
end

-- Recompute our own set and store it. Returns the list and its signature.
local function UpdateOwnKnown()
    local me = UnitName("player")
    local list = ComputeKnownList()
    local sig = table.concat(list, ",")
    if me then
        local set = {}
        for _, id in ipairs(list) do set[id] = true end
        CC.knownSpells[me] = set
        CC.addonVersions[me] = CC.version
    end
    return list, sig
end

local function SendKnownSpells(list)
    local _, classTag = UnitClass("player")
    local header = "K:" .. tostring(CC.version) .. ":" .. (classTag or "UNKNOWN") .. ":"

    -- Chunk into parts under the byte budget ("n/m:" suffix is <= 8 bytes).
    local parts, cur = {}, {}
    local curLen = #header + 8
    for _, id in ipairs(list) do
        local s = tostring(id)
        if curLen + #s + 1 > MAX_MSG_BYTES and #cur > 0 then
            parts[#parts + 1] = table.concat(cur, ",")
            cur, curLen = {}, #header + 8
        end
        cur[#cur + 1] = s
        curLen = curLen + #s + 1
    end
    parts[#parts + 1] = table.concat(cur, ",")   -- always at least one part (may be empty)

    CC:CancelQueuedMessages("known:")
    for i, ids in ipairs(parts) do
        local msg = string.format("%s%d/%d:%s", header, i, #parts, ids)
        CC:QueueAddonMessage(CC.PREFIX, msg, "known:" .. i)
    end
    Log("known-spells queued: %d spells in %d part(s)", #list, #parts)
end

-- Recompute; broadcast if forced or the set changed since the last broadcast.
local function CheckKnownSpells(force)
    local list, sig = UpdateOwnKnown()
    local changed = (sig ~= lastSentSig)
    if changed then CC:RefreshAllViews() end
    if force or changed then
        lastSentSig = sig
        SendKnownSpells(list)
    end
end

local function ScheduleKnownCheck()
    debounceToken = debounceToken + 1
    local token = debounceToken
    C_Timer.After(2, function()
        if token == debounceToken then CheckKnownSpells(false) end
    end)
end

-------------------------------------------------------------------------------
-- Requests and replies
-------------------------------------------------------------------------------

-- Send our own still-active cooldowns (casts made solo or in another group,
-- and ones restored from the saved variable, were never announced here).
local function SendOwnActiveCooldowns()
    local me = UnitName("player")
    local entry = me and CC.state[me]
    if not entry then return end
    local now = GetTime()
    for spellID, usedAt in pairs(entry.spells) do
        local data = CC.SpellData[spellID]
        if not data or usedAt + data.duration > now then
            CC:SendCooldownSync(spellID, me, usedAt)
        end
    end
end

function CC:SendStateRequest()
    if not IsInGroup() then return end
    Log("sending state request")
    self:QueueAddonMessage(self.PREFIX, "R:" .. tostring(self.version), "request", GetTime() + 60)
    SendOwnActiveCooldowns()
    CheckKnownSpells(true)
end

-- Called from Comms.lua when another player asks for our state.
function CC:OnSyncRequest(sender)
    Log("state request from %s", tostring(sender))
    if replyPending then return end   -- several requests inside the window get one answer
    replyPending = true
    C_Timer.After(0.5 + math.random() * 2.5, function()
        replyPending = false
        if not IsInGroup() then return end
        SendOwnActiveCooldowns()
        CheckKnownSpells(true)
    end)
end

-------------------------------------------------------------------------------
-- Saved own cooldowns
-------------------------------------------------------------------------------

local function EnsureCharDB()
    CooldownCollaboratorCharDB = CooldownCollaboratorCharDB or {}
    CooldownCollaboratorCharDB.cooldowns = CooldownCollaboratorCharDB.cooldowns or {}
    return CooldownCollaboratorCharDB
end

-- Called by core's RecordCooldown for the player's own casts.
function CC:OnOwnCooldown(canonicalID, usedAt)
    local db = EnsureCharDB()
    db.cooldowns[canonicalID] = GetServerTime() - (GetTime() - usedAt)
end

local function RestoreOwnCooldowns()
    local db = EnsureCharDB()
    local me = UnitName("player")
    if not me then return end
    local srv, now = GetServerTime(), GetTime()
    local restored = 0

    for id, epoch in pairs(db.cooldowns) do
        local data = CC.SpellData[id]
        local elapsed = srv - (tonumber(epoch) or 0)
        if not data or type(epoch) ~= "number" or elapsed < 0 or elapsed >= data.duration then
            db.cooldowns[id] = nil
        else
            if not CC.state[me] then
                local _, classTag = UnitClass("player")
                CC.state[me] = { class = classTag or "UNKNOWN", spells = {} }
            end
            local usedAt = now - elapsed
            local cur = CC.state[me].spells[id]
            if not cur or usedAt > cur then CC.state[me].spells[id] = usedAt end
            restored = restored + 1
        end
    end
    if restored > 0 then
        Log("restored %d saved cooldown(s)", restored)
        CC:RefreshAllViews()
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Not every event exists on every client.
for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
                      "CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    pcall(f.RegisterEvent, f, ev)
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        RestoreOwnCooldowns()
        wasInGroup = IsInGroup()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Only after login or /reload: every loading screen (portals, instance
        -- entry) fires this too, and a whole raid zoning in together would
        -- otherwise all ask and all answer at once.
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi or (isInitialLogin == nil and isReloadingUi == nil) then
            -- Spellbook/talents may not be readable the instant the world loads.
            C_Timer.After(3, function()
                if not CC.db then return end   -- core never initialized
                CC:SendStateRequest()          -- sends known-spells too
            end)
        end
        wasInGroup = IsInGroup()
    elseif event == "GROUP_ROSTER_UPDATE" then
        local inGroup = IsInGroup()
        if inGroup and not wasInGroup and CC.db then
            wasInGroup = true
            CC:SendStateRequest()
        end
        wasInGroup = inGroup
    else
        ScheduleKnownCheck()
    end
end)
