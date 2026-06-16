-- Options panel — registered with Blizzard Settings (Escape → Interface → AddOns)
-- Also opens via /cdc settings or minimap right-click.

local PANEL_W = 600
local PANEL_H = 580

local MIN_DURATION_VALUES = { 30, 60, 90, 120, 180 }

local function MakeHeader(parent, text, anchorTo, offsetY)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if anchorTo then
        fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or -12)
    end
    fs:SetText(text)
    return fs
end

local function MakeDivider(parent, anchorTo, offsetY)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(PANEL_W - 32, 1)
    line:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or -6)
    line:SetColorTexture(0.3, 0.3, 0.4, 0.6)
    return line
end

-- Lightweight checkbox helper (avoids needing CheckButtonTemplate everywhere)
local function MakeCheckbox(parent, label, anchorTo, offsetY, getValue, setValue)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or -8)
    cb:SetChecked(getValue())
    cb:SetScript("OnClick", function(self)
        setValue(self:GetChecked())
    end)
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    return cb, lbl
end

local function MakeSlider(parent, labelText, minVal, maxVal, step, anchorTo, offsetY, getValue, setValue, fmt)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetSize(260, 20)
    slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 4, offsetY or -20)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetValue(getValue())
    slider:SetObeyStepOnDrag(true)

    slider.Text:SetText(labelText)
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valueText:SetText(string.format(fmt or "%s", tostring(getValue())))

    slider:SetScript("OnValueChanged", function(self, val)
        setValue(val)
        valueText:SetText(string.format(fmt or "%s", tostring(val)))
    end)
    return slider, valueText
end

