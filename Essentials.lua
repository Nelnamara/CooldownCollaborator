-- Essentials Bar — slim, always-visible view of just the highest-value
-- raid-wide resources (Bloodlust/Heroism, Battle Rez), driven entirely by
-- Roster.lua's capability scan + the same CC.state used by the main panel.
-- Shows "ready" placeholders for capable-but-unused providers BEFORE anyone
-- has cast anything, which the main row list cannot do (it only ever shows
-- something once a cast has been observed).

local ROW_HEIGHT   = 22
local HEADER_HEIGHT = 16
local FRAME_WIDTH  = 220
local MAX_ROWS     = 10

local function FormatTime(secs)
    if not secs or secs <= 0 then return "READY" end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    if m > 0 then return string.format("%d:%02d", m, s) end
    return string.format("%ds", s)
end

function CC:BuildEssentialsBar()
    local db = self.db

    local f = CreateFrame("Frame", "CCEssentialsFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, HEADER_HEIGHT + ROW_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", db.essentialsX or 220, db.essentialsY or 200)
    f:SetScale(db.essentialsScale or 1.0)
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
    f:SetBackdropBorderColor(0.6, 0.5, 0.1, 0.85)

    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not CC.db.essentialsLocked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        CC:SaveEssentialsPosition()
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -3)
    title:SetText("|cFFFFD100Essentials|r")

    local emptyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetPoint("CENTER", f, "CENTER", 0, -HEADER_HEIGHT / 2)
    emptyLabel:SetText("No providers in group")
    self.essentialsEmptyLabel = emptyLabel

    self.essentialsRows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(FRAME_WIDTH - 8, ROW_HEIGHT)
        row.isHeader = false

        local bar = row:CreateTexture(nil, "BACKGROUND")
        bar:SetSize(3, ROW_HEIGHT - 4)
        bar:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.classBar = bar

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon = icon

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        nameText:SetWidth(110)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        timeText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        timeText:SetJustifyH("RIGHT")
        row.timeText = timeText

        local headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", row, "LEFT", 4, 0)
        headerText:SetTextColor(0.6, 0.8, 1)
        row.headerText = headerText

        row:Hide()
        self.essentialsRows[i] = row
    end

    local rezBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rezBtn:SetSize(50, 16)
    rezBtn:SetText("Rez")
    rezBtn:GetFontString():SetFontObject("GameFontHighlightSmall")
    rezBtn:SetScript("OnClick", function() CC:RequestRez() end)
    rezBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Target a dead player, then click to announce")
        GameTooltip:AddLine("which Battle Rez provider should rez them.")
        GameTooltip:Show()
    end)
    rezBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rezBtn:Hide()
    self.essentialsRezBtn = rezBtn

    f:Hide()
    self.essentialsFrame = f
    self:UpdateEssentialsLock()

    C_Timer.NewTicker(0.5, function()
        if CC.essentialsFrame and CC.essentialsFrame:IsShown() then
            CC:RefreshEssentials()
        end
    end)
end

function CC:RefreshEssentials()
    if not self.essentialsFrame then return end
    if not self.db.essentialsEnabled then
        self.essentialsFrame:Hide()
        return
    end

    local rows = self.essentialsRows
    local idx = 0
    local any = false
    local rezHeaderRow = nil

    for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
        local cap = CC.CAPABILITIES[capKey]
        local status = self:GetCapabilityStatus(capKey)

        if #status > 0 then
            any = true
            idx = idx + 1
            if idx > MAX_ROWS then break end
            local hdrRow = rows[idx]
            hdrRow.isHeader = true
            hdrRow.headerText:SetText(cap.label)
            hdrRow.headerText:Show()
            hdrRow.icon:Hide()
            hdrRow.nameText:Hide()
            hdrRow.timeText:Hide()
            hdrRow.classBar:Hide()
            hdrRow:Show()

            if capKey == "BATTLEREZ" then rezHeaderRow = hdrRow end

            for _, entry in ipairs(status) do
                idx = idx + 1
                if idx > MAX_ROWS then break end
                local row = rows[idx]
                row.isHeader = false
                local c = CC.ClassColors[entry.class] or CC.ClassColors.UNKNOWN
                local data = CC.SpellData[entry.spellID]

                row.headerText:Hide()
                row.icon:Show(); row.nameText:Show(); row.timeText:Show(); row.classBar:Show()

                row.classBar:SetColorTexture(c[1], c[2], c[3], 1)
                if data then row.icon:SetTexture(data.icon) end
                row.nameText:SetText(entry.name)
                row.nameText:SetTextColor(c[1], c[2], c[3])

                if entry.ready then
                    row.timeText:SetText("READY")
                    row.timeText:SetTextColor(0.3, 1.0, 0.3)
                else
                    row.timeText:SetText(FormatTime(entry.remaining))
                    row.timeText:SetTextColor(1.0, entry.remaining < 30 and 0.8 or 0.3, 0.3)
                end
                row:Show()
            end
        end
    end

    for i = idx + 1, MAX_ROWS do
        rows[i]:Hide()
    end

    self.essentialsEmptyLabel:SetShown(not any)

    -- Lay out visible rows top to bottom
    local y = HEADER_HEIGHT
    for i = 1, idx do
        local row = rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.essentialsFrame, "TOPLEFT", 4, -y)
        y = y + ROW_HEIGHT
    end
    self.essentialsFrame:SetHeight(math.max(y, HEADER_HEIGHT + ROW_HEIGHT))

    if rezHeaderRow and CC:CanRequestRez() then
        self.essentialsRezBtn:ClearAllPoints()
        self.essentialsRezBtn:SetPoint("LEFT", rezHeaderRow.headerText, "RIGHT", 6, 0)
        self.essentialsRezBtn:Show()
    else
        self.essentialsRezBtn:Hide()
    end

    if IsInGroup() and self.db.essentialsEnabled then
        self.essentialsFrame:Show()
    end
end

function CC:UpdateEssentialsLock()
    if self.essentialsFrame then
        self.essentialsFrame:SetMovable(not self.db.essentialsLocked)
    end
end

function CC:SaveEssentialsPosition()
    if not self.essentialsFrame then return end
    local x, y   = self.essentialsFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        self.db.essentialsX = x - ux
        self.db.essentialsY = y - uy
    end
end
