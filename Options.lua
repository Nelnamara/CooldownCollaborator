-- Options for CooldownCollaborator
-- Main settings: standalone CCOptionsFrame (spellbook-safe, Escape to close)
-- Blizzard AddOns stub: single button that opens the standalone frame

local FRAME_W = 560
local FRAME_H = 600
local TAB_H   = 26

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
}
local CLASS_DISPLAY = {
    WARRIOR     = "Warrior",     PALADIN     = "Paladin",
    PRIEST      = "Priest",      DEATHKNIGHT = "Death Knight",
    SHAMAN      = "Shaman",      MAGE        = "Mage",
    WARLOCK     = "Warlock",     MONK        = "Monk",
    DRUID       = "Druid",       DEMONHUNTER = "Demon Hunter",
    EVOKER      = "Evoker",
}
local MIN_DURATIONS = { 30, 60, 90, 120, 180 }

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function MakeLabel(parent, text, size, anchor, ox, oy)
    local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ox or 0, oy or -8)
    fs:SetText(text)
    return fs
end

local function MakeLine(parent, anchor, oy)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(FRAME_W - 32, 1)
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, oy or -4)
    t:SetColorTexture(0.3, 0.3, 0.4, 0.6)
    return t
end

local function MakeCB(parent, label, anchor, ox, oy, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ox or 0, oy or -4)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetText(label)
    return cb, lbl
end

local function ResolveSpell(text)
    local linkID = text:match("|Hspell:(%d+)")
    if linkID then return tonumber(linkID) end
    if text:match("^%d+$") then return tonumber(text) end
    -- name lookup via old compat API (7th return = canonical spellID)
    if GetSpellInfo and text:len() >= 2 then
        local n, _, _, _, _, _, sid = GetSpellInfo(text)
        if n and sid then return sid end
    end
    return nil
end

local function LookupSpellName(spellID)
    if not spellID then return nil end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info then return info.name, info.iconID end
    if GetSpellInfo then
        local n, _, ic = GetSpellInfo(spellID)
        return n, ic
    end
end

-- ── Default Spells tab ───────────────────────────────────────────────────────

function CC:RefreshDefaultSpellList()
    local content = self.defaultSpellContent
    if not content then return end

    for _, c in pairs({ content:GetChildren() }) do c:Hide(); c:SetParent(nil) end
    for _, r in pairs({ content:GetRegions() }) do r:Hide() end

    local byClass = {}
    for spellID, data in pairs(CC.SpellData) do
        if not data.custom then
            local cls = data.class or "UNKNOWN"
            if not byClass[cls] then byClass[cls] = {} end
            byClass[cls][#byClass[cls]+1] = { id = spellID, data = data }
        end
    end
    for cls in pairs(byClass) do
        table.sort(byClass[cls], function(a, b) return a.data.name < b.data.name end)
    end

    local ROW = 22
    local HDR = 20
    local y   = 0

    for _, cls in ipairs(CLASS_ORDER) do
        local spells = byClass[cls]
        if spells and #spells > 0 then
            local c = CC.ClassColors[cls] or CC.ClassColors.UNKNOWN

            local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
            hdr:SetText(CLASS_DISPLAY[cls] or cls)
            hdr:SetTextColor(c[1], c[2], c[3])
            y = y + HDR

            for _, entry in ipairs(spells) do
                local sid  = entry.id
                local data = entry.data

                local row = CreateFrame("Frame", nil, content)
                row:SetSize(content:GetWidth() - 4, ROW)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)

                local ico = row:CreateTexture(nil, "ARTWORK")
                ico:SetSize(16, 16)
                ico:SetPoint("LEFT", 0, 0)
                ico:SetTexture(data.icon)
                ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nm:SetPoint("LEFT", ico, "RIGHT", 4, 0)
                nm:SetWidth(210)
                nm:SetJustifyH("LEFT")
                nm:SetText(data.name)

                local dur = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                dur:SetPoint("LEFT", nm, "RIGHT", 4, 0)
                local m, s = math.floor(data.duration/60), data.duration % 60
                dur:SetText(s == 0 and (m.."m") or (m > 0 and (m.."m "..s.."s") or (s.."s")))

                local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                cb:SetChecked(not (CC.db.disabledSpells and CC.db.disabledSpells[sid]))

                local function Dim()
                    local a = (CC.db.disabledSpells and CC.db.disabledSpells[sid]) and 0.35 or 1.0
                    ico:SetAlpha(a); nm:SetAlpha(a); dur:SetAlpha(a)
                end
                cb:SetScript("OnClick", function(self)
                    if self:GetChecked() then CC.db.disabledSpells[sid] = nil
                    else CC.db.disabledSpells[sid] = true end
                    CC:RefreshRows()
                    Dim()
                end)
                Dim()

                y = y + ROW
            end
            y = y + 4
        end
    end

    content:SetHeight(math.max(y, 20))
