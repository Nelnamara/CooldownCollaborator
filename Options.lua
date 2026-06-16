-- Options panel — registered with Blizzard Settings (Escape → Interface → AddOns)
-- Tab 1: Default Spells  — built-in spell list with per-spell enable/disable
-- Tab 2: Custom Spells   — add/remove custom tracked spells by ID or shift-click link

local PANEL_W = 580
local PANEL_H = 620

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
    EVOKER      = "Evoker",      UNKNOWN     = "Custom",
}
local MIN_DURATIONS = { 30, 60, 90, 120, 180 }

-- ── Small UI helpers ─────────────────────────────────────────────────────────

local function Hdr(parent, text, anchor, oy)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, oy or -12)
    fs:SetText(text)
    return fs
end

local function Line(parent, anchor, oy)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(PANEL_W - 32, 1)
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, oy or -4)
    t:SetColorTexture(0.3, 0.3, 0.4, 0.6)
    return t
end

local function CB(parent, label, anchor, oy, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, oy or -6)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetText(label)
    return cb, lbl
end

local function Slider(parent, label, lo, hi, step, anchor, oy, getter, setter, fmtFn)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetSize(240, 16)
    s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, oy or -22)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetValue(getter())
    s.Text:SetText(label)
    s.Low:SetText(tostring(lo))
    s.High:SetText(tostring(hi))
    local vt = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    vt:SetPoint("LEFT", s, "RIGHT", 8, 0)
    vt:SetText(fmtFn(getter()))
    s:SetScript("OnValueChanged", function(self, v)
        setter(v)
        vt:SetText(fmtFn(v))
    end)
    return s
end

-- ── Tab switching ────────────────────────────────────────────────────────────

