-- Lane View: one lane per capability (Bloodlust/Heroism, Battle Rez), over the
-- same capability data as the Essentials bar. A provider still cooling rides
-- its lane from just used (left) to ready (right) with a thin class-coloured
-- ring; the ready ones line up side by side on a row under their lane, up to
-- eight, then "+N" (R20, R21, R22). A dead or offline owner's icon is greyed
-- with a mark, a guessed ready one carries a "?" (P44). With a next hit set (a
-- typed time or a pull countdown, P25) the icons back by then get a gold ring
-- and the title says when. The window grows with what it holds.
--
-- Also here: the pieces the windows this lane adds share (DeadList.lua,
-- Strips.lua, Burst.lua): a window with a title and a close button, and the
-- ring icon.

local L = CC.L

local LANE_WIDTH  = 240
local LANE_HEIGHT = 28
local ICON_SIZE   = 22
local LEVEL_STEP  = 18   -- a cooling icon that would overlap another drops this much
local MAX_LEVELS  = 5    -- past this they share the last level (overlapping, never left out)
local READY_SIZE  = 18
local READY_GAP   = 3
local READY_MAX   = 8
local ROW_HEIGHT  = 20   -- the ready row
local LABEL_ROOM  = 15   -- the next lane's name sits in this gap
local TOP         = 20
local BOTTOM      = 5

local READY_RGB = { 0.30, 1.00, 0.30 }
local GOLD_RGB  = { 1.00, 0.82, 0.00 }
local GREY_RGB  = { 0.48, 0.48, 0.48 }
local MARKS = {
    dead    = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",   -- the skull
    offline = "Interface\\CharacterFrame\\Disconnect-Icon",
}

-------------------------------------------------------------------------------
-- Times as the windows write them
-------------------------------------------------------------------------------

-- "0:45", "12:05" (whole seconds gone by; a countdown passes its time rounded up)
function CC:LookClock(secs)
    secs = math.max(0, math.floor(secs or 0))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- on an icon: "41" under a minute, "1:12" from there
function CC:LookIconTime(secs)
    secs = math.max(0, math.ceil(secs or 0))
    if secs < 60 then return tostring(secs) end
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-------------------------------------------------------------------------------
-- The windows this lane adds: the shared panel look (main panel edge), a title,
-- a close button, dragging under the Lane view's lock, position saved.
-------------------------------------------------------------------------------

function CC:AddLookTitle(f, text)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -4)
    title:SetText(text)
    return title
end

function CC:AddLookClose(f, onClick)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(13, 13)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.07)
    local x = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    x:SetPoint("CENTER", b, "CENTER", 0, 1)
    x:SetText("\195\151")
    x:SetTextColor(0.7, 0.7, 0.7)
    b:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function() x:SetTextColor(0.7, 0.7, 0.7) end)
    b:SetScript("OnClick", function() onClick() end)
    f.closeButton = b
    return b
end

