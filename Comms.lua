-- Addon messaging — sync CD state with other CooldownCollaborator users.
-- Blocked during boss/M+ encounters AND briefly around death/resurrect; queues
-- and retries rather than dropping.
--
-- CDCOLLAB wire formats (fields split on ":"):
--
--   Cooldown (1.0.x compatible, never change):
--     "spellID:secondsAgo:playerName:classTag"
--     GetTime() is seconds since THAT CLIENT's own process started, not a shared
--     clock - sending a raw GetTime() timestamp and comparing it against the
--     receiver's own GetTime() is meaningless (produced a displayed "36839:39"
--     remaining bug). Send elapsed time since cast instead, and have the
--     receiver re-anchor it to their own GetTime() on arrival.
--
--   Known spells (1.1.0+; first field is non-numeric so 1.0.x clients ignore it):
--     "K:addonVersion:classTag:part/total:id,id,id,..."
--     The canonical IDs of the built-in tracked spells the sender knows. Split
--     into numbered parts to stay under 255 bytes; part 1 replaces the sender's
--     stored set, later parts add to it.
--
--   Request (1.1.0+):
--     "R:addonVersion"
--     "Please send me your own state." Receivers answer after a random delay
--     with their own active cooldowns plus a known-spells message.
--
-- All outgoing addon messages go through CC:QueueAddonMessage (token bucket +
-- keyed replacement + retry), defined below.

CC.knownSpells   = CC.knownSpells   or {}   -- [playerName] = { [canonicalID] = true }
CC.addonVersions = CC.addonVersions or {}   -- [playerName] = "1.1.0"

