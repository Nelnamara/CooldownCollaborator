-- Cauldron/Feast tracking — each client detects its own buffs and broadcasts
-- its category status (flask/food) so the raid can see who is buffed.
--
-- Detection: aura.name and .spellId are SECRET even on the local player.
-- The only safe lookup is C_UnitAuras.GetPlayerAuraBySpellID(knownID), so
-- consumables must be registered by ID up front (/cdc consumable).
--
-- Group status: flask/food presence is broadcast as "CDC:BUFF:flask:1" etc.
-- Receivers track CC.buffRoster[playerName] = { flask=bool, food=bool }.
-- The Essentials Bar displays "Flask N/N | Food N/N" with click-to-expand.
--
-- Category field on consumable entries:
--   "flask"  = counts toward group flask counter
--   "food"   = counts toward group food counter
--   nil/""   = tracked but not counted in either group total

CC.consumableActive = CC.consumableActive or {}
CC.buffRoster       = CC.buffRoster or {}        -- [playerName] = { flask=bool, food=bool }

-- Wire format for group buff sync
local BUFF_PREFIX = "CDCBUFF"

-------------------------------------------------------------------------------
-- Load / register consumables
-------------------------------------------------------------------------------

function CC:LoadConsumableBuffs()
    -- Built-ins (CC.BuiltinConsumables, per client in Data.lua) already carry
    -- their category and are merged into CC.SpellData by CC:Init.
    for idStr, data in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID and data.duration and data.duration > 0 then
            CC.SpellData[spellID] = {
                name       = data.name or ("Consumable " .. spellID),
                duration   = data.duration,
                icon       = data.icon or 134400,
                class      = "UNKNOWN",
                consumable = true,
                category   = data.category,
            }
        end
    end
end

-- /cdc consumable <spellID> <duration> <name> [flask|food]
-- The last word of the name, if it is "flask" or "food", is treated as the
-- category flag so users can type: /cdc consumable 12345 3600 Haste Flask flask
function CC:AddConsumableBuff(spellID, duration, name)
    spellID = tonumber(spellID)
    if not spellID or not duration or duration <= 0 then return false end

    -- Parse optional trailing category keyword
    local category = nil
    if name then
        local stripped, trailing = name:match("^(.-)%s+(flask)$")
                                or name:match("^(.-)%s+(food)$")
        if stripped and trailing then
            name     = stripped ~= "" and stripped or nil
            category = trailing
        end
    end
    name = name ~= "" and name or ("Consumable " .. spellID)

    self.db.consumableBuffs[tostring(spellID)] = {
        name     = name,
        duration = duration,
        icon     = 134400,
        category = category,
    }
    CC.SpellData[spellID] = {
        name       = name,
        duration   = duration,
        icon       = 134400,
        class      = "UNKNOWN",
        consumable = true,
        category   = category,
    }
    local catStr = category and (" [" .. category .. "]") or ""
    print(string.format("|cFF54a3ffCooldownCollaborator|r tracking consumable: %s (%ds)%s",
        name, duration, catStr))
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

-------------------------------------------------------------------------------
-- Self-detection poll (rising-edge only)
-------------------------------------------------------------------------------

-- Is this aura on the player? true/false, or nil when it can't be read right
-- now. Auras are secret in combat on Forever and on retail 12.1, and reading
-- one there can throw ("Auras cannot be accessed when secret while tainted"),
-- so the read and the nil-compare both run inside the pcall.
local function PlayerHasAura(spellID)
    local present, expiresAt
    local ok = pcall(function()
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        present = aura ~= nil
        -- expirationTime is GetTime()-based; 0 means no expiry. Read inside the
        -- pcall too: it can be secret.
        if aura and aura.expirationTime and aura.expirationTime > 0 then
            expiresAt = aura.expirationTime
        end
    end)
    if not ok then return nil end
    return present, expiresAt
end