-- opts: width, height, xKey, yKey (its saved position), title, onClose, name,
-- edge = { r, g, b } (default the main panel's)
function CC:NewLookWindow(opts)
    local db = self.db
    local f = CreateFrame("Frame", opts.name, UIParent, CC.BackdropTemplate)
    f:SetSize(opts.width, opts.height)
    f:SetPoint("CENTER", UIParent, "CENTER", db[opts.xKey] or 0, db[opts.yKey] or 0)
    local edge = opts.edge or { 0.35, 0.35, 0.55 }
    self:StylePanelFrame(f, edge[1], edge[2], edge[3])
    f:SetScript("OnMouseDown", function(widget, btn)
        -- each window has its own lock: laneLocked, deadListLocked, externalsLocked ...
        local lockKey = (opts.xKey:gsub("X$", "Locked"))
        if btn == "LeftButton" and not CC.db[lockKey] then widget:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(widget)
        widget:StopMovingOrSizing()
        local x, y = widget:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then
            CC.db[opts.xKey], CC.db[opts.yKey] = x - ux, y - uy
        end
    end)
    if opts.title then f.title = self:AddLookTitle(f, opts.title) end
    self:AddLookClose(f, opts.onClose or function() f:Hide() end)
    f:Hide()
    return f
end

-------------------------------------------------------------------------------
-- The ring icon: a thin ring around the icon (under it, never over it: R22), a
-- corner mark for a dead or offline owner, a "?" for a guessed one, an optional
-- time on it. Hover shows the panel's cooldown tooltip where Tooltip.lua has one.
-------------------------------------------------------------------------------

function CC:CreateRingIcon(parent, size)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(size, size)

    local glow = w:CreateTexture(nil, "BACKGROUND", nil, -1)   -- the gold ring's soft outside
    glow:SetPoint("TOPLEFT", w, "TOPLEFT", -5, 5)
    glow:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 5, -5)
    glow:SetColorTexture(GOLD_RGB[1], GOLD_RGB[2], GOLD_RGB[3], 0.3)
    glow:Hide()
    local edge = w:CreateTexture(nil, "BACKGROUND")            -- black outside the ring
    edge:SetPoint("TOPLEFT", w, "TOPLEFT", -3, 3)
    edge:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 3, -3)
    edge:SetColorTexture(0, 0, 0, 1)
    local ring = w:CreateTexture(nil, "BORDER")
    ring:SetPoint("TOPLEFT", w, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 2, -2)
    local tex = w:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local mark = w:CreateTexture(nil, "OVERLAY")
    mark:SetSize(11, 11)
    mark:SetPoint("TOPRIGHT", w, "TOPRIGHT", 4, 4)
    mark:Hide()
    -- "?": a small yellow disc with a black question mark
    local qdot = w:CreateTexture(nil, "OVERLAY")
    qdot:SetSize(11, 11)
    qdot:SetPoint("TOPRIGHT", w, "TOPRIGHT", 4, 4)
    qdot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    qdot:SetVertexColor(1, 0.8, 0)
    qdot:Hide()
    local q = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    q:SetPoint("CENTER", qdot, "CENTER", 0, 0)
    q:SetText("?")
    q:SetTextColor(0, 0, 0)
    q:SetShadowOffset(0, 0)
    q:Hide()
    local timeText = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeText:SetPoint("CENTER", w, "CENTER", 0, 0)
    timeText:Hide()

    w.glow, w.edge, w.ring, w.tex, w.mark, w.qdot, w.q, w.timeText = glow, edge, ring, tex, mark, qdot, q, timeText

    -- hover without taking the clicks, so the window still drags from its icons
    w:EnableMouse(true)
    if w.SetMouseClickEnabled then w:SetMouseClickEnabled(false) end
    w:SetScript("OnEnter", function(widget)
        if CC.ShowCooldownTooltip and widget.spellID then CC:ShowCooldownTooltip(widget, widget.owner, widget.spellID) end
    end)
    w:SetScript("OnLeave", function()
        if CC.HideCooldownTooltip then CC:HideCooldownTooltip() end
    end)
    return w
end

-- look = { spellID, owner, class, ring = "class" | "ready" | "gold" | "none",
--          state = nil | "dead" | "offline", guessed, dim (a cooling strip icon), time }
function CC:SetRingIcon(w, look)
    local data = look.spellID and CC.SpellData[look.spellID]
    if data then w.tex:SetTexture(data.icon) end
    w.owner, w.spellID, w.look = look.owner, look.spellID, look

    local greyed = look.state ~= nil
    w.tex:SetDesaturated(greyed or look.dim and true or false)
    local shade = (greyed or look.dim) and 0.62 or 1
    w.tex:SetVertexColor(shade, shade, shade)

    local rgb
    if look.ring == "ready" then rgb = READY_RGB
    elseif look.ring == "gold" then rgb = GOLD_RGB
    elseif look.ring == "class" then rgb = CC.ClassColors[look.class] or CC.ClassColors.UNKNOWN
    end
    if rgb and greyed then rgb = GREY_RGB end
    if rgb then
        w.ring:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        w.ring:Show()
    else
        w.ring:Hide()
    end
    w.glow:SetShown(look.ring == "gold" and not greyed)

    if MARKS[look.state] then
        w.mark:SetTexture(MARKS[look.state])
        w.mark:Show()
    else
        w.mark:Hide()
    end
    -- "?" only on Retail and Forever: Era, TBC and MoP see casts in the combat log
    local guessed = look.guessed and CC.retailAPI and not greyed and true or false
    w.qdot:SetShown(guessed)
    w.q:SetShown(guessed)

    if look.time then
        w.timeText:SetText(look.time)
        w.timeText:Show()
    else
        w.timeText:Hide()
    end
    w:Show()