-------------------------------------------------------------------------------
-- Outgoing queue (modeled on Blizzard's own cooldown broadcaster)
-------------------------------------------------------------------------------

local BUCKET_MAX     = 10     -- tokens
local REFILL_PER_SEC = 1
local RETRY_DELAY    = 2      -- seconds before a failed item is retried
local MAX_MSG_LEN    = 255

-- Enum.SendAddonMessageResult
local R_SUCCESS, R_INVALID_PREFIX, R_INVALID_MESSAGE, R_THROTTLE, R_INVALID_CHAT_TYPE,
      R_NOT_IN_GROUP, R_TARGET_REQUIRED, R_INVALID_CHANNEL, R_CHANNEL_THROTTLE, R_GENERAL_ERROR =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9

local queue      = {}            -- ordered list of items
local queueByKey = {}            -- [key] = item
local tokens     = BUCKET_MAX
local lastRefill = GetTime()

local function Log(fmt, ...)
    if CC.verbose then
        print("|cFF54a3ffCDC|r " .. string.format(fmt, ...))
    end
end

-- Group-finder (instance) groups talk on INSTANCE_CHAT: sending RAID/PARTY
-- there returns NotInGroup, so nothing synced in those groups before 1.1.0.
function CC:GroupChatType()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end
local function GroupChatType() return CC:GroupChatType() end

local function RemoveItem(item)
    if queueByKey[item.key] == item then queueByKey[item.key] = nil end
    for i = 1, #queue do
        if queue[i] == item then table.remove(queue, i) break end
    end
end

-- Drop queued messages whose key starts with `prefix`.
function CC:CancelQueuedMessages(prefix)
    for i = #queue, 1, -1 do
        local item = queue[i]
        if item.key:sub(1, #prefix) == prefix then
            if queueByKey[item.key] == item then queueByKey[item.key] = nil end
            table.remove(queue, i)
        end
    end
end

local function Pump()
    local now = GetTime()
    tokens = math.min(BUCKET_MAX, tokens + (now - lastRefill) * REFILL_PER_SEC)
    lastRefill = now

    -- Known-spells parts must arrive in order (part 1 starts a new set), so
    -- once one part is waiting, later parts wait too.
    local knownBlocked = false
    local i = 1
    while i <= #queue do
        local item = queue[i]
        local isKnown = item.key:sub(1, 6) == "known:"
        if isKnown and knownBlocked then
            i = i + 1
        elseif item.expiresAt and now >= item.expiresAt then
            Log("queue: dropped expired %s", item.key)
            RemoveItem(item)
        elseif item.notBefore and now < item.notBefore then
            if isKnown then knownBlocked = true end
            i = i + 1
        elseif tokens < 1 then
            break
        else
            local chatType = GroupChatType()
            if not chatType then
                Log("queue: dropped %s (not in a group)", item.key)
                RemoveItem(item)
            else
                local msg = item.message
                if type(msg) == "function" then msg = msg() end
                if not msg or #msg > MAX_MSG_LEN then
                    Log("queue: dropped %s (no message / too long)", item.key)
                    RemoveItem(item)
                else
                    local ok, result = pcall(C_ChatInfo.SendAddonMessage, item.prefix, msg, chatType)
                    if not ok then result = R_GENERAL_ERROR end
                    -- nil/true/0 = success. Never nil in practice, but be liberal.
                    local success = (result == nil or result == true or result == R_SUCCESS)
                    Log("send %s [%s] via %s -> %s", item.prefix, msg, chatType, tostring(result))

                    if success then
                        tokens = tokens - 1
                        RemoveItem(item)
                    elseif result == R_INVALID_PREFIX or result == R_INVALID_MESSAGE
                        or result == R_INVALID_CHAT_TYPE or result == R_NOT_IN_GROUP
                        or result == R_TARGET_REQUIRED or result == R_INVALID_CHANNEL then
                        -- Will never succeed as-is.
                        RemoveItem(item)
                    else
                        -- 3 throttle, 8 channel throttle, 9 general error (boss-fight
                        -- lockdown surfaces here) or an unknown code: keep and retry.
                        if result == R_THROTTLE or result == R_CHANNEL_THROTTLE then
                            tokens = tokens - 1
                        end
                        item.notBefore = now + RETRY_DELAY
                        if isKnown then knownBlocked = true end
                        i = i + 1
                    end
                end
            end
        end
    end
end

-- message may be a string or a function returning one (evaluated at send time,
-- so a delayed cooldown message carries the right secondsAgo). A newer message
-- with the same key replaces a queued older one. expiresAt (GetTime) is optional:
-- the message is dropped if still unsent by then.
function CC:QueueAddonMessage(prefix, message, key, expiresAt)
    if not GroupChatType() then
        Log("queue: %s skipped (not in a group)", tostring(key or prefix))
        return
    end
    key = key or (prefix .. ":" .. tostring(message))

    local existing = queueByKey[key]
    if existing then
        existing.prefix, existing.message, existing.expiresAt = prefix, message, expiresAt
        existing.notBefore = nil
    else
        local item = { prefix = prefix, message = message, key = key, expiresAt = expiresAt }
        queue[#queue + 1] = item
        queueByKey[key] = item
    end
    Pump()
end

C_Timer.NewTicker(0.5, Pump)

-------------------------------------------------------------------------------
-- Cooldown sync
-------------------------------------------------------------------------------

function CC:SendCooldownSync(spellID, playerName, usedAt)
    spellID = self:CanonicalSpellID(spellID)
    local data = self.SpellData[spellID]
    -- Once the cooldown would have expired anyway there is nothing to tell.
    local expiresAt = data and (usedAt + data.duration) or nil
    if expiresAt and expiresAt <= GetTime() then return end

    local state = self.state
    self:QueueAddonMessage(self.PREFIX, function()
        local entry = state[playerName]
        local classTag = entry and entry.class or "UNKNOWN"
        local secondsAgo = math.max(0, GetTime() - usedAt)
        return string.format("%d:%.3f:%s:%s", spellID, secondsAgo, playerName, classTag)
    end, "cd:" .. playerName .. ":" .. spellID, expiresAt)
end

-------------------------------------------------------------------------------
-- Receive
-------------------------------------------------------------------------------

local pendingKnown = {}   -- [senderName] = { set = {} } while parts arrive

local function HandleKnownSpells(senderName, message)
    local _, ver, _, partStr, ids = strsplit(":", message, 5)
    local part, total = string.match(partStr or "", "^(%d+)/(%d+)$")
    part, total = tonumber(part), tonumber(total)
    if not part or not total or not ids then return end

    if ver and ver ~= "" then CC.addonVersions[senderName] = ver end

    -- Build the set aside and swap it in when the last part arrives, so a
    -- refresh between parts never sees a half-filled set.
    if part == 1 then pendingKnown[senderName] = { set = {} } end
    local pending = pendingKnown[senderName]
    if not pending then return end   -- missed part 1; the next report fixes it
    for idStr in string.gmatch(ids, "%d+") do
        local id = CC:CanonicalSpellID(tonumber(idStr))
        if CC.SpellData[id] then pending.set[id] = true end
    end
    if part >= total then
        CC.knownSpells[senderName] = pending.set
        pendingKnown[senderName] = nil
        CC:RefreshAllViews()
    end
end

function CC:OnAddonMessage(prefix, message, _, sender)
    local short = self:ShortName(sender)

    -- Route buff-status messages to the consumables handler
    if prefix == "CDCBUFF" then
        CC:OnBuffStatusMessage(short, message)
        return
    end

    if prefix ~= self.PREFIX then return end
    if not message then return end

    Log("sync received from %s: %s", tostring(sender), tostring(message))

    local isSelf = (short == UnitName("player"))

    local first, rest = strsplit(":", message, 2)
    if first == "K" then
        if not isSelf and short then HandleKnownSpells(short, message) end
        return
    elseif first == "R" then
        if not isSelf and short then
            if rest and rest ~= "" then CC.addonVersions[short] = rest end
            if CC.OnSyncRequest then CC:OnSyncRequest(short) end
        end
        return
    end

    local spellIDStr, secondsAgoStr, playerName, classTag = strsplit(":", message, 4)
    local spellID    = tonumber(spellIDStr)
    local secondsAgo = tonumber(secondsAgoStr)

    if not spellID or not secondsAgo or not playerName or playerName == "" then return end

    -- A negative value would put the cast in the future and pin the timer
    -- (newest wins), so clamp it.
    if secondsAgo < 0 then secondsAgo = 0 end

    -- Re-anchor to OUR OWN clock - secondsAgo is clock-independent, unlike
    -- the sender's raw GetTime() value.
    local localUsedAt = GetTime() - secondsAgo
    self:RecordCooldownFromComm(playerName, spellID, localUsedAt, classTag)
end
