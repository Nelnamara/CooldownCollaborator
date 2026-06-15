local ROW_HEIGHT      = 28
local ICON_SIZE       = 22
local FRAME_WIDTH     = 320
local MAX_ROWS        = 14
local TITLE_HEIGHT    = 20
local PADDING         = 6

local function FormatTime(secs)
    if not secs or secs <= 0 then return "READY" end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    if m > 0 then
        return string.format("%d:%02d", m, s)
    else
        return string.format("%ds", s)
    end
end

local function StatusColor(remaining)
    if not remaining or remaining == 0 then
        return 0.30, 1.00, 0.30   -- green: ready
    elseif remaining < 30 then
        return 1.00, 0.80, 0.00   -- yellow: almost ready
    else
        return 1.00, 0.30, 0.30   -- red: on CD
    end
end

function CC:BuildUI()
    local db = self.db

    local frame = CreateFrame("Frame", "CCMainFrame", UIParent, "BackdropTemplate")
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

    frame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not CC.db.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        CC:SavePosition()
    end)

    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetText("|cFF54a3ffCD Collab|r  |cFF888888" .. CC.version .. "|r")
    title:SetJustifyH("CENTER")

    -- Divider line under title
    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(FRAME_WIDTH - 16, 1)
    divider:SetPoint("TOP", frame, "TOP", 0, -(TITLE_HEIGHT - 2))
    divider:SetColorTexture(0.3, 0.3, 0.5, 0.6)

    -- Empty state label
    local emptyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetPoint("CENTER", frame, "CENTER", 0, -TITLE_HEIGHT / 2)
    emptyLabel:SetText("No cooldowns tracked")
    self.emptyLabel = emptyLabel

    -- Row pool
    self.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(FRAME_WIDTH - PADDING * 2, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(TITLE_HEIGHT + (i - 1) * ROW_HEIGHT))

        -- Class color bar (3px left stripe)
        local bar = row:CreateTexture(nil, "BACKGROUND")
        bar:SetSize(3, ROW_HEIGHT - 4)
        bar:SetPoint("LEFT", row, "LEFT", 0, 0)
        bar:SetColorTexture(0.5, 0.5, 0.5, 1)
        row.classBar = bar

        -- Spell icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon = icon

        -- Player name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 4, 2)
        nameText:SetWidth(85)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        -- Spell name
        local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        spellText:SetPoint("LEFT", nameText, "RIGHT", 2, 0)
        spellText:SetWidth(105)
        spellText:SetJustifyH("LEFT")
        spellText:SetWordWrap(false)
        row.spellText = spellText

        -- Timer / READY
        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        timeText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        timeText:SetJustifyH("RIGHT")
        row.timeText = timeText

        -- Hover highlight
        row:SetScript("OnEnter", function(self)
            self.classBar:SetColorTexture(1, 1, 1, 0.35)
        end)
        row:SetScript("OnLeave", function(self)
            local entry = CC.state[self._playerName]
            local classTag = entry and entry.class or "UNKNOWN"
            local c = CC.ClassColors[classTag] or CC.ClassColors.UNKNOWN
            self.classBar:SetColorTexture(c[1], c[2], c[3], 1)
        end)

        row:Hide()
        self.rows[i] = row
    end

    frame:Hide()
    self.frame = frame

    -- 0.5s ticker keeps timers refreshed while frame is visible
    C_Timer.NewTicker(0.5, function()
        if CC.frame and CC.frame:IsShown() then
            CC:RefreshRows()
        end
    end)

    self:UpdateLock()
end

function CC:BuildRowData()
    local rows = {}
    local now = GetTime()
    local activeNames = self:GetActiveGroupNames()
    local minDur = self.db.minDuration or 60

    for name in pairs(activeNames) do
        local entry = self.state[name]
        if entry then
            for spellID, usedAt in pairs(entry.spells) do
                local data = CC.SpellData[spellID]
                if data and data.duration >= minDur then
                    local remaining = (usedAt + data.duration) - now
                    if remaining < 0 then remaining = 0 end
                    if remaining > 0 or self.db.showReady then
                        rows[#rows + 1] = {
                            name      = name,
                            class     = entry.class,
                            spellID   = spellID,
                            data      = data,
                            remaining = remaining,
                        }
                    end
                end
            end
        end
    end

    -- Sort: ready (0) first, then ascending remaining time
    table.sort(rows, function(a, b)
        if a.remaining == 0 and b.remaining > 0 then return true end
        if a.remaining > 0 and b.remaining == 0 then return false end
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.name < b.name
    end)

    return rows
end

function CC:RefreshRows()
    local rowData = self:BuildRowData()
    local count   = math.min(#rowData, MAX_ROWS)

    for i = 1, MAX_ROWS do
        local row = self.rows[i]
        if i <= count then
            local rd  = rowData[i]
            local c   = CC.ClassColors[rd.class] or CC.ClassColors.UNKNOWN
            local r, g, b = StatusColor(rd.remaining)

            row._playerName = rd.name
            row.classBar:SetColorTexture(c[1], c[2], c[3], 1)
            row.icon:SetTexture(rd.data.icon)
            row.nameText:SetText(rd.name)
            row.nameText:SetTextColor(c[1], c[2], c[3])
            row.spellText:SetText(rd.data.name)
            row.spellText:SetTextColor(0.85, 0.85, 0.85)
            row.timeText:SetTextColor(r, g, b)
            row.timeText:SetText(FormatTime(rd.remaining))
            row:Show()
        else
            row:Hide()
        end
    end

    local hasData = count > 0
    self.emptyLabel:SetShown(not hasData)

    -- Resize frame height to fit rows (min 1 row tall)
    local newHeight = TITLE_HEIGHT + math.max(count, 1) * ROW_HEIGHT + PADDING
    self.frame:SetHeight(newHeight)

    -- Auto-show when in a group with data
    if IsInGroup() then
        self.frame:Show()
    end
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