end

-------------------------------------------------------------------------------
-- The next big hit (P25): a typed time (/cdc nexthit) or a pull countdown (the
-- game's, BigWigs' or DBM's: Plan.lua hears them). CC.nextHit = { at, from }.
-------------------------------------------------------------------------------

function CC:SetNextHit(seconds, from)
    if type(seconds) == "number" and seconds > 0 then
        self.nextHit = { at = GetTime() + seconds, from = from }
    else
        self.nextHit = nil
    end
    self:RefreshView("RefreshLanes")
end

-- A pull countdown cancelled: its time goes, a typed one stays.
function CC:ClearPullHit()
    if self.nextHit and self.nextHit.from == "pull" then self:SetNextHit(nil) end
end

-- Seconds to the next hit, or nil (one that has come is forgotten).
function CC:NextHitIn()
    local hit = self.nextHit
    if not hit then return nil end
    local left = hit.at - GetTime()
    if left <= 0 then
        self.nextHit = nil
        return nil
    end
    return left
end

-- /cdc nexthit <seconds or M:SS> | off
function CC:NextHitCommand(arg)
    arg = (arg or ""):lower()
    local tag = "|cFF54a3ffCooldownCollaborator|r "
    if arg == "off" or arg == "clear" then
        self:SetNextHit(nil)
        print(tag .. L["next hit cleared."])
        return
    end
    local m, s = arg:match("^(%d+):(%d%d)$")
    local secs = m and (tonumber(m) * 60 + tonumber(s)) or tonumber(arg)
    if not secs or secs <= 0 or secs > 3600 then
        print(tag .. L["usage: /cdc nexthit <seconds or M:SS>  |  /cdc nexthit off"])
        return
    end
    self:SetNextHit(secs, "typed")
    print(tag .. string.format(self.db.laneEnabled and L["next hit in %s: cooldowns back by then get a gold ring on the Lane view."]
        or L["next hit in %s: cooldowns back by then get a gold ring on the Lane view (it's off: /cdc lanes)."], self:LookClock(secs)))
end

-------------------------------------------------------------------------------
-- The Lane view
-------------------------------------------------------------------------------

local function LaneFrameHeight(laneHeights)
    local y = TOP
    for i, h in ipairs(laneHeights) do
        y = y + h + 1 + ROW_HEIGHT
        if i < #laneHeights then y = y + LABEL_ROOM end
    end
    return y + BOTTOM
end

local function NewLane(f, cap)
    local lane = CreateFrame("Frame", nil, f)
    lane:SetSize(LANE_WIDTH, LANE_HEIGHT)

    local track = lane:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", lane, "TOPLEFT", 0, -12)
    track:SetSize(LANE_WIDTH, 4)
    track:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    lane.track = track

    local label = lane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("BOTTOMLEFT", lane, "TOPLEFT", 0, -2)
    label:SetText(cap.label)
    lane.label = label

    -- the ready row under the lane: icons from the right (ready) end, "+N", and its label at the left
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(LANE_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", lane, "BOTTOMLEFT", 0, -1)
    local rowLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label = rowLabel
    local more = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    more:SetPoint("RIGHT", row, "RIGHT", -(READY_MAX * (READY_SIZE + READY_GAP)) - 2, 0)
    more:SetTextColor(READY_RGB[1], READY_RGB[2], READY_RGB[3])
    more:Hide()
    row.more = more
    row.icons = {}
    for i = 1, READY_MAX do
        local w = CC:CreateRingIcon(row, READY_SIZE)
        w:SetPoint("RIGHT", row, "RIGHT", -((i - 1) * (READY_SIZE + READY_GAP)) - 2, 0)
        w:Hide()
        row.icons[i] = w
    end
    lane.readyRow = row
    lane.icons = {}   -- the cooling ones, made as they're needed
    return lane
end

function CC:BuildLaneView()
    local db = self.db

    -- One lane per capability this client has (Era and Forever: Battle Rez only)
    local f = self:NewLookWindow({
        name = "CCLaneFrame", width = LANE_WIDTH + 16, height = 0, xKey = "laneX", yKey = "laneY",
        edge = { 0.3, 0.5, 0.7 },
        title = "|cFF54a3ff" .. L["Lanes"] .. "|r",
        onClose = function()
            CC.db.laneEnabled = false
            CC.laneFrame:Hide()
            print("|cFF54a3ffCooldownCollaborator|r " .. L["Lane view: OFF (/cdc lanes brings it back)"])
        end,
    })
    f:SetScale(db.laneScale or 1.0)
    -- dragged as one of the joined windows (Setups.lua), not as the free windows below
    f:SetScript("OnMouseDown", nil)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() CC:StartWindowDrag("lanes") end)
    f:SetScript("OnDragStop", function() CC:StopWindowDrag("lanes") end)
    f:SetScript("OnMouseUp", function() CC:StopWindowDrag("lanes") end)
    self.laneFrame = f

    self.lanes = {}
    local heights = {}
    for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
        self.lanes[capKey] = NewLane(f, CC.CAPABILITIES[capKey])
        heights[#heights + 1] = LANE_HEIGHT
    end
    self:LayoutLanes(heights)
    self:UpdateLaneLock()
    self:LayoutBlock()

    C_Timer.NewTicker(CC.TICK_RATES.lanes[1], function()
        if CC.laneFrame and CC.laneFrame:IsShown() and CC:TickDue("lanes") then
            CC:RefreshLanes()
        end
    end)

    -- The windows this lane's other files add are built with it, each on its own
    -- so an error in one can't stop the others.
    for _, build in ipairs({ "BuildDeadList", "BuildExternalsStrip", "BuildManaStrip", "BuildBurstLine", "BuildPlanBar" }) do
        if self[build] then xpcall(function() self[build](self) end, geterrorhandler()) end
    end
end

-- Lanes top down, each with its ready row under it; the frame as tall as they are.
function CC:LayoutLanes(heights)
    local f = self.laneFrame
    local y = TOP
    for i, capKey in ipairs(CC.CAPABILITY_ORDER) do
        local lane = self.lanes[capKey]
        lane:SetHeight(heights[i])
        lane:ClearAllPoints()
        lane:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -y)
        y = y + heights[i] + 1 + ROW_HEIGHT + LABEL_ROOM
    end
    f:SetHeight(LaneFrameHeight(heights))
end

-- Ready ones on the row, live ones first (nearest the ready end), then the dead, then the offline.
local STATE_ORDER = { [false] = 0, dead = 1, offline = 2 }
local function SplitLane(status)
    local cooling, ready = {}, {}
    for _, e in ipairs(status) do
        if (e.remaining or 0) > 0 then cooling[#cooling + 1] = e else ready[#ready + 1] = e end
    end
    -- the longest left first, so the soonest-ready ends up rightmost
    table.sort(cooling, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining > b.remaining end
        return a.name < b.name
    end)
    table.sort(ready, function(a, b)
        local sa, sb = STATE_ORDER[CC:OwnerState(a) or false], STATE_ORDER[CC:OwnerState(b) or false]
        if sa ~= sb then return sa < sb end
        return a.name < b.name
    end)
    return cooling, ready
end

-- Cooling icons along the lane; one that would overlap another drops a level
-- (the lowest level where it fits: an "offset if it overlaps the previous one"
-- rule breaks for chains). Returns the deepest level used.
local function PlaceCooling(lane, cooling, hitIn)
    local levels, deepest = {}, 0
    for i, e in ipairs(cooling) do
        local w = lane.icons[i]
        if not w then
            w = CC:CreateRingIcon(lane, ICON_SIZE)
            lane.icons[i] = w
        end
        local data = CC.SpellData[e.spellID]
        local duration = data and data.duration or 300
        local progress = math.max(0, math.min(1, 1 - e.remaining / duration))
        local x = progress * (LANE_WIDTH - ICON_SIZE)

        local level = 0
        while level < MAX_LEVELS - 1 do
            local fits = true
            for _, ox in ipairs(levels[level] or {}) do
                if math.abs(ox - x) < ICON_SIZE then fits = false break end
            end
            if fits then break end
            level = level + 1
        end
        levels[level] = levels[level] or {}
        table.insert(levels[level], x)
        if level > deepest then deepest = level end

        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", lane, "TOPLEFT", x, -3 - level * LEVEL_STEP)
        CC:SetRingIcon(w, {
            spellID = e.spellID, owner = e.name, class = e.class,
            ring = (hitIn and e.remaining <= hitIn) and "gold" or "class",
            state = CC:OwnerState(e),
        })
    end
    for i = #cooling + 1, #lane.icons do lane.icons[i]:Hide() end
    return deepest
end

local function FillReadyRow(row, ready)
    for i, w in ipairs(row.icons) do
        local e = ready[i]
        if e then
            CC:SetRingIcon(w, {
                spellID = e.spellID, owner = e.name, class = e.class, ring = "ready",
                -- an empty Battle Rez pool greys the icon like a dead owner's
                state = CC:OwnerState(e) or (e.noCharges and "nocharge" or nil), guessed = e.guessed,
            })
        else
            w:Hide()
        end
    end
    local extra = #ready - READY_MAX
    if extra > 0 then
        row.more:SetText("+" .. extra)
        row.more:Show()
    else
        row.more:Hide()
    end
    local usable = 0
    for _, e in ipairs(ready) do if not e.noCharges then usable = usable + 1 end end
    if #ready > 0 and usable == 0 and ready[1].noCharges then
        row.label:SetText(L["No charge"])
    else
        row.label:SetText(#ready > 0 and L["Ready"] or L["none ready"])
    end
end

function CC:RefreshLanes()
    if not self.laneFrame then return end
    if not (self.db.laneEnabled or self.sampling) then
        self.laneFrame:Hide()
        return
    end

    if IsInGroup() and not self:WindowsWanted() then
        self.laneFrame:Hide()
        return
    end

    local hitIn = self:NextHitIn()
    self.laneFrame.title:SetText("|cFF54a3ff" .. L["Lanes"] .. "|r"
        .. (hitIn and ("  |cFFFFD100" .. string.format(L["next hit %s"], self:LookClock(math.ceil(hitIn))) .. "|r") or ""))

    local heights = {}
    for i, capKey in ipairs(CC.CAPABILITY_ORDER) do
        local lane = self.lanes[capKey]
        local cooling, ready = SplitLane(self:GetCapabilityStatus(capKey))
        local deepest = PlaceCooling(lane, cooling, hitIn)
        FillReadyRow(lane.readyRow, ready)
        heights[i] = LANE_HEIGHT + deepest * LEVEL_STEP
    end
    self:LayoutLanes(heights)

    if (IsInGroup() and self.db.laneEnabled) or self.sampling then
        self.laneFrame:SetShown(self:WindowsWanted())
    end
end

function CC:UpdateLaneLock()
    if self.laneFrame then
        self.laneFrame:SetMovable(not self.db.laneLocked)
    end
end

function CC:SaveLanePosition()
    self:SaveWindowPlace("lanes")
end
