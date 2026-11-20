-- Essentials Bar — slim, always-visible view of the highest-value raid-wide
-- resources (Bloodlust/Heroism, Battle Rez), driven by Roster.lua's capability
-- scan and the same CC.state the main panel uses. It lists "ready" providers
-- before anyone has cast anything.
--
-- Built to the owner's picks on the Collaborator Looks board (19 Nov 2026,
-- tools/look-board in the main checkout, docs/REVIEW_PLAN.md "Look picks"),
-- top down:
--   a banner on a ready check or pull countdown (P7), a line when you are the
--   group's lust or Battle Rez (P22), then per capability a heading that always
--   shows with a count (P4) and the Battle Rez charge pips (P11), the lust and
--   Sated bars under lust (P27), the first three providers (ready first) and one
--   "+N more" line for the rest; a dead or offline provider is greyed with a
--   mark (P5), a guessed one has a "?" (P44); under Battle Rez one icon per way
--   back with its ready count and the Rez button (P48). Then the Soulstones line
--   (P46), the Defensives pips (P6) and the buff counts, each of which opens who
--   lacks it on a click (P17, P47).
-- The bar never runs out of lines: they come from pools that grow.
-- Hidden values (Retail and Forever) only go into widgets or a pcall.

local L = CC.L

local FRAME_WIDTH   = 220
local INNER_WIDTH   = FRAME_WIDTH - 8
local TITLE_HEIGHT  = 16
local LINE_HEIGHT   = 22
local TOP_PROVIDERS = 3      -- provider lines per heading; the rest share one line
local STONE_WARN    = 300    -- a Soulstone with less than this left gets its own line
local FLASH_TIME    = 1.2    -- FlashEssentialsFor: two green flashes
local PIP, PIP_STEP = 10, 13 -- a pip and the room it takes

-- the board's colours
local COLORS = {
    head    = { 0.6, 0.8, 1 },          -- headings
    ready   = { 0.3, 1, 0.3 },          -- READY, lit pips
    cd      = { 1, 0.3, 0.3 },          -- cooling, none
    soon    = { 1, 0.8, 0.3 },          -- under 30 s
    amber   = { 1, 0.6, 0 },            -- down to one, about to run out
    greyed  = { 0.48, 0.48, 0.48 },     -- a dead or offline provider
    tipGrey = { 0.7, 0.7, 0.7 },        -- "+N more", times beside a heading
    gold    = { 1, 0.82, 0 },
    white   = { 1, 1, 1 },
    ok      = { 0.4, 1, 0.4 },          -- a buff count at its aim
    bad     = { 1, 0.4, 0.4 },          -- a buff count under it
    stone   = { 0.78, 0.49, 1 },        -- Soulstones
    track   = { 0.2, 0.2, 0.25, 0.9 },  -- dark pips, bar tracks
    soft    = { 0.3, 1, 0.3, 0.55 },    -- a pip filling
    lust    = { 0.85, 0.33, 0.12 },     -- the lust buff's bar
    sated   = { 0.42, 0.42, 0.5 },      -- the Sated bar
    glow    = { 0.3, 1, 0.3, 0.3 },     -- a flashing line
    banner  = { 1, 1, 1, 0.07 },
}

