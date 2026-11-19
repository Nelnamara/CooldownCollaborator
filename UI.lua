-- The main panel (the owner's look picks, 19 Nov 2026: "Running first" with
-- "Two columns"). Running cooldowns come first, soonest at the top; ready ones
-- fold into one line per spell with their owners and a count; one column in a
-- party, two from 10 players; 28 lines (or cells), then "+N more". A spell with
-- a rotation order (CC.rotations) shows its rows first, numbered, the next ready
-- one reading NEXT. A ready cooldown whose owner is dead or offline is greyed
-- with DEAD or OFFLINE where its timer would be. db.panelStyle = "icons" shows a
-- row of spell icons instead. Flask and food live on the Essentials bar, never
-- here (R2). The close button keeps the panel shut until /cdc or the minimap
-- opens it again (R19). Team tabs (db.teams) narrow it to one team; with guild
-- sharing on, a Guild tab lists guildmates outside the group (Comms.lua).

local FRAME_WIDTH  = 320
local WIDE_WIDTH   = 380   -- two columns
local WIDE_FROM    = 10    -- a group this big gets two columns
local TITLE_HEIGHT = 20
local TAB_HEIGHT   = 16
local ROW_HEIGHT   = 28    -- one column: a running cooldown
local CELL_HEIGHT  = 22    -- two columns: one cell
local FOLD_HEIGHT  = 20    -- one column: a folded ready line
local HEAD_HEIGHT  = 17    -- the "Ready" heading
local MORE_HEIGHT  = 20
local EMPTY_HEIGHT = 46
local PADDING      = 6
local COLUMN_GAP   = 6
local MAX_LINES    = 28    -- lines or cells before "+N more"
local POOL         = MAX_LINES + 2   -- plus the heading and the "+N more" line
local ICON_SIZE    = 26    -- the icon style
local ICON_GAP     = 5
local MAX_ICONS    = 30
local FLASH_TIME   = 1.2   -- a ready flash: two green pulses

local GREEN = { 0.30, 1.00, 0.30 }
local SOON  = { 1.00, 0.80, 0.00 }
local RED   = { 1.00, 0.30, 0.30 }
local GOLD  = { 1.00, 0.82, 0.00 }
local GREY  = { 0.48, 0.48, 0.48 }
local SPELL = { 0.85, 0.85, 0.85 }
local MUTED = { 0.70, 0.70, 0.70 }
local HEAD  = { 0.60, 0.80, 1.00 }
local DOT_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- "1:12", "41s", or READY for nothing left (also used by Tooltip.lua and Alerts.lua)
function CC:FormatTime(secs)
    if not secs or secs <= 0 then return "READY" end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    if m > 0 then return string.format("%d:%02d", m, s) end
    return string.format("%ds", s)
end

local function Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

local function ClassColor(classTag)
    return CC.ClassColors[classTag or "UNKNOWN"] or CC.ClassColors.UNKNOWN
end

local function TimeColor(remaining)
    if remaining < 30 then return SOON end
    return RED
end

-------------------------------------------------------------------------------
-- Who runs it, guesses, dead and offline owners
-------------------------------------------------------------------------------

-- "ok" (this version, or us), "old" (an older version or a 1.x copy), or nil
-- (no copy heard from them).
function CC:VersionMark(name)
    if name == self:FullName("player") then return "ok" end
    local peer = self.peers and self.peers[name]
    if not peer then return nil end
    if peer.proto == 1 or self:IsOlderVersion(peer.version) then return "old" end
    return "ok"
end

-- The small dot by a name: green for the current version, amber for an old one.
local function Dot(mark)
    if mark == "ok" then return "|T" .. DOT_TEXTURE .. ":6:6:2:1:64:64:0:64:0:64:77:255:77|t" end
    if mark == "old" then return "|T" .. DOT_TEXTURE .. ":6:6:2:1:64:64:0:64:0:64:255:153:0|t" end
    return ""
end
function CC:VersionDot(name) return Dot(self:VersionMark(name)) end

-- A ready cooldown that nobody confirmed (P44): not ours, the owner's copy sent
-- no format 2 hello, and either no cast of theirs was ever seen, or the timer we
-- hold came from the combat log or from before a /reload and ran out by its
-- base length. "Ready as far as we know."
function CC:IsGuessedReady(name, spellID)
    if name == self:FullName("player") then return false end
    local peer = self.peers and self.peers[name]
    if peer and (peer.proto or 0) >= 2 then return false end
    local entry = self.state[name]
    if not entry or not entry.spells[spellID] then return true end
    return ((entry.log and entry.log[spellID]) or (entry.restored and entry.restored[spellID])) and true or false
end

-- name -> unit token for everyone in the group (one pass per refresh)
local function GroupUnits()
    local map = {}
    local function add(unit)
        local name = CC:FullName(unit)
        if name and not map[name] then map[name] = unit end
    end
    add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do add("party" .. i) end
    end
    return map
end