function CC:PollConsumables()
    -- Flask/food checks are a pre-pull thing; in combat the auras are secret.
    if InCombatLockdown() then return end

    local myName   = UnitName("player")
    local changed  = false
    local hasFlask = false
    local hasFood  = false

    local function check(spellID, cat)
        local present, expiresAt = PlayerHasAura(spellID)
        if present == nil then
            -- Unreadable: keep what we knew.
            present = self.consumableActive[spellID] and true or false
        else
            local wasActive = self.consumableActive[spellID]
            if present and not wasActive then
                -- First sight since load may be an aura that was already up
                -- (login, /reload): use its real start, or keep the restored
                -- time, instead of restarting the timer at full length.
                local data = CC.SpellData[spellID]
                local usedAt = expiresAt and data and (expiresAt - data.duration) or nil
                local me = UnitName("player")
                local known = me and CC.state[me] and CC.state[me].spells[spellID]
                local stillRunning = known and data and (known + data.duration > GetTime())
                if wasActive == nil and stillRunning and not usedAt then
                    -- restored from the saved variable; nothing to do
                else
                    CC:RecordCooldown("player", spellID, usedAt)
                end
            end
            if present ~= (wasActive and true or false) then changed = true end
            self.consumableActive[spellID] = present
        end
        if present then
            if cat == "flask" then hasFlask = true end
            if cat == "food"  then hasFood  = true end
        end
    end

    -- Built-ins for this client
    for id, data in pairs(CC.BuiltinConsumables or {}) do
        check(id, data.category)
    end

    -- User-registered consumables
    for idStr in pairs(self.db.consumableBuffs or {}) do
        local spellID = tonumber(idStr)
        if spellID then
            check(spellID, CC.SpellData[spellID] and CC.SpellData[spellID].category)
        end
    end

    -- Broadcast status to group if anything changed, or do an initial broadcast
    if changed or not self.buffBroadcastDone then
        self.buffBroadcastDone = true
        self:BroadcastBuffStatus(myName, hasFlask, hasFood)
    end
    self.lastBuffStatus = { flask = hasFlask, food = hasFood }

    -- Update own entry in buffRoster for local display
    if myName then
        self.buffRoster[myName] = { flask = hasFlask, food = hasFood }
    end
end

-------------------------------------------------------------------------------
-- Group buff status sync
-------------------------------------------------------------------------------

function CC:BroadcastBuffStatus(playerName, hasFlask, hasFood)
    if not IsInGroup() then return end
    -- Message format: "flask:1:food:1"
    local msg = string.format("flask:%d:food:%d",
        hasFlask and 1 or 0, hasFood and 1 or 0)
    if CC.QueueAddonMessage then
        -- Shared queue (Comms.lua): throttled, retried, newest status wins.
        CC:QueueAddonMessage(BUFF_PREFIX, msg, "buffstatus")
    else
        C_ChatInfo.SendAddonMessage(BUFF_PREFIX, msg, CC:GroupChatType() or "PARTY")
    end
end

-- Someone joined: they have nobody's status yet, so announce ours again
-- (debounced, with a little jitter so a full raid doesn't send at once).
local buffResendPending = false
local function ScheduleBuffResend()
    if buffResendPending then return end
    buffResendPending = true
    C_Timer.After(3 + math.random() * 2, function()
        buffResendPending = false
        local st = CC.lastBuffStatus
        if st and IsInGroup() then
            CC:BroadcastBuffStatus(UnitName("player"), st.flask, st.food)
        end
    end)
end

local lastGroupSize = 0
local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:SetScript("OnEvent", function()
    local size = GetNumGroupMembers()
    if size > lastGroupSize then ScheduleBuffResend() end
    lastGroupSize = size
end)

-- Called from Comms.lua or directly from the event handler
function CC:OnBuffStatusMessage(sender, msg)
    local flask, food = msg:match("flask:(%d):food:(%d)")
    if not flask then return end
    -- Senders arrive as "Name-Realm"; the roster is keyed by UnitName().
    sender = CC:ShortName(sender)
    self.buffRoster[sender] = { flask = flask == "1", food = food == "1" }
    if CC.RefreshEssentials then CC:RefreshEssentials() end
end

-- Returns { total=N, flask=N, food=N, missingFlask={names}, missingFood={names} }
-- for the current group.
function CC:GetGroupBuffStatus()
    local total        = 0
    local hasFlask     = 0
    local hasFood      = 0
    local missingFlask = {}
    local missingFood  = {}

    if not IsInGroup() then return nil end

    local function check(unit)
        local name = UnitName(unit)
        if not name or not UnitIsConnected(unit) then return end
        total = total + 1
        local entry = self.buffRoster[name]
        if entry and entry.flask then
            hasFlask = hasFlask + 1
        else
            missingFlask[#missingFlask + 1] = name
        end
        if entry and entry.food then
            hasFood = hasFood + 1
        else
            missingFood[#missingFood + 1] = name
        end
    end

    check("player")
    if IsInRaid() then
        -- The raid1..N list includes the player; don't count them twice.
        local me = UnitName("player")
        for i = 1, GetNumGroupMembers() do
            if UnitName("raid" .. i) ~= me then check("raid" .. i) end
        end
    else
        for i = 1, GetNumGroupMembers() - 1 do check("party" .. i) end
    end

    return { total=total, flask=hasFlask, food=hasFood,
             missingFlask=missingFlask, missingFood=missingFood }
end

C_Timer.NewTicker(2, function()
    if CC.db then CC:PollConsumables() end
end)