local function MakeTabs(panel, labels, anchor, oy, onSwitch)
    local btns = {}
    panel.numTabs = #labels
    for i, text in ipairs(labels) do
        local t = CreateFrame("Button", "CCOptTab"..i, panel, "TabButtonTemplate")
        t:SetText(text)
        t:SetID(i)
        PanelTemplates_TabResize(t, 4)
        if i == 1 then
            t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, oy or -4)
        else
            t:SetPoint("LEFT", btns[i-1], "RIGHT", -14, 0)
        end
        t:SetScript("OnClick", function()
            PanelTemplates_SetTab(panel, i)
            onSwitch(i)
        end)
        btns[i] = t
    end
    PanelTemplates_SetNumTabs(panel, #labels)
    PanelTemplates_SetTab(panel, 1)
    return btns
end

-- ── Default spells list (Tab 1) ──────────────────────────────────────────────

function CC:BuildDefaultSpellsTab(parent)
    local scroll = CreateFrame("ScrollFrame", "CCDefaultScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(PANEL_W - 48, parent:GetHeight() - 8)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(PANEL_W - 64)
    scroll:SetScrollChild(content)

    self.defaultSpellContent = content
    self.defaultSpellScroll  = scroll

    self:RefreshDefaultSpellList()
end

function CC:RefreshDefaultSpellList()
    local content = self.defaultSpellContent
    if not content then return end

    for _, child in pairs({ content:GetChildren() }) do child:Hide(); child:SetParent(nil) end
    for _, child in pairs({ content:GetRegions() }) do child:Hide() end

    -- Group spells by class
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

    local CROW = 22    -- spell row height
    local CHDR = 24    -- class header height
    local y = 0

    for _, cls in ipairs(CLASS_ORDER) do
        local spells = byClass[cls]
        if spells and #spells > 0 then
            local c = CC.ClassColors[cls] or CC.ClassColors.UNKNOWN

            -- Class header
            local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            hdr:SetText(CLASS_DISPLAY[cls] or cls)
            hdr:SetTextColor(c[1], c[2], c[3])
            y = y + CHDR

            for _, entry in ipairs(spells) do
                local spellID = entry.id
                local data    = entry.data
                local row     = CreateFrame("Frame", nil, content)
                row:SetSize(content:GetWidth(), CROW)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)

                local ico = row:CreateTexture(nil, "ARTWORK")
                ico:SetSize(18, 18)
                ico:SetPoint("LEFT", row, "LEFT", 0, 0)
                ico:SetTexture(data.icon)
                ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nm:SetPoint("LEFT", ico, "RIGHT", 4, 0)
                nm:SetText(data.name)
                nm:SetWidth(220)
                nm:SetJustifyH("LEFT")

                local dur = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                dur:SetPoint("LEFT", nm, "RIGHT", 4, 0)
                local m = math.floor(data.duration / 60)
                local s = data.duration % 60
                dur:SetText(s == 0 and (m.."m") or (m > 0 and (m.."m "..s.."s") or (s.."s")))

                -- Enable/disable checkbox
                local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                cb:SetChecked(not (CC.db.disabledSpells and CC.db.disabledSpells[spellID]))
                local sid = spellID
                cb:SetScript("OnClick", function(self)
                    if self:GetChecked() then
                        CC.db.disabledSpells[sid] = nil
                    else
                        CC.db.disabledSpells[sid] = true
                    end
                    CC:RefreshRows()
                end)

                -- Dim row when disabled
                local function UpdateRowAlpha()
                    local a = (CC.db.disabledSpells and CC.db.disabledSpells[spellID]) and 0.4 or 1.0
                    ico:SetAlpha(a); nm:SetAlpha(a); dur:SetAlpha(a)
                end
                cb:SetScript("PostClick", UpdateRowAlpha)
                UpdateRowAlpha()

                y = y + CROW
            end

            y = y + 4  -- gap between classes
        end
    end

    content:SetHeight(math.max(y, 20))
end

-- ── Custom spells list (Tab 2) ───────────────────────────────────────────────

function CC:BuildCustomSpellsTab(parent)
    local instrText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    instrText:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -4)
    instrText:SetText("Shift-click a spell from your spellbook, or type a Spell ID:")

    local spellInput = CreateFrame("EditBox", "CCSpellInput", parent, "InputBoxTemplate")
    spellInput:SetSize(200, 20)
    spellInput:SetPoint("TOPLEFT", instrText, "BOTTOMLEFT", 2, -8)
    spellInput:SetAutoFocus(false)
    spellInput:SetNumeric(false)
    spellInput:SetMaxLetters(128)

    local preview = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    preview:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)
    preview:SetTextColor(0.5, 0.8, 1)
    preview:SetWidth(150)

    local durLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    durLabel:SetPoint("TOPLEFT", spellInput, "BOTTOMLEFT", 0, -10)
    durLabel:SetText("Cooldown duration (seconds):")

    local durInput = CreateFrame("EditBox", "CCDurInput", parent, "InputBoxTemplate")
    durInput:SetSize(60, 20)
    durInput:SetPoint("LEFT", durLabel, "RIGHT", 6, 0)
    durInput:SetAutoFocus(false)
    durInput:SetNumeric(true)
    durInput:SetMaxLetters(5)

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", durInput, "RIGHT", 8, 0)
    addBtn:SetText("Add Spell")

    local pendingSpellID = nil

    spellInput:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        local linkID = text:match("|Hspell:(%d+)")
        if linkID then
            pendingSpellID = tonumber(linkID)
            self:SetText(linkID)
        else
            pendingSpellID = tonumber(text)
        end
        if pendingSpellID then
            local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(pendingSpellID)
            local name = info and info.name
                or (GetSpellInfo and select(1, GetSpellInfo(pendingSpellID)))
            preview:SetText(name or "|cFFFF4444Unknown ID|r")
        else
            pendingSpellID = nil
            preview:SetText("")
        end
    end)

    addBtn:SetScript("OnClick", function()
        local sid = pendingSpellID or tonumber(spellInput:GetText())
        local dur = tonumber(durInput:GetText())
        if CC:AddCustomSpell(sid, dur) then
            spellInput:SetText(""); durInput:SetText(""); preview:SetText("")
            pendingSpellID = nil
            CC:RefreshSpellList()
        end
    end)

    -- Custom spell scroll list
    local listLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    listLabel:SetPoint("TOPLEFT", durLabel, "BOTTOMLEFT", 0, -18)
    listLabel:SetText("Custom tracked spells:")

    local scroll = CreateFrame("ScrollFrame", "CCCustomScroll", parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(PANEL_W - 48, 150)
    scroll:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -6)

    local listContent = CreateFrame("Frame", nil, scroll)
    listContent:SetSize(PANEL_W - 64, 150)
    scroll:SetScrollChild(listContent)

    self.spellListContent = listContent
    self:RefreshSpellList()
end