-- "DEAD", "OFFLINE" or nil for a unit (an answer that can't be read counts as fine).
local function UnitMark(unit)
    if not unit then return nil end
    local okC, connected = pcall(function() return UnitIsConnected(unit) and true or false end)
    if okC and not connected then return "OFFLINE" end
    local okD, dead = pcall(function() return UnitIsDeadOrGhost(unit) and true or false end)
    if okD and dead then return "DEAD" end
    return nil
end

function CC:OwnerState(name)
    return UnitMark(self:UnitTokenFor(name))
end

-------------------------------------------------------------------------------
-- Teams (P43) and tabs
-------------------------------------------------------------------------------

-- Saved teams' names, A to Z (db.teams = { [team] = { "Name-Realm" or "Name", ... } }).
function CC:TeamNames()
    local names = {}
    for name, members in pairs(self.db.teams or {}) do
        if type(name) == "string" and type(members) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

-- The chosen tab: "all", "guild" (guild sharing on) or "team:<name>" (a saved team).
function CC:PanelTab()
    local tab = self.db.panelTab
    if tab == "guild" and self.db.guildSync then return "guild" end
    local team = type(tab) == "string" and tab:match("^team:(.+)$")
    if team and type((self.db.teams or {})[team]) == "table" then return tab end
    return "all"
end

function CC:SetPanelTab(tab)
    self.db.panelTab = tab
    self:RefreshRows()
end

-- The names the panel lists: the group, or the chosen team's members in it.
function CC:PanelMembers()
    local names = self:GetActiveGroupNames()
    local team = self:PanelTab():match("^team:(.+)$")
    local members = team and self.db.teams[team]
    if not members then return names end
    local want = {}
    for _, who in ipairs(members) do
        if type(who) == "string" then want[who] = true end
    end
    local out = {}
    for name in pairs(names) do
        if want[name] or want[self:ShortName(name)] then out[name] = true end
    end
    return out
end

-------------------------------------------------------------------------------
-- Rotation orders (P39): CC.rotations[spellID] = { "Name-Realm", ... }. Our own
-- (set from Settings: CC:SetRotation) are saved in db.rotations and shared with
-- the group while we lead it or assist; the leader's or an assistant's reach us
-- as P:2:rot-<spellID>:<part>/<parts>:<data> (Comms.lua keeps the whole text in
-- CC.payloads.P), with data "1;s=<spellID>;o=<name>,<name>,...", names escaped
-- (%XX for % : ; , =). An empty order clears it.
-------------------------------------------------------------------------------

CC.rotations = CC.rotations or {}
local rotationAt = {}   -- spellID -> GetTime() the order we hold was set or heard

local function Escape(s)
    return (s:gsub("[%%:;,=]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function CC:EncodeRotation(spellID, names)
    local list = {}
    for _, name in ipairs(names or {}) do list[#list + 1] = Escape(name) end
    return string.format("1;s=%d;o=%s", spellID, table.concat(list, ","))
end

-- spellID, names (a list, maybe empty), or nil when it isn't a rotation.
function CC:DecodeRotation(data)
    if type(data) ~= "string" then return nil end
    local version, rest = data:match("^(%d+);(.*)$")
    if version ~= "1" then return nil end
    local fields = {}
    for pair in rest:gmatch("[^;]+") do
        local k, v = pair:match("^(%w+)=(.*)$")
        if k then fields[k] = v end
    end
    local spellID = tonumber(fields.s)
    if not spellID or not fields.o then return nil end
    local names = {}
    for item in fields.o:gmatch("[^,]+") do names[#names + 1] = Unescape(item) end
    return spellID, names
end

-- May this group member's word set an order? The party leader, or a raid's leader or assistant.
function CC:CanShareRotation(name)
    local unit = self:UnitTokenFor(name)
    if not unit then return false end
    local ok, yes = pcall(function()
        return UnitIsGroupLeader(unit) or (IsInRaid() and UnitIsGroupAssistant(unit)) or false
    end)
    return ok and yes == true
end

-- The Settings lane's call: our own order for a spell (an empty list clears it).
function CC:SetRotation(spellID, names)
    spellID = tonumber(spellID)
    if not spellID then return end
    local list = {}
    for _, name in ipairs(names or {}) do
        if type(name) == "string" and name ~= "" then list[#list + 1] = name end
    end
    self.db.rotations = self.db.rotations or {}
    self.db.rotations[spellID] = #list > 0 and list or nil
    self.rotations[spellID] = #list > 0 and list or nil
    rotationAt[spellID] = GetTime()
    if self:GroupChannel() and self:CanShareRotation(self:FullName("player")) then self:SendRotation(spellID) end
    self:RefreshRows()
end

-- Our order for a spell to the group, in parts of at most 200 characters.
function CC:SendRotation(spellID)
    local data = self:EncodeRotation(spellID, self.rotations[spellID] or {})
    local parts = {}
    for i = 1, #data, 200 do parts[#parts + 1] = data:sub(i, i + 199) end
    for i, part in ipairs(parts) do
        self:QueueSend(self.PREFIX, string.format("P:2:rot-%d:%d/%d:%s", spellID, i, #parts, part), { kind = "plan" })
    end
end

-- The orders the group's leader or an assistant shared, newest first.
function CC:ReadSharedRotations()
    for sender, byID in pairs(self.payloads and self.payloads.P or {}) do
        for id, payload in pairs(byID) do
            local idSpell = tonumber(type(id) == "string" and id:match("^rot%-(%d+)$"))
            if idSpell and payload.at > (rotationAt[idSpell] or -math.huge) and self:CanShareRotation(sender) then
                local spellID, names = self:DecodeRotation(payload.data)
                if spellID == idSpell and names then
                    self.rotations[idSpell] = #names > 0 and names or nil
                    rotationAt[idSpell] = payload.at
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- What the panel shows
-------------------------------------------------------------------------------

-- A tracked spell this panel lists: never flask or food (the Essentials bar has
-- them, R2), nor a spell unticked in Settings or shorter than the minimum.
function CC:PanelShowsSpell(spellID, data)
    data = data or CC.SpellData[spellID]
    if not data or data.consumable then return false end
    if data.duration < (self.db.minDuration or 60) then return false end
    return not (self.db.disabledSpells and self.db.disabledSpells[spellID])
end

-- Every tracked cooldown someone the panel lists has used:
-- { name, class, spellID, data, remaining, usedAt }, running first (soonest at
-- the top), then ready ones by spell and owner. Ready ones only with Show
-- ready cooldowns on; the second value counts the ones that setting hid.
function CC:BuildRowData()
    local rows, hiddenReady = {}, 0
    local now = GetTime()
    for name in pairs(self:PanelMembers()) do
        local entry = self.state[name]
        if entry then
            for spellID, usedAt in pairs(entry.spells) do
                local data = CC.SpellData[spellID]
                if self:PanelShowsSpell(spellID, data) then
                    local remaining = (usedAt + data.duration) - now
                    -- a spell marked ready can come back a hair above 0 (GetRemaining's rule)
                    if remaining <= 0.001 then remaining = 0 end
                    if remaining > 0 or self.db.showReady then
                        rows[#rows + 1] = { name = name, class = entry.class, spellID = spellID, data = data,
                            remaining = remaining, usedAt = usedAt }
                    else
                        hiddenReady = hiddenReady + 1
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if (a.remaining > 0) ~= (b.remaining > 0) then return a.remaining > 0 end
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        if a.data.name ~= b.data.name then return a.data.name < b.data.name end
        return a.name < b.name
    end)
    return rows, hiddenReady
end

-- The effect still running on a cooldown just used (an external's or a raid
-- defensive's `effect`), in seconds, or nil.
local function EffectLeft(data, usedAt, now)
    if not data.effect or not usedAt then return nil end
    local left = data.effect - (now - usedAt)
    if left > 0 then return left end
    return nil
end

-- The panel's sections:
--   rotation = rows of spells with an order, in place order (place, next)
--   running  = rows still cooling, soonest first (effectLeft while the effect runs)
--   folded   = { spellID, data, owners = { { name, class, guessed } }, count }, one per ready spell
--   greyed   = ready rows whose owner is dead or offline (state = "DEAD" / "OFFLINE")
--   wide     = two columns
function CC:BuildPanelData()
    self:ReadSharedRotations()
    local now = GetTime()
    local units = GroupUnits()
    local members = self:PanelMembers()
    local out = { rotation = {}, running = {}, folded = {}, greyed = {},
        wide = (GetNumGroupMembers() or 0) >= WIDE_FROM }
    local rows, hiddenReady = self:BuildRowData()
    out.hiddenReady = hiddenReady
    out.any = #rows > 0

    -- rotation spells, A to Z by spell name
    local taken = {}
    local spells = {}
    for spellID, order in pairs(self.rotations) do
        if type(order) == "table" and #order > 0 and self:PanelShowsSpell(spellID) then spells[#spells + 1] = spellID end
    end
    table.sort(spells, function(a, b) return CC.SpellData[a].name < CC.SpellData[b].name end)
    for _, spellID in ipairs(spells) do
        local data = CC.SpellData[spellID]
        local nextFound = false
        for place, who in ipairs(self.rotations[spellID]) do
            local name = self:MemberByName(who)
            if name and members[name] and not taken[name .. "\t" .. spellID] then
                taken[name .. "\t" .. spellID] = true
                local entry = self.state[name]
                local usedAt = entry and entry.spells[spellID]
                local remaining = self:GetRemaining(name, spellID) or 0
                local class = entry and entry.class
                if not class or class == "UNKNOWN" then
                    local _, classTag = UnitClass(units[name] or "none")
                    class = classTag or "UNKNOWN"
                end
                local row = { name = name, class = class, spellID = spellID, data = data, remaining = remaining,
                    usedAt = usedAt, place = place, state = UnitMark(units[name]),
                    effectLeft = remaining > 0 and EffectLeft(data, usedAt, now) or nil }
                if remaining <= 0 then
                    row.guessed = self:IsGuessedReady(name, spellID)
                    if not nextFound and not row.state then
                        row.next = true
                        nextFound = true
                    end
                end
                out.rotation[#out.rotation + 1] = row
                out.any = true
            end
        end
    end

    local foldedBy = {}
    for _, row in ipairs(rows) do
        if not taken[row.name .. "\t" .. row.spellID] then
            row.state = UnitMark(units[row.name])
            if row.remaining > 0 then
                row.effectLeft = EffectLeft(row.data, row.usedAt, now)
                out.running[#out.running + 1] = row
            elseif row.state then
                out.greyed[#out.greyed + 1] = row
            else
                local fold = foldedBy[row.spellID]
                if not fold then
                    fold = { spellID = row.spellID, data = row.data, owners = {}, remaining = 0 }
                    foldedBy[row.spellID] = fold
                    out.folded[#out.folded + 1] = fold
                end
                fold.owners[#fold.owners + 1] = { name = row.name, class = row.class,
                    guessed = self:IsGuessedReady(row.name, row.spellID) }
                fold.count = #fold.owners
            end
        end
    end
    return out
end

-- Why the panel is empty (P13): nobody else runs it, or nothing was used yet.
function CC:PanelEmptyText(data)
    if data and data.hiddenReady and data.hiddenReady > 0 then
        return "Nothing is cooling down. Ready cooldowns are hidden (Settings: Show ready cooldowns)."
    end
    if self:PanelTab():match("^team:") then
        return "Nobody on this team has used a tracked cooldown yet."
    end
    if not IsInGroup() then
        return "Nothing used yet. Your own cooldowns show here once you use one; in a group, everyone's do."
    end
    local me = self:FullName("player")
    local total, runners = 0, {}
    for name in pairs(self:GetActiveGroupNames()) do
        total = total + 1
        if name ~= me and self.peers[name] then runners[#runners + 1] = self:ShortName(name) end
    end
    table.sort(runners)
    if #runners == 0 then
        if self.retailAPI then
            return "Nobody else here runs CooldownCollaborator, so only your own cooldowns can show. Nothing has been used yet."
        end
        return "Nobody else here runs CooldownCollaborator; casts seen in the combat log still show. Nothing has been used yet."
    end
    local who = ""
    if #runners <= 3 then
        who = " (" .. table.concat(runners, ", ") .. " and you)"
    end
    return string.format("%d of %d here run CooldownCollaborator%s. Nothing has been used yet; cooldowns show once someone uses one.",
        #runners + 1, total, who)
end

-- The soonest lust (P26) on a client that has lust: ready first, a dead or
-- offline holder skipped; nil when nobody here can lust.
function CC:NextLust()
    if not (CC.CAPABILITIES and CC.CAPABILITIES.BLOODLUST) then return nil end
    local best
    for _, s in ipairs(self:GetCapabilityStatus("BLOODLUST")) do
        if s.online ~= false and s.alive ~= false then
            if s.ready then return s end
            if not best or s.remaining < best.remaining then best = s end
        end
    end
    return best
end

-- "Lust Ashka READY" / "Lust Ravelle 2:10" for the title bar
function CC:NextLustText()
    local s = self:NextLust()
    if not s then return "" end
    local c = ClassColor(s.class)
    local when
    if s.ready then
        when = Hex(GREEN) .. "READY|r" .. (s.guessed and (Hex(SOON) .. "?|r") or "")
    else
        when = Hex(RED) .. self:FormatTime(s.remaining) .. "|r"
    end
    return Hex(HEAD) .. "Lust|r " .. Hex(c) .. self:ShortName(s.name) .. "|r " .. when
end

-- "4 of 5": how many in the group run it (us included), in a group
function CC:RunsCountText()
    local me = self:FullName("player")
    local total, runs = 0, 0
    for name in pairs(self:GetActiveGroupNames()) do
        total = total + 1
        if name == me or self.peers[name] then runs = runs + 1 end
    end
    if total <= 1 then return "" end
    return string.format("%d of %d", runs, total)
end

-------------------------------------------------------------------------------
-- Opening and closing (R19)
-------------------------------------------------------------------------------

-- Closed with its button, /cdc or the minimap: it stays shut through casts,
-- syncs and roster changes until /cdc or the minimap opens it again.
function CC:ClosePanel()
    self.db.panelClosed = true
    if self.frame then self.frame:Hide() end
end

function CC:OpenPanel()
    self.db.panelClosed = false
    if not self.frame then return end
    self.frame:Show()
    self:RefreshRows()
end

function CC:TogglePanel()
    if self.frame and self.frame:IsShown() then
        self:ClosePanel()
    else
        self:OpenPanel()
    end
end

-------------------------------------------------------------------------------
-- Asking for a cooldown (P8): a click on a ready line whispers its owner, a
-- Shift-click asks in the group's channel. Only from a click, never on our own
-- spell or a dead or offline owner's.
-------------------------------------------------------------------------------

-- Every client has C_ChatInfo.SendChatMessage; the bare global is a deprecation fallback.
local function SendChatLine(msg, chatType, target)
    ---@diagnostic disable-next-line: deprecated
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    local ok = pcall(send, msg, chatType, nil, target)
    if not ok then print("|cFF54a3ffCDC|r The game didn't let that message go out just now.") end
    return ok
end

-- Whom a line's ask goes to, or nil: a ready cooldown's live owner who isn't us.
function CC:AskTarget(info)
    if not info then return nil end
    local me = self:FullName("player")
    if info.owners then
        for _, owner in ipairs(info.owners) do
            if owner.name ~= me then return owner.name end
        end
        return nil
    end
    if (info.remaining or 0) > 0 or info.state or info.name == me then return nil end
    return info.name
end

function CC:AskForCooldown(info, toGroup)
    local owner = self:AskTarget(info)
    local data = owner and CC.SpellData[info.spellID]
    if not data then return false end
    if toGroup then
        local channel = self:GroupChannel()
        if not channel then return false end
        return SendChatLine(string.format("%s, %s on me please", self:ShortName(owner), data.name), channel)
    end
    return SendChatLine(string.format("%s on me please", data.name), "WHISPER", owner)
end

-------------------------------------------------------------------------------
-- Building the window
-------------------------------------------------------------------------------

-- A panel line drags the panel and, on a click (the cursor hardly moved), asks.
local function HookDragAndClick(widget)
    widget:EnableMouse(true)
    widget:SetScript("OnMouseDown", function(w, btn)
        w.downX, w.downY = GetCursorPosition()
        if btn == "LeftButton" and not CC.db.locked then
            CC.frame:StartMoving()
            w.moving = true
        end
    end)
    widget:SetScript("OnMouseUp", function(w, btn)
        if w.moving then
            CC.frame:StopMovingOrSizing()
            CC:SavePosition()
            w.moving = false
        end
        local x, y = GetCursorPosition()
        if btn == "LeftButton" and w.downX and math.abs((x or 0) - w.downX) + math.abs((y or 0) - (w.downY or 0)) < 5 then
            CC:AskForCooldown(w.info, IsShiftKeyDown and IsShiftKeyDown())
        end
    end)
end

local function ShowTooltipFor(widget)
    local info = widget.info
    if not info or not CC.ShowCooldownTooltip then return end
    local owner = info.name
    if info.owners then
        owner = {}
        for _, o in ipairs(info.owners) do owner[#owner + 1] = o.name end
    end
    local hint = CC:AskTarget(info) and "Click: whisper to ask for it. Shift-click: ask in group chat." or nil
    CC:ShowCooldownTooltip(widget, owner, info.spellID, hint)
end

local function NewLine(parent)
    local line = CreateFrame("Frame", nil, parent)

    local flash = line:CreateTexture(nil, "BACKGROUND")
    flash:SetAllPoints()
    flash:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.32)
    flash:Hide()
    line.flash = flash

    local bar = line:CreateTexture(nil, "BORDER")
    line.classBar = bar

    local icon = line:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.icon = icon

    -- a rotation place: a small box with the number (gold for NEXT)
    local badge = line:CreateTexture(nil, "ARTWORK")
    badge:SetSize(14, 13)
    line.badge = badge
    local badgeText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeText:SetTextColor(0, 0, 0)
    line.badgeText = badgeText

    local nameText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    line.nameText = nameText

    local spellText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellText:SetJustifyH("LEFT")
    spellText:SetWordWrap(false)
    line.spellText = spellText

    local ownersText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ownersText:SetJustifyH("LEFT")
    ownersText:SetWordWrap(false)
    line.ownersText = ownersText

    local timeText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeText:SetJustifyH("RIGHT")
    line.timeText = timeText

    local headText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headText:SetJustifyH("LEFT")
    line.headText = headText

    local divider = line:CreateTexture(nil, "BORDER")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", line, "TOPLEFT", 4, -1)
    divider:SetPoint("TOPRIGHT", line, "TOPRIGHT", -4, -1)
    divider:SetColorTexture(0.3, 0.3, 0.5, 0.6)
    line.divider = divider

    -- the effect bar: a thin gold bar along the foot that drains with the effect
    local fx = CreateFrame("StatusBar", nil, line)
    fx:SetStatusBarTexture(BAR_TEXTURE)
    fx:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 1)
    local track = fx:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    fx:Hide()
    line.fx = fx

    line:SetScript("OnEnter", function(widget)
        widget.classBar:SetColorTexture(1, 1, 1, 0.35)
        ShowTooltipFor(widget)
    end)
    line:SetScript("OnLeave", function(widget)
        local c = widget.barColor or GREY
        widget.classBar:SetColorTexture(c[1], c[2], c[3], 1)
        if CC.HideCooldownTooltip then CC:HideCooldownTooltip() end
    end)
    HookDragAndClick(line)
    line:Hide()
    return line
end

local function NewIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(ICON_SIZE, ICON_SIZE)

    -- ready: a green edge (gold for a rotation's NEXT) round a black ring
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.edge = edge
    local ring = b:CreateTexture(nil, "BORDER")
    ring:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    ring:SetColorTexture(0, 0, 0, 1)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon

    -- the sweep (the game's own cooldown swipe, without its numbers: the time sits on top)
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    b.cd = cd

    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel((cd:GetFrameLevel() or 1) + 2)

    local flash = over:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.45)
    flash:Hide()
    b.flash = flash

    local time = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    time:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.time = time

    local mark = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -1)
    mark:SetTextColor(SOON[1], SOON[2], SOON[3])
    mark:SetText("?")
    b.mark = mark

    -- the owner's class: a dot in the corner
    local dotRing = over:CreateTexture(nil, "ARTWORK")
    dotRing:SetSize(10, 10)
    dotRing:SetPoint("CENTER", b, "TOPRIGHT", -1, -1)
    dotRing:SetTexture(DOT_TEXTURE)
    dotRing:SetVertexColor(0, 0, 0, 1)
    local dot = over:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER", b, "TOPRIGHT", -1, -1)
    dot:SetTexture(DOT_TEXTURE)
    b.dot = dot

    local fx = CreateFrame("StatusBar", nil, b)
    fx:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -3)
    fx:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -3)
    fx:SetHeight(2)
    fx:SetStatusBarTexture(BAR_TEXTURE)
    fx:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 1)
    fx:Hide()
    b.fx = fx

    b:SetScript("OnEnter", function(widget) ShowTooltipFor(widget) end)
    b:SetScript("OnLeave", function() if CC.HideCooldownTooltip then CC:HideCooldownTooltip() end end)
    HookDragAndClick(b)
    b:Hide()
    return b
end

function CC:BuildUI()
    local db = self.db

    local frame = CreateFrame("Frame", "CCMainFrame", UIParent, CC.BackdropTemplate)
    frame:SetSize(FRAME_WIDTH, TITLE_HEIGHT + ROW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 200)
    frame:SetScale(db.scale or 1.0)
    frame:SetAlpha(db.alpha or 0.9)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.88)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.55, 0.85)

    frame:SetScript("OnMouseDown", function(widget, btn)
        if btn == "LeftButton" and not CC.db.locked then
            widget:StartMoving()
        end
    end)
    frame:SetScript("OnMouseUp", function(widget)
        widget:StopMovingOrSizing()
        CC:SavePosition()
    end)

    -- Title bar: who runs it at the left, the name in the middle, the next lust
    -- at the right, then the close button
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetText("|cFF54a3ffCD Collab|r  |cFF888888" .. CC.version .. "|r")
    title:SetJustifyH("CENTER")
    self.titleText = title

    local runs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    runs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
    runs:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    self.runsText = runs

    local lust = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lust:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -5)
    lust:SetJustifyH("RIGHT")
    self.lustText = lust

    -- Post (P38): what is ready for the spells picked in Settings, to the group's chat
    local post = CreateFrame("Button", nil, frame)
    post:SetSize(13, 13)
    post:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -21, -4)
    local postBg = post:CreateTexture(nil, "BACKGROUND")
    postBg:SetAllPoints()
    postBg:SetColorTexture(1, 1, 1, 0.07)
    local postText = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    postText:SetPoint("CENTER", post, "CENTER", 0, 0)
    postText:SetText("P")
    postText:SetTextColor(0.7, 0.7, 0.7)
    post:SetScript("OnEnter", function(widget)
        postText:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(widget, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Post to chat")
        GameTooltip:AddLine("Says what is ready, and who has it, in group chat (the spells picked in Settings).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    post:SetScript("OnLeave", function() postText:SetTextColor(0.7, 0.7, 0.7); GameTooltip:Hide() end)
    post:SetScript("OnClick", function() CC:PostReady() end)
    self.postButton = post

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(13, 13)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -4)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(1, 1, 1, 0.07)
    local closeX = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    closeX:SetPoint("CENTER", close, "CENTER", 0, 1)
    closeX:SetText("\195\151")   -- the multiplication sign
    closeX:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    close:SetScript("OnClick", function() CC:ClosePanel() end)
    close:SetScript("OnEnter", function(widget)
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Close")
        GameTooltip:AddLine("It stays shut until /cdc or the minimap button opens it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.closeButton = close

    -- Divider line under title
    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(TITLE_HEIGHT - 2))
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(TITLE_HEIGHT - 2))
    divider:SetColorTexture(0.3, 0.3, 0.5, 0.6)

    -- Empty state: says why (P13)
    local emptyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetWidth(FRAME_WIDTH - 28)
    emptyLabel:SetWordWrap(true)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetText("Nothing used yet.")
    self.emptyLabel = emptyLabel

    self.rows = {}
    for i = 1, POOL do self.rows[i] = NewLine(frame) end
    self.icons = {}
    for i = 1, MAX_ICONS do self.icons[i] = NewIcon(frame) end
    self.tabs = {}
    for spellID, names in pairs(db.rotations or {}) do
        if type(names) == "table" then self.rotations[spellID] = names end
    end

    frame:Hide()
    self.frame = frame

    -- 0.5s ticker keeps timers refreshed while frame is visible
    C_Timer.NewTicker(CC.TICK_RATES.panel[1], function()
        if CC.frame and CC.frame:IsShown() and CC:TickDue("panel") then
            CC:RefreshRows()
        end
    end)

    self:UpdateLock()
end

-------------------------------------------------------------------------------
-- Tabs: All (or Group), one per saved team, and Guild with guild sharing on
-------------------------------------------------------------------------------

local function TabButton(index)
    local tab = CC.tabs[index]
    if tab then return tab end
    tab = CreateFrame("Button", nil, CC.frame)
    tab:SetHeight(TAB_HEIGHT)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    tab.bg = bg
    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.text = text
    tab:SetScript("OnClick", function(widget) CC:SetPanelTab(widget.key) end)
    CC.tabs[index] = tab
    return tab
end

-- The tabs' height (0 when there are none to pick between).
function CC:LayoutTabs(top)
    local list = {}
    local teams = self:TeamNames()
    if #teams > 0 or self.db.guildSync then
        list[1] = { key = "all", label = #teams > 0 and "All" or "Group" }
        for _, team in ipairs(teams) do list[#list + 1] = { key = "team:" .. team, label = team } end
        if self.db.guildSync then list[#list + 1] = { key = "guild", label = "Guild" } end
    end
    local current = self:PanelTab()
    local x = PADDING
    for i, item in ipairs(list) do
        local tab = TabButton(i)
        tab.key = item.key
        tab.text:SetText(item.label)
        local width = (tab.text:GetStringWidth() or (#item.label * 6)) + 14
        tab:SetWidth(width)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -top)
        x = x + width + 2
        if item.key == current then
            tab.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            tab.bg:SetColorTexture(0.23, 0.23, 0.27, 1)
        else
            tab.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
            tab.bg:SetColorTexture(1, 1, 1, 0.07)
        end
        tab.current = item.key == current
        tab:Show()
    end
    for i = #list + 1, #self.tabs do self.tabs[i]:Hide() end
    return #list > 0 and (TAB_HEIGHT + 3) or 0
end

-------------------------------------------------------------------------------
-- Text lines
-------------------------------------------------------------------------------

-- Anchor a line's parts for its look; done again only when the look changes.
-- looks: "row" (28 px, one column), "cell" (22 px, two columns), "fold" (20 px
-- folded ready line), "foldcell" (22 px), "guild" (22 px), "head", "more".
local function PlaceParts(line, look, width, badge)
    local key = look .. ":" .. width .. (badge and ":b" or "")
    if line.look == key then return end
    line.look = key
    for _, part in ipairs({ line.classBar, line.icon, line.badge, line.nameText, line.spellText, line.ownersText,
        line.timeText, line.headText, line.fx }) do
        part:ClearAllPoints()
    end
    local tall = look == "row" and ROW_HEIGHT or ((look == "fold" or look == "more") and FOLD_HEIGHT) or CELL_HEIGHT
    line.classBar:SetSize(3, tall - 4)
    line.classBar:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.timeText:SetPoint("RIGHT", line, "RIGHT", -2, 0)
    if look == "row" then
        line.icon:SetSize(22, 22)
        line.icon:SetPoint("LEFT", line, "LEFT", 6, 0)
        line.badge:SetPoint("LEFT", line, "LEFT", 32, 1)
        line.nameText:SetPoint("LEFT", line, "LEFT", badge and 49 or 32, 1)
        line.nameText:SetWidth(badge and 68 or 85)
        line.spellText:SetPoint("LEFT", line, "LEFT", 119, 1)
        line.spellText:SetWidth(105)
        line.fx:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 32, 2)
        line.fx:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", -2, 2)
        line.fx:SetHeight(3)
    elseif look == "cell" then
        line.icon:SetSize(18, 18)
        line.icon:SetPoint("LEFT", line, "LEFT", 6, 0)
        line.badge:SetPoint("LEFT", line, "LEFT", 28, 0)
        line.nameText:SetPoint("LEFT", line, "LEFT", badge and 45 or 28, 0)
        line.nameText:SetWidth(width - (badge and 45 or 28) - 42)
        line.fx:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 28, 1)
        line.fx:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", -2, 1)
        line.fx:SetHeight(2)
    elseif look == "fold" or look == "foldcell" then
        local cell = look == "foldcell"
        local size = cell and 18 or 16
        line.icon:SetSize(size, size)
        line.icon:SetPoint("LEFT", line, "LEFT", 6, 0)
        local spellX = cell and 28 or 27
        local spellW = cell and math.floor(width * 0.42) or 108
        line.spellText:SetPoint("LEFT", line, "LEFT", spellX, 0)
        line.spellText:SetWidth(spellW)
        line.ownersText:SetPoint("LEFT", line, "LEFT", spellX + spellW + 4, 0)
        line.ownersText:SetWidth(width - (spellX + spellW + 4) - (badge and 50 or 26))
    elseif look == "guild" then
        line.icon:SetSize(18, 18)
        line.icon:SetPoint("LEFT", line, "LEFT", 6, 0)
        line.nameText:SetPoint("LEFT", line, "LEFT", 28, 0)
        line.nameText:SetWidth(80)
        line.spellText:SetPoint("LEFT", line, "LEFT", 111, 0)
        line.spellText:SetWidth(width - 111 - 46)
    elseif look == "head" then
        line.headText:SetPoint("LEFT", line, "LEFT", 4, -1)
    elseif look == "more" then
        line.headText:SetPoint("LEFT", line, "LEFT", 6, 0)
    end
end

-- Hide every part, so each look shows only its own.
local function Clear(line)
    line.classBar:Hide(); line.icon:Hide(); line.badge:Hide(); line.badgeText:Hide()
    line.nameText:Hide(); line.spellText:Hide(); line.ownersText:Hide(); line.timeText:Hide()
    line.headText:Hide(); line.divider:Hide(); line.fx:Hide()
    line.fxEnd = nil
    line.info = nil
    line.flashKeys = nil
    line.greyed = nil
    line.icon:SetDesaturated(false)
    line.icon:SetVertexColor(1, 1, 1)
end

local function SetBar(line, c)
    line.barColor = c
    line.classBar:SetColorTexture(c[1], c[2], c[3], 1)
    line.classBar:Show()
end

local function StartEffect(line, row)
    if not row.effectLeft then return end
    line.fx:SetMinMaxValues(0, row.data.effect)
    line.fx:SetValue(row.effectLeft)
    line.fxEnd = GetTime() + row.effectLeft
    line.fx:Show()
    CC:StartPanelAnimation()
end

-- A running cooldown, a rotation row, or a greyed ready one (dead or offline owner).
local function ShowCooldownRow(line, row, look, width)
    local hasBadge = row.place ~= nil
    PlaceParts(line, look, width, hasBadge)
    Clear(line)
    line.info = row
    line.flashKeys = { [row.name .. "\t" .. row.spellID] = true }
    local greyed = row.state ~= nil and row.remaining <= 0
    line.greyed = greyed
    local c = greyed and GREY or ClassColor(row.class)
    SetBar(line, c)
    line.icon:SetTexture(row.data.icon)
    line.icon:Show()
    if greyed then
        line.icon:SetDesaturated(true)
        line.icon:SetVertexColor(0.55, 0.55, 0.55)
    end
    if hasBadge then
        local badgeColor = row.next and GOLD or { 0.70, 0.70, 0.70 }
        line.badge:SetColorTexture(badgeColor[1], badgeColor[2], badgeColor[3], 1)
        line.badge:Show()
        line.badgeText:SetText(tostring(row.place))
        line.badgeText:Show()
    end
    line.nameText:SetText(CC:ShortName(row.name) .. Dot(CC:VersionMark(row.name)))
    line.nameText:SetTextColor(c[1], c[2], c[3])
    line.nameText:Show()
    if look == "row" then
        line.spellText:SetText(row.data.name)
        local s = greyed and GREY or SPELL
        line.spellText:SetTextColor(s[1], s[2], s[3])
        line.spellText:Show()
    end
    if greyed then
        line.timeText:SetText(row.state)
        line.timeText:SetTextColor(GREY[1], GREY[2], GREY[3])
    elseif row.remaining > 0 then
        local t = TimeColor(row.remaining)
        line.timeText:SetText(CC:FormatTime(row.remaining))
        line.timeText:SetTextColor(t[1], t[2], t[3])
        StartEffect(line, row)
    elseif row.next then
        line.timeText:SetText("NEXT")
        line.timeText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else
        line.timeText:SetText("READY" .. (row.guessed and (Hex(SOON) .. "?|r") or ""))
        line.timeText:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    end
    line.timeText:Show()
end

-- Owners of a folded ready line: class-coloured names with their version dot, "?" when guessed.
local function OwnerList(owners)
    local parts = {}
    for _, o in ipairs(owners) do
        parts[#parts + 1] = Hex(ClassColor(o.class)) .. CC:ShortName(o.name) .. "|r" .. Dot(CC:VersionMark(o.name))
            .. (o.guessed and (Hex(SOON) .. "?|r") or "")
    end
    return table.concat(parts, Hex(MUTED) .. ", |r")
end

-- One line per ready spell: its icon, name, owners and a count; a greyed one
-- (dead or offline owner) shows that owner and DEAD or OFFLINE instead.
local function ShowReadyLine(line, item, look, width)
    local greyed = item.owners == nil
    -- a greyed line leaves room for OFFLINE where the count would be
    PlaceParts(line, look, width, greyed)
    Clear(line)
    line.info = item
    line.barColor = GREY
    line.icon:SetTexture(item.data.icon)
    line.icon:Show()
    line.spellText:SetText(item.data.name)
    line.spellText:Show()
    line.ownersText:Show()
    line.timeText:Show()
    if greyed then
        line.greyed = true
        line.flashKeys = { [item.name .. "\t" .. item.spellID] = true }
        line.icon:SetDesaturated(true)
        line.icon:SetVertexColor(0.55, 0.55, 0.55)
        line.spellText:SetTextColor(GREY[1], GREY[2], GREY[3])
        line.ownersText:SetText(Hex(GREY) .. CC:ShortName(item.name) .. "|r" .. Dot(CC:VersionMark(item.name)))
        line.timeText:SetText(item.state)
        line.timeText:SetTextColor(GREY[1], GREY[2], GREY[3])
        return
    end
    line.flashKeys = {}
    for _, o in ipairs(item.owners) do line.flashKeys[o.name .. "\t" .. item.spellID] = true end
    line.spellText:SetTextColor(SPELL[1], SPELL[2], SPELL[3])
    line.ownersText:SetText(OwnerList(item.owners))
    line.timeText:SetText(item.count > 1 and ("\195\151" .. item.count) or "")
    line.timeText:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
end

local function ShowTextLine(line, look, text, c, width)
    PlaceParts(line, look, width, false)
    Clear(line)
    line.headText:SetText(text)
    line.headText:SetTextColor(c[1], c[2], c[3])
    line.headText:Show()
    if look == "head" then line.divider:Show() end
end

local function Place(line, x, y, w, h)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", CC.frame, "TOPLEFT", x, -y)
    line:SetSize(w, h)
    line:Show()
end

-- "+3 more running, 8 spells ready"
local function MoreText(hiddenRunning, hiddenReady)
    local parts = {}
    if hiddenRunning > 0 then parts[#parts + 1] = string.format("+%d more running", hiddenRunning) end
    if hiddenReady > 0 then
        local what = hiddenReady == 1 and "spell" or "spells"
        parts[#parts + 1] = string.format(#parts == 0 and "+%d more %s ready" or "%d %s ready", hiddenReady, what)
    end
    return table.concat(parts, ", ")
end

function CC:LayoutLines(top, data)
    local width = data.wide and WIDE_WIDTH or FRAME_WIDTH
    self.frame:SetWidth(width)
    local inner = width - PADDING * 2
    local lines = self.rows
    local n = 0
    local function take() n = n + 1; return lines[n] end

    local cooling, ready = {}, {}
    for _, r in ipairs(data.rotation) do cooling[#cooling + 1] = r end
    for _, r in ipairs(data.running) do cooling[#cooling + 1] = r end
    for _, f in ipairs(data.folded) do ready[#ready + 1] = f end
    for _, g in ipairs(data.greyed) do ready[#ready + 1] = g end
    local showCooling = math.min(#cooling, MAX_LINES)
    local showReady = math.min(#ready, MAX_LINES - showCooling)

    local y = top
    if data.wide then
        local cellW = math.floor((inner - COLUMN_GAP) / 2)
        local function cells(list, count, show)
            local perColumn = math.ceil(count / 2)
            for i = 1, count do
                local col = i <= perColumn and 0 or 1
                local idx = col == 0 and (i - 1) or (i - perColumn - 1)
                local line = take()
                show(line, list[i], cellW)
                Place(line, PADDING + col * (cellW + COLUMN_GAP), y + idx * CELL_HEIGHT, cellW, CELL_HEIGHT)
            end
            y = y + perColumn * CELL_HEIGHT
        end
        cells(cooling, showCooling, function(line, row, w) ShowCooldownRow(line, row, "cell", w) end)
        if showReady > 0 then
            local head = take()
            ShowTextLine(head, "head", "Ready", GREEN, inner)
            Place(head, PADDING, y, inner, HEAD_HEIGHT)
            y = y + HEAD_HEIGHT
            cells(ready, showReady, function(line, item, w) ShowReadyLine(line, item, "foldcell", w) end)
        end
    else
        for i = 1, showCooling do
            local line = take()
            ShowCooldownRow(line, cooling[i], "row", inner)
            Place(line, PADDING, y, inner, ROW_HEIGHT)
            y = y + ROW_HEIGHT
        end
        if showReady > 0 then
            local head = take()
            ShowTextLine(head, "head", "Ready", GREEN, inner)
            Place(head, PADDING, y, inner, HEAD_HEIGHT)
            y = y + HEAD_HEIGHT
            for i = 1, showReady do
                local line = take()
                ShowReadyLine(line, ready[i], "fold", inner)
                Place(line, PADDING, y, inner, FOLD_HEIGHT)
                y = y + FOLD_HEIGHT
            end
        end
    end
    local hiddenCooling, hiddenReady = #cooling - showCooling, #ready - showReady
    if hiddenCooling + hiddenReady > 0 then
        local more = take()
        ShowTextLine(more, "more", MoreText(hiddenCooling, hiddenReady), MUTED, inner)
        Place(more, PADDING, y, inner, MORE_HEIGHT)
        y = y + MORE_HEIGHT
    end
    for i = n + 1, #lines do
        lines[i]:Hide()
        lines[i].info = nil
    end
    self.panelShown = { cooling = showCooling, ready = showReady, hiddenCooling = hiddenCooling,
        hiddenReady = hiddenReady, wide = data.wide }
    return y, showCooling + showReady
end

-------------------------------------------------------------------------------
-- The icon style: running first, then ready ones, each its own icon
-------------------------------------------------------------------------------

function CC:LayoutIcons(top, data)
    self.frame:SetWidth(FRAME_WIDTH)
    local list = {}
    for _, r in ipairs(data.rotation) do list[#list + 1] = r end
    for _, r in ipairs(data.running) do list[#list + 1] = r end
    for _, f in ipairs(data.folded) do
        for _, o in ipairs(f.owners) do
            list[#list + 1] = { name = o.name, class = o.class, spellID = f.spellID, data = f.data, remaining = 0,
                guessed = o.guessed }
        end
    end
    for _, g in ipairs(data.greyed) do list[#list + 1] = g end

    local perRow = math.floor((FRAME_WIDTH - PADDING * 2 + ICON_GAP) / (ICON_SIZE + ICON_GAP))
    local show = math.min(#list, MAX_ICONS)
    local now = GetTime()
    for i = 1, show do
        local row = list[i]
        local b = self.icons[i]
        local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PADDING + 2 + col * (ICON_SIZE + ICON_GAP),
            -(top + 4 + line * (ICON_SIZE + ICON_GAP + 2)))
        b.info = row
        b.flashKeys = { [row.name .. "\t" .. row.spellID] = true }
        b.icon:SetTexture(row.data.icon)
        local c = ClassColor(row.class)
        b.dot:SetVertexColor(c[1], c[2], c[3], 1)
        b.mark:SetShown(row.remaining <= 0 and row.guessed == true and not row.state)
        b.fxEnd = nil
        b.fx:Hide()
        if row.remaining > 0 then
            -- cooling: grey, the sweep, the time on top
            b.state = "cool"
            b.edge:Hide()
            b.icon:SetDesaturated(true)
            b.icon:SetVertexColor(0.6, 0.6, 0.6)
            if b.cdStart ~= row.usedAt or b.cdDuration ~= row.data.duration then
                b.cdStart, b.cdDuration = row.usedAt, row.data.duration
                b.cd:SetCooldown(row.usedAt or (now - row.data.duration + row.remaining), row.data.duration)
            end
            b.cd:Show()
            b.time:SetText(self:FormatTime(row.remaining))
            b.time:SetTextColor(1, 1, 1)
            if row.effectLeft then
                b.fx:SetMinMaxValues(0, row.data.effect)
                b.fx:SetValue(row.effectLeft)
                b.fxEnd = now + row.effectLeft
                b.fx:Show()
                self:StartPanelAnimation()
            end
        else
            b.cdStart, b.cdDuration = nil, nil
            b.cd:Hide()
            if row.state then
                b.state = "greyed"
                b.edge:Hide()
                b.icon:SetDesaturated(true)
                b.icon:SetVertexColor(0.45, 0.45, 0.45)
                b.time:SetText(row.state == "DEAD" and "DEAD" or "OFF")
                b.time:SetTextColor(GREY[1], GREY[2], GREY[3])
            else
                -- ready: bright, a green edge (gold for the rotation's NEXT)
                b.state = row.next and "next" or "ready"
                local e = row.next and GOLD or GREEN
                b.edge:SetColorTexture(e[1], e[2], e[3], 1)
                b.edge:Show()
                b.icon:SetDesaturated(false)
                b.icon:SetVertexColor(1, 1, 1)
                b.time:SetText("")
            end
        end
        b:Show()
    end
    for i = show + 1, #self.icons do
        self.icons[i]:Hide()
        self.icons[i].info = nil
    end
    local rowsUsed = math.ceil(show / perRow)
    local y = top + 4 + rowsUsed * (ICON_SIZE + ICON_GAP + 2)
    local lines = self.rows
    local n = 0
    if #list > show then
        n = 1
        ShowTextLine(lines[1], "more", string.format("+%d more", #list - show), MUTED, FRAME_WIDTH - PADDING * 2)
        Place(lines[1], PADDING, y, FRAME_WIDTH - PADDING * 2, MORE_HEIGHT)
        y = y + MORE_HEIGHT
    end
    for i = n + 1, #lines do
        lines[i]:Hide()
        lines[i].info = nil
    end
    self.panelShown = { icons = show, hiddenIcons = #list - show }
    return y, show
end

local function HideIcons()
    for _, b in ipairs(CC.icons) do
        b:Hide()
        b.info = nil
    end
end

-------------------------------------------------------------------------------
-- The Guild tab (P41): guildmates outside the group with guild sharing on,
-- their lust and Battle Rez (Comms.lua: CC:GuildRows)
-------------------------------------------------------------------------------

function CC:LayoutGuild(top)
    self.frame:SetWidth(FRAME_WIDTH)
    local inner = FRAME_WIDTH - PADDING * 2
    local rows, runners = self:GuildRows()
    local lines = self.rows
    local y = top
    local n = 1
    ShowTextLine(lines[1], "head", string.format("Outside your group: %d run it", runners), HEAD, inner)
    lines[1].divider:Hide()
    Place(lines[1], PADDING, y, inner, HEAD_HEIGHT)
    y = y + HEAD_HEIGHT
    local show = math.min(#rows, MAX_LINES)
    for i = 1, show do
        local row = rows[i]
        n = n + 1
        local line = lines[n]
        PlaceParts(line, "guild", inner, false)
        Clear(line)
        line.info = row
        line.flashKeys = {}
        local c = ClassColor(row.class)
        SetBar(line, c)
        line.icon:SetTexture(row.data.icon)
        line.icon:Show()
        line.nameText:SetText(self:ShortName(row.name) .. Dot(row.old and "old" or "ok"))
        line.nameText:SetTextColor(c[1], c[2], c[3])
        line.nameText:Show()
        line.spellText:SetText(row.data.name)
        line.spellText:SetTextColor(SPELL[1], SPELL[2], SPELL[3])
        line.spellText:Show()
        if row.remaining > 0 then
            local t = TimeColor(row.remaining)
            line.timeText:SetText(self:FormatTime(row.remaining))
            line.timeText:SetTextColor(t[1], t[2], t[3])
        else
            line.timeText:SetText("READY")
            line.timeText:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        end
        line.timeText:Show()
        Place(line, PADDING, y, inner, CELL_HEIGHT)
        y = y + CELL_HEIGHT
    end
    if #rows > show then
        n = n + 1
        ShowTextLine(lines[n], "more", string.format("+%d more", #rows - show), MUTED, inner)
        Place(lines[n], PADDING, y, inner, MORE_HEIGHT)
        y = y + MORE_HEIGHT
    end
    for i = n + 1, #lines do
        lines[i]:Hide()
        lines[i].info = nil
    end
    self.panelShown = { guild = show, hiddenGuild = #rows - show }
    return y, show
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

function CC:RefreshRows()
    if not self.frame then return end
    self.runsText:SetText(self:RunsCountText())
    self.lustText:SetText(self:NextLustText())

    local top = TITLE_HEIGHT + self:LayoutTabs(TITLE_HEIGHT + 1)
    local tab = self:PanelTab()
    local y, shown, data
    if tab == "guild" then
        HideIcons()
        y, shown = self:LayoutGuild(top)
    else
        data = self:BuildPanelData()
        if self.db.panelStyle == "icons" then
            y, shown = self:LayoutIcons(top, data)
        else
            HideIcons()
            y, shown = self:LayoutLines(top, data)
        end
    end

    local empty = shown == 0 and tab ~= "guild"
    if empty then
        self.emptyLabel:SetText(self:PanelEmptyText(data))
        self.emptyLabel:ClearAllPoints()
        self.emptyLabel:SetPoint("TOP", self.frame, "TOP", 0, -(top + 8))
        y = top + EMPTY_HEIGHT
    end
    self.emptyLabel:SetShown(empty)
    self.frame:SetHeight(y + PADDING)
    self:AnimatePanel()

    -- In a group it opens by itself, unless the player closed it (R19); with "only in combat" or
    -- "only on boss fights" it shows and hides with them (P30)
    if IsInGroup() then
        if not self:WindowsWanted() then
            self.frame:Hide()
        elseif not self.db.panelClosed then
            self.frame:Show()
        end
    end
end

-------------------------------------------------------------------------------
-- Moving parts: the ready flash and the effect bars
-------------------------------------------------------------------------------

CC.panelFlash = CC.panelFlash or {}   -- ["Name-Realm\tspellID"] = GetTime() the flash began

-- Two green pulses in FLASH_TIME seconds; 0 outside it.
local function FlashAlpha(t)
    if t < 0 or t >= FLASH_TIME then return 0 end
    local half = FLASH_TIME / 2
    return math.sin(((t % half) / half) * math.pi)
end

-- The row (or folded line, or icon) holding this owner's spell flashes green twice (P1).
function CC:FlashPanelRow(owner, spellID)
    if not owner or not spellID then return end
    self.panelFlash[owner .. "\t" .. spellID] = GetTime()
    self:StartPanelAnimation()
    self:AnimatePanel()
end

local function Animate(widget, now)
    local alpha = 0
    for key in pairs(widget.flashKeys or {}) do
        local at = CC.panelFlash[key]
        if at then alpha = math.max(alpha, FlashAlpha(now - at)) end
    end
    widget.flash:SetAlpha(alpha)
    widget.flash:SetShown(alpha > 0)
    widget.flashAlpha = alpha
    local busy = alpha > 0
    if widget.fxEnd then
        local left = widget.fxEnd - now
        if left > 0 then
            widget.fx:SetValue(left)
            busy = true
        else
            widget.fxEnd = nil
            widget.fx:Hide()
        end
    end
    return busy
end

-- One step of the flashes and effect bars; the OnUpdate goes once nothing moves.
function CC:AnimatePanel()
    if not self.frame then return end
    local now = GetTime()
    local busy = false
    for key, at in pairs(self.panelFlash) do
        if now - at >= FLASH_TIME then self.panelFlash[key] = nil else busy = true end
    end
    for _, line in ipairs(self.rows) do
        if line:IsShown() and Animate(line, now) then busy = true end
    end
    for _, b in ipairs(self.icons) do
        if b:IsShown() and Animate(b, now) then busy = true end
    end
    if not busy and self.animating then
        self.animating = false
        self.frame:SetScript("OnUpdate", nil)
    end
end

function CC:StartPanelAnimation()
    if self.animating or not self.frame then return end
    self.animating = true
    self.frame:SetScript("OnUpdate", function() CC:AnimatePanel() end)
end

function CC:UpdateLock()
    if self.frame then
        self.frame:SetMovable(not self.db.locked)
    end
end

function CC:SavePosition()
    if not self.frame then return end
    local x, y   = self.frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        self.db.x = x - ux
        self.db.y = y - uy
    end
end