end

-- ── Custom Spells tab ────────────────────────────────────────────────────────

function CC:RefreshSpellList()
    local content = self.spellListContent
    if not content then return end

    for _, c in pairs({ content:GetChildren() }) do c:Hide(); c:SetParent(nil) end

    local ROW = 22
    local y   = 0
    local any = false

    for idStr, data in pairs(self.db.customSpells) do
        any = true
        local sid = tonumber(idStr)
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth(), ROW)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(16, 16)
        ico:SetPoint("LEFT", 0, 0)
        ico:SetTexture(data.icon or 134400)
        ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", ico, "RIGHT", 4, 0)
        lbl:SetText(string.format("|cFFCCCCCC%s|r  |cFF888888%ds|r",
            data.name or idStr, data.duration or 0))

        local rmv = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        rmv:SetSize(56, 18)
        rmv:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        rmv:SetText("Remove")
        local s = sid
        rmv:SetScript("OnClick", function() CC:RemoveCustomSpell(s) end)

        y = y + ROW
    end

    if not any then
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", 0, 0)
        fs:SetText("No custom spells added yet.")
    end
    content:SetHeight(math.max(y, 20))
end

-- ── Standalone options frame ─────────────────────────────────────────────────

function CC:OpenOptions()
    if self.optionsFrame then
        self.optionsFrame:SetShown(not self.optionsFrame:IsShown())
        return
    end

    local f = CreateFrame("Frame", "CCOptionsFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
    f:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
    -- Escape key closes it
    tinsert(UISpecialFrames, "CCOptionsFrame")

    -- Title bar (drag handle)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetSize(FRAME_W - 16, 30)
    titleBar:SetPoint("TOP", f, "TOP", 0, -8)
    titleBar:EnableMouse(true)
    titleBar:SetScript("OnMouseDown", function() f:StartMoving() end)
    titleBar:SetScript("OnMouseUp",   function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("|cFF54a3ffCooldownCollaborator|r  |cFF888888" .. CC.version .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local yOff = -46   -- current vertical pen position from top of f

    -- ── Display settings ──────────────────────────────────────────────────

    local hdrDisp = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrDisp:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    hdrDisp:SetText("Display Settings")
    yOff = yOff - 16
    MakeLine(f, hdrDisp, -2)
    yOff = yOff - 6

    local anchor = f   -- for relative positioning below
    local anchorY = yOff

    local cbReady = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cbReady:SetSize(22, 22)
    cbReady:SetPoint("TOPLEFT", f, "TOPLEFT", 16, anchorY)
    cbReady:SetChecked(CC.db.showReady)
    cbReady:SetScript("OnClick", function(self)
        CC.db.showReady = self:GetChecked(); CC:RefreshRows()
    end)
    local lReady = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lReady:SetPoint("LEFT", cbReady, "RIGHT", 2, 0)
    lReady:SetText("Show ready cooldowns")
    yOff = yOff - 26

    local cbLock = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cbLock:SetSize(22, 22)
    cbLock:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    cbLock:SetChecked(CC.db.locked)
    cbLock:SetScript("OnClick", function(self)
        CC.db.locked = self:GetChecked(); CC:UpdateLock()
    end)
    local lLock = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lLock:SetPoint("LEFT", cbLock, "RIGHT", 2, 0)
    lLock:SetText("Lock panel position")
    yOff = yOff - 26

    local cbMM = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cbMM:SetSize(22, 22)
    cbMM:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    cbMM:SetChecked(CC.db.minimapHide)
    cbMM:SetScript("OnClick", function(self)
        CC.db.minimapHide = self:GetChecked()
        if CC.minimapBtn then CC.minimapBtn:SetShown(not CC.db.minimapHide) end
    end)
    local lMM = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lMM:SetPoint("LEFT", cbMM, "RIGHT", 2, 0)
    lMM:SetText("Hide minimap button")
    yOff = yOff - 30

    -- Min duration buttons
    local mdLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mdLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    mdLbl:SetText("Minimum cooldown to track:")
    yOff = yOff - 26

    local durBtns = {}
    for i, val in ipairs(MIN_DURATIONS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(50, 22)
        b:SetText(val.."s")
        if i == 1 then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
        else
            b:SetPoint("LEFT", durBtns[i-1], "RIGHT", 4, 0)
        end
        local v = val
        b:SetScript("OnClick", function()
            CC.db.minDuration = v
            for _, btn in ipairs(durBtns) do btn:SetEnabled(true) end
            b:SetEnabled(false)
            CC:RefreshRows()
        end)
        if CC.db.minDuration == val then b:SetEnabled(false) end
        durBtns[i] = b
    end
    yOff = yOff - 30

    -- Alpha slider
    local alphaLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alphaLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    alphaLbl:SetText("Panel opacity:")
    local alphaSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    alphaSlider:SetSize(200, 16)
    alphaSlider:SetPoint("LEFT", alphaLbl, "RIGHT", 10, 0)
    alphaSlider:SetMinMaxValues(0.2, 1.0)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetValue(CC.db.alpha or 0.9)
    alphaSlider.Text:SetText("")
    alphaSlider.Low:SetText("20%")
    alphaSlider.High:SetText("100%")
    local alphaVal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alphaVal:SetPoint("LEFT", alphaSlider, "RIGHT", 6, 0)
    alphaVal:SetText(string.format("%.0f%%", (CC.db.alpha or 0.9) * 100))
    alphaSlider:SetScript("OnValueChanged", function(self, v)
        CC.db.alpha = v
        alphaVal:SetText(string.format("%.0f%%", v * 100))
        if CC.frame then CC.frame:SetAlpha(v) end
    end)
    yOff = yOff - 30

    -- Scale slider
    local scaleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    scaleLbl:SetText("Panel scale:    ")
    local scaleSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    scaleSlider:SetSize(200, 16)
    scaleSlider:SetPoint("LEFT", scaleLbl, "RIGHT", 10, 0)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetValue(CC.db.scale or 1.0)
    scaleSlider.Text:SetText("")
    scaleSlider.Low:SetText("0.5x")
    scaleSlider.High:SetText("2.0x")
    local scaleVal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleVal:SetPoint("LEFT", scaleSlider, "RIGHT", 6, 0)
    scaleVal:SetText(string.format("%.1fx", CC.db.scale or 1.0))
    scaleSlider:SetScript("OnValueChanged", function(self, v)
        CC.db.scale = v
        scaleVal:SetText(string.format("%.1fx", v))
        if CC.frame then CC.frame:SetScale(v) end
    end)
    yOff = yOff - 26

    -- ── Spell tracking section ────────────────────────────────────────────

    local hdrSpells = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrSpells:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    hdrSpells:SetText("Spell Tracking")
    yOff = yOff - 16
    MakeLine(f, hdrSpells, -2)
    yOff = yOff - 10

    -- Tab buttons
    local TAB_Y = yOff
    local tabDefault = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabDefault:SetSize(130, TAB_H)
    tabDefault:SetText("Default Spells")
    tabDefault:SetPoint("TOPLEFT", f, "TOPLEFT", 16, TAB_Y)

    local tabCustom = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tabCustom:SetSize(130, TAB_H)
    tabCustom:SetText("Custom Spells")
    tabCustom:SetPoint("LEFT", tabDefault, "RIGHT", 4, 0)

    yOff = yOff - (TAB_H + 4)

    -- Content area
    local contentArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    contentArea:SetSize(FRAME_W - 32, FRAME_H - (-yOff) - 16)
    contentArea:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    contentArea:SetBackdrop({
        bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    contentArea:SetBackdropColor(0.04, 0.04, 0.07, 0.8)
    contentArea:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)

    local CAW = contentArea:GetWidth() - 8
    local CAH = contentArea:GetHeight() - 8

    -- ── Default spells panel ──

    local defPanel = CreateFrame("ScrollFrame", "CCDefScroll", contentArea, "UIPanelScrollFrameTemplate")
    defPanel:SetSize(CAW - 16, CAH)
    defPanel:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 4, -4)

    local defContent = CreateFrame("Frame", nil, defPanel)
    defContent:SetWidth(CAW - 32)
    defPanel:SetScrollChild(defContent)

    self.defaultSpellContent = defContent

    -- ── Custom spells panel ──

    local custPanel = CreateFrame("Frame", nil, contentArea)
    custPanel:SetSize(CAW, CAH)
    custPanel:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 4, -4)
    custPanel:Hide()

    -- Instruction
    local hint = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", custPanel, "TOPLEFT", 4, -4)
    hint:SetText("Type a spell name or ID, then set its cooldown duration and click Add.\nShift-click a spell link to auto-fill (spellbook must be open).")
    hint:SetJustifyH("LEFT")
    hint:SetWidth(CAW - 16)

    local spellInput = CreateFrame("EditBox", "CCSpellInput", custPanel, "InputBoxTemplate")
    spellInput:SetSize(180, 22)
    spellInput:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 2, -10)
    spellInput:SetAutoFocus(false)
    spellInput:SetNumeric(false)
    spellInput:SetMaxLetters(128)
    spellInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local preview = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)
    preview:SetWidth(160)
    preview:SetTextColor(0.5, 0.85, 1)

    local durLbl = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    durLbl:SetPoint("TOPLEFT", spellInput, "BOTTOMLEFT", 0, -10)
    durLbl:SetText("Duration (sec):")

    local durInput = CreateFrame("EditBox", "CCDurInput", custPanel, "InputBoxTemplate")
    durInput:SetSize(60, 22)
    durInput:SetPoint("LEFT", durLbl, "RIGHT", 6, 0)
    durInput:SetAutoFocus(false)
    durInput:SetNumeric(true)
    durInput:SetMaxLetters(5)
    durInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, custPanel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", durInput, "RIGHT", 8, 0)
    addBtn:SetText("Add Spell")

    local pendingID = nil

    spellInput:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        local linkID = text:match("|Hspell:(%d+)")
        if linkID then
            pendingID = tonumber(linkID)
            self:SetText(linkID)
            local name = LookupSpellName(pendingID)
            preview:SetText(name or "|cFFFF4444Unknown|r")
            return
        end
        pendingID = ResolveSpell(text)
        if pendingID then
            local name = LookupSpellName(pendingID)
            preview:SetText(name or "|cFFFF4444Unknown ID|r")
        elseif text:len() > 0 then
            preview:SetText("|cFF888888resolving...|r")
        else
            preview:SetText("")
        end
    end)

    addBtn:SetScript("OnClick", function()
        local sid = pendingID or ResolveSpell(spellInput:GetText())
        local dur = tonumber(durInput:GetText())
        if CC:AddCustomSpell(sid, dur) then
            spellInput:SetText(""); durInput:SetText(""); preview:SetText("")
            pendingID = nil
            CC:RefreshSpellList()
        end
    end)

    -- Custom list scroll
    local listHdr = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    listHdr:SetPoint("TOPLEFT", durLbl, "BOTTOMLEFT", 0, -18)
    listHdr:SetText("Custom tracked spells:")

    local listScroll = CreateFrame("ScrollFrame", "CCCustScroll", custPanel, "UIPanelScrollFrameTemplate")
    listScroll:SetSize(CAW - 16, CAH - 130)
    listScroll:SetPoint("TOPLEFT", listHdr, "BOTTOMLEFT", 0, -6)

    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetWidth(CAW - 32)
    listScroll:SetScrollChild(listContent)
    self.spellListContent = listContent

    -- ── Tab switching ──

    local function ShowDefault()
        defPanel:Show(); custPanel:Hide()
        tabDefault:SetEnabled(false); tabCustom:SetEnabled(true)
    end
    local function ShowCustom()
        defPanel:Hide(); custPanel:Show()
        tabDefault:SetEnabled(true); tabCustom:SetEnabled(false)
        CC:RefreshSpellList()
    end
    tabDefault:SetScript("OnClick", ShowDefault)
    tabCustom:SetScript("OnClick",  ShowCustom)

    -- Default tab active on open
    ShowDefault()
    CC:RefreshDefaultSpellList()
    CC:RefreshSpellList()

    self.optionsFrame = f
    f:Show()
end

-- ── Blizzard AddOns stub (opens the standalone frame) ────────────────────────

function CC:BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel:SetSize(400, 120)

    local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 16, -20)
    lbl:SetText("|cFF54a3ffCooldownCollaborator|r " .. CC.version)

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    note:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -8)
    note:SetText("Click below to open the full settings window.\nYou can also right-click the minimap button or type /cdc settings.")

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(200, 26)
    openBtn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    openBtn:SetText("Open CooldownCollaborator Settings")
    openBtn:SetScript("OnClick", function() CC:OpenOptions() end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "CooldownCollaborator")
    Settings.RegisterAddOnCategory(category)
    self.optionsCategoryID = category.ID
end
