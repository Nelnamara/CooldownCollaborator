-- Addon messaging: sync cooldown state with other CooldownCollaborator users.
-- The wire is docs/MESSAGE_FORMAT_2.md. Prefixes: CDCOLLAB (cooldowns) and
-- CDCBUFF (flask and food, "flask:N:food:N").
--
-- 1.x lines, still sent and read so old copies keep working beside new ones:
--   "spellID:secondsAgo:name:class"   a cast; name is the sender's bare name
--   "R:spellID"                       the sender's own spell is ready again
-- Format 2: a letter, the format number, then fields (old copies drop these:
-- tonumber("H") is nil):
--   H:2:<version>:<client>            hello
--   Q:2                               state request
--   S:2:<class>:<id>,<ago>;...[;+]    the sender's running cooldowns (absent = ready);
--                                     a trailing ";+" says more of the list follows
--   C:2:<charges>:<max>:<secondsToNext>  the raid's battle rez charges (0:0:0: no pool)
--   T:2:<Name-Realm>:<secondsAgo>     a Soulstone the sender placed on a living group
--                                     member (Retail and Forever, where only its client knows)
--   P:2:<id>:<part>/<parts>:<data>    plan or order, kept once every part is in
--   O:2:<id>:<part>/<parts>:<data>    officer setup, GUILD only, kept the same way
--
-- GetTime() is seconds since THAT client started, not a shared clock, so the
-- wire carries secondsAgo and the receiver re-anchors it to its own GetTime()
-- (a raw timestamp once showed "36839:39" remaining).
--
-- A message belongs to its sender (the game's Name-Realm): nothing in a body
-- can name someone else. Only the group's own channels and current members are
-- heard; whispers are dropped. With guild sharing on (db.guildSync, P41), H, Q
-- and S also go over GUILD and are read into the guild's own tables, never the
-- group's (the guild channel, below).

CC.peers        = CC.peers or {}        -- [Name-Realm] = { version, client, proto, heardAt }
CC.pendingSyncs = CC.pendingSyncs or {} -- sends the game refused, tried again every 2 s
CC.sendQueue    = CC.sendQueue or {}    -- sends waiting for their time or for the channel
CC.heldReady    = CC.heldReady or {}    -- [spellID] = true: a ready-now refused during a boss
CC.payloads     = CC.payloads or { P = {}, O = {} }  -- [kind][sender][id] = { data, at }

local SPACING        = 0.25  -- seconds between two messages on one channel
local REPEAT_WINDOW  = 1     -- the same message again within this is dropped
local ANSWER_EVERY   = 10    -- one state answer per this many seconds
local ANSWER_JITTER  = 3     -- answers wait a random 0 to 3 s, so a raid doesn't answer at once
local MAX_MESSAGE    = 255
local CHUNK_KEEP     = 30    -- seconds a part of a P or O message waits for the rest
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- The channel that reaches the whole group: INSTANCE_CHAT in an instance group
-- (dungeon finder, battleground), else RAID or PARTY; nil when not grouped.
function CC:GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

-- Did SendAddonMessage send it? Retail and Forever return an
-- Enum.SendAddonMessageResult (0 = Success); other builds nothing or true.
-- Anything else (3 = throttled, 11 = lockdown, false, ...) didn't go out.
function CC:AddonMessageSent(result)
    if result == nil or result == true or result == 0 then return true end
    local results = Enum and Enum.SendAddonMessageResult
    return results ~= nil and results.Success ~= nil and result == results.Success
end

-- The client name a hello carries.
function CC:ClientTag()
    if self.isForever then return "forever" end
    local toc = self.tocversion or 0
    if toc >= 110000 then return "retail" end
    if toc >= 50000 then return "mists" end
    if toc >= 20000 then return "tbc" end
    return "era"
end

-- Who runs it, for /cdc roster (P13): a member's version from their hello, "old
-- version" for an older one or a 1.x copy (heard, but no hello), "no hello" for
-- a member no copy was heard from.
local function VersionParts(v)
    local a, b, c = tostring(v):match("^(%d+)%.?(%d*)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

function CC:IsOlderVersion(version)
    local a1, b1, c1 = VersionParts(version)
    local a2, b2, c2 = VersionParts(self.version)
    if a1 ~= a2 then return a1 < a2 end
    if b1 ~= b2 then return b1 < b2 end
    return c1 < c2
end

function CC:PeerNote(name)   -- the /cdc roster dump only: English on purpose
    if name == self:FullName("player") then return "you, " .. self.version end
    local peer = self.peers[name]
    if not peer then return "no hello" end
    if peer.proto == 1 then return "1.x (old version, no hello)" end
    return tostring(peer.version) .. (self:IsOlderVersion(peer.version) and " (old version)" or "")
end

-------------------------------------------------------------------------------
-- The send queue. Every CDCOLLAB and CDCBUFF send goes through it: one message
-- every 0.25 s per channel, the same message again within 1 s dropped, and a
-- send the game refuses tried again every 2 s, 15 times at most. A message is
-- built when it goes out, so a wait in the queue doesn't age its secondsAgo.
-------------------------------------------------------------------------------

-- A send the game keeps refusing is tried again every 2 s, at most this many times (about half a minute)
CC.MAX_SEND_TRIES = 15

local lastSendAt = {}  -- channel -> GetTime() of the last attempt
local recent     = {}  -- prefix \t channel \t text -> GetTime() it went out
local drainAt    = nil -- the earliest drain already scheduled

local function ScheduleDrain(at)
    if drainAt and drainAt <= at then return end
    drainAt = at
    C_Timer.After(math.max(0, at - GetTime()), function()
        if drainAt == at then drainAt = nil end
        CC:DrainSendQueue()
    end)
end

-- opts: delay (seconds), kind, spellID, tries, key (one queued item per key: a
-- second one joins the first), onSent(), onRefused(item), channel ("GUILD";
-- nil = the group's channel when it goes out).
function CC:QueueSend(prefix, build, opts)
    opts = opts or {}
    if opts.key then
        for _, q in ipairs(self.sendQueue) do
            if q.key == opts.key then return end
        end
    end
    self.sendQueue[#self.sendQueue + 1] = {
        prefix = prefix, build = build, at = GetTime() + (opts.delay or 0), key = opts.key,
        kind = opts.kind, spellID = opts.spellID, tries = opts.tries or 0,
        onSent = opts.onSent, onRefused = opts.onRefused, channel = opts.channel, always = opts.always,
    }
    self:DrainSendQueue()
end

function CC:DrainSendQueue()
    local group = self:GroupChannel()
    local guildOn = self:GuildSyncOn()
    -- what has nowhere to go is dropped: group sends while solo (our running
    -- cooldowns go out with the state message on joining), guild sends with guild sharing off
    for i = #self.sendQueue, 1, -1 do
        local q = self.sendQueue[i]
        if (q.channel == "GUILD" and not guildOn and not q.always) or (q.channel == nil and not group) then
            table.remove(self.sendQueue, i)
        end
    end
    local now = GetTime()
    while true do
        -- the first item whose time has come and whose channel is free
        local idx, nextAt
        for i, q in ipairs(self.sendQueue) do
            local at = math.max(q.at, (lastSendAt[q.channel or group] or -math.huge) + SPACING)
            if at <= now then idx = i break end
            if not nextAt or at < nextAt then nextAt = at end
        end
        if not idx then
            if nextAt then ScheduleDrain(nextAt) end
            return
        end
        local q = table.remove(self.sendQueue, idx)
        -- (a group send while solo was dropped above, so there is always a channel)
        local channel = q.channel or group
        local text = q.build
        if type(text) == "function" then text = text() end
        if channel and type(text) == "string" and text ~= "" then
            local seen = q.prefix .. "\t" .. channel .. "\t" .. text
            local last = recent[seen]
            if last and now - last < REPEAT_WINDOW then
                if q.onSent then q.onSent() end   -- it just went out
            else
                local ok, result = pcall(C_ChatInfo.SendAddonMessage, q.prefix, text, channel)
                lastSendAt[channel] = now
                if self.verbose then
                    print(string.format("|cFF54a3ffCDC|r send: %s %s via %s (result=%s)", -- debug
                        q.prefix, text, channel, ok and tostring(result) or "error"))
                end
                if ok and self:AddonMessageSent(result) then
                    recent[seen] = now
                    if q.onSent then q.onSent() end
                elseif ok then
                    -- Not sent (throttled, lockdown, etc.): tried again, not dropped.
                    q.tries = q.tries + 1
                    self:NoteSendError(result)
                    if q.onRefused then q.onRefused(q) end
                    if q.tries < CC.MAX_SEND_TRIES then
                        self.pendingSyncs[#self.pendingSyncs + 1] = q
                    end
                end
            end
        end
    end
end

-- Retry what the game refused, and forget old repeats.
C_Timer.NewTicker(2, function()
    local now = GetTime()
    for k, t in pairs(recent) do
        if now - t >= REPEAT_WINDOW then recent[k] = nil end
    end
    CC:ExpireChunks()
    if #CC.pendingSyncs == 0 then return end
    local retry = CC.pendingSyncs
    CC.pendingSyncs = {}
    for _, q in ipairs(retry) do
        q.at = now
        CC.sendQueue[#CC.sendQueue + 1] = q
    end
    CC:DrainSendQueue()
end)

-------------------------------------------------------------------------------
-- What we send
-------------------------------------------------------------------------------

-- A cast as the 1.x line every copy reads: "spellID:secondsAgo:name:class".
-- The wire carries the bare name so older copies read it; identity (name and
-- realm) comes from the sender.
function CC:SendCooldownSync(spellID, playerName, usedAt, tries)
    self:GuildStateChanged()
    if not self:GroupChannel() then
        if CC.verbose then print("|cFF54a3ffCDC|r sync skipped: not in a group") end -- debug
        return
    end
    local entry = self.state[playerName]
    local classTag = entry and entry.class or "UNKNOWN"
    local bare = self:ShortName(playerName)
    local data = CC.SpellData[spellID]
    self:QueueSend(self.PREFIX, function()
        -- nothing once it is over
        local ago = math.max(0, GetTime() - usedAt)
        if data and ago >= data.duration then return nil end
        return string.format("%d:%.3f:%s:%s", spellID, ago, bare, classTag)
    end, { kind = "cast", spellID = spellID, tries = tries })
end

-- "Ready now": "R:spellID", our own tracked spell is off cooldown. Old copies
-- read "R" as the spell ID, get nil from tonumber and drop it. One refused
-- during a boss is sent again once when the boss ends (BroadcastState).
function CC:SendReadySync(spellID, tries)
    self:GuildStateChanged()
    if not self:GroupChannel() then return end
    self:QueueSend(self.PREFIX, "R:" .. spellID, {
        kind = "ready", spellID = spellID, tries = tries,
        onSent = function() CC.heldReady[spellID] = nil end,
        onRefused = function() if CC.inEncounter then CC.heldReady[spellID] = true end end,
    })
end

-- channel: nil for the group's, or "GUILD" (guild sharing, below)
function CC:SendHello(delay, channel)
    self:QueueSend(self.PREFIX, function()
        return string.format("H:2:%s:%s", self.version, self:ClientTag())
    end, { kind = "hello", key = channel and ("hello:" .. channel) or "hello", delay = delay, channel = channel })
end

function CC:SendStateRequest(delay, channel)
    self:QueueSend(self.PREFIX, "Q:2", { kind = "request", key = channel and ("request:" .. channel) or "request",
        delay = delay, channel = channel })
end

-- Our own running cooldowns, as one S message or more (each but the last ends
-- ";+"). Ready spells are left out: absence means ready.
function CC:StateMessages()
    local me = self:FullName("player")
    local entry = me and self.state[me]
    local class = entry and entry.class
    if not class or class == "UNKNOWN" then
        local _, classTag = UnitClass("player")
        class = classTag or "UNKNOWN"
    end
    local head = "S:2:" .. class .. ":"
    local items = {}
    if entry then
        local now, ids = GetTime(), {}
        for id in pairs(entry.spells) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local data = CC.SpellData[id]
            local ago = now - entry.spells[id]
            if data and ago < data.duration then
                items[#items + 1] = string.format("%d,%.1f", id, math.max(0, ago))
            end
        end
    end
    local out, cur, len = {}, {}, #head
    for _, item in ipairs(items) do
        -- room for this entry, its ";" and a closing ";+"
        if #cur > 0 and len + #item + 3 > MAX_MESSAGE then
            out[#out + 1] = head .. table.concat(cur, ";") .. ";+"
            cur, len = {}, #head
        end
        cur[#cur + 1] = item
        len = len + #item + 1
    end
    out[#out + 1] = head .. table.concat(cur, ";")
    return out
end

-- Built when it goes out; a list too long for one message queues its other parts right behind.
function CC:SendState(delay, channel)
    self:QueueSend(self.PREFIX, function()
        local parts = CC:StateMessages()
        for i = #parts, 2, -1 do
            table.insert(CC.sendQueue, 1, { prefix = CC.PREFIX, build = parts[i], at = 0, kind = "state", tries = 0,
                channel = channel })
        end
        return parts[1]
    end, { kind = "state", key = channel and ("state:" .. channel) or "state", delay = delay, channel = channel })
end

-- Our flask and food status again (in answer to Q, and on joining a group).
function CC:SendBuffStatus(delay)
    local mine = self.myBuffStatus
    if not mine then return end
    self:QueueSend(self.BUFF_PREFIX, function()
        -- "flask:N:food:N", then this client's other buff counts (Consumables.lua)
        return CC:BuffStatusText()
    end, { kind = "buff", key = "buff", delay = delay })
end

-- The battle rez charge pool we read, for the whole group: C:2:<charges>:<max>:<secondsToNext>
-- (0:0:0 when the pool is gone). Built when it goes out; dropped when someone else just said
-- the same.
function CC:SendRezCharges(delay)
    self:QueueSend(self.PREFIX, function()
        local mine = CC.rezChargesRead
        if not mine then return "C:2:0:0:0" end
        local heard = CC.rezCharges
        if heard and heard.from ~= CC:FullName("player") and (heard.heardAt or 0) >= (mine.changedAt or 0)
            and heard.charges == mine.charges and heard.max == mine.max
            and math.abs((heard.nextAt or 0) - (mine.nextAt or 0)) < 2 then
            return nil
        end
        local toNext = mine.nextAt and math.max(0, mine.nextAt - GetTime()) or 0
        return string.format("C:2:%d:%d:%d", mine.charges, mine.max, math.floor(toNext + 0.5))
    end, { kind = "charges", key = "charges", delay = delay })
end

-- T: a Soulstone we placed on a living group member. Retail hides other players'
-- buffs in combat and Forever has no combat log, so only our client knows; Era,
-- TBC and MoP see it in the combat log, so nothing is sent there.
function CC:SendStone(target, delay)
    if not self.retailAPI then return end
    self:QueueSend(self.PREFIX, function()
        local stone = CC.stones[target]
        if not stone or stone.from ~= CC:FullName("player") then return nil end
        local ago = GetTime() - stone.placedAt
        if ago < 0 or ago >= stone.duration then return nil end
        return string.format("T:2:%s:%.1f", target, ago)
    end, { kind = "stone", key = "stone:" .. target, delay = delay })
end

-- Our stones still running, again (a state request, a join, a boss end).
function CC:SendOwnStones(delay)
    local me = self:FullName("player")
    for target, stone in pairs(self.stones) do
        if stone.from == me then self:SendStone(target, delay) end
    end
end

-------------------------------------------------------------------------------
-- Joining, hellos and answers
-------------------------------------------------------------------------------

-- Our group's channel changed: we joined a group, left one, or moved between an
-- instance group and the home group. A new group hears our hello, a state
-- request, our own running cooldowns and our flask/food status.
function CC:CheckGroupChange()
    self:CheckGuildSync()
    local channel = self:GroupChannel()
    local was = self.syncChannel
    self.syncChannel = channel
    if channel == was then return end
    if not channel then
        wipe(self.peers)
        self.rezCharges = nil
        return
    end
    -- PARTY to RAID (or back) is the same group converting
    if was and was ~= "INSTANCE_CHAT" and channel ~= "INSTANCE_CHAT" then return end
    self:ScheduleJoinSync()
end

-- A short random wait first: right after a login the chat channels may not take
-- messages yet, and a raid that forms at once doesn't all speak at once.
function CC:ScheduleJoinSync()
    if self.joinSyncAt and self.joinSyncAt > GetTime() then return end
    local delay = 1 + math.random() * 2
    self.joinSyncAt = GetTime() + delay
    C_Timer.After(delay, function()
        CC.joinSyncAt = nil
        if not CC:GroupChannel() then return end
        CC:SendHello()
        CC:SendStateRequest()
        CC:SendState()
        CC:SendBuffStatus()
        CC:SendOwnStones()
    end)
end

-- A state request: our hello (so a /reload learns versions too), our running
-- cooldowns and our flask/food status, after a random 0 to 3 s. One answer per
-- 10 s: a request inside that window is answered when it ends.
local answerAt = -math.huge
function CC:AnswerStateRequest()
    local now = GetTime()
    -- a state message still waiting to go out answers this request too
    for _, q in ipairs(self.sendQueue) do
        if q.key == "state" then
            local wait = math.max(0, q.at - now)
            self:SendHello(wait)
            self:SendBuffStatus(wait)
            self:SendOwnStones(wait)
            return
        end
    end
    local delay = math.max(0, answerAt + ANSWER_EVERY - now) + math.random() * ANSWER_JITTER
    answerAt = now + delay
    self:SendHello(delay)
    self:SendState(delay)
    self:SendBuffStatus(delay)
    self:SendOwnStones(delay)
end

-------------------------------------------------------------------------------
-- What we hear
-------------------------------------------------------------------------------

-- A current group member (the roster, or the group itself when a message beats
-- our own roster update).
function CC:IsGroupMember(name)
    if self.roster and self.roster[name] then return true end
    return self:GetActiveGroupNames()[name] == true
end

-- A sane secondsAgo for a spell of this length: 0 .. duration (a negative,
-- huge or not-a-number value is dropped, not stored).
local function ValidAgo(ago, duration)
    return type(ago) == "number" and ago == ago and ago >= 0 and ago <= duration
end

local function ClassOrNil(classTag)
    if type(classTag) == "string" and classTag:match("^%u+$") then return classTag end
    return nil
end

-- A member heard sending 1.x lines but no hello runs an old copy (proto 1).
local function NoteOldCopy(owner)
    local peer = CC.peers[owner]
    if not peer then
        CC.peers[owner] = { proto = 1, heardAt = GetTime() }
    elseif peer.proto == 1 then
        peer.heardAt = GetTime()
    end
end

-- A possible old copy in the group still needs the per-spell 1.x lines at a boss end:
-- true unless every other current member is known (by their hello) to run format 2.
-- A member not heard from yet may be a 1.x copy, which never says hello.
function CC:OldCopyInGroup()
    local active = self:GetActiveGroupNames()
    local me = self:FullName("player")
    for name in pairs(active) do
        if name ~= me then
            local peer = self.peers[name]
            if not peer or (peer.proto or 0) < 2 then return true end
        end
    end
    return false
end

-- The 1.x cast line, from the sender's own copy only: an old 1.0.x copy's relay
-- of someone else's state (another name in the body) is dropped (R10, R11).
local function OnCastLine(self, owner, message)
    local spellIDStr, agoStr, bare, classTag = strsplit(":", message, 4)
    local spellID, ago = tonumber(spellIDStr), tonumber(agoStr)
    if not spellID or not ago or not bare or bare == "" then return end
    if bare ~= self:ShortName(owner) then
        if self.verbose then print("|cFF54a3ffCDC|r dropped a relay from " .. owner .. ": " .. message) end -- debug
        return
    end
    NoteOldCopy(owner)
    local base = self:BaseSpellID(spellID)
    local data = CC.SpellData[base]
    if not data or not ValidAgo(ago, data.duration) then return end
    self:RecordCooldownFromComm(owner, base, GetTime() - ago, ClassOrNil(classTag))
end

-- S: the sender's running cooldowns. Listed ones take the sender's time (it
-- owns them, and it beats a restored one); a built-in spell of theirs that we
-- hold as running but they leave out is ready (one from the combat log stays:
-- their copy may not track it).
-- An S body: the sender's class, its sane entries { id = base ID, ago }, and
-- whether more of the list follows (";+").
local function ReadStateBody(self, body)
    local classField, listField = strsplit(":", body, 2)
    local list = listField or ""
    local more = false
    if list:sub(-2) == ";+" then
        more, list = true, list:sub(1, -3)
    elseif list == "+" then
        more, list = true, ""
    end
    local items = {}
    for item in list:gmatch("[^;]+") do
        local idStr, agoStr = item:match("^(%d+),([%d%.]+)$")
        local id, ago = tonumber(idStr), tonumber(agoStr)
        if id and ago then
            local base = self:BaseSpellID(id)
            local data = CC.SpellData[base]
            if data and ValidAgo(ago, data.duration) then items[#items + 1] = { id = base, ago = ago } end
        end
    end
    return ClassOrNil(classField), items, more
end

local pendingState = {}  -- [owner] = { ids = {}, at = } while a ";+" list is still arriving
local function OnState(self, owner, body)
    local classTag, items, more = ReadStateBody(self, body)
    local now = GetTime()
    local pend = pendingState[owner]
    local listed = (pend and now - pend.at < 5) and pend.ids or {}
    local changed = false
    for _, item in ipairs(items) do
        listed[item.id] = true
        if self:SetRemoteCooldown(owner, item.id, now - item.ago, classTag, "state") then changed = true end
    end
    if more then
        pendingState[owner] = { ids = listed, at = now }
    else
        pendingState[owner] = nil
        local entry = self.state[owner]
        if entry then
            if classTag and entry.class == "UNKNOWN" then entry.class = classTag end
            for id, usedAt in pairs(entry.spells) do
                local data = CC.SpellData[id]
                if not listed[id] and data and not data.custom and not (entry.log and entry.log[id])
                    and usedAt + data.duration > now then
                    entry.spells[id] = now - data.duration
                    if entry.restored then entry.restored[id] = nil end
                    self:BridgeStop(owner, id)
                    changed = true
                end
            end
        end
    end
    if changed then self:RefreshAllViews() end
end

-- C: the raid's battle rez charge pool, from whoever can read it.
local function OnCharges(self, owner, body)
    local chargesField, maxField, nextField = strsplit(":", body, 3)
    local charges, max, toNext = tonumber(chargesField), tonumber(maxField), tonumber(nextField)
    if not charges or not max or not toNext then return end
    if max == 0 then
        self.rezCharges = nil
        return
    end
    if max < 1 or max > 20 or charges < 0 or charges > max or toNext < 0 or toNext > 3600
        or charges ~= math.floor(charges) or max ~= math.floor(max) then
        return
    end
    local now = GetTime()
    self.rezCharges = { charges = charges, max = max, nextAt = toNext > 0 and now + toNext or nil,
        from = owner, heardAt = now }
end

-- T: the sender's Soulstone on a group member (the body names its target; the
-- stone is the sender's). A target outside the group, or a time outside the
-- buff's length, is dropped.
local function OnStone(self, owner, body)
    local targetField, agoField = strsplit(":", body, 2)
    local ago = tonumber(agoField)
    local target = self:NormalizeSender(targetField)
    if not target or not ago or not self:IsGroupMember(target) then return end
    if not ValidAgo(ago, self:StoneDuration()) then return end
    self:PlaceStone(owner, target, GetTime() - ago)
end

-- P and O: parts of one id are kept 30 s; the whole text is stored once every part is in
-- (CC.payloads[kind][sender][id]). Rotation orders (rot-<spellID>) are read by UI.lua.
local chunks = {}  -- kind \t sender \t id -> { total, got, list, at }
local function OnChunk(self, kind, owner, body)
    local id, partStr, data = strsplit(":", body, 3)
    local part, total = (partStr or ""):match("^(%d+)/(%d+)$")
    part, total = tonumber(part), tonumber(total)
    if not id or not id:match("^[%w_%-]+$") or #id > 32 or not part or not total
        or part < 1 or total < 1 or part > total or total > 64 or not data or #data > 200 then
        return
    end
    local key = kind .. "\t" .. owner .. "\t" .. id
    local now = GetTime()
    local c = chunks[key]
    if not c or c.total ~= total or now - c.at > CHUNK_KEEP then
        c = { total = total, got = 0, list = {}, at = now }
        chunks[key] = c
    end
    if not c.list[part] then c.got = c.got + 1 end
    c.list[part] = data
    if c.got < total then return end
    chunks[key] = nil
    local byOwner = self.payloads[kind][owner] or {}
    self.payloads[kind][owner] = byOwner
    byOwner[id] = { data = table.concat(c.list), at = now }
    if kind == "O" and self.OnOfficerSetup then self:OnOfficerSetup(owner, id) end
    -- a rotation order (P:2:rot-<spellID>, UI.lua) shows at once
    if kind == "P" and id:match("^rot%-%d+$") and self.ReadSharedRotations then
        self:ReadSharedRotations()
        self:RefreshView("RefreshRows")
    end
end

function CC:ExpireChunks()
    local now = GetTime()
    for key, c in pairs(chunks) do
        if now - c.at > CHUNK_KEEP then chunks[key] = nil end
    end
end

function CC:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= self.PREFIX and prefix ~= self.BUFF_PREFIX then return end
    if type(message) ~= "string" then return end
    local owner = self:NormalizeSender(sender)
    -- our own echo: already applied here
    if not owner or owner == self:FullName("player") then return end
    if CC.verbose then
        print(string.format("|cFF54a3ffCDC|r heard %s from %s via %s: %s", -- debug
            prefix, tostring(sender), tostring(channel), message))
    end

    -- The guild's own messages go to their own tables, never the group's: officer
    -- setups (O) always, and with guild sharing on hellos, state requests and states.
    if channel == "GUILD" then
        if prefix == self.PREFIX then
            local kind, rest = message:match("^(%u):2:(.*)$")
            if kind == "O" then
                OnChunk(self, "O", owner, rest)
            elseif self:GuildSyncOn() then
                self:OnGuildMessage(owner, message)
            end
        end
        return
    end
    if not GROUP_CHANNELS[channel] or not self:IsGroupMember(owner) then
        if CC.verbose then print("|cFF54a3ffCDC|r dropped: not from a group member on a group channel") end -- debug
        return
    end

    if prefix == self.BUFF_PREFIX then
        self:OnBuffStatusMessage(owner, message)
        return
    end

    if message:sub(1, 2) == "R:" then
        local readyID = tonumber(message:sub(3))
        if readyID then
            NoteOldCopy(owner)
            self:RecordReadyFromComm(owner, readyID)
        end
        return
    end

    local kind, proto, tail = message:match("^(%u):(%d+)(.*)$")
    if not kind then
        OnCastLine(self, owner, message)
        return
    end
    proto = tonumber(proto)
    local body = tail:sub(1, 1) == ":" and tail:sub(2) or tail
    if kind == "H" then
        -- a newer format's hello still says who runs which version
        local version, client = strsplit(":", body, 2)
        if proto >= 2 and version and version ~= "" then
            self.peers[owner] = { version = version, client = client, proto = proto, heardAt = GetTime() }
        end
        return
    end
    if proto ~= 2 then return end
    if kind == "Q" then
        self:AnswerStateRequest()
    elseif kind == "S" then
        OnState(self, owner, body)
    elseif kind == "C" then
        OnCharges(self, owner, body)
    elseif kind == "T" then
        OnStone(self, owner, body)
    elseif kind == "P" then
        OnChunk(self, "P", owner, body)
    end
end

-------------------------------------------------------------------------------
-- The guild channel (P41): optional, off by default (db.guildSync). The same
-- format 2 H, Q and S messages over GUILD, read into the guild's own tables,
-- never the group's:
--   CC.guildPeers[name] = { version, client, proto, heardAt }
--   CC.guildState[name] = { class, spells = { [id] = usedAt (local GetTime()) }, heardAt }
-- With it on: a hello, a state request and our state a few seconds after login
-- (or after turning it on); our state again after our casts and ready-nows (one
-- message for a burst); a hello every 5 minutes; a Q answered with H and S after
-- a random 0 to 5 s, once per 30 s. A guildmate not heard for 11 minutes is
-- forgotten. Off: nothing goes out over GUILD and GUILD H, Q and S are dropped.
-------------------------------------------------------------------------------

CC.guildPeers = CC.guildPeers or {}
CC.guildState = CC.guildState or {}

local GUILD_START_DELAY   = 3     -- seconds, plus a random 0 to 3
local GUILD_HELLO_EVERY   = 300
local GUILD_FORGET        = 660
local GUILD_ANSWER_EVERY  = 30
local GUILD_ANSWER_JITTER = 5
local GUILD_STATE_DELAY   = 1     -- casts in a burst share one state message

local guildStarted, guildTicker = false, nil
local guildAnswerAt = -math.huge
local pendingGuild = {}   -- [owner] = { spells, at } while a ";+" list is still arriving

function CC:GuildSyncOn()
    return self.db ~= nil and self.db.guildSync == true and IsInGuild ~= nil and IsInGuild() and true or false
end

-- Turned on (or in a guild at login with it on): say hello, ask, and tell. Turned
-- off: the guild's tables are let go.
function CC:CheckGuildSync()
    local on = self:GuildSyncOn()
    if on and not guildStarted then
        guildStarted = true
        local delay = GUILD_START_DELAY + math.random() * 3
        self:SendHello(delay, "GUILD")
        self:SendStateRequest(delay, "GUILD")
        self:SendState(delay, "GUILD")
        if not guildTicker then
            guildTicker = C_Timer.NewTicker(GUILD_HELLO_EVERY, function()
                if CC:GuildSyncOn() then CC:SendHello(math.random() * 5, "GUILD") end
            end)
        end
    elseif not on and guildStarted then
        guildStarted = false
        wipe(self.guildPeers)
        wipe(self.guildState)
        wipe(pendingGuild)
    end
end

-- The settings lane's switch.
function CC:SetGuildSync(on)
    self.db.guildSync = on and true or false
    if not self.db.guildSync and self.db.panelTab == "guild" then self.db.panelTab = "all" end
    self:CheckGuildSync()
    self:RefreshView("RefreshRows")
end

-- Our own cooldowns changed: the guild hears our state (one message for a burst).
function CC:GuildStateChanged()
    if self:GuildSyncOn() then self:SendState(GUILD_STATE_DELAY, "GUILD") end
end

-- A guild Q: our hello and state after a random wait, once per 30 s (a request
-- inside that window is answered when it ends; one still queued answers it too).
function CC:AnswerGuildRequest()
    for _, q in ipairs(self.sendQueue) do
        if q.key == "state:GUILD" then return end
    end
    local now = GetTime()
    local delay = math.max(0, guildAnswerAt + GUILD_ANSWER_EVERY - now) + math.random() * GUILD_ANSWER_JITTER
    guildAnswerAt = now + delay
    self:SendHello(delay, "GUILD")
    self:SendState(delay, "GUILD")
end

local function HeardInGuild(self, owner, now)
    local peer = self.guildPeers[owner] or { proto = 2 }
    peer.heardAt = now
    self.guildPeers[owner] = peer
    return peer
end

-- A guild S: the sender's whole running list replaces what we held for them.
local function OnGuildState(self, owner, body)
    local classTag, items, more = ReadStateBody(self, body)
    local now = GetTime()
    local pend = pendingGuild[owner]
    local spells = (pend and now - pend.at < 5) and pend.spells or {}
    for _, item in ipairs(items) do spells[item.id] = now - item.ago end
    if more then
        pendingGuild[owner] = { spells = spells, at = now }
        return
    end
    pendingGuild[owner] = nil
    local old = self.guildState[owner]
    self.guildState[owner] = { class = classTag or (old and old.class) or "UNKNOWN", spells = spells, heardAt = now }
    HeardInGuild(self, owner, now)
end

function CC:OnGuildMessage(owner, message)
    local kind, proto, tail = message:match("^(%u):(%d+)(.*)$")
    if not kind then return end   -- 1.x lines never go over GUILD
    proto = tonumber(proto)
    local body = tail:sub(1, 1) == ":" and tail:sub(2) or tail
    if kind == "H" then
        local version, client = strsplit(":", body, 2)
        if proto >= 2 and version and version ~= "" then
            local peer = HeardInGuild(self, owner, GetTime())
            peer.version, peer.client, peer.proto = version, client, proto
        end
    elseif proto == 2 and kind == "Q" then
        self:AnswerGuildRequest()
    elseif proto == 2 and kind == "S" then
        OnGuildState(self, owner, body)
    end
end

-- The Guild tab's rows: each guildmate outside our group heard in the last 11
-- minutes, their lust and Battle Rez (by class, CC.Providers) with the time
-- left from their last state (not listed = ready): { name, class, spellID,
-- data, remaining, capKey, old }, lust first, ready first. Also how many
-- guildmates outside the group run it.
function CC:GuildRows()
    local rows, runners = {}, 0
    if not self:GuildSyncOn() then return rows, 0 end
    local now = GetTime()
    local inGroup = self:GetActiveGroupNames()
    for name, peer in pairs(self.guildPeers) do
        if now - (peer.heardAt or 0) > GUILD_FORGET then
            self.guildPeers[name] = nil
            self.guildState[name] = nil
        elseif not inGroup[name] then
            runners = runners + 1
            local st = self.guildState[name]
            local old = peer.version ~= nil and self:IsOlderVersion(peer.version)
            for order, capKey in ipairs({ "BLOODLUST", "BATTLEREZ" }) do
                local ids = st and CC.Providers[capKey] and CC.Providers[capKey][st.class]
                if ids then
                    -- a shaman has Bloodlust or Heroism: the one they used, else the first
                    local pick, usedAt = ids[1], nil
                    for _, id in ipairs(ids) do
                        local at = st.spells[id]
                        if at and (not usedAt or at > usedAt) then pick, usedAt = id, at end
                    end
                    local data = CC.SpellData[pick]
                    if data then
                        local remaining = usedAt and (usedAt + data.duration - now) or 0
                        rows[#rows + 1] = { name = name, class = st.class, spellID = pick, data = data,
                            remaining = remaining > 0 and remaining or 0, capKey = capKey, order = order, old = old }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if (a.remaining > 0) ~= (b.remaining > 0) then return a.remaining <= 0 end
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.name < b.name
    end)
    return rows, runners
end
