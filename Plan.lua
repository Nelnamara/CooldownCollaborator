-- Raid plan runtime (P12, "Boss timer rows"; the editor goes in Settings later).
-- A plan is rows of { timer = a boss-mod timer's text, or at = seconds into the
-- fight; player = Name-Realm; spellID }, kept in db.plans[name] = { rows, from, at }.
-- The leader (or a raid assist) shares one with the group as the format 2 P kind
-- (docs/MESSAGE_FORMAT_2.md); a copy keeps a plan shared by its group's leader or
-- an assist and makes it the active one (db.activePlan).
-- In a fight, when a row's timer starts (BigWigs_StartBar, DBM_TimerStart) or its
-- time into the encounter comes near, the assigned player gets a prompt bar like
-- the boss mod's, counting down the last db.planLead seconds; CC:PlannedSpellLate
-- tells the main panel a planned spell that won't be back in time.
-- Also here: the pull countdowns the Lane view's next hit uses (the game's own,
-- BigWigs' and DBM's pull timers). Every boss-mod call is guarded: none of them
-- need be there, and on Retail a timer's text or length can be hidden (it is
-- then only ever read inside a pcall, and a hidden one matches nothing).

local L = CC.L

local PLAN_FORMAT = "1"
local CHUNK       = 200   -- bytes of plan data per P message
local MAX_PARTS   = 64
local MAX_ROWS    = 200
local BAR_W, BAR_H, MAX_BARS = 240, 20, 3

CC.planPending = CC.planPending or {}   -- [key] = { row, due, length, label, bar }

-------------------------------------------------------------------------------
-- The text a plan travels as: a version, then key=value pairs (";" between),
-- with ":" ";" "," "=" "%" "|" and line breaks escaped as %XX.
--   1;k=plan;n=<name>;r=t,<timer text>,<player>,<spellID>;r=a,<seconds>,<player>,<spellID>
-- (k=plan tells it from a rotation order, which also travels as P.)
-------------------------------------------------------------------------------