function CC:RefreshSpellList()
    local content = self.spellListContent
    if not content then return end

    for _, child in pairs({ content:GetChildren() }) do child:Hide(); child:SetParent(nil) end

    local y = 0
    local ROW = 22
    local hasAny = false

    for idStr, data in pairs(self.db.customSpells) do
        hasAny = true
        local spellID = tonumber(idStr)
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth(), ROW)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", row, "LEFT", 0, 0)
        ico:SetTexture(data.icon or 134400)
        ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", ico, "RIGHT", 4, 0)
        lbl:SetText(string.format("|cFFCCCCCC%s|r  |cFF888888%ds|r",
            data.name or idStr, data.duration or 0))

        local rmv = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        rmv:SetSize(60, 18)
        rmv:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        rmv:SetText("Remove")
        local sid = spellID
        rmv:SetScript("OnClick", function() CC:RemoveCustomSpell(sid) end)

        y = y + ROW
    end

    if not hasAny then
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        empty:SetText("No custom spells added yet.")
    end
    content:SetHeight(math.max(y, 20))
end

-- ── Main panel builder ───────────────────────────────────────────────────────

function CC:BuildOptionsPanel()
    local panel = CreateFrame("Frame")
    panel:SetSize(PANEL_W, PANEL_H)

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFF54a3ffCooldownCollaborator|r")
    local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
    ver:SetText("v"..CC.version)

    -- ── Display settings ──
    local hdrDisp = Hdr(panel, "Display Settings", title, -18)
    Line(panel, hdrDisp, -2)

    local cbReady, _ = CB(panel, "Show ready cooldowns", hdrDisp, -12,
        function() return CC.db.showReady end,
        function(v) CC.db.showReady = v; CC:RefreshRows() end)

    local cbLock, _ = CB(panel, "Lock panel position", cbReady, -2,
        function() return CC.db.locked end,
        function(v) CC.db.locked = v; CC:UpdateLock() end)

    local cbMM, _ = CB(panel, "Hide minimap button", cbLock, -2,
        function() return CC.db.minimapHide end,
        function(v)
            CC.db.minimapHide = v
            if CC.minimapBtn then CC.minimapBtn:SetShown(not v) end
        end)

    -- Min duration row
    local mdLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    mdLbl:SetPoint("TOPLEFT", cbMM, "BOTTOMLEFT", 22, -10)
    mdLbl:SetText("Minimum cooldown to track:")

    local durBtns = {}
    for i, val in ipairs(MIN_DURATIONS) do
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(52, 22)
        b:SetText(val.."s")
        if i == 1 then
            b:SetPoint("TOPLEFT", mdLbl, "BOTTOMLEFT", 0, -4)
        else
            b:SetPoint("LEFT", durBtns[i-1], "RIGHT", 4, 0)
        end
        local v = val
        b:SetScript("OnClick", function()
            CC.db.minDuration = v
            for j, btn in ipairs(durBtns) do btn:SetEnabled(true) end
            b:SetEnabled(false)
            CC:RefreshRows()
        end)
        if CC.db.minDuration == val then b:SetEnabled(false) end
        durBtns[i] = b
    end

    Slider(panel, "Panel opacity", 0.3, 1.0, 0.05, durBtns[1], -24,
        function() return CC.db.alpha end,
        function(v) CC.db.alpha = v; if CC.frame then CC.frame:SetAlpha(v) end end,
        function(v) return string.format("%.0f%%", v * 100) end)

    Slider(panel, "Panel scale", 0.6, 2.0, 0.1, durBtns[1], -52,
        function() return CC.db.scale end,
        function(v) CC.db.scale = v; if CC.frame then CC.frame:SetScale(v) end end,
        function(v) return string.format("%.1f", v) end)

    -- ── Tab section ──
    local hdrSpells = Hdr(panel, "Spell Tracking", durBtns[1], -76)
    Line(panel, hdrSpells, -2)

    -- Tab content area
    local tabArea = CreateFrame("Frame", nil, panel)
    tabArea:SetSize(PANEL_W - 32, 240)

    local defaultContent = CreateFrame("Frame", nil, tabArea)
    defaultContent:SetAllPoints(tabArea)

    local customContent = CreateFrame("Frame", nil, tabArea)
    customContent:SetAllPoints(tabArea)
    customContent:Hide()

    local tabs = MakeTabs(panel,
        { "Default Spells", "Custom Spells" },
        hdrSpells, -14,
        function(id)
            if id == 1 then
                defaultContent:Show(); customContent:Hide()
            else
                defaultContent:Hide(); customContent:Show()
            end
        end)

    tabArea:SetPoint("TOPLEFT", tabs[1], "BOTTOMLEFT", 0, 2)

    self:BuildDefaultSpellsTab(defaultContent)
    self:BuildCustomSpellsTab(customContent)

    -- Register
    local category = Settings.RegisterCanvasLayoutCategory(panel, "CooldownCollaborator")
    Settings.RegisterAddOnCategory(category)
    self.optionsCategory = category
end