function CC:BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel:SetSize(PANEL_W, PANEL_H)

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFF54a3ffCooldownCollaborator|r")

    local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 8, -1)
    ver:SetText("v" .. CC.version)

    -- ── Display Settings ─────────────────────────────────────────────────────
    local hdrDisplay = MakeHeader(panel, "Display Settings", title, -20)
    MakeDivider(panel, hdrDisplay, -2)

    local cbReady = MakeCheckbox(panel, "Show ready cooldowns",
        hdrDisplay, -14,
        function() return CC.db.showReady end,
        function(v) CC.db.showReady = v; CC:RefreshRows() end)

    local cbLock = MakeCheckbox(panel, "Lock panel position",
        cbReady, -4,
        function() return CC.db.locked end,
        function(v) CC.db.locked = v; CC:UpdateLock() end)

    local cbMinimap = MakeCheckbox(panel, "Hide minimap button",
        cbLock, -4,
        function() return CC.db.minimapHide end,
        function(v)
            CC.db.minimapHide = v
            if CC.minimapBtn then CC.minimapBtn:SetShown(not v) end
        end)

    -- Min duration dropdown (simple button group)
    local minDurLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    minDurLabel:SetPoint("TOPLEFT", cbMinimap, "BOTTOMLEFT", 24, -12)
    minDurLabel:SetText("Minimum cooldown duration to track:")

    local durButtons = {}
    for i, val in ipairs(MIN_DURATION_VALUES) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(54, 22)
        btn:SetText(val .. "s")
        if i == 1 then
            btn:SetPoint("TOPLEFT", minDurLabel, "BOTTOMLEFT", 0, -6)
        else
            btn:SetPoint("LEFT", durButtons[i-1], "RIGHT", 4, 0)
        end
        btn:SetScript("OnClick", function()
            CC.db.minDuration = val
            for _, b in ipairs(durButtons) do
                b:SetEnabled(true)
            end
            btn:SetEnabled(false)
            CC:RefreshRows()
        end)
        if CC.db.minDuration == val then btn:SetEnabled(false) end
        durButtons[i] = btn
    end

    local sliderAlpha = MakeSlider(panel, "Panel opacity", 0.3, 1.0, 0.05,
        durButtons[1], -20,
        function() return CC.db.alpha end,
        function(v)
            CC.db.alpha = v
            if CC.frame then CC.frame:SetAlpha(v) end
        end, "%.0f%%", function(v) return math.floor(v * 100) end)

    -- Manually fix the format for alpha since it needs percent
    sliderAlpha:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val * 20 + 0.5) / 20  -- snap to 0.05
        CC.db.alpha = val
        if CC.frame then CC.frame:SetAlpha(val) end
        select(2, MakeSlider(panel, "", 0, 1, 1, panel, 0,
            function() return 0 end, function() end, "")  -- dummy, just update text
        )
        -- Update the value label directly
        if self.valueText then
            self.valueText:SetText(string.format("%.0f%%", val * 100))
        end
    end)
    sliderAlpha.valueText = select(2, sliderAlpha, panel:CreateFontString()) -- attach ref

    local sliderScale = MakeSlider(panel, "Panel scale", 0.6, 2.0, 0.1,
        sliderAlpha, -28,
        function() return CC.db.scale end,
        function(v)
            CC.db.scale = v
            if CC.frame then CC.frame:SetScale(v) end
        end, "%.1f")

    -- ── Custom Spell Tracking ────────────────────────────────────────────────
    local hdrCustom = MakeHeader(panel, "Custom Spell Tracking", sliderScale, -20)
    MakeDivider(panel, hdrCustom, -2)

    local instrText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    instrText:SetPoint("TOPLEFT", hdrCustom, "BOTTOMLEFT", 0, -10)
    instrText:SetText("Shift-click a spell from your spellbook, or type a Spell ID:")

    -- Spell ID input
    local spellInput = CreateFrame("EditBox", "CCSpellInput", panel, "InputBoxTemplate")
    spellInput:SetSize(220, 20)
    spellInput:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", 2, -8)
    spellInput:SetAutoFocus(false)
    spellInput:SetNumeric(false)
    spellInput:SetMaxLetters(128)

    local spellNamePreview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spellNamePreview:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)
    spellNamePreview:SetTextColor(0.5, 0.8, 1)

    -- Duration input
    local durLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    durLabel:SetPoint("TOPLEFT", spellInput, "BOTTOMLEFT", 0, -10)
    durLabel:SetText("Cooldown duration (seconds):")

    local durInput = CreateFrame("EditBox", "CCDurInput", panel, "InputBoxTemplate")
    durInput:SetSize(80, 20)
    durInput:SetPoint("LEFT", durLabel, "RIGHT", 8, 0)
    durInput:SetAutoFocus(false)
    durInput:SetNumeric(true)
    durInput:SetMaxLetters(5)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", durInput, "RIGHT", 8, 0)
    addBtn:SetText("Add Spell")

    -- Detect shift-click spell link pasted into spellInput
    local pendingSpellID = nil
    spellInput:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()

        -- Check for spell hyperlink
        local linkID = text:match("|Hspell:(%d+)")
        if linkID then
            pendingSpellID = tonumber(linkID)
            self:SetText(linkID)
            local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(pendingSpellID)
            local name = info and info.name or (GetSpellInfo and select(1, GetSpellInfo(pendingSpellID)))
            spellNamePreview:SetText(name or "Unknown spell")
        else
            pendingSpellID = tonumber(text)
            if pendingSpellID then
                local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(pendingSpellID)
                local name = info and info.name or (GetSpellInfo and select(1, GetSpellInfo(pendingSpellID)))
                spellNamePreview:SetText(name or "|cFFFF4444Unknown spell ID|r")
            else
                pendingSpellID = nil
                spellNamePreview:SetText("")
            end
        end
    end)

    addBtn:SetScript("OnClick", function()
        local spellID = pendingSpellID or tonumber(spellInput:GetText())
        local dur     = tonumber(durInput:GetText())
        if CC:AddCustomSpell(spellID, dur) then
            spellInput:SetText("")
            durInput:SetText("")
            spellNamePreview:SetText("")
            pendingSpellID = nil
            CC:RefreshSpellList()
        end
    end)

    -- Custom spell list scroll frame
    local listLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    listLabel:SetPoint("TOPLEFT", durLabel, "BOTTOMLEFT", 0, -22)
    listLabel:SetText("Tracked custom spells:")

    local listFrame = CreateFrame("ScrollFrame", "CCSpellListScroll", panel, "UIPanelScrollFrameTemplate")
    listFrame:SetSize(PANEL_W - 48, 120)
    listFrame:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -6)

    local listContent = CreateFrame("Frame", nil, listFrame)
    listContent:SetSize(PANEL_W - 64, 120)
    listFrame:SetScrollChild(listContent)

    self.spellListContent = listContent
    self.spellListFrame   = listFrame

    -- Register panel with Blizzard Settings
    local category = Settings.RegisterCanvasLayoutCategory(panel, "CooldownCollaborator")
    Settings.RegisterAddOnCategory(category)
    self.optionsCategory = category

    -- Populate on first open
    self:RefreshSpellList()
end

function CC:RefreshSpellList()
    local content = self.spellListContent
    if not content then return end

    -- Clear old entries
    for _, child in pairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local y = 0
    local ROW = 22
    local hasAny = false

    for idStr, data in pairs(self.db.customSpells) do
        hasAny = true
        local spellID = tonumber(idStr)
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth(), ROW)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        icon:SetTexture(data.icon or 134400)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        lbl:SetText(string.format("|cFFCCCCCC%s|r  |cFF888888%ds|r", data.name or idStr, data.duration or 0))

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(60, 18)
        removeBtn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        removeBtn:SetText("Remove")
        local sid = spellID
        removeBtn:SetScript("OnClick", function()
            CC:RemoveCustomSpell(sid)
        end)

        y = y + ROW
    end

    if not hasAny then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        empty:SetText("No custom spells added yet.")
    end

    content:SetHeight(math.max(y, 20))
end