local function Esc(s)
    return (tostring(s):gsub("[%%:;,=|\r\n]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function Unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function CC:EncodePlan(name, plan)
    local parts = { PLAN_FORMAT, "k=plan", "n=" .. Esc(name) }
    for _, row in ipairs(plan.rows or {}) do
        local trigger = row.timer and ("t," .. Esc(row.timer)) or string.format("a,%d", math.floor(row.at or 0))
        parts[#parts + 1] = string.format("r=%s,%s,%d", trigger, Esc(row.player or ""), row.spellID or 0)
    end
    return table.concat(parts, ";")
end

-- name, { rows } from the text, or nil when it isn't a plan of this format.
function CC:DecodePlan(data)
    if type(data) ~= "string" then return nil end
    local version, kind, name, rows = nil, nil, nil, {}
    for item in data:gmatch("[^;]+") do
        if not version then
            version = item
        else
            local key, value = item:match("^(%a+)=(.*)$")
            if key == "k" then
                kind = value
            elseif key == "n" then
                name = Unesc(value)
            elseif key == "r" and #rows < MAX_ROWS then
                local how, trigger, player, id = value:match("^([ta]),([^,]*),([^,]*),(%d+)$")
                player, id = player and Unesc(player), tonumber(id)
                if how and player ~= "" and #player <= 64 and id and id > 0 then
                    if how == "t" then
                        local text = Unesc(trigger)
                        if text ~= "" and #text <= 100 then rows[#rows + 1] = { timer = text, player = player, spellID = id } end
                    else
                        local at = tonumber(trigger)
                        if at and at >= 0 and at <= 3600 then rows[#rows + 1] = { at = at, player = player, spellID = id } end
                    end
                end
            end
        end
    end
    if version ~= PLAN_FORMAT or kind ~= "plan" or not name or name == "" or #name > 64 then return nil end
    return name, { rows = rows }
end

-- The id a plan travels under: its name's letters, digits, "_" and "-" (32 at most).
local function PlanID(name)
    local id = tostring(name):gsub("[^%w_%-]", ""):sub(1, 32)
    return id ~= "" and id or "plan"
end

-------------------------------------------------------------------------------
-- Sharing
-------------------------------------------------------------------------------

-- The group's leader, or an assist in a raid.
local function Leads(unit)
    local ok, yes = pcall(function()
        return UnitIsGroupLeader(unit) or (IsInRaid() and UnitIsGroupAssistant(unit)) or false
    end)
    return ok and yes and true or false
end

function CC:CanSharePlan()
    return IsInGroup() and Leads("player")
end

-- The leader shares a saved plan with the group; it becomes their own active plan too.
function CC:SharePlan(name)
    local plan = self.db.plans[name]
    if type(plan) ~= "table" then return false end
    if not self:CanSharePlan() then
        print("|cFF54a3ffCDC|r " .. L["Only the group's leader or a raid assist can share a plan."])
        return false
    end
    local data = self:EncodePlan(name, plan)
    local parts = math.ceil(#data / CHUNK)
    if parts > MAX_PARTS then
        print("|cFF54a3ffCDC|r " .. L["That plan is too long to share."])
        return false
    end
    local id = PlanID(name)
    for i = 1, parts do
        local text = string.format("P:2:%s:%d/%d:%s", id, i, parts, data:sub((i - 1) * CHUNK + 1, i * CHUNK))
        self:QueueSend(self.PREFIX, text, { kind = "plan" })
    end
    self.db.activePlan = name
    return true
end

-- Plans the sync lane has put together (CC.payloads.P, Comms.lua): one from our
-- group's leader or an assist is kept and becomes the active plan. Each is taken once.
local taken = {}   -- sender \t id -> the arrival time we took
function CC:TakeSharedPlans()
    local byOwner = self.payloads and self.payloads.P
    if not byOwner then return end
    for owner, byId in pairs(byOwner) do
        for id, payload in pairs(byId) do
            local key = owner .. "\t" .. id
            if taken[key] ~= payload.at then
                taken[key] = payload.at
                local unit = self:UnitTokenFor(owner)
                local name, plan = self:DecodePlan(payload.data)
                if name and plan and unit and Leads(unit) then
                    plan.from, plan.at = owner, time()
                    self.db.plans[name] = plan
                    self.db.activePlan = name
                    print(string.format("|cFF54a3ffCDC|r " .. L["%s shared the raid plan \"%s\" (%d rows)."],
                        self:ShortName(owner), name, #plan.rows))
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Rows coming up in a fight
-------------------------------------------------------------------------------

local function ActiveRows()
    local plans, active = CC.db and CC.db.plans, CC.db and CC.db.activePlan
    local plan = plans and active and plans[active]
    return type(plan) == "table" and plan.rows or {}
end

local function Norm(s)
    return (s:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Big Wave" matches the bar "Big Wave (3)"; "Big Wave (3)" only that bar.
local function TimerMatches(rowText, barText)
    local a, b = Norm(rowText), Norm(barText)
    return a == b or (b:gsub("%s*%(%d+%)$", "")) == a
end

local function SamePlayer(planned, name)
    if type(planned) ~= "string" or type(name) ~= "string" then return false end
    if planned == name then return true end
    return not planned:find("-", 1, true) and CC:ShortName(name) == planned
end

-- A boss-mod bar started: a pull timer sets the next hit; a row hung on this
-- timer is coming up. Every read of the bar is in the pcall (it can be hidden).
function CC:OnBossBar(source, key, text, duration, barType)
    local ok, isPull, length, matched, bar = pcall(function()
        if not (duration > 0) then return nil end
        local pull = (key == "pull") or (barType == "pull") or (type(text) == "string" and Norm(text):match("^pull") ~= nil)
        pull = pull and true or false
        local rows = {}
        if not pull and type(text) == "string" then
            for i, row in ipairs(ActiveRows()) do
                if row.timer and TimerMatches(row.timer, text) then rows[#rows + 1] = i end
            end
        end
        return pull, duration + 0, rows, source .. "\t" .. tostring(key)
    end)
    if not ok or isPull == nil then return end
    if isPull then
        self:OnPullTimer(length)
        self.pullBar = bar
        return
    end
    local now, rows = GetTime(), ActiveRows()
    for _, i in ipairs(matched or {}) do
        local row = rows[i]
        self.planPending["t" .. i] = { row = row, due = now + length, length = length, label = row.timer, bar = bar }
    end
end

-- A boss-mod bar stopped (BigWigs names it by its text, DBM by its id); key nil: all of that
-- mod's. A hidden name matches nothing (the whole match is in the pcall).
function CC:OnBossBarStop(source, key)
    local ok, pullStopped = pcall(function()
        local bar = key ~= nil and (source .. "\t" .. tostring(key)) or false
        local mine = source .. "\t"
        local function hit(b) return (bar and b == bar) or (not bar and b:sub(1, #mine) == mine) end
        for k, p in pairs(self.planPending) do
            if p.bar and hit(p.bar) then self.planPending[k] = nil end
        end
        return self.pullBar ~= nil and hit(self.pullBar) and true or false
    end)
    if ok and pullStopped then self:OnPullCancel() end
end

-- The rows at a time into the fight, counted from `start` (the pull, or the encounter's start).
local function ArmTimeRows(start)
    for k, p in pairs(CC.planPending) do
        if not p.bar then CC.planPending[k] = nil end
    end
    for i, row in ipairs(ActiveRows()) do
        if row.at then
            CC.planPending["a" .. i] = { row = row, due = start + row.at, length = math.max(row.at, 1),
                label = CC:LookClock(row.at) }
        end
    end
end

-- A pull countdown (the game's, BigWigs' or DBM's): the next hit is the pull.
function CC:OnPullTimer(seconds)
    local ok, plain = pcall(function() return seconds > 0 and seconds + 0 or nil end)
    if not ok or not plain then return end
    self.pullBar = nil
    self:SetNextHit(plain, "pull")
    ArmTimeRows(GetTime() + plain)
end

function CC:OnPullCancel()
    self.pullBar = nil
    self:ClearPullHit()
    if not self.inEncounter then
        for k, p in pairs(self.planPending) do
            if not p.bar then self.planPending[k] = nil end
        end
    end
end

function CC:OnPlanEncounter(started)
    if started then
        ArmTimeRows(GetTime())
    else
        wipe(self.planPending)
    end
end

-- Is a planned use of this spell coming up that it won't be back for? Returns
-- late (true / false) and the seconds to that use. For the main panel (UI.lua).
function CC:PlannedSpellLate(owner, spellID)
    local now, base = GetTime(), self:BaseSpellID(spellID)
    local soonest
    for _, p in pairs(self.planPending) do
        local row = p.row
        if p.due > now and self:BaseSpellID(row.spellID) == base and SamePlayer(row.player, owner) then
            if not soonest or p.due < soonest.due then soonest = p end
        end
    end
    if not soonest then return false end
    local remaining
    if owner == self:FullName("player") then remaining = self:GetLocalReadiness(base) end
    if remaining == nil then remaining = self:GetRemaining(owner, base) or 0 end
    return remaining > soonest.due - now, soonest.due - now
end

-------------------------------------------------------------------------------
-- The prompt bar: the assigned player's own rows, the last planLead seconds
-------------------------------------------------------------------------------

local function NewBar(holder, i)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * (BAR_H + 4))
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.24, 0.44, 0.82)
    local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0, 0, 0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(BAR_H, BAR_H)
    icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    left:SetPoint("LEFT", bar, "LEFT", 5, 0)
    left:SetPoint("RIGHT", bar, "RIGHT", -40, 0)
    left:SetJustifyH("LEFT")
    left:SetWordWrap(false)
    local right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    right:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    bar.icon, bar.left, bar.right = icon, left, right
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not CC.db.laneLocked then holder:StartMoving() end
    end)
    bar:SetScript("OnMouseUp", function()
        holder:StopMovingOrSizing()
        local x, y = holder:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then CC.db.planBarX, CC.db.planBarY = x - ux, y - uy end
    end)
    bar:Hide()
    return bar
end

function CC:BuildPlanBar()
    local db = self.db
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(BAR_W, BAR_H)
    holder:SetPoint("CENTER", UIParent, "CENTER", db.planBarX or 0, db.planBarY or 160)
    holder:SetFrameStrata("HIGH")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    self.planHolder = holder
    self.planBars = {}
    for i = 1, MAX_BARS do self.planBars[i] = NewBar(holder, i) end
end

-- The prompts showing now: our own rows within planLead seconds of their use, soonest first.
function CC:PlanPrompts()
    local now, me = GetTime(), self:FullName("player")
    local lead = tonumber(self.db.planLead) or 5
    local list = {}
    for _, p in pairs(self.planPending) do
        local left = p.due - now
        if left > 0 and left <= lead and SamePlayer(p.row.player, me) then list[#list + 1] = p end
    end
    table.sort(list, function(a, b) return a.due < b.due end)
    return list
end

function CC:RefreshPlanBars()
    if not self.planBars then return end
    local now = GetTime()
    local list = self:PlanPrompts()
    for i, bar in ipairs(self.planBars) do
        local p = list[i]
        if p then
            local data = CC.SpellData[p.row.spellID]
            local left = p.due - now
            bar.icon:SetTexture(data and data.icon or 134400)
            bar.left:SetText(string.format("%s: %s", data and data.name or string.format(L["Spell %d"], p.row.spellID), p.label))
            bar.right:SetText(self:LookClock(math.ceil(left)))
            bar:SetMinMaxValues(0, p.length)
            bar:SetValue(math.min(left, p.length))
            bar:Show()
        else
            bar:Hide()
        end
    end
    self.planBarsShown = #list > 0
end

-- 10 times a second: forget the rows whose time has come, show the prompts, and
-- (once a second) take any plan the group's leader shared.
local lastTake = 0
function CC:PlanTick()
    local now = GetTime()
    for k, p in pairs(self.planPending) do
        if p.due <= now then self.planPending[k] = nil end
    end
    if now - lastTake >= 1 then
        lastTake = now
        self:TakeSharedPlans()
    end
    if next(self.planPending) or self.planBarsShown then self:RefreshPlanBars() end
end

-------------------------------------------------------------------------------
-- Hooks: encounters, the game's countdown, BigWigs and DBM (each only if there)
-------------------------------------------------------------------------------

local hooks = CreateFrame("Frame")
CC.planHooks = hooks

function CC:HookBossMods()
    if self.bossModsHooked then return end
    self.bossModsHooked = true
    local bw = _G["BigWigsLoader"]
    if type(bw) == "table" and type(bw.RegisterMessage) == "function" then
        -- BigWigsLoader.RegisterMessage(owner, message, func): func(message, ...)
        -- BigWigs_StartBar: module, key, text, duration, icon; its StopBar names a bar by text
        pcall(bw.RegisterMessage, hooks, "BigWigs_StartBar", function(_, _, _, text, duration)
            CC:OnBossBar("bw", text, text, duration, nil)
        end)
        pcall(bw.RegisterMessage, hooks, "BigWigs_StopBar", function(_, _, text) CC:OnBossBarStop("bw", text) end)
        pcall(bw.RegisterMessage, hooks, "BigWigs_StopBars", function() CC:OnBossBarStop("bw", nil) end)
        pcall(bw.RegisterMessage, hooks, "BigWigs_OnBossDisable", function() CC:OnBossBarStop("bw", nil) end)
        pcall(bw.RegisterMessage, hooks, "BigWigs_StartPull", function(_, _, seconds) CC:OnPullTimer(seconds) end)
        pcall(bw.RegisterMessage, hooks, "BigWigs_StopPull", function() CC:OnPullCancel() end)
    end
    local dbm = _G["DBM"]
    if type(dbm) == "table" and type(dbm.RegisterCallback) == "function" then
        -- DBM:RegisterCallback(event, func): func(event, id, text, duration, icon, barType, ...)
        pcall(dbm.RegisterCallback, dbm, "DBM_TimerStart", function(_, id, text, duration, _, barType)
            CC:OnBossBar("dbm", id, text, duration, barType)
        end)
        pcall(dbm.RegisterCallback, dbm, "DBM_TimerStop", function(_, id) CC:OnBossBarStop("dbm", id) end)
    end
end

hooks:RegisterEvent("PLAYER_LOGIN")
hooks:RegisterEvent("ENCOUNTER_START")
hooks:RegisterEvent("ENCOUNTER_END")
hooks:RegisterEvent("START_PLAYER_COUNTDOWN")
hooks:RegisterEvent("CANCEL_PLAYER_COUNTDOWN")
hooks:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        -- every addon that loads at login is in by now
        CC:HookBossMods()
        C_Timer.NewTicker(0.1, function() CC:RefreshView("PlanTick") end)
    elseif event == "ENCOUNTER_START" then
        CC:OnPlanEncounter(true)
    elseif event == "ENCOUNTER_END" then
        CC:OnPlanEncounter(false)
    elseif event == "START_PLAYER_COUNTDOWN" then
        -- initiatedBy, timeRemaining, totalTime, ...
        local _, timeRemaining = ...
        CC:OnPullTimer(timeRemaining)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        CC:OnPullCancel()
    end
end)