local function Hex(c)
    return string.format("|cFF%02X%02X%02X", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- "3:51", "28s", READY at 0: provider lines and the lust bars
local function FormatTime(secs)
    if not secs or secs <= 0 then return "READY" end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    if m > 0 then return string.format("%d:%02d", m, s) end
    return string.format("%ds", s)
end

-- "0:41", "4:02": the banner, "next", charges, stones
local function Clock(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- What each capability is called in "You're the ..."
local NOUNS = { BLOODLUST = L["lust"], BATTLEREZ = L["Battle Rez"] }

-- The lust buff on you (40 s: SpellMisc DurationIndex 64 in each build) and the
-- debuff that blocks the next one (10 min: DurationIndex 6), by client; IDs from
-- SpellName of the builds in cdtl3-dev/tools/spell-list-check/builds.json.
-- Retail: Bloodlust, Heroism, Time Warp, Fury of the Aspects, Primal Rage,
-- Harrier's Cry and the two drums; Sated, Exhaustion, Temporal Displacement,
-- Fatigued, the Evoker's Exhaustion and Insanity.
local LUST_BUFFS = {
    retail = { 2825, 32182, 80353, 390386, 264667, 466904, 444257, 381301 },
    mists  = { 2825, 32182, 80353, 90355 },   -- 90355: the core hound's Primal Rage
    tbc    = { 2825, 32182 },
}
local SATED_DEBUFFS = {
    retail = { 57724, 57723, 80354, 264689, 390435, 95809 },
    mists  = { 57724, 57723, 80354, 95809 },  -- 95809: Fatigued
    tbc    = { 57724, 57723 },
}
local LUST_LENGTH, SATED_LENGTH = 40, 600

-- Shared by the Essentials bar and the Lane view: strata, dragging, clamping and the
-- dark backdrop; only the border colour differs.
function CC:StylePanelFrame(f, borderR, borderG, borderB)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    f:SetBackdropBorderColor(borderR, borderG, borderB, 0.85)
end

-------------------------------------------------------------------------------
-- Small widget parts
-------------------------------------------------------------------------------

local function FontString(parent, font, c)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    if c then fs:SetTextColor(c[1], c[2], c[3]) end
    return fs
end

local function Paint(texture, c)
    texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- A line that takes the mouse still drags the bar (as one of the joined windows: Setups.lua).
local function PassDrag(widget)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", function() CC:StartWindowDrag("essentials") end)
    widget:SetScript("OnDragStop", function() CC:StopWindowDrag("essentials") end)
end

-- A rounded count beside a heading: black figures on red, amber or green.
local function NewPill(parent)
    local pill = parent:CreateTexture(nil, "ARTWORK")
    pill:SetHeight(14)
    local text = FontString(parent, "GameFontHighlightSmall")
    text:SetJustifyH("CENTER")
    text:SetTextColor(0, 0, 0)
    text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    return { bg = pill, text = text }
end

local function SetPill(pill, value, c)
    pill.text:SetText(tostring(value))
    pill.bg:SetWidth(math.max(16, (pill.text:GetStringWidth() or 0) + 10))
    Paint(pill.bg, c)
    pill.bg:Show(); pill.text:Show()
end

-- A row of 10 px pips, wrapping every `perRow`: { { lit = bool, part = 0..1 }, ... }
local function NewPips(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder.pips = {}
    return holder
end

local function SetPips(holder, list, perRow)
    perRow = math.max(1, perRow or #list)
    for i, p in ipairs(list) do
        local pip = holder.pips[i]
        if not pip then
            pip = {
                edge = holder:CreateTexture(nil, "BORDER"),
                fill = holder:CreateTexture(nil, "ARTWORK"),
                part = holder:CreateTexture(nil, "OVERLAY"),
            }
            pip.edge:SetSize(PIP + 2, PIP + 2)
            pip.edge:SetColorTexture(0, 0, 0, 1)
            pip.fill:SetSize(PIP, PIP)
            pip.fill:SetPoint("CENTER", pip.edge, "CENTER", 0, 0)
            pip.part:SetWidth(PIP)
            pip.part:SetPoint("BOTTOM", pip.fill, "BOTTOM", 0, 0)
            holder.pips[i] = pip
        end
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        pip.edge:ClearAllPoints()
        pip.edge:SetPoint("TOPLEFT", holder, "TOPLEFT", col * PIP_STEP, -row * PIP_STEP)
        Paint(pip.fill, p.lit and COLORS.ready or COLORS.track)
        pip.lit = p.lit and true or false
        if not p.lit and (p.part or 0) > 0 then
            pip.part:SetHeight(math.max(1, PIP * math.min(1, p.part)))
            Paint(pip.part, COLORS.soft)
            pip.part:Show()
        else
            pip.part:Hide()
        end
        pip.edge:Show(); pip.fill:Show()
    end
    for i = #list + 1, #holder.pips do
        local pip = holder.pips[i]
        pip.edge:Hide(); pip.fill:Hide(); pip.part:Hide()
    end
    holder.count = #list
    local rows = math.max(1, math.ceil(#list / perRow))
    holder:SetSize(math.min(#list, perRow) * PIP_STEP, rows * PIP_STEP)
    holder:SetShown(#list > 0)
    return rows
end

-------------------------------------------------------------------------------
-- Line kinds. Each maker builds one line frame; lines come from per-kind pools
-- and are reused from one refresh to the next, so each painter sets every part
-- it uses.
-------------------------------------------------------------------------------

local Makers, Painters = {}, {}

local function NewLine(kind, frameType)
    local line = CreateFrame(frameType or "Frame", nil, CC.essentialsFrame)
    line:SetSize(INNER_WIDTH, LINE_HEIGHT)
    line.lineKind = kind
    return line
end

-- A tooltip for a line: the panel's cooldown tooltip where it exists (Tooltip.lua),
-- else the game's own with our lines.
local function ShowLines(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    for _, l in ipairs(lines) do
        if l.right then
            GameTooltip:AddDoubleLine(l.text, l.right, l.r or 1, l.g or 1, l.b or 1, l.rr or 1, l.rg or 1, l.rb or 1)
        else
            GameTooltip:AddLine(l.text, l.r or 1, l.g or 1, l.b or 1, true)
        end
    end
    GameTooltip:Show()
end

local function HideTooltip()
    if CC.HideCooldownTooltip then
        CC:HideCooldownTooltip()
    else
        GameTooltip:Hide()
    end
end

-- heading: label, charge pips and their time, count pill on the right
function Makers.heading()
    local line = NewLine("heading")
    line.label = FontString(line, "GameFontNormalSmall", COLORS.head)
    line.label:SetPoint("LEFT", line, "LEFT", 4, 0)
    line.pipHolder = NewPips(line)
    line.pipHolder:SetPoint("LEFT", line.label, "RIGHT", 6, 0)
    line.timeText = FontString(line, "GameFontHighlightSmall", COLORS.tipGrey)
    line.pill = NewPill(line)
    line.pill.bg:SetPoint("RIGHT", line, "RIGHT", -4, 0)
    return line
end

function Painters.heading(line, m)
    line.label:SetText(m.label)
    local c = m.count == 0 and COLORS.cd or (m.count == 1 and COLORS.amber or COLORS.ready)
    SetPill(line.pill, m.count, c)
    line.timeText:ClearAllPoints()
    if m.pips then
        SetPips(line.pipHolder, m.pips)
        line.timeText:SetPoint("LEFT", line.pipHolder, "RIGHT", 5, 0)
    else
        SetPips(line.pipHolder, {})
        line.timeText:SetPoint("LEFT", line.label, "RIGHT", 6, 0)
    end
    if m.noCharges then
        line.timeText:SetText(m.timeText and string.format(L["no charges %s"], m.timeText) or L["no charges"])
        line.timeText:SetTextColor(COLORS.cd[1], COLORS.cd[2], COLORS.cd[3])
    else
        line.timeText:SetText(m.timeText or "")
        line.timeText:SetTextColor(COLORS.tipGrey[1], COLORS.tipGrey[2], COLORS.tipGrey[3])
    end
    line.timeText:SetShown(m.noCharges or m.timeText ~= nil)
    return LINE_HEIGHT
end

-- provider: class bar, icon, name, time (or DEAD / OFFLINE), "?" when guessed
function Makers.provider()
    local line = NewLine("provider")
    line.flash = line:CreateTexture(nil, "BACKGROUND")
    line.flash:SetAllPoints(line)
    Paint(line.flash, COLORS.glow)
    line.flash:Hide()
    line.classBar = line:CreateTexture(nil, "ARTWORK")
    line.classBar:SetSize(3, LINE_HEIGHT - 4)
    line.classBar:SetPoint("LEFT", line, "LEFT", 2, 0)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(18, 18)
    line.icon:SetPoint("LEFT", line, "LEFT", 8, 0)
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.nameText = FontString(line, "GameFontHighlightSmall")
    line.nameText:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
    line.nameText:SetWidth(110)
    line.timeText = FontString(line, "GameFontHighlight")
    line.timeText:SetJustifyH("RIGHT")
    line.qmark = line:CreateTexture(nil, "ARTWORK")
    line.qmark:SetSize(12, 12)
    line.qmark:SetPoint("RIGHT", line, "RIGHT", -4, 0)
    Paint(line.qmark, COLORS.soon)
    line.qText = FontString(line, "GameFontHighlightSmall")
    line.qText:SetJustifyH("CENTER")
    line.qText:SetTextColor(0, 0, 0)
    line.qText:SetPoint("CENTER", line.qmark, "CENTER", 0, 0)
    line.qText:SetText("?")
    line:EnableMouse(true)
    PassDrag(line)
    line:SetScript("OnEnter", function(self)
        local m = self.model
        if not m then return end
        if CC.ShowCooldownTooltip then
            CC:ShowCooldownTooltip(self, m.entry.name, m.entry.spellID)
            return
        end
        local data = CC.SpellData[m.entry.spellID]
        local lines = { { text = data and data.name or "", r = COLORS.head[1], g = COLORS.head[2], b = COLORS.head[3] } }
        if m.state == "dead" or m.state == "offline" then
            lines[#lines + 1] = { text = m.state == "dead" and L["Dead: can't use it now."] or L["Offline."] }
        elseif m.state == "nocharge" then
            lines[#lines + 1] = { text = L["No Battle Rez charges."] }
        elseif m.guessed then
            lines[#lines + 1] = { text = L["Doesn't run CooldownCollaborator and hasn't been seen casting."] }
            lines[#lines + 1] = { text = L["Ready as far as we know."], r = COLORS.soon[1], g = COLORS.soon[2], b = COLORS.soon[3] }
        end
        ShowLines(self, CC:ShortName(m.entry.name), lines)
    end)
    line:SetScript("OnLeave", HideTooltip)
    return line
end

function Painters.provider(line, m)
    local entry = m.entry
    local c = CC.ClassColors[entry.class] or CC.ClassColors.UNKNOWN
    local data = CC.SpellData[entry.spellID]
    local greyed = m.state == "dead" or m.state == "offline" or m.state == "nocharge"
    line.owner, line.cap = entry.name, m.cap
    if greyed then c = COLORS.greyed end
    Paint(line.classBar, c)
    if data then line.icon:SetTexture(data.icon) end
    line.icon:SetDesaturated(greyed)
    if greyed then line.icon:SetVertexColor(0.55, 0.55, 0.55) else line.icon:SetVertexColor(1, 1, 1) end
    line.nameText:SetText(CC:ShortName(entry.name))
    line.nameText:SetTextColor(c[1], c[2], c[3])

    local t, tc
    if m.state == "dead" then
        t, tc = L["DEAD"], COLORS.greyed
    elseif m.state == "offline" then
        t, tc = L["OFFLINE"], COLORS.greyed
    elseif m.state == "nocharge" then
        t, tc = L["NO CHARGE"], COLORS.greyed
    elseif m.state == "ready" then
        t, tc = L["READY"], COLORS.ready
    else
        t, tc = FormatTime(entry.remaining), entry.remaining < 30 and COLORS.soon or COLORS.cd
    end
    line.timeText:SetText(t)
    line.timeText:SetTextColor(tc[1], tc[2], tc[3])
    line.timeText:ClearAllPoints()
    local q = m.guessed and m.state == "ready"
    if q then
        line.timeText:SetPoint("RIGHT", line.qmark, "LEFT", -3, 0)
    else
        line.timeText:SetPoint("RIGHT", line, "RIGHT", -4, 0)
    end
    line.qmark:SetShown(q)
    line.qText:SetShown(q)
    line.flash:Hide()
    return LINE_HEIGHT
end

-- text: one line of coloured text ("+N more", "You're the Battle Rez", Soulstones)
function Makers.text()
    local line = NewLine("text")
    line.text = FontString(line, "GameFontNormalSmall")
    line.text:SetPoint("LEFT", line, "LEFT", 4, 0)
    line.text:SetWidth(INNER_WIDTH - 8)
    line.flash = line:CreateTexture(nil, "BACKGROUND")
    line.flash:SetAllPoints(line)
    Paint(line.flash, COLORS.glow)
    line.flash:Hide()
    return line
end

function Painters.text(line, m)
    local c = m.color or COLORS.head
    line.text:SetText(m.text)
    line.text:SetTextColor(c[1], c[2], c[3])
    line.cap, line.folded = m.cap, m.folded
    line.flash:Hide()
    return LINE_HEIGHT
end

-- banner: the ready check or pull countdown summary, two lines
function Makers.banner()
    local line = NewLine("banner")
    line.bg = line:CreateTexture(nil, "BACKGROUND")
    line.bg:SetAllPoints(line)
    Paint(line.bg, COLORS.banner)
    line.first = FontString(line, "GameFontNormalSmall")
    line.first:SetPoint("TOPLEFT", line, "TOPLEFT", 4, -4)
    line.first:SetWidth(INNER_WIDTH - 8)
    line.second = FontString(line, "GameFontNormalSmall", COLORS.amber)
    line.second:SetPoint("TOPLEFT", line.first, "BOTTOMLEFT", 0, -2)
    line.second:SetWidth(INNER_WIDTH - 8)
    return line
end

function Painters.banner(line, m)
    local parts = { Hex(COLORS.gold) .. m.title .. "|r" }
    for _, p in ipairs(m.parts) do
        parts[#parts + 1] = Hex(COLORS.white) .. p.label .. " " .. Hex(p.ok and COLORS.ready or COLORS.cd) .. p.value .. "|r"
    end
    line.first:SetText(table.concat(parts, Hex(COLORS.white) .. " · |r"))
    if m.cooling ~= "" then
        line.second:SetText(string.format(L["cooling: %s"], m.cooling))
        line.second:Show()
        line:SetHeight(38)
        return 38
    end
    line.second:Hide()
    line:SetHeight(LINE_HEIGHT)
    return LINE_HEIGHT
end

-- bars: the lust buff on you and the Sated debuff, each with its time
local function NewTimerBar(line)
    local bar = CreateFrame("StatusBar", nil, line)
    bar:SetSize(INNER_WIDTH - 12, 16)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    Paint(bar.track, COLORS.track)
    bar.icon = bar:CreateTexture(nil, "OVERLAY")
    bar.icon:SetSize(16, 16)
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.label = FontString(bar, "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", bar, "LEFT", 20, 0)
    bar.timeText = FontString(bar, "GameFontHighlightSmall")
    bar.timeText:SetJustifyH("RIGHT")
    bar.timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    return bar
end

function Makers.bars()
    local line = NewLine("bars")
    line.bars = { NewTimerBar(line), NewTimerBar(line) }
    return line
end

-- Fill one bar from an aura of ours. Readable (Era, TBC, MoP, often Retail out of
-- combat): the aura's own end and length. Hidden: the client's timer object
-- fills the bar where it has one, and the time is counted from when we saw the
-- aura come on (blank when we didn't see that, say after a /reload).
local function FillTimerBar(bar, info, now)
    local aura = info.aura
    local ok = pcall(function()
        local expires, length = aura.expirationTime, aura.duration
        if not (expires > 0) then error("no end") end
        if not (length and length > 0) then length = info.length end
        local left = math.max(0, expires - now)
        bar:SetMinMaxValues(0, length)
        bar:SetValue(left)
        bar.timeText:SetText(FormatTime(left))
    end)
    if ok then
        bar.hidden = false
        return
    end
    bar.hidden = true
    local timed = false
    if bar.SetTimerDuration and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        timed = pcall(function()
            local duration = C_UnitAuras.GetAuraDuration("player", aura.auraInstanceID)
            local direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            bar:SetTimerDuration(duration, nil, direction)
        end)
    end
    local left = info.seenAt and math.max(0, info.seenAt + info.length - now)
    if not timed then
        bar:SetMinMaxValues(0, info.length)
        bar:SetValue(left or info.length)
    end
    bar.timeText:SetText(left and FormatTime(left) or "")
end

function Painters.bars(line, m)
    local now = GetTime()
    local y = -2
    for i, bar in ipairs(line.bars) do
        local info = m.bars[i]
        if info then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", line, "TOPLEFT", 6, y)
            bar:SetStatusBarColor(info.color[1], info.color[2], info.color[3], 1)
            bar.icon:SetTexture(info.icon)
            bar.label:SetText(info.label)
            bar.spellID = info.spellID
            FillTimerBar(bar, info, now)
            bar:Show()
            y = y - 20
        else
            bar:Hide()
        end
    end
    local height = -y + 3
    line:SetHeight(height)
    return height
end

-- icons: one icon per way back with its ready count, the Rez button on the right
function Makers.icons()
    local line = NewLine("icons")
    line.slots = {}
    line:SetHeight(32)
    return line
end

local function IconSlot(line, i)
    local slot = line.slots[i]
    if slot then return slot end
    slot = CreateFrame("Frame", nil, line)
    slot:SetSize(24, 24)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)
    slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.edge = slot:CreateTexture(nil, "BACKGROUND")
    slot.edge:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1)
    slot.edge:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1)
    slot.badge = NewPill(slot)
    slot.badge.bg:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 4, -4)
    slot:EnableMouse(true)
    PassDrag(slot)
    slot:SetScript("OnEnter", function(self)
        if self.tip then ShowLines(self, self.tip.title, self.tip.lines) end
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    line.slots[i] = slot
    return slot
end

function Painters.icons(line, m)
    local n = #m.icons
    local room = INNER_WIDTH - 12 - (m.rezButton and 56 or 0)
    local gap = n > 1 and math.max(4, math.min(14, math.floor((room - n * 24) / (n - 1)))) or 0
    for i, icon in ipairs(m.icons) do
        local slot = IconSlot(line, i)
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", line, "LEFT", 7 + (i - 1) * (24 + gap), 0)
        slot.icon:SetTexture(icon.icon)
        slot.icon:SetDesaturated(icon.count == 0)
        slot.edge:SetColorTexture(icon.edge and icon.edge[1] or 0, icon.edge and icon.edge[2] or 0,
            icon.edge and icon.edge[3] or 0, 1)
        SetPill(slot.badge, icon.count, icon.count > 0 and COLORS.ready or COLORS.cd)
        slot.kindKey, slot.count, slot.tip = icon.key, icon.count, icon.tip
        slot:Show()
    end
    for i = n + 1, #line.slots do line.slots[i]:Hide() end
    -- the button stays the bar's own; it sits on this line, above it
    local btn = CC.essentialsRezBtn
    if m.rezButton then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", line, "RIGHT", -4, 0)
        local level = line:GetFrameLevel()
        if level then btn:SetFrameLevel(level + 2) end
        btn:Show()
    end
    return 32
end

-- defensives: one pip per counted cooldown, lit when ready; hover lists who and what
function Makers.defensives()
    local line = NewLine("defensives")
    line.label = FontString(line, "GameFontNormalSmall", COLORS.head)
    line.label:SetPoint("TOPLEFT", line, "TOPLEFT", 4, -4)
    line.label:SetText(L["Defensives"])
    line.pipHolder = NewPips(line)
    line.pipHolder:SetPoint("TOPLEFT", line, "TOPLEFT", 74, -5)
    line.flash = line:CreateTexture(nil, "BACKGROUND")
    line.flash:SetAllPoints(line)
    Paint(line.flash, COLORS.glow)
    line.flash:Hide()
    line:EnableMouse(true)
    PassDrag(line)
    line:SetScript("OnEnter", function(self)
        local m = self.model
        if not m then return end
        local lines = {}
        for _, d in ipairs(m.list) do
            local data = CC.SpellData[d.spellID]
            local c = CC.ClassColors[d.class] or CC.ClassColors.UNKNOWN
            local right, rc = L["READY"], COLORS.ready
            if d.state == "dead" then right, rc = L["DEAD"], COLORS.greyed
            elseif d.state == "offline" then right, rc = L["OFFLINE"], COLORS.greyed
            elseif d.state == "cool" then right, rc = Clock(d.remaining), COLORS.cd
            elseif d.guessed then right = L["READY"] .. " ?" end
            lines[#lines + 1] = { text = CC:ShortName(d.name) .. "  " .. (data and data.name or ""), r = c[1], g = c[2], b = c[3],
                right = right, rr = rc[1], rg = rc[2], rb = rc[3] }
        end
        ShowLines(self, string.format(L["Defensives: %d of %d ready"], m.ready, #m.list), lines)
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return line
end

function Painters.defensives(line, m)
    local pips = {}
    for i, d in ipairs(m.list) do pips[i] = { lit = d.state == "ready" } end
    local perRow = math.floor((INNER_WIDTH - 78) / PIP_STEP)
    local rows = SetPips(line.pipHolder, pips, perRow)
    local height = LINE_HEIGHT + (rows - 1) * PIP_STEP
    line:SetHeight(height)
    line.flash:Hide()
    return height
end

-- A buff count to click for who lacks it.
local function CountButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(LINE_HEIGHT)
    btn.text = FontString(btn, "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", btn, "LEFT", 0, 0)
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self) CC:ToggleBuffMissing(self.countKey, self) end)
    PassDrag(btn)
    return btn
end

-- strip: "Flask 4/5   Food 5/5" on one line
function Makers.strip()
    local line = NewLine("strip")
    line.parts = {}
    return line
end

function Painters.strip(line, m)
    local x = 4
    for i, item in ipairs(m.items) do
        local btn = line.parts[i] or CountButton(line)
        line.parts[i] = btn
        local c = item.ok and COLORS.ok or COLORS.bad
        btn.text:SetText(string.format("%s %d/%d", item.label, item.have, item.total))
        btn.text:SetTextColor(c[1], c[2], c[3])
        btn:SetWidth((btn.text:GetStringWidth() or 60) + 2)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", line, "LEFT", x, 0)
        btn.countKey = item.key
        btn:Show()
        x = x + (btn.text:GetStringWidth() or 60) + 14
    end
    for i = #m.items + 1, #line.parts do line.parts[i]:Hide() end
    return LINE_HEIGHT
end

-- count: one buff count per line, its label left and "31/40" right
function Makers.count()
    local line = NewLine("count")
    line.button = CountButton(line)
    line.button:SetAllPoints(line)
    line.label = line.button.text
    line.label:ClearAllPoints()
    line.label:SetPoint("LEFT", line.button, "LEFT", 4, 0)
    line.right = FontString(line.button, "GameFontHighlight")
    line.right:SetJustifyH("RIGHT")
    line.right:SetPoint("RIGHT", line.button, "RIGHT", -4, 0)
    return line
end

function Painters.count(line, m)
    local c = m.item.ok and COLORS.ok or COLORS.bad
    line.label:SetText(m.item.label)
    line.label:SetTextColor(c[1], c[2], c[3])
    local rc = m.item.ok and COLORS.ready or COLORS.cd
    line.right:SetText(string.format("%d/%d", m.item.have, m.item.total))
    line.right:SetTextColor(rc[1], rc[2], rc[3])
    line.button.countKey = m.item.key
    return LINE_HEIGHT
end

-------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------

function CC:BuildEssentialsBar()
    local db = self.db

    local f = CreateFrame("Frame", "CCEssentialsFrame", UIParent, CC.BackdropTemplate)
    f:SetSize(FRAME_WIDTH, TITLE_HEIGHT + LINE_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", db.essentialsX or 220, db.essentialsY or 200)
    f:SetScale(db.essentialsScale or 1.0)
    self:StylePanelFrame(f, 0.6, 0.5, 0.1)

    -- dragged as one of the joined windows (Setups.lua): the block's top one moves the block
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() CC:StartWindowDrag("essentials") end)
    f:SetScript("OnDragStop", function() CC:StopWindowDrag("essentials") end)
    f:SetScript("OnMouseUp", function() CC:StopWindowDrag("essentials") end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -3)
    title:SetText("|cFFFFD100" .. L["Essentials"] .. "|r")

    self.essentialsFrame = f
    self.essentialsPools = {}
    self.essentialsShown = {}

    local rezBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rezBtn:SetSize(50, 16)
    rezBtn:SetText(L["Rez"])
    rezBtn:GetFontString():SetFontObject("GameFontHighlightSmall")
    rezBtn:SetScript("OnClick", function() CC:RequestRez() end)
    rezBtn:SetScript("OnEnter", function(widget)
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Target a dead player, then click to announce"])
        GameTooltip:AddLine(L["which Battle Rez provider should rez them."])
        GameTooltip:Show()
    end)
    rezBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rezBtn:Hide()
    self.essentialsRezBtn = rezBtn

    f:Hide()
    self:UpdateEssentialsLock()
    self:LayoutBlock()
    self:BuildBuffMissing()
    self:WatchPullTimers()

    C_Timer.NewTicker(CC.TICK_RATES.panel[1], function()
        if CC.essentialsFrame and CC.essentialsFrame:IsShown() and CC:TickDue("essentials") then
            CC:RefreshEssentials()
        end
    end)
end

-------------------------------------------------------------------------------
-- What the bar shows: CC:EssentialsModel() is a list of line descriptions,
-- top down ({ kind = "heading", ... }); RefreshEssentials paints them.
-------------------------------------------------------------------------------

-- How a provider (or a counted cooldown) stands: dead and offline first, as
-- neither can be used whatever the cooldown says.
local function StateOf(entry)
    if entry.online == false then return "offline" end
    if entry.alive == false then return "dead" end
    if (entry.remaining or 0) <= 0 then
        -- Battle Rez with the raid's pool empty: nobody can be brought back, so it isn't ready
        if entry.noCharges then return "nocharge" end
        return "ready"
    end
    return "cool"
end

local function IsLive(entry)
    return entry.online ~= false and entry.alive ~= false
end

-- Ready first, then by time left, then by name: a dead or offline provider
-- keeps its cooldown's place, greyed, and the next live one shows after it.
local function SortProviders(list)
    table.sort(list, function(a, b)
        local ra, rb = (a.remaining or 0) <= 0, (b.remaining or 0) <= 0
        if ra ~= rb then return ra end
        if (a.remaining or 0) ~= (b.remaining or 0) then return (a.remaining or 0) < (b.remaining or 0) end
        return a.name < b.name
    end)
end

-- The first three, then the rest. When none of the three is live and a live one
-- waits in the rest, the third is the first live one, so the next live provider
-- is always named.
local function SplitProviders(status)
    local top, rest = {}, {}
    for i, entry in ipairs(status) do
        if i <= TOP_PROVIDERS then top[#top + 1] = entry else rest[#rest + 1] = entry end
    end
    local anyLive = false
    for _, e in ipairs(top) do if IsLive(e) then anyLive = true end end
    if not anyLive and #top == TOP_PROVIDERS then
        for i, e in ipairs(rest) do
            if IsLive(e) then
                local moved = top[TOP_PROVIDERS]
                top[TOP_PROVIDERS] = e
                table.remove(rest, i)
                table.insert(rest, 1, moved)
                break
            end
        end
    end
    return top, rest
end

-- "+2 more, 1 ready" / "+1 more, next 4:02" / "+3 more"
local function MoreText(rest)
    local ready, nextIn = 0, nil
    for _, e in ipairs(rest) do
        if IsLive(e) then
            if (e.remaining or 0) <= 0 then
                if not e.noCharges then ready = ready + 1 end
            elseif not nextIn or e.remaining < nextIn then
                nextIn = e.remaining
            end
        end
    end
    if ready > 0 then return string.format(L["+%d more, %d ready"], #rest, ready) end
    if nextIn then return string.format(L["+%d more, next %s"], #rest, Clock(nextIn)) end
    return string.format(L["+%d more"], #rest)
end

-- The charge pool as pips: lit per banked charge, the next one filling. How
-- far it has filled comes from the longest wait we saw for that charge (the C
-- message carries only the time left).
function CC:RezChargePips()
    local charges, max, nextAt = self:RezPool()
    if not charges or not max or max <= 0 then return nil end
    local now = GetTime()
    local pips, part, left = {}, 0, nil
    local ok = pcall(function()
        if nextAt and charges < max then
            left = math.max(0, nextAt - now)
            local cycle = self.rezChargeCycle
            if not cycle or cycle.nextAt ~= nextAt then
                cycle = { nextAt = nextAt, length = left }
                self.rezChargeCycle = cycle
            end
            cycle.length = math.max(cycle.length, left)
            if cycle.length > 0 then part = 1 - left / cycle.length end
        end
        for i = 1, max do
            pips[i] = { lit = i <= charges, part = (i == charges + 1) and part or 0 }
        end
    end)
    if not ok then return nil end
    return { pips = pips, charges = charges, left = left }
end

-- Our own lust buff and Sated debuff, by spell ID.
local function FindOwnAura(ids, filter)
    if not ids then return nil end
    if CC.retailAPI then
        if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
        for _, id in ipairs(ids) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and aura then return id, aura end
        end
        return nil
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
        if not aura then break end
        if aura.spellId and want[aura.spellId] then return aura.spellId, aura end
    end
    return nil
end

local auraWatch = {}   -- spellID -> { seenAt = GetTime() it came on, as far as we saw }
local auraWatchStarted = false

-- fallback: the bar's name and icon (SpellMisc) when the client can't name the spell
local function TimerBarInfo(id, aura, length, color, now, fallback, fallbackIcon)
    local w = auraWatch[id]
    if not w then
        -- the first look this session can't tell when it came on
        w = { seenAt = auraWatchStarted and now or nil }
        auraWatch[id] = w
    end
    w.live = true
    local ok, name, icon = pcall(CC.Compat.GetSpellInfo, id)
    local data = CC.SpellData[id]
    return {
        spellID = id, aura = aura, length = length, color = color, seenAt = w.seenAt,
        label = (ok and type(name) == "string" and name ~= "") and name or (data and data.name) or fallback,
        icon = (ok and icon) or (data and data.icon) or fallbackIcon,
    }
end

function CC:LustBars()
    local client = self:ClientTag()
    local now = GetTime()
    for _, w in pairs(auraWatch) do w.live = false end
    local bars = {}
    local id, aura = FindOwnAura(LUST_BUFFS[client], "HELPFUL")
    if id then bars[#bars + 1] = TimerBarInfo(id, aura, LUST_LENGTH, COLORS.lust, now, L["Bloodlust"], 136012) end
    id, aura = FindOwnAura(SATED_DEBUFFS[client], "HARMFUL")
    if id then bars[#bars + 1] = TimerBarInfo(id, aura, SATED_LENGTH, COLORS.sated, now, L["Sated"], 136090) end
    for key, w in pairs(auraWatch) do
        if not w.live then auraWatch[key] = nil end
    end
    auraWatchStarted = true
    return bars
end

-- One icon per way back from the dead, with how many are ready now (P48).
function CC:RezIcons(status)
    local icons = {}
    local ids, seenID = {}, {}
    for _, list in pairs((self.CAPABILITIES.BATTLEREZ or {}).classes or {}) do
        for _, id in ipairs(list) do
            if not seenID[id] then seenID[id] = true; ids[#ids + 1] = id end
        end
    end
    -- Rebirth, Raise Ally, Intercession, Soulstone: the board's order
    local rank = { [20484] = 1, [61999] = 2, [391054] = 3, [CC.SOULSTONE_ID] = 4 }
    table.sort(ids, function(a, b) return (rank[a] or 9) < (rank[b] or 9) end)
    for _, id in ipairs(ids) do
        local ready, have, names = 0, 0, {}
        for _, e in ipairs(status) do
            if e.spellID == id then
                have = have + 1
                if StateOf(e) == "ready" then
                    ready = ready + 1
                    names[#names + 1] = { text = CC:ShortName(e.name) }
                end
            end
        end
        if have > 0 then
            local data = CC.SpellData[id]
            local title = data and data.name or ""
            if id == CC.SOULSTONE_ID then title = string.format(L["%s on the dead"], title) end
            icons[#icons + 1] = { key = "spell:" .. id, icon = data and data.icon or 136080, count = ready,
                tip = { title = string.format(L["%s: %d ready"], title, ready), lines = names } }
        end
    end

    -- Soulstones already on someone
    if CC.SpellData[CC.SOULSTONE_ID] then
        local stones, lines, warlock = 0, {}, false
        for name in pairs(self.stones) do
            if self:GetStone(name) and self:IsGroupMember(name) then
                stones = stones + 1
                lines[#lines + 1] = { text = CC:ShortName(name) }
            end
        end
        for _, info in pairs(self.roster or {}) do
            if info.class == "WARLOCK" then warlock = true end
        end
        if stones > 0 or warlock then
            icons[#icons + 1] = { key = "stones", icon = CC.SpellData[CC.SOULSTONE_ID].icon, count = stones,
                edge = COLORS.stone, tip = { title = string.format(L["Soulstones placed: %d"], stones), lines = lines } }
        end
    end

    -- Classic: Reincarnation, for the shaman himself
    local reinc = CC.SpellData[20608]
    local _, myClass = UnitClass("player")
    if reinc and not self.isRetail and myClass == "SHAMAN" and self:KnownRank(20608) then
        local left = self:GetLocalReadiness(20608)
        if left == nil then left = self:GetRemaining(self:FullName("player"), 20608) or 0 end
        local ready = left <= 0 and 1 or 0
        icons[#icons + 1] = { key = "reincarnation", icon = reinc.icon, count = ready,
            tip = { title = string.format(L["Reincarnation (yours): %s"], ready == 1 and L["ready"] or Clock(left)), lines = {} } }
    end
    return icons
end

-- A member's role: TANK, HEALER or nil (the role the group gave them; the raid's
-- main tank mark on clients without roles).
local function RoleOf(unit)
    if not unit then return nil end
    local ok, role = pcall(function()
        if UnitGroupRolesAssigned then
            local r = UnitGroupRolesAssigned(unit)
            if r == "TANK" or r == "HEALER" then return r end
        end
        if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return "TANK" end
        return nil
    end)
    if ok then return role end
    return nil
end

-- The Soulstones line (P46): the stones out, by tank and healer, and a line for
-- each one about to run out.
function CC:StoneLines()
    if not CC.SpellData[CC.SOULSTONE_ID] then return {} end
    local now = GetTime()
    local stones = {}
    local warlock = false
    for _, info in pairs(self.roster or {}) do
        if info.class == "WARLOCK" then warlock = true end
    end
    for name in pairs(self.stones) do
        local stone = self:GetStone(name)
        if stone and self:IsGroupMember(name) then
            stones[#stones + 1] = { name = name, left = stone.placedAt + stone.duration - now }
        end
    end
    if #stones == 0 and not warlock then return {} end
    table.sort(stones, function(a, b) return a.left < b.left end)

    local tanks, healers, tankStones, healerStones = 0, 0, 0, 0
    local stoned = {}
    for _, s in ipairs(stones) do stoned[s.name] = true end
    for name, info in pairs(self.roster or {}) do
        local role = RoleOf(self:UnitTokenFor(name, info.unit))
        if role == "TANK" then
            tanks = tanks + 1
            if stoned[name] then tankStones = tankStones + 1 end
        elseif role == "HEALER" then
            healers = healers + 1
            if stoned[name] then healerStones = healerStones + 1 end
        end
    end
    local text = Hex(COLORS.stone) .. string.format(L["Soulstones %d"], #stones) .. "|r"
    local roles = {}
    if tanks > 0 then roles[#roles + 1] = Hex(tankStones == 0 and COLORS.amber or COLORS.white) .. string.format(L["tank %d"], tankStones) .. "|r" end
    if healers > 0 then roles[#roles + 1] = Hex(healerStones == 0 and COLORS.amber or COLORS.white) .. string.format(L["healer %d"], healerStones) .. "|r" end
    if #roles > 0 then
        text = text .. "  " .. table.concat(roles, Hex(COLORS.white) .. " · |r")
    elseif #stones > 0 then
        local names = {}
        for i = 1, math.min(2, #stones) do names[i] = CC:ShortName(stones[i].name) end
        text = text .. Hex(COLORS.white) .. "  " .. string.format(L["on %s"], table.concat(names, ", ") .. (#stones > 2 and ", ..." or "")) .. "|r"
    end
    local lines = { { kind = "text", key = "stones", text = text, color = COLORS.white, count = #stones,
        tank = tankStones, healer = healerStones } }
    for i = 1, math.min(2, #stones) do
        local s = stones[i]
        if s.left < STONE_WARN then
            lines[#lines + 1] = { kind = "text", key = "stonewarn", target = s.name, color = COLORS.amber,
                text = string.format(L["%s's runs out in %s"], CC:ShortName(s.name), Clock(s.left)) }
        end
    end
    return lines
end

-- The cooldowns the Defensives line counts: spells of kind "external" or "raid"
-- (the panel's Data rows; a spell with no kind is left out) or the saved list,
-- for every group member whose class has them (level and spec allowing). On
-- Retail and Forever only players who run the addon, or seen casting it, count.
-- { { name, class, spellID, remaining, state, guessed }, ... }, ready first.
function CC:CountedDefensives(kinds)
    local ids = {}
    local saved = self.db.essentialsDefensives
    if not kinds and type(saved) == "table" and #saved > 0 then
        for _, id in ipairs(saved) do
            id = tonumber(id)
            if id and CC.SpellData[id] then ids[#ids + 1] = id end
        end
    else
        kinds = kinds or { external = true, raid = true }
        for id, data in pairs(CC.SpellData) do
            if data.kind and kinds[data.kind] and not data.consumable then ids[#ids + 1] = id end
        end
    end
    table.sort(ids)
    local list = {}
    if #ids == 0 then return list end
    local me = self:FullName("player")
    for name, info in pairs(self.roster or {}) do
        local unit = self:UnitTokenFor(name, info.unit)
        local isSelf = name == me
        local peer = self.peers and self.peers[name]
        local runsIt = peer and (peer.proto or 0) >= 2
        local entry = self.state[name]
        for _, id in ipairs(ids) do
            local data = CC.SpellData[id]
            local seen = entry and entry.spells[id] ~= nil
            local counts = data.class == info.class
            if counts and isSelf then
                counts = self:KnownRank(id) ~= nil
            elseif counts then
                local okLevel, low = pcall(function()
                    local level = unit and UnitLevel(unit)
                    return data.level and level and level > 0 and level < data.level
                end)
                if okLevel and low then counts = false end
                if counts and data.spec then
                    local okSpec, same = pcall(function() return self.rosterSpecs[name] == data.spec end)
                    counts = okSpec and same == true
                end
                if counts and self.retailAPI and not runsIt and not seen then counts = false end
            end
            if counts then
                local remaining = isSelf and self:GetLocalReadiness(id) or nil
                if remaining == nil then remaining = self:GetRemaining(name, id) or 0 end
                -- online and alive as far as the game says (an unreadable answer counts as yes)
                local online, alive = true, true
                if unit then
                    local okC, connected = pcall(function() return UnitIsConnected(unit) and true or false end)
                    local okD, dead = pcall(function() return UnitIsDeadOrGhost(unit) and true or false end)
                    online, alive = (not okC) or connected, (not okD) or not dead
                end
                local d = { name = name, class = info.class, spellID = id, remaining = remaining,
                    online = online, alive = alive, guessed = not isSelf and not seen and not runsIt }
                d.state = StateOf(d)
                list[#list + 1] = d
            end
        end
    end
    table.sort(list, function(a, b)
        local ra, rb = a.state == "ready", b.state == "ready"
        if ra ~= rb then return ra end
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        if a.spellID ~= b.spellID then return a.spellID < b.spellID end
        return a.name < b.name
    end)
    return list
end

-- The buff counts the saved list asks for (P17, P47): one strip for flask and
-- food alone, else a line each.
function CC:BuffCountLines()
    local status = IsInGroup() and self:GetGroupBuffStatus()
    if not status or status.total <= 0 then return {} end
    local aim = tonumber(self.db.essentialsBuffAim) or 0
    aim = (aim > 0) and math.min(aim, status.total) or status.total
    local items, onlyStrip = {}, true
    for _, key in ipairs(self.db.essentialsBuffCounts or {}) do
        local count = status.counts[key]
        if count then
            items[#items + 1] = { key = key, label = count.label, have = count.have, total = status.total,
                ok = count.have >= aim }
            if key ~= "flask" and key ~= "food" then onlyStrip = false end
        end
    end
    if #items == 0 then return {} end
    if onlyStrip then return { { kind = "strip", items = items } } end
    local lines = {}
    for _, item in ipairs(items) do lines[#lines + 1] = { kind = "count", item = item } end
    return lines
end

-- The banner's summary for a ready check or pull (P7).
local function BannerLine(self, sections)
    local banner = self.essentialsBanner
    if not banner then return nil end
    local now = GetTime()
    if banner.endsAt and now >= banner.endsAt then
        self.essentialsBanner = nil
        return nil
    end
    local title = L["Ready check"]
    if banner.pull then
        title = banner.known and string.format(L["Pull in %d"], math.max(0, math.ceil(banner.endsAt - now))) or L["Pull timer"]
    end
    local parts, cooling = {}, {}
    local lust = sections.BLOODLUST
    if lust then
        local ready, soonest = 0, nil
        for _, e in ipairs(lust) do
            if StateOf(e) == "ready" then ready = ready + 1
            elseif StateOf(e) == "cool" and (not soonest or e.remaining < soonest) then soonest = e.remaining end
        end
        if ready > 0 then
            parts[#parts + 1] = { label = L["lust"], value = L["ready"], ok = true }
        else
            parts[#parts + 1] = { label = L["lust"], value = soonest and Clock(soonest) or L["none"], ok = false }
            if soonest then cooling[#cooling + 1] = { text = L["lust"], left = soonest } end
        end
    end
    if sections.BATTLEREZ then
        local charges, _, nextAt = self:RezPool()
        local value = charges
        if value == nil then
            value = 0
            for _, e in ipairs(sections.BATTLEREZ) do
                if StateOf(e) == "ready" then value = value + 1 end
            end
        elseif value == 0 and nextAt then
            cooling[#cooling + 1] = { text = L["rez charges"], left = math.max(0, nextAt - now) }
        end
        parts[#parts + 1] = { label = L["rez"], value = tostring(value), ok = value > 0 }
    end
    local externals = self:CountedDefensives({ external = true })
    if #externals > 0 then
        local ready = 0
        local cool = {}
        for _, d in ipairs(externals) do
            if d.state == "ready" then
                ready = ready + 1
            elseif d.state == "cool" then
                local data = CC.SpellData[d.spellID]
                cool[#cool + 1] = { text = data and data.name or "", left = d.remaining }
            end
        end
        parts[#parts + 1] = { label = L["externals"], value = ready .. "/" .. #externals, ok = ready > 0 }
        for _, c in ipairs(cool) do cooling[#cooling + 1] = c end
    end
    table.sort(cooling, function(a, b) return a.left < b.left end)
    local named = {}
    for i = 1, math.min(3, #cooling) do named[i] = cooling[i].text .. " " .. Clock(cooling[i].left) end
    local text = table.concat(named, ", ")
    if #cooling > 3 then text = text .. string.format(", +%d", #cooling - 3) end
    return { kind = "banner", title = title, parts = parts, cooling = text }
end

function CC:EssentialsModel()
    local lines = {}
    local me = self:FullName("player")
    local sections, statusByCap = {}, {}
    for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
        local status = self:GetCapabilityStatus(capKey)
        SortProviders(status)
        statusByCap[capKey] = status
        sections[#sections + 1] = capKey
    end

    local banner = BannerLine(self, statusByCap)
    if banner then lines[#lines + 1] = banner end

    -- You're the lust / Battle Rez (P22): amber when you're the only live one
    for _, capKey in ipairs(sections) do
        local live, mine = 0, nil
        for _, e in ipairs(statusByCap[capKey]) do
            if IsLive(e) then live = live + 1 end
            if e.name == me then mine = e end
        end
        if mine and IsLive(mine) and not mine.noCharges then
            local noun = NOUNS[capKey] or CC.CAPABILITIES[capKey].label
            lines[#lines + 1] = live <= 1
                and { kind = "text", key = "you", cap = capKey, only = true, color = COLORS.amber,
                      text = string.format(L["You're the %s, the only one"], noun) }
                or { kind = "text", key = "you", cap = capKey, only = false, color = COLORS.head,
                      text = string.format(L["You're a %s, one of %d"], noun, live) }
        end
    end

    for _, capKey in ipairs(sections) do
        local status = statusByCap[capKey]
        local live = 0
        for _, e in ipairs(status) do if IsLive(e) then live = live + 1 end end
        local heading = { kind = "heading", cap = capKey, label = CC.CAPABILITIES[capKey].label, count = live }
        if capKey == "BATTLEREZ" then
            local pool = self:RezChargePips()
            if pool then
                heading.pips = pool.pips
                heading.charges = pool.charges
                heading.noCharges = pool.charges == 0
                if pool.left then heading.timeText = Clock(pool.left) end
            end
        end
        lines[#lines + 1] = heading

        if capKey == "BLOODLUST" then
            local bars = self:LustBars()
            if #bars > 0 then lines[#lines + 1] = { kind = "bars", bars = bars } end
        end

        -- "?" on guessed lines: Retail and Forever only (Era, TBC and MoP see casts in the combat log)
        local top, rest = SplitProviders(status)
        for _, entry in ipairs(top) do
            lines[#lines + 1] = { kind = "provider", cap = capKey, entry = entry, state = StateOf(entry),
                guessed = (self.retailAPI and entry.guessed) and true or false }
        end
        if #rest > 0 then
            local folded = {}
            for _, e in ipairs(rest) do folded[e.name] = true end
            lines[#lines + 1] = { kind = "text", key = "more", cap = capKey, color = COLORS.tipGrey,
                text = MoreText(rest), count = #rest, folded = folded }
        end

        if capKey == "BATTLEREZ" then
            local icons = self:RezIcons(status)
            local rezButton = self:CanRequestRez()
            if #icons > 0 or rezButton then
                lines[#lines + 1] = { kind = "icons", icons = icons, rezButton = rezButton }
            end
        end
    end

    for _, l in ipairs(self:StoneLines()) do lines[#lines + 1] = l end

    local defensives = self:CountedDefensives()
    if #defensives > 0 then
        local ready = 0
        for _, d in ipairs(defensives) do if d.state == "ready" then ready = ready + 1 end end
        lines[#lines + 1] = { kind = "defensives", list = defensives, ready = ready }
    end

    for _, l in ipairs(self:BuffCountLines()) do lines[#lines + 1] = l end
    return lines
end

-------------------------------------------------------------------------------
-- Paint
-------------------------------------------------------------------------------

local function Acquire(self, kind, used)
    local pool = self.essentialsPools[kind]
    if not pool then
        pool = {}
        self.essentialsPools[kind] = pool
    end
    used[kind] = (used[kind] or 0) + 1
    local line = pool[used[kind]]
    if not line then
        line = Makers[kind]()
        pool[used[kind]] = line
    end
    return line
end

function CC:RefreshEssentials()
    if not self.essentialsFrame then return end
    if not self.db.essentialsEnabled then
        self.essentialsFrame:Hide()
        return
    end

    -- hidden and staying hidden (a group, windows not wanted now): no rebuild
    if IsInGroup() and not self:WindowsWanted() then
        self.essentialsFrame:Hide()
        return
    end

    local model = self:EssentialsModel()
    local used, shown = {}, {}
    self.essentialsRezBtn:Hide()

    local y = TITLE_HEIGHT
    for _, m in ipairs(model) do
        local line = Acquire(self, m.kind, used)
        line.model = m
        local height = Painters[m.kind](line, m)
        line:SetHeight(height)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", self.essentialsFrame, "TOPLEFT", 4, -y)
        line:Show()
        shown[#shown + 1] = line
        y = y + height
    end
    for kind, pool in pairs(self.essentialsPools) do
        for i = (used[kind] or 0) + 1, #pool do pool[i]:Hide() end
    end
    self.essentialsShown = shown
    self.essentialsFrame:SetHeight(math.max(y + 2, TITLE_HEIGHT + LINE_HEIGHT))
    if self.essentialsFlash then self:StepEssentialsFlash() end
    if self.buffMissingFrame and self.buffMissingFrame:IsShown() then self:FillBuffMissing() end

    if IsInGroup() and self.db.essentialsEnabled then
        self.essentialsFrame:SetShown(self:WindowsWanted())
    end
end

-------------------------------------------------------------------------------
-- Flash a provider's line (the panel's alerts call this when a chosen cooldown
-- is ready): green twice. A provider folded into "+N more" flashes that line; a
-- counted defensive flashes the Defensives line.
-------------------------------------------------------------------------------

local function SpellInCapability(capKey, spellID)
    local cap = capKey and CC.CAPABILITIES[capKey]
    for _, list in pairs(cap and cap.classes or {}) do
        for _, id in ipairs(list) do
            if id == spellID then return true end
        end
    end
    return false
end

local function FlashTarget(line, owner, spellID)
    local m = line.model
    if not m or not line.flash then return false end
    if m.kind == "provider" then
        return m.entry.name == owner and (m.entry.spellID == spellID or SpellInCapability(m.cap, spellID))
    elseif m.kind == "text" and m.key == "more" then
        return m.folded[owner] == true and SpellInCapability(m.cap, spellID)
    elseif m.kind == "defensives" then
        for _, d in ipairs(m.list) do
            if d.name == owner and d.spellID == spellID then return true end
        end
    end
    return false
end

function CC:StepEssentialsFlash()
    local fl = self.essentialsFlash
    local t = fl and (GetTime() - fl.at)
    local on = t ~= nil and t < FLASH_TIME and (t % 0.6) < 0.3
    for _, line in ipairs(self.essentialsShown or {}) do
        if line.flash then
            line.flash:SetShown(on and fl ~= nil and FlashTarget(line, fl.owner, fl.spellID))
        end
    end
    if not t or t >= FLASH_TIME then
        self.essentialsFlash = nil
        if self.essentialsFlashTicker then
            self.essentialsFlashTicker:Cancel()
            self.essentialsFlashTicker = nil
        end
    end
end

function CC:FlashEssentialsFor(owner, spellID)
    if not self.essentialsFrame or not owner then return end
    spellID = self:BaseSpellID(spellID) or spellID
    self.essentialsFlash = { owner = owner, spellID = spellID, at = GetTime() }
    if not self.essentialsFlashTicker then
        self.essentialsFlashTicker = C_Timer.NewTicker(0.1, function() CC:StepEssentialsFlash() end)
    end
    self:StepEssentialsFlash()
end

-------------------------------------------------------------------------------
-- Ready check and pull countdown (P7): the game's events where the client has
-- them, and BigWigs' and DBM's pull timers through their public callbacks when
-- those addons are loaded. Every registration is guarded.
-------------------------------------------------------------------------------

local READY_CHECK_TIME = 35   -- how long the game's ready check waits

function CC:StartEssentialsBanner(pull, seconds)
    local now = GetTime()
    local length
    local ok = pcall(function()
        if seconds and seconds > 0 then length = seconds end
    end)
    if not ok then length = nil end
    local cur = self.essentialsBanner
    if pull then
        -- a countdown we can't read still shows, for ten seconds
        self.essentialsBanner = { pull = true, known = length ~= nil, endsAt = now + (length or 10) }
    elseif not (cur and cur.pull) then
        -- a ready check doesn't hide a countdown already running
        self.essentialsBanner = { pull = false, endsAt = now + (length or READY_CHECK_TIME) }
    end
    self:RefreshView("RefreshEssentials")
end

function CC:StopEssentialsBanner(pull)
    local cur = self.essentialsBanner
    if cur and (cur.pull == pull) then
        self.essentialsBanner = nil
        self:RefreshView("RefreshEssentials")
    end
end

function CC:OnEssentialsEvent(event, ...)
    if event == "READY_CHECK" then
        local _, timeLeft = ...
        self:StartEssentialsBanner(false, timeLeft)
    elseif event == "READY_CHECK_FINISHED" then
        self:StopEssentialsBanner(false)
    elseif event == "START_PLAYER_COUNTDOWN" then
        local _, timeRemaining = ...
        self:StartEssentialsBanner(true, timeRemaining)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        self:StopEssentialsBanner(true)
    elseif event == "START_TIMER" then
        local timerType, timeRemaining = ...
        local types = Enum and Enum.StartTimerType
        local ok, isCountdown = pcall(function() return types and timerType == types.PlayerCountdown end)
        if ok and isCountdown then self:StartEssentialsBanner(true, timeRemaining) end
    elseif event == "STOP_TIMER_OF_TYPE" then
        local timerType = ...
        local types = Enum and Enum.StartTimerType
        local ok, isCountdown = pcall(function() return types and timerType == types.PlayerCountdown end)
        if ok and isCountdown then self:StopEssentialsBanner(true) end
    elseif event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        self:WatchBossMods()
    end
end

-- BigWigs (BigWigsLoader.RegisterMessage, "BigWigs_StartPull" with the seconds) and DBM
-- (DBM:RegisterCallback, "DBM_TimerBegin" / older "DBM_TimerStart" with the timer's type
-- "pull" sixth), each once and in a pcall.
function CC:WatchBossMods()
    -- BigWigs' and DBM's own globals, there only while that addon is loaded
    ---@diagnostic disable-next-line: undefined-field
    local bw = _G.BigWigsLoader
    if bw and bw.RegisterMessage and not self.watchingBigWigs then
        self.watchingBigWigs = pcall(bw.RegisterMessage, self, "BigWigs_StartPull", function(_, _, seconds)
            CC:StartEssentialsBanner(true, seconds)
        end)
        pcall(bw.RegisterMessage, self, "BigWigs_StopPull", function() CC:StopEssentialsBanner(true) end)
    end
    ---@diagnostic disable-next-line: undefined-field
    local dbm = _G.DBM
    if dbm and dbm.RegisterCallback and not self.watchingDBM then
        local function onTimer(_, _, _, timer, _, timerType)
            if timerType == "pull" then CC:StartEssentialsBanner(true, timer) end
        end
        local okNew = pcall(dbm.RegisterCallback, dbm, "DBM_TimerBegin", onTimer)
        local okOld = pcall(dbm.RegisterCallback, dbm, "DBM_TimerStart", onTimer)
        self.watchingDBM = okNew or okOld
    end
end

function CC:WatchPullTimers()
    local ev = CreateFrame("Frame")
    for _, event in ipairs({ "READY_CHECK", "READY_CHECK_FINISHED", "START_PLAYER_COUNTDOWN",
        "CANCEL_PLAYER_COUNTDOWN", "START_TIMER", "STOP_TIMER_OF_TYPE", "ADDON_LOADED", "PLAYER_LOGIN" }) do
        -- an event this client doesn't have can't be registered
        pcall(ev.RegisterEvent, ev, event)
    end
    ev:SetScript("OnEvent", function(_, event, ...) CC:OnEssentialsEvent(event, ...) end)
    self.essentialsEvents = ev
    self:WatchBossMods()
end

-------------------------------------------------------------------------------
-- Who lacks it (P17, P47): click a buff count for the names missing it, and a
-- button to post them to the group's chat.
-------------------------------------------------------------------------------

local MISSING_NAMES = 6   -- names shown; the rest are "and N more"

function CC:BuildBuffMissing()
    local f = CreateFrame("Frame", "CCBuffMissingFrame", UIParent, CC.BackdropTemplate)
    f:SetSize(240, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.04, 0.11, 0.95)
    f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
    f.title = FontString(f, "GameFontNormal", COLORS.white)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -8)
    f.names = FontString(f, "GameFontHighlightSmall", COLORS.white)
    f.names:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.names:SetWidth(222)
    f.names:SetWordWrap(true)
    f.unknown = FontString(f, "GameFontHighlightSmall", COLORS.tipGrey)
    f.unknown:SetPoint("TOPLEFT", f.names, "BOTTOMLEFT", 0, -3)
    f.unknown:SetWidth(222)
    f.unknown:SetWordWrap(true)
    f.post = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.post:SetSize(100, 18)
    f.post:GetFontString():SetFontObject("GameFontHighlightSmall")
    f.post:SetScript("OnClick", function() CC:PostBuffMissing(f.countKey) end)
    f:Hide()
    table.insert(UISpecialFrames, "CCBuffMissingFrame")   -- Escape closes it
    self.buffMissingFrame = f
end

local function ColoredName(name)
    local info = CC.roster and CC.roster[name]
    local c = CC.ClassColors[info and info.class or "UNKNOWN"] or CC.ClassColors.UNKNOWN
    return Hex(c) .. CC:ShortName(name) .. "|r"
end

-- Fill the window for its count; false (and hidden) when the count is gone.
function CC:FillBuffMissing()
    local f = self.buffMissingFrame
    local status = self:GetGroupBuffStatus()
    local count = status and status.counts[f.countKey]
    if not count then
        f:Hide()
        return false
    end
    f.title:SetText(string.format(L["%s: %d missing"], count.name, #count.missing))
    local shown = {}
    for i = 1, math.min(MISSING_NAMES, #count.missing) do shown[i] = ColoredName(count.missing[i]) end
    local text = table.concat(shown, ", ")
    if #count.missing > MISSING_NAMES then
        text = text .. " " .. Hex(COLORS.tipGrey) .. string.format(L["and %d more"], #count.missing - MISSING_NAMES) .. "|r"
    end
    f.names:SetText(text)
    f.names:SetShown(#count.missing > 0)
    if #count.unknown > 0 then
        f.unknown:SetText(string.format(L["%d not known (they don't run CooldownCollaborator)"], #count.unknown))
        f.unknown:Show()
    else
        f.unknown:SetText("")
        f.unknown:Hide()
    end
    local channel = self:GroupChannel()
    local postTo = { RAID = L["Post to raid"], PARTY = L["Post to party"], INSTANCE_CHAT = L["Post to instance"] }
    f.post:SetText(postTo[channel or ""] or L["Post to group"])
    f.post:ClearAllPoints()
    f.post:SetPoint("TOPLEFT", (#count.unknown > 0) and f.unknown or f.names, "BOTTOMLEFT", 0, -6)
    f.post:SetEnabled(#count.missing > 0 and channel ~= nil)
    local textHeight = (f.names:GetStringHeight() or 14) + ((#count.unknown > 0) and ((f.unknown:GetStringHeight() or 14) + 3) or 0)
    f:SetHeight(8 + 16 + 4 + textHeight + 6 + 18 + 9)
    return true
end

function CC:ToggleBuffMissing(key, anchor)
    local f = self.buffMissingFrame
    if not f or not key then return end
    if f:IsShown() and f.countKey == key then
        f:Hide()
        return
    end
    f.countKey = key
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor or self.essentialsFrame, "TOPRIGHT", 8, 0)
    if self:FillBuffMissing() then f:Show() end
end

-- "Missing Songflower Serenade (21): Gorvak, Skarde, ..." in pieces the chat takes.
function CC:PostBuffMissing(key)
    local status = self:GetGroupBuffStatus()
    local count = status and status.counts[key]
    local channel = self:GroupChannel()
    if not count or #count.missing == 0 or not channel then return end
    local head = string.format(L["Missing %s (%d): "], count.name, #count.missing)
    local msgs, cur, fresh = {}, head, true
    for _, name in ipairs(count.missing) do
        local piece = (fresh and "" or ", ") .. CC:ShortName(name)
        if not fresh and #cur + #piece > 250 then
            msgs[#msgs + 1] = cur
            cur = CC:ShortName(name)
        else
            cur = cur .. piece
        end
        fresh = false
    end
    if #count.unknown > 0 then cur = cur .. string.format(L["; %d not known"], #count.unknown) end
    msgs[#msgs + 1] = cur
    -- Deliberate fallback to the old global.
    ---@diagnostic disable-next-line: deprecated
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, msg in ipairs(msgs) do send(msg, channel) end
end

-------------------------------------------------------------------------------

function CC:UpdateEssentialsLock()
    if self.essentialsFrame then
        self.essentialsFrame:SetMovable(not self.db.essentialsLocked)
    end
end

function CC:SaveEssentialsPosition()
    self:SaveWindowPlace("essentials")
end
