-- Options for CooldownCollaborator
-- Main settings: standalone CCOptionsFrame (spellbook-safe, Escape to close)
-- Blizzard AddOns stub: single button that opens the standalone frame

local L = CC.L

local FRAME_W = 560
local FRAME_H = 640
local TAB_H   = 26

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER", "HUNTER", "ROGUE",
}
local CLASS_DISPLAY = {
    WARRIOR     = L["Warrior"],     PALADIN     = L["Paladin"],
    PRIEST      = L["Priest"],      DEATHKNIGHT = L["Death Knight"],
    SHAMAN      = L["Shaman"],      MAGE        = L["Mage"],
    WARLOCK     = L["Warlock"],     MONK        = L["Monk"],
    DRUID       = L["Druid"],       DEMONHUNTER = L["Demon Hunter"],
    EVOKER      = L["Evoker"],      HUNTER      = L["Hunter"],
    ROGUE       = L["Rogue"],
    ITEMS       = L["ITEMS"],   -- the group header for item spells
}
local MIN_DURATIONS = { 30, 60, 90, 120, 180 }

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function ResolveSpell(text)
    local linkID = text:match("|Hspell:(%d+)")
    if linkID then return tonumber(linkID) end
    if text:match("^%d+$") then return tonumber(text) end
    -- name lookup: C_Spell.GetSpellInfo takes a name on the modern engine (the
    -- only way on Forever), then the old global where it exists
    if text:len() >= 2 then
        local ok, n, _, sid = pcall(CC.Compat.GetSpellInfo, text)
        if ok and n and sid then return sid end
    end
    return nil
end

local function LookupSpellName(spellID)
    if not spellID then return nil end
    return CC.Compat.GetSpellInfo(spellID)
end

-- ── Windows: one list for Getting Started, lock, reset and on/off ────────────
-- Each entry names the saved setting and the frame, so a control and a slash command
-- always agree. `onKey` nil means the main panel: its On is "not closed by the player".

CC.WINDOWS = {
    { key = "main",       label = L["Main panel"],     frame = "frame",           w = 64, h = 46, xKey = "x",           yKey = "y",
      lockKey = "locked",          lockUpdate = "UpdateLock" },
    { key = "essentials", label = L["Essentials bar"], frame = "essentialsFrame", w = 40, h = 46, xKey = "essentialsX", yKey = "essentialsY",
      onKey = "essentialsEnabled", refresh = "RefreshEssentials", lockKey = "essentialsLocked", lockUpdate = "UpdateEssentialsLock" },
    { key = "lanes",      label = L["Lane view"],      frame = "laneFrame",       w = 70, h = 30, xKey = "laneX",       yKey = "laneY",
      onKey = "laneEnabled",       refresh = "RefreshLanes", lockKey = "laneLocked", lockUpdate = "UpdateLaneLock" },
    { key = "dead",       label = L["Dead list"],      frame = "deadFrame",       w = 46, h = 36, xKey = "deadListX",   yKey = "deadListY",
      onKey = "deadListEnabled",   refresh = "RefreshDeadList", lockKey = "deadListLocked" },
    { key = "externals",  label = L["Externals"],      frame = "externalsFrame",  w = 58, h = 20, xKey = "externalsX",  yKey = "externalsY",
      onKey = "externalsEnabled",  refresh = "RefreshExternalsStrip", lockKey = "externalsLocked" },
    { key = "mana",       label = L["Mana"],           frame = "manaFrame",       w = 40, h = 26, xKey = "manaX",       yKey = "manaY",
      onKey = "manaEnabled",       refresh = "RefreshManaStrip", lockKey = "manaLocked" },
    { key = "burst",      label = L["Burst"],          frame = "burstFrame",      w = 72, h = 16, xKey = "burstX",      yKey = "burstY",
      onKey = "burstEnabled",      refresh = "RefreshBurstLine", lockKey = "burstLocked" },
}

function CC:WindowIsOn(w)
    if not w.onKey then return not self.db.panelClosed end
    return self.db[w.onKey] and true or false
end

function CC:SetWindowOn(w, on)
    on = on and true or false
    if not w.onKey then
        if on then self:OpenPanel() else self:ClosePanel() end
        return
    end
    self.db[w.onKey] = on
    self:RefreshView(w.refresh)
end

function CC:SetOneWindowLocked(w, locked)
    self.db[w.lockKey] = locked and true or false
    if w.lockUpdate and self[w.lockUpdate] then self[w.lockUpdate](self) end
    if self.lockCheck then self.lockCheck:SetChecked(self:AreWindowsLocked()) end
end

-- Back to where the window starts: the saved position's default, and the frame moves there now.
function CC:ResetWindow(w)
    local defaults = self.DEFAULTS or {}
    local x, y = defaults[w.xKey] or 0, defaults[w.yKey] or 0
    self.db[w.xKey], self.db[w.yKey] = x, y
    local f = self[w.frame]
    if f then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

-- One lock for every window: /cdc lock, /cdc unlock and the Settings box come through here.
function CC:AreWindowsLocked()
    for _, w in ipairs(CC.WINDOWS) do
        if not self.db[w.lockKey] then return false end
    end
    return true
end

function CC:SetWindowsLocked(locked)
    locked = locked and true or false
    for _, w in ipairs(CC.WINDOWS) do self.db[w.lockKey] = locked end
    self:UpdateLock()
    self:UpdateEssentialsLock()
    self:UpdateLaneLock()
    if self.lockCheck then self.lockCheck:SetChecked(locked) end
    if self.startPage and self.startPage.refresh then self.startPage.refresh() end
end

-- ── Show presets and kinds (P2) ──────────────────────────────────────────────
-- A preset picks spells by their `kind` (the Data rows). Choosing one unticks the default
-- spells whose kind it leaves out; a spell with no kind stays as it was. Everything ticks all.

CC.PRESET_ORDER = { "everything", "simple", "healer", "tank", "dps" }
CC.PRESETS = {
    everything = { label = L["Everything"] },
    simple     = { label = L["Simple"],  kinds = { rez = true, lust = true, raid = true } },
    healer     = { label = L["Healer"],  kinds = { rez = true, lust = true, raid = true, external = true, mana = true } },
    tank       = { label = L["Tank"],    kinds = { rez = true, lust = true, raid = true, external = true, utility = true } },
    dps        = { label = L["DPS"],     kinds = { rez = true, lust = true, raid = true, utility = true } },
}

local KIND_ORDER = { "rez", "lust", "raid", "external", "mana", "personal", "utility" }
local KIND_LABEL = {
    rez = L["Battle rez"], lust = L["Bloodlust"], raid = L["Raid cooldowns"], external = L["Externals"],
    mana = L["Mana"], personal = L["Personal defensives"], utility = L["Utility"], other = L["Other"],
}

function CC:ApplyShowPreset(name)
    local preset = CC.PRESETS[name]
    if not preset then return false end
    self.db.showPreset = name
    self.db.disabledSpells = self.db.disabledSpells or {}
    for id, data in pairs(CC.SpellData) do
        if not data.custom and not data.consumable then
            if preset.kinds and data.kind and not preset.kinds[data.kind] then
                self.db.disabledSpells[id] = true
            else
                self.db.disabledSpells[id] = nil
            end
        end
    end
    self:RefreshView("RefreshRows")
    self:RefreshDefaultSpellList()
    return true
end

-- ── Ready alerts per spell (P1) ──────────────────────────────────────────────

-- The game's named sound constants, with the plain number where a client lacks the name.
local function Sound(name, number)
    return SOUNDKIT and SOUNDKIT[name] or number
end
CC.ALERT_SOUNDS = {
    { id = Sound("RAID_WARNING", 8959),             label = L["Raid warning"] },
    { id = Sound("READY_CHECK", 8960),              label = L["Ready check"] },
    { id = Sound("ALARM_CLOCK_WARNING_3", 12867),   label = L["Alarm clock"] },
    { id = Sound("AUCTION_WINDOW_OPEN", 5274),      label = L["Auction bell"] },
}

function CC:GetAlert(spellID)
    local a = self.db.alerts
    local cfg = a and a[spellID]
    return type(cfg) == "table" and cfg or nil
end

function CC:SetAlertEnabled(spellID, on)
    self.db.alerts = self.db.alerts or {}
    if on then
        if not self:GetAlert(spellID) then
            self.db.alerts[spellID] = { sound = true, flash = true, midscreen = false, warn = 0 }
        end
    else
        self.db.alerts[spellID] = nil
    end
    self:UpdateAlertBell(spellID)
end

-- field: "sound" (true, an ID or false), "flash", "midscreen" or "warn" (seconds)
function CC:SetAlertField(spellID, field, value)
    local cfg = self:GetAlert(spellID)
    if not cfg then return false end
    cfg[field] = value
    return true
end

-- Which entry of CC.ALERT_SOUNDS the saved sound is (true: the first, the raid warning).
function CC:AlertSoundIndex(cfg)
    if cfg.sound == true then return 1 end
    for i, s in ipairs(CC.ALERT_SOUNDS) do
        if s.id == cfg.sound then return i end
    end
    return nil
end

local bells = {}   -- [spellID] = the bell buttons showing it

function CC:UpdateAlertBell(spellID)
    for _, b in ipairs(bells[spellID] or {}) do
        if b.icon then b.icon:SetDesaturated(self:GetAlert(spellID) == nil) end
    end
end

local function NewBell(row, spellID, anchor, dx)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(18, 18)
    b:SetPoint("RIGHT", anchor, "RIGHT", dx, 0)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon
    icon:SetDesaturated(CC:GetAlert(spellID) == nil)
    b:SetScript("OnClick", function(widget) CC:OpenAlertOptions(spellID, widget) end)
    b:SetScript("OnEnter", function(widget)
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Ready alert"])
        GameTooltip:AddLine(L["Sound, row flash, a mid-screen icon or a warning before it is back, for this spell."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bells[spellID] = bells[spellID] or {}
    table.insert(bells[spellID], b)
    return b
end

-- The one alert box, for whichever spell's bell was clicked.
function CC:OpenAlertOptions(spellID, anchor)
    local f = self.alertFrame
    if not f then
        f = CreateFrame("Frame", "CCAlertOptions", UIParent, CC.BackdropTemplate)
        f:SetSize(250, 236)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 20,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
        f:SetBackdropBorderColor(0.4, 0.4, 0.6, 1)
        tinsert(UISpecialFrames, "CCAlertOptions")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() f:Hide() end)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -14)
        f.title:SetWidth(210)
        f.title:SetJustifyH("LEFT")

        local function Check(y, text, onClick)
            local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y)
            local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            lbl:SetText(text)
            cb:SetScript("OnClick", function(widget) onClick(widget:GetChecked() and true or false) end)
            return cb
        end
        local function Sid() return f.spellID end

        f.enable = Check(-40, L["Alert when it is ready"], function(on)
            CC:SetAlertEnabled(Sid(), on)
            f:Refresh()
        end)
        f.sound = Check(-68, L["Play a sound"], function(on)
            local cfg = CC:GetAlert(Sid())
            if cfg then cfg.sound = on and (cfg.lastSound or true) or false end
            f:Refresh()
        end)
        f.soundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.soundBtn:SetSize(104, 20)
        f.soundBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -96)
        f.soundBtn:SetScript("OnClick", function()
            local cfg = CC:GetAlert(Sid())
            if not cfg or not cfg.sound then return end
            local nextIndex = ((CC:AlertSoundIndex(cfg) or 0) % #CC.ALERT_SOUNDS) + 1
            cfg.sound = CC.ALERT_SOUNDS[nextIndex].id
            f:Refresh()
        end)
        f.testBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.testBtn:SetSize(50, 20)
        f.testBtn:SetPoint("LEFT", f.soundBtn, "RIGHT", 4, 0)
        f.testBtn:SetText(L["Test"])
        f.testBtn:SetScript("OnClick", function()
            local cfg = CC:GetAlert(Sid())
            local idx = cfg and cfg.sound and CC:AlertSoundIndex(cfg)
            if idx then pcall(PlaySound, CC.ALERT_SOUNDS[idx].id, "Master") end
        end)
        f.flash = Check(-124, L["Flash its row"], function(on)
            CC:SetAlertField(Sid(), "flash", on)
        end)
        f.mid = Check(-152, L["Show its icon in the middle of the screen"], function(on)
            CC:SetAlertField(Sid(), "midscreen", on)
        end)
        local warnLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        warnLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -190)
        warnLbl:SetText(L["Warn this many seconds before:"])
        f.warn = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.warn:SetSize(40, 20)
        f.warn:SetPoint("LEFT", warnLbl, "RIGHT", 10, 0)
        f.warn:SetAutoFocus(false)
        f.warn:SetNumeric(true)
        f.warn:SetMaxLetters(3)
        f.warn:SetScript("OnEscapePressed", function(widget) widget:ClearFocus() end)
        f.warn:SetScript("OnEnterPressed", function(widget) widget:ClearFocus() end)
        f.warn:SetScript("OnTextChanged", function(widget, userInput)
            if userInput then CC:SetAlertField(Sid(), "warn", tonumber(widget:GetText()) or 0) end
        end)

        function f:Refresh()
            local cfg = CC:GetAlert(self.spellID) or {}
            local on = CC:GetAlert(self.spellID) ~= nil
            local idx = on and cfg.sound and CC:AlertSoundIndex(cfg) or nil
            self.enable:SetChecked(on)
            self.sound:SetChecked(on and cfg.sound and true or false)
            self.soundBtn:SetText(idx and CC.ALERT_SOUNDS[idx].label or ((on and cfg.sound) and L["Custom sound"] or L["No sound"]))
            self.soundBtn:SetEnabled(on and cfg.sound and true or false)
            self.testBtn:SetEnabled(idx ~= nil)
            self.flash:SetChecked(on and cfg.flash ~= false)
            self.mid:SetChecked(on and cfg.midscreen == true)
            self.warn:SetText(tostring(tonumber(cfg.warn) or 0))
            for _, w in ipairs({ self.sound, self.flash, self.mid, self.warn }) do w:SetEnabled(on) end
        end
        self.alertFrame = f
    end
    f.spellID = spellID
    local data = CC.SpellData[spellID]
    f.title:SetText(string.format(L["%s ready alert"], data and data.name or string.format(L["Spell %d"], spellID)))
    f:ClearAllPoints()
    if self.optionsFrame then
        f:SetPoint("TOPLEFT", self.optionsFrame, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:Refresh()
    f:Show()
    return anchor
end

-- ── Default Spells tab ───────────────────────────────────────────────────────

local ROW = 22
local HDR = 20

-- One spell's row in the Default Spells list: icon, name, cooldown, bell, tick.
local function DefaultRow(content, y, sid, data)
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
    nm:SetWidth(190)
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
    NewBell(row, sid, cb, -24)

    local function Dim()
        local a = (CC.db.disabledSpells and CC.db.disabledSpells[sid]) and 0.35 or 1.0
        ico:SetAlpha(a); nm:SetAlpha(a); dur:SetAlpha(a)
    end
    cb:SetScript("OnClick", function(widget)
        if widget:GetChecked() then CC.db.disabledSpells[sid] = nil
        else CC.db.disabledSpells[sid] = true end
        CC.db.showPreset = "custom"
        CC:RefreshRows()
        Dim()
        if CC.RefreshPresetButtons then CC:RefreshPresetButtons() end
    end)
    Dim()
end

function CC:RefreshDefaultSpellList()
    local content = self.defaultSpellContent
    if not content then return end

    for _, c in pairs({ content:GetChildren() }) do c:Hide(); c:SetParent(nil) end
    for _, r in pairs({ content:GetRegions() }) do r:Hide() end
    for id in pairs(bells) do bells[id] = nil end

    -- group by class (the default) or by what the spell is for
    local byKind = self.db.spellGroupBy == "kind"
    local groups, order, label = {}, {}, {}
    if byKind then
        for _, k in ipairs(KIND_ORDER) do order[#order + 1] = k; label[k] = KIND_LABEL[k] end
        order[#order + 1] = "other"; label.other = KIND_LABEL.other
    else
        for _, c in ipairs(CLASS_ORDER) do order[#order + 1] = c; label[c] = CLASS_DISPLAY[c] end
        order[#order + 1] = "ITEMS"; label.ITEMS = CLASS_DISPLAY.ITEMS
    end
    for spellID, data in pairs(CC.SpellData) do
        if not data.custom and not data.consumable then
            local g
            if byKind then
                g = KIND_LABEL[data.kind or ""] and data.kind or "other"
            else
                g = data.class or "UNKNOWN"
            end
            groups[g] = groups[g] or {}
            groups[g][#groups[g] + 1] = { id = spellID, data = data }
        end
    end
    for g in pairs(groups) do
        table.sort(groups[g], function(a, b) return a.data.name < b.data.name end)
    end

    local y = 0
    for _, g in ipairs(order) do
        local spells = groups[g]
        if spells and #spells > 0 then
            local c = byKind and { 1, 0.82, 0 } or CC.ClassColors[g] or CC.ClassColors.UNKNOWN

            local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
            hdr:SetText(label[g] or g)
            hdr:SetTextColor(c[1], c[2], c[3])
            y = y + HDR

            for _, entry in ipairs(spells) do
                DefaultRow(content, y, entry.id, entry.data)
                y = y + ROW
            end
            y = y + 4
        end
    end

    content:SetHeight(math.max(y, 20))
end

-- ── Custom Spells tab ────────────────────────────────────────────────────────

-- Turn a shift-clicked spell link into the box's text while it has focus
local function SpellIDFromLink(link)
    local id = type(link) == "string" and link:match("|Hspell:(%d+)")
    return id and tonumber(id) or nil
end

function CC:RefreshSpellList()
    local content = self.spellListContent
    if not content then return end

    for _, c in pairs({ content:GetChildren() }) do c:Hide(); c:SetParent(nil) end

    -- the empty-list note and the consumables heading are single strings made once, shown or
    -- hidden and placed again on every refresh, so none is left behind under a row
    if not self.noCustomFS then
        self.noCustomFS = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        self.noCustomFS:SetText(L["No custom spells added yet."])
        self.consumableHdrFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.consumableHdrFS:SetText(L["Consumables you added with /cdc consumable:"])
    end

    local y   = 0
    local any = false

    local function MakeRow(data, fallbackName, onRemove, alertID)
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
            data.name or fallbackName, data.duration or 0))

        local rmv = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        rmv:SetSize(56, 18)
        rmv:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        rmv:SetText(L["Remove"])
        rmv:SetScript("OnClick", onRemove)
        if alertID then NewBell(row, alertID, rmv, 22) end
        y = y + ROW
    end

    for idStr, data in pairs(self.db.customSpells) do
        any = true
        local sid = tonumber(idStr)
        MakeRow(data, idStr, function() CC:RemoveCustomSpell(sid) end, sid)
    end

    self.noCustomFS:ClearAllPoints()
    self.noCustomFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.noCustomFS:SetShown(not any)
    if not any then y = ROW end

    -- consumables registered with /cdc consumable, each with a Remove button
    local list = {}
    for idStr, data in pairs(self.db.consumableBuffs or {}) do
        list[#list + 1] = { sid = tonumber(idStr), data = data, idStr = idStr }
    end
    table.sort(list, function(l, r) return (l.sid or 0) < (r.sid or 0) end)
    self.consumableHdrFS:ClearAllPoints()
    self.consumableHdrFS:SetShown(#list > 0)
    if #list > 0 then
        y = y + 8
        self.consumableHdrFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + 18
        for _, e in ipairs(list) do
            local sid = e.sid
            MakeRow(e.data, e.idStr, function() CC:RemoveConsumableBuff(sid, true) end)
        end
    end
    content:SetHeight(math.max(y, 20))
end

-- ── CooldownTimeline3 ────────────────────────────────────────────────────────

-- Opens CooldownTimeline3's settings on Filters, where Group cooldowns sits (Defaults > Group
-- cooldowns). False when it isn't loaded.
function CC:OpenCDTL3GroupSettings()
    if not self:BridgeAvailable() then return false end
    ---@diagnostic disable-next-line: undefined-field
    local api = _G.CDTL3
    if type(api) ~= "table" or type(api.ChatCommand) ~= "function" then return false end
    return pcall(api.ChatCommand, api, "filters") and true or false
end

-- ── Rezzers to skip (P40) ────────────────────────────────────────────────────

-- mode: "last" (only when nobody else can), "never", or nil to forget the name
function CC:SetRezSkip(name, mode)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or nil
    if not name or name == "" then return false end
    self.db.rezSkip = self.db.rezSkip or {}
    if mode == "last" or mode == "never" then
        self.db.rezSkip[name] = mode
    else
        self.db.rezSkip[name] = nil
    end
    if self.RefreshRezSkipList then self:RefreshRezSkipList() end
    return true
end

-- ── Standalone options frame ─────────────────────────────────────────────────

-- The Defensives line's and the burst line's spells: a saved list overrides the rule below.
local function IsDefensiveDefault(data) return data.kind == "external" or data.kind == "raid" end
local function IsBurstDefault(data)
    return (data.kind == "personal" or data.kind == "raid") and (data.duration or 0) >= 90
end

function CC:DefensiveCandidates()
    local list = {}
    for id, data in pairs(CC.SpellData) do
        if not data.consumable and (data.kind == "external" or data.kind == "raid" or data.kind == "personal") then
            list[#list + 1] = id
        end
    end
    table.sort(list, function(a, b) return (CC.SpellData[a].name or "") < (CC.SpellData[b].name or "") end)
    return list
end

function CC:DefensiveIsCounted(id)
    local saved = self.db.essentialsDefensives
    if type(saved) == "table" and #saved > 0 then
        for _, v in ipairs(saved) do if tonumber(v) == id then return true end end
        return false
    end
    return IsDefensiveDefault(CC.SpellData[id])
end

function CC:SetDefensiveCounted(id, on)
    local set = {}
    for _, cid in ipairs(self:DefensiveCandidates()) do
        if self:DefensiveIsCounted(cid) then set[cid] = true end
    end
    set[id] = on and true or nil
    local list = {}
    for cid in pairs(set) do list[#list + 1] = cid end
    table.sort(list)
    self.db.essentialsDefensives = list   -- an empty list means the default again
end

function CC:BurstCandidates()
    local _, class = UnitClass("player")
    local list = {}
    for id, data in pairs(CC.SpellData) do
        if data.class == class and not data.consumable and data.kind ~= "lust" then list[#list + 1] = id end
    end
    table.sort(list, function(a, b) return (CC.SpellData[a].name or "") < (CC.SpellData[b].name or "") end)
    return list
end

function CC:BurstIsCounted(id)
    local chosen = self.db.burstSpells
    if type(chosen) == "table" and next(chosen) ~= nil then
        return (chosen[id] or chosen[tostring(id)]) and true or false
    end
    return IsBurstDefault(CC.SpellData[id])
end

function CC:SetBurstCounted(id, on)
    local set = {}
    for _, cid in ipairs(self:BurstCandidates()) do
        if self:BurstIsCounted(cid) then set[cid] = true end
    end
    set[id] = on and true or nil
    self.db.burstSpells = set   -- an empty set means the default again
end

-- The Essentials bar's buff counts, in the order the bar shows them: Flask, Food, then this client's others.
function CC:BuffCountKeys()
    local keys = { "flask", "food" }
    for _, c in ipairs(CC.BuffCategories or {}) do keys[#keys + 1] = c.key end
    return keys
end

function CC:SetBuffCountShown(key, on)
    local shown = {}
    for _, k in ipairs(self.db.essentialsBuffCounts or {}) do shown[k] = true end
    shown[key] = on and true or nil
    local list = {}
    for _, k in ipairs(self:BuffCountKeys()) do
        if shown[k] then list[#list + 1] = k end
    end
    self.db.essentialsBuffCounts = list
    self:RefreshView("RefreshEssentials")
end

-- ── Editors: plans (P12), rotation orders (P39), teams (P43) ─────────────────

local function Trim(s) return ((tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))) end

-- A tracked spell's ID from a name, an ID or a link.
function CC:ResolveTracked(text)
    text = Trim(text)
    if text == "" then return nil end
    return CC.SpellByName[text] or ResolveSpell(text)
end

-- A plan row's trigger: "1:30" or "90" is a time into the fight (second value), anything else
-- is the boss timer's text (first value).
function CC:ParseTrigger(text)
    text = Trim(text)
    if text == "" then return nil, nil end
    local m, s = text:match("^(%d+):(%d%d)$")
    if m then return nil, tonumber(m) * 60 + tonumber(s) end
    if text:match("^%d+$") then return nil, tonumber(text) end
    return text, nil
end

-- inputs: { { trigger, player, spell } ... } as typed. Rows missing a part are skipped (counted).
function CC:PlanRowsFromInput(inputs)
    local rows, skipped = {}, 0
    for _, r in ipairs(inputs or {}) do
        local timer, at = self:ParseTrigger(r.trigger)
        local sid = self:ResolveTracked(r.spell)
        local player = Trim(r.player)
        if (timer or at) and sid and player ~= "" then
            rows[#rows + 1] = { timer = timer, at = at, player = player, spellID = sid }
        elseif Trim(r.trigger) ~= "" or player ~= "" or Trim(r.spell) ~= "" then
            skipped = skipped + 1
        end
    end
    return rows, skipped
end

function CC:PlanInputsFromRows(rows)
    local inputs = {}
    for _, row in ipairs(rows or {}) do
        local data = CC.SpellData[row.spellID]
        inputs[#inputs + 1] = {
            trigger = row.timer or self:LookClock(row.at or 0),
            player = row.player,
            spell = data and data.name or tostring(row.spellID),
        }
    end
    return inputs
end

function CC:SavePlan(name, inputs)
    name = Trim(name)
    if name == "" then return false end
    local rows, skipped = self:PlanRowsFromInput(inputs)
    self.db.plans[name] = { rows = rows, at = time() }
    return true, #rows, skipped
end

-- The order text "A, B, C" (or one a line) as a list of names.
local function NameList(text)
    local list = {}
    for item in tostring(text or ""):gmatch("[^,\r\n]+") do
        item = Trim(item)
        if item ~= "" then list[#list + 1] = item end
    end
    return list
end

function CC:SaveRotationFromText(spellText, namesText)
    local sid = self:ResolveTracked(spellText)
    if not sid then return false end
    local names = {}
    for _, n in ipairs(NameList(namesText)) do names[#names + 1] = n end   -- bare names match a member at use time
    self:SetRotation(sid, names)
    return true, sid
end

function CC:SaveTeam(name, members)
    name = Trim(name)
    if name == "" then return false end
    local list = {}
    for _, m in ipairs(members or {}) do
        m = Trim(m)
        if m ~= "" then list[#list + 1] = m end
    end
    self.db.teams = self.db.teams or {}
    self.db.teams[name] = list
    self:RefreshView("RefreshRows")
    return true
end

function CC:RemoveTeam(name)
    if not (self.db.teams and self.db.teams[name]) then return false end
    self.db.teams[name] = nil
    self:RefreshView("RefreshRows")
    return true
end

function CC:OpenOptions()
    if self.optionsFrame then
        self.optionsFrame:SetShown(not self.optionsFrame:IsShown())
        return
    end

    local f = CreateFrame("Frame", "CCOptionsFrame", UIParent, CC.BackdropTemplate)
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

    -- ── Widgets ───────────────────────────────────────────────────────────

    local function NewCheck(parent, x, y, text, get, set, tip)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        cb:SetChecked(get())
        cb:SetScript("OnClick", function(widget) set(widget:GetChecked() and true or false) end)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        lbl:SetText(text)
        if tip then
            cb:SetScript("OnEnter", function(widget)
                GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
                GameTooltip:SetText(text)
                GameTooltip:AddLine(tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return cb, lbl
    end

    local function NewButton(parent, x, y, w, text, onClick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- A row of buttons, the chosen one greyed. Returns a function that redraws it.
    local function NewChoice(parent, x, y, options, width, get, pick)
        local buttons = {}
        local function Redraw()
            for _, b in ipairs(buttons) do b:SetEnabled(b.value ~= get()) end
        end
        for i, opt in ipairs(options) do
            local b = NewButton(parent, x + (i - 1) * (width + 4), y, width, opt.label, function()
                pick(opt.value); Redraw()
            end)
            b.value = opt.value
            buttons[i] = b
        end
        Redraw()
        return Redraw, buttons
    end

    local function NewHeader(parent, y, text)
        local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
        h:SetText(text)
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetSize(FRAME_W - 70, 1)
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y - 16)
        line:SetColorTexture(0.3, 0.3, 0.4, 0.6)
        return h
    end

    local function NewNote(parent, x, y, width, text)
        local n = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        n:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        n:SetWidth(width)
        n:SetJustifyH("LEFT")
        n:SetText(text)
        return n
    end

    -- ── Tabs and pages ────────────────────────────────────────────────────

    local TAB_Y = -44
    local tabNames = { L["Getting Started"], L["Display"], L["Lists"], L["Spells"], L["Plans"], L["Profiles"] }
    local tabs, pages = {}, {}

    local contentArea = CreateFrame("Frame", nil, f, CC.BackdropTemplate)
    contentArea:SetSize(FRAME_W - 32, FRAME_H - (-TAB_Y) - TAB_H - 22)
    contentArea:SetPoint("TOPLEFT", f, "TOPLEFT", 16, TAB_Y - TAB_H - 4)
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

    local function ShowPage(index)
        for i, p in ipairs(pages) do
            p:SetShown(i == index)
            tabs[i]:SetEnabled(i ~= index)
        end
        f.page = index
        if index == 1 and CC.startPage then CC.startPage.refresh() end
    end
    for i, name in ipairs(tabNames) do
        local t = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        t:SetSize(i == 1 and 112 or 80, TAB_H)
        t:SetText(name)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + (i == 1 and 0 or 114 + (i - 2) * 82), TAB_Y)
        t:SetScript("OnClick", function() ShowPage(i) end)
        tabs[i] = t
    end

    local function NewPage(scrolling)
        if scrolling then
            local scroll = CreateFrame("ScrollFrame", nil, contentArea, "UIPanelScrollFrameTemplate")
            scroll:SetSize(CAW - 16, CAH)
            scroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 4, -4)
            local content = CreateFrame("Frame", nil, scroll)
            content:SetWidth(CAW - 32)
            scroll:SetScrollChild(content)
            return scroll, content
        end
        local p = CreateFrame("Frame", nil, contentArea)
        p:SetSize(CAW, CAH)
        p:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 4, -4)
        return p, p
    end

    -- ══ Page 1: Getting Started ═══════════════════════════════════════════
    -- A small drawing of each window with its On, Lock and Reset under it (P14), and a
    -- CooldownTimeline3 card beside them (P23).

    local startPage = NewPage(false)
    pages[1] = startPage
    NewNote(startPage, 4, -2, CAW - 16,
        L["Each window with its switches. Windows open by themselves in a group; drag one to move it."])

    local CARD_W, CARD_H = 168, 124
    local cards = {}
    local function Card(i, w)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local card = CreateFrame("Frame", nil, startPage)
        card:SetSize(CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", startPage, "TOPLEFT", 2 + col * CARD_W, -34 - row * CARD_H)

        -- the drawing: the window's border, its dark body, a blue title strip and a few lines
        local pic = CreateFrame("Frame", nil, card)
        pic:SetSize(w.w, w.h)
        pic:SetPoint("TOP", card, "TOP", 0, -4)
        local edge = pic:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0.35, 0.35, 0.55, 1)
        local body = pic:CreateTexture(nil, "BORDER")
        body:SetPoint("TOPLEFT", pic, "TOPLEFT", 1, -1)
        body:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", -1, 1)
        body:SetColorTexture(0.06, 0.06, 0.10, 1)
        local strip = pic:CreateTexture(nil, "ARTWORK")
        strip:SetPoint("TOPLEFT", pic, "TOPLEFT", 3, -3)
        strip:SetSize(math.max(8, w.w * 0.4), 3)
        strip:SetColorTexture(0.33, 0.64, 1, 1)
        local lines = math.max(0, math.min(4, math.floor((w.h - 12) / 7)))
        for n = 1, lines do
            local ln = pic:CreateTexture(nil, "ARTWORK")
            ln:SetPoint("TOPLEFT", pic, "TOPLEFT", 3, -(8 + (n - 1) * 7))
            ln:SetSize((w.w - 6) * (n % 2 == 0 and 0.7 or 0.95), 3)
            ln:SetColorTexture(0.55, 0.55, 0.62, 0.8)
        end

        local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("TOP", pic, "BOTTOM", 0, -(52 - w.h) - 4)
        name:SetText(w.label)

        local on = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
        on:SetSize(20, 20)
        on:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -76)
        local onLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        onLbl:SetPoint("LEFT", on, "RIGHT", 0, 0)
        onLbl:SetText(L["On"])
        on:SetScript("OnClick", function(widget) CC:SetWindowOn(w, widget:GetChecked() and true or false) end)

        local lock = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
        lock:SetSize(20, 20)
        lock:SetPoint("LEFT", onLbl, "RIGHT", 6, 0)
        local lockLbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lockLbl:SetPoint("LEFT", lock, "RIGHT", 0, 0)
        lockLbl:SetText(L["Lock"])
        lock:SetScript("OnClick", function(widget) CC:SetOneWindowLocked(w, widget:GetChecked() and true or false) end)

        local reset = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        reset:SetSize(46, 18)
        reset:SetPoint("LEFT", lockLbl, "RIGHT", 6, 0)
        reset:SetText(L["Reset"])
        reset:SetScript("OnClick", function() CC:ResetWindow(w) end)
        reset:SetScript("OnEnter", function(widget)
            GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format(L["Reset %s"], w.label))
            GameTooltip:AddLine(L["Moves the window back to where it starts."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

        cards[#cards + 1] = { window = w, on = on, lock = lock }
    end
    for i, w in ipairs(CC.WINDOWS) do Card(i, w) end

    -- the CooldownTimeline3 card: two cells wide, after the last window
    do
        local i = #CC.WINDOWS + 1
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local card = CreateFrame("Frame", nil, startPage, CC.BackdropTemplate)
        card:SetSize(CARD_W * 2 - 6, CARD_H - 6)
        card:SetPoint("TOPLEFT", startPage, "TOPLEFT", 2 + col * CARD_W, -34 - row * CARD_H)
        card:SetBackdrop({
            bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        card:SetBackdropColor(0.08, 0.08, 0.14, 0.9)
        card:SetBackdropBorderColor(0.35, 0.35, 0.55, 0.9)
        local head = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
        head:SetText("CooldownTimeline3")
        local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
        text:SetWidth(CARD_W * 2 - 30)
        text:SetJustifyH("LEFT")
        local btn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        btn:SetSize(190, 22)
        btn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
        btn:SetText(L["Open Group cooldowns settings"])
        btn:SetScript("OnClick", function() CC:OpenCDTL3GroupSettings() end)
        local where = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        where:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 12)
        where:SetText(L["Not installed. Get it on CurseForge or Wago."])
        function card.Refresh()
            local avail = CC:BridgeAvailable()
            btn:SetShown(avail)
            where:SetShown(not avail)
            text:SetText(avail
                and L["Adds your group's cooldowns to its lanes as icons with a countdown. It decides which lane they go on."]
                or L["Adds your group's cooldowns to its timeline lanes as icons with a countdown, beside your own."])
        end
        startPage.cdtl3Card = card
    end

    startPage.refresh = function()
        for _, c in ipairs(cards) do
            c.on:SetChecked(CC:WindowIsOn(c.window))
            c.lock:SetChecked(CC.db[c.window.lockKey] and true or false)
        end
        startPage.cdtl3Card.Refresh()
    end
    CC.startPage = startPage

    -- ══ Page 2: Display ═══════════════════════════════════════════════════

    local dispScroll, d = NewPage(true)
    pages[2] = dispScroll
    local y = -2

    NewHeader(d, y, L["Panel"]); y = y - 24
    NewCheck(d, 4, y, L["Show ready cooldowns"], function() return CC.db.showReady end,
        function(v) CC.db.showReady = v; CC:RefreshRows() end)
    y = y - 26

    local cbLock = NewCheck(d, 4, y, L["Lock windows"], function() return CC:AreWindowsLocked() end,
        function(v) CC:SetWindowsLocked(v) end)
    CC.lockCheck = cbLock
    -- /cdc lock and /cdc unlock may have changed it while this window was closed
    f:SetScript("OnShow", function()
        cbLock:SetChecked(CC:AreWindowsLocked())
        if f.page == 1 then startPage.refresh() end
    end)
    y = y - 26

    NewCheck(d, 4, y, L["Hide minimap button"], function() return CC.db.minimapHide end, function(v)
        CC.db.minimapHide = v
        if CC.minimapBtn then CC.minimapBtn:SetShown(not v) end
    end)
    y = y - 26

    -- CDTL3 bridge: greyed/hidden unless CDTL3 (with the timer API) is loaded
    local bridgeTip = L["Your cooldowns and your group's show as icons with a countdown on CooldownTimeline3's lanes. CooldownTimeline3 decides which lane. Change it in CooldownTimeline3 under Filters > Defaults > Group cooldowns."]
    local cbBridge, lBridge = NewCheck(d, 4, y, L["Show group cooldowns on CooldownTimeline3's lanes"],
        function() return CC.db.showOnCDTL3 ~= false end, function(v) CC:SetShowOnCDTL3(v) end, bridgeTip)
    function CC:RefreshBridgeOption()
        local avail = CC:BridgeAvailable()
        cbBridge:SetShown(avail)
        lBridge:SetShown(avail)
        cbBridge:SetChecked(CC.db.showOnCDTL3 ~= false)
    end
    CC:RefreshBridgeOption()
    y = y - 30

    NewCheck(d, 4, y, L["Share with my guild (adds a Guild tab to the panel)"],
        function() return CC.db.guildSync == true end, function(v) CC:SetGuildSync(v) end,
        L["Your cooldowns and who runs the addon go out on the guild channel, and the panel gets a Guild tab. Off by default."])
    y = y - 30

    local lbl = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", d, "TOPLEFT", 4, y - 4)
    lbl:SetText(L["Panel style:"])
    NewChoice(d, 100, y, { { label = L["Text rows"], value = "text" }, { label = L["Icon row"], value = "icons" } }, 100,
        function() return CC.db.panelStyle or "text" end,
        function(v) CC.db.panelStyle = v; CC:RefreshRows() end)
    y = y - 32

    -- Min duration buttons
    local mdLbl = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mdLbl:SetPoint("TOPLEFT", d, "TOPLEFT", 4, y)
    mdLbl:SetText(L["Minimum cooldown to track:"])
    y = y - 22
    local durOptions = {}
    for _, val in ipairs(MIN_DURATIONS) do durOptions[#durOptions + 1] = { label = val .. "s", value = val } end
    NewChoice(d, 4, y, durOptions, 50, function() return CC.db.minDuration end,
        function(v) CC.db.minDuration = v; CC:RefreshRows() end)
    y = y - 32

    local function NewSlider(label, lo, hi, step, lowText, highText, get, set, format)
        local sl = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        sl:SetPoint("TOPLEFT", d, "TOPLEFT", 4, y)
        sl:SetText(label)
        local slider = CreateFrame("Slider", nil, d, "OptionsSliderTemplate")
        slider:SetSize(200, 16)
        slider:SetPoint("TOPLEFT", d, "TOPLEFT", 150, y - 2)
        slider:SetMinMaxValues(lo, hi)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(get())
        slider.Text:SetText("")
        slider.Low:SetText(lowText)
        slider.High:SetText(highText)
        local val = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        val:SetText(format(get()))
        slider:SetScript("OnValueChanged", function(_, v)
            set(v)
            val:SetText(format(v))
        end)
        y = y - 30
        return slider
    end
    NewSlider(L["Panel opacity:"], 0.2, 1.0, 0.05, "20%", "100%",
        function() return CC.db.alpha or 0.9 end,
        function(v) CC.db.alpha = v; if CC.frame then CC.frame:SetAlpha(v) end end,
        function(v) return string.format("%.0f%%", v * 100) end)
    NewSlider(L["Panel scale:"], 0.5, 2.0, 0.1, "0.5x", "2.0x",
        function() return CC.db.scale or 1.0 end,
        function(v) CC.db.scale = v; if CC.frame then CC.frame:SetScale(v) end end,
        function(v) return string.format("%.1fx", v) end)

    y = y - 6
    NewHeader(d, y, L["When the windows show"]); y = y - 24
    NewChoice(d, 4, y, {
        { label = L["Always"], value = "always" },
        { label = L["Only in combat"], value = "combat" },
        { label = L["Only on boss fights"], value = "boss" },
    }, 150, function() return CC.db.showWindows or "always" end,
        function(v) CC.db.showWindows = v; CC:RefreshAllViews() end)
    y = y - 28
    NewNote(d, 4, y, CAW - 40, L["The main panel, the Essentials bar and the Lane view. Closing a window yourself still keeps it shut."])
    y = y - 30

    NewCheck(d, 4, y, L["Lighter mode"], function() return CC.db.lighterMode == true end,
        function(v) CC.db.lighterMode = v end,
        L["Refreshes the panel and the Essentials bar every second instead of every half second, and the Lane view every half second instead of every fifth. /cdc debug shows the rates."])
    y = y - 30
    d:SetHeight(-y + 10)

    -- ══ Page 3: Bars & Lists ══════════════════════════════════════════════

    local listScroll, b = NewPage(true)
    pages[3] = listScroll
    y = -2

    NewHeader(b, y, L["Essentials bar: buff counts"]); y = y - 24
    local shownCounts = {}
    local function CountsShown()
        wipe(shownCounts)
        for _, k in ipairs(CC.db.essentialsBuffCounts or {}) do shownCounts[k] = true end
    end
    for i, key in ipairs(CC:BuffCountKeys()) do
        local count = CC.BuffCounts and CC.BuffCounts[key]
        local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
        CountsShown()
        NewCheck(b, 4 + col * 240, y - rowN * 24, count and count.label or key,
            function() return shownCounts[key] == true end,
            function(v) CC:SetBuffCountShown(key, v) end)
    end
    y = y - math.ceil(#CC:BuffCountKeys() / 2) * 24 - 6
    do
        local aimLbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        aimLbl:SetPoint("TOPLEFT", b, "TOPLEFT", 4, y)
        aimLbl:SetText(L["Green from this many players:"])
        local slider = CreateFrame("Slider", nil, b, "OptionsSliderTemplate")
        slider:SetSize(180, 16)
        slider:SetPoint("TOPLEFT", b, "TOPLEFT", 220, y - 2)
        slider:SetMinMaxValues(0, 40)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider.Text:SetText("")
        slider.Low:SetText(L["whole group"])
        slider.High:SetText("40")
        local val = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        local function Say(v) val:SetText(v > 0 and tostring(v) or L["whole group"]) end
        local aim = tonumber(CC.db.essentialsBuffAim) or 0
        slider:SetValue(aim)
        Say(aim)
        slider:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v + 0.5)
            CC.db.essentialsBuffAim = v
            Say(v)
        end)
        y = y - 34
    end

    -- A list of spells with ticks, two to a line; returns the next y.
    local function SpellTicks(list, isOn, setOn)
        for i, id in ipairs(list) do
            local data = CC.SpellData[id]
            local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
            local cb, lb = NewCheck(b, 4 + col * 240, y - rowN * 22, data.name or tostring(id),
                function() return isOn(id) end, function(v) setOn(id, v) end)
            cb:SetSize(20, 20)
            lb:SetFontObject(GameFontHighlightSmall)
            lb:SetWidth(190)
            lb:SetJustifyH("LEFT")
        end
        y = y - math.ceil(#list / 2) * 22 - 6
    end

    NewHeader(b, y, L["Essentials bar: Defensives line"]); y = y - 24
    NewNote(b, 4, y, CAW - 40, L["The cooldowns the line counts. Unticking every one goes back to every external and raid cooldown."])
    y = y - 30
    SpellTicks(CC:DefensiveCandidates(), function(id) return CC:DefensiveIsCounted(id) end,
        function(id, v) CC:SetDefensiveCounted(id, v); CC:RefreshView("RefreshEssentials") end)

    NewHeader(b, y, L["Burst line: your counted spells"]); y = y - 24
    NewNote(b, 4, y, CAW - 40, L["Your own cooldowns the burst line shows. Unticking every one goes back to your personal and raid cooldowns of 90 s or more."])
    y = y - 30
    SpellTicks(CC:BurstCandidates(), function(id) return CC:BurstIsCounted(id) end,
        function(id, v) CC:SetBurstCounted(id, v); CC:RefreshView("RefreshBurstLine") end)

    NewHeader(b, y, L["Rezzers to skip"]); y = y - 24
    NewNote(b, 4, y, CAW - 40,
        L["Last choice: asked only when nobody else can. Never: not asked at all. The rez call and the dead list both follow it."])
    y = y - 30
    local skipInput = CreateFrame("EditBox", nil, b, "InputBoxTemplate")
    skipInput:SetSize(150, 22)
    skipInput:SetPoint("TOPLEFT", b, "TOPLEFT", 10, y)
    skipInput:SetAutoFocus(false)
    skipInput:SetMaxLetters(60)
    skipInput:SetScript("OnEscapePressed", function(widget) widget:ClearFocus() end)
    local function SkipName()
        local text = skipInput:GetText()
        if (not text or text == "") and UnitExists("target") then
            local ok, name = pcall(CC.FullName, CC, "target")
            text = ok and name and CC:ShortName(name) or ""
        end
        return text
    end
    local function AddSkip(mode)
        if CC:SetRezSkip(SkipName(), mode) then skipInput:SetText("") end
    end
    NewButton(b, 166, y + 1, 90, L["Last choice"], function() AddSkip("last") end)
    NewButton(b, 260, y + 1, 60, L["Never"], function() AddSkip("never") end)
    y = y - 26
    NewNote(b, 10, y, CAW - 50, L["Type a player's name, or leave it empty to use your target."])
    y = y - 22
    local skipTop = y
    local skipRows = {}
    function CC:RefreshRezSkipList()
        for _, r in ipairs(skipRows) do r:Hide() end
        local names = {}
        for name in pairs(CC.db.rezSkip or {}) do names[#names + 1] = name end
        table.sort(names)
        for i, name in ipairs(names) do
            local r = skipRows[i]
            if not r then
                r = CreateFrame("Frame", nil, b)
                r:SetSize(CAW - 40, 22)
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
                r.mode = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
                r.mode:SetSize(90, 18)
                r.mode:SetPoint("LEFT", r, "LEFT", 220, 0)
                r.rm = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
                r.rm:SetSize(56, 18)
                r.rm:SetPoint("LEFT", r.mode, "RIGHT", 4, 0)
                r.rm:SetText(L["Remove"])
                skipRows[i] = r
            end
            r:SetPoint("TOPLEFT", b, "TOPLEFT", 4, skipTop - (i - 1) * 22)
            r.text:SetText(name)
            local mode = CC.db.rezSkip[name]
            r.mode:SetText(mode == "never" and L["Never"] or L["Last choice"])
            r.mode:SetScript("OnClick", function()
                CC:SetRezSkip(name, mode == "never" and "last" or "never")
            end)
            r.rm:SetScript("OnClick", function() CC:SetRezSkip(name, nil) end)
            r:Show()
        end
        b:SetHeight(-skipTop + #names * 22 + 14)
    end
    CC:RefreshRezSkipList()

    -- ══ Page 4: Spells ════════════════════════════════════════════════════

    local spellPage = NewPage(false)
    pages[4] = spellPage

    -- Show preset (P2)
    local presetLbl = spellPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    presetLbl:SetPoint("TOPLEFT", spellPage, "TOPLEFT", 4, -8)
    presetLbl:SetText(L["Show:"])
    local presetOptions = {}
    for _, key in ipairs(CC.PRESET_ORDER) do
        presetOptions[#presetOptions + 1] = { label = CC.PRESETS[key].label, value = key }
    end
    local redrawPresets = NewChoice(spellPage, 50, -4, presetOptions, 86,
        function() return CC.db.showPreset or "everything" end,
        function(v) CC:ApplyShowPreset(v) end)
    function CC:RefreshPresetButtons() redrawPresets() end
    NewNote(spellPage, 4, -30, CAW - 16,
        L["Simple: rez, lust and the big raid cooldowns. Ticking a spell yourself below changes it from there."])

    -- sub-tabs and grouping
    local SUB_Y = -58
    local tabDefault = NewButton(spellPage, 4, SUB_Y, 110, L["Default Spells"], function() end)
    local tabCustom  = NewButton(spellPage, 118, SUB_Y, 110, L["Custom Spells"], function() end)
    local groupLbl = spellPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupLbl:SetPoint("TOPLEFT", spellPage, "TOPLEFT", 270, SUB_Y - 5)
    groupLbl:SetText(L["Group by:"])
    local redrawGroup, groupButtons = NewChoice(spellPage, 330, SUB_Y, {
        { label = L["Class"], value = "class" }, { label = L["Kind"], value = "kind" },
    }, 80, function() return CC.db.spellGroupBy or "class" end,
        function(v) CC.db.spellGroupBy = v; CC:RefreshDefaultSpellList() end)

    local LIST_Y = SUB_Y - 28
    local LIST_H = CAH - (-LIST_Y) - 4

    -- ── Default spells panel ──

    local defPanel = CreateFrame("ScrollFrame", "CCDefScroll", spellPage, "UIPanelScrollFrameTemplate")
    defPanel:SetSize(CAW - 24, LIST_H)
    defPanel:SetPoint("TOPLEFT", spellPage, "TOPLEFT", 4, LIST_Y)

    local defContent = CreateFrame("Frame", nil, defPanel)
    defContent:SetWidth(CAW - 40)
    defPanel:SetScrollChild(defContent)

    self.defaultSpellContent = defContent

    -- ── Custom spells panel ──

    local custPanel = CreateFrame("Frame", nil, spellPage)
    custPanel:SetSize(CAW - 8, LIST_H)
    custPanel:SetPoint("TOPLEFT", spellPage, "TOPLEFT", 4, LIST_Y)
    custPanel:Hide()

    -- Instruction
    local hint = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", custPanel, "TOPLEFT", 4, -4)
    hint:SetText(L["Type a spell name or ID, then set its cooldown duration and click Add.\nClick the box, then shift-click a spell in your spellbook to fill it in."])
    hint:SetJustifyH("LEFT")
    hint:SetWidth(CAW - 24)

    local spellInput = CreateFrame("EditBox", "CCSpellInput", custPanel, "InputBoxTemplate")
    spellInput:SetSize(180, 22)
    spellInput:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 2, -10)
    spellInput:SetAutoFocus(false)
    spellInput:SetNumeric(false)
    spellInput:SetMaxLetters(128)
    spellInput:SetScript("OnEscapePressed", function(widget) widget:ClearFocus() end)

    local preview = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)
    preview:SetWidth(160)
    preview:SetTextColor(0.5, 0.85, 1)

    local durLbl = custPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    durLbl:SetPoint("TOPLEFT", spellInput, "BOTTOMLEFT", 0, -10)
    durLbl:SetText(L["Duration (sec):"])

    local durInput = CreateFrame("EditBox", "CCDurInput", custPanel, "InputBoxTemplate")
    durInput:SetSize(60, 22)
    durInput:SetPoint("LEFT", durLbl, "RIGHT", 6, 0)
    durInput:SetAutoFocus(false)
    durInput:SetNumeric(true)
    durInput:SetMaxLetters(5)
    durInput:SetScript("OnEscapePressed", function(widget) widget:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, custPanel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", durInput, "RIGHT", 8, 0)
    addBtn:SetText(L["Add Spell"])

    local pendingID = nil

    local function TakeSpellID(id)
        pendingID = id
        spellInput:SetText(tostring(id))
        local name = LookupSpellName(id)
        preview:SetText(name or ("|cFFFF4444" .. L["Unknown"] .. "|r"))
    end

    -- A shift-clicked spell link goes to the game's link-insert call, which only knows chat boxes.
    -- Follow it (after it runs, so chat is untouched) and take the link while this box has focus.
    -- The call is ChatFrameUtil.InsertLink on the newer interface and ChatEdit_InsertLink on the
    -- older; each is hooked where it exists, and taking the same link twice is harmless.
    local function OnLinkInserted(link)
        if not spellInput:HasFocus() then return end
        local id = SpellIDFromLink(link)
        if id then TakeSpellID(id) end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", OnLinkInserted)
    end
    ---@diagnostic disable-next-line: undefined-global
    if ChatEdit_InsertLink then
        pcall(hooksecurefunc, "ChatEdit_InsertLink", OnLinkInserted)
    end

    spellInput:SetScript("OnTextChanged", function(widget, userInput)
        if not userInput then return end
        local text = widget:GetText()
        local linkID = text:match("|Hspell:(%d+)")
        if linkID then
            TakeSpellID(tonumber(linkID))
            return
        end
        pendingID = ResolveSpell(text)
        if pendingID then
            local name = LookupSpellName(pendingID)
            preview:SetText(name or ("|cFFFF4444" .. L["Unknown ID"] .. "|r"))
        elseif text:len() > 0 then
            preview:SetText("|cFF888888" .. L["resolving..."] .. "|r")
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
    listHdr:SetText(L["Custom tracked spells:"])

    local listScroll2 = CreateFrame("ScrollFrame", "CCCustScroll", custPanel, "UIPanelScrollFrameTemplate")
    listScroll2:SetSize(CAW - 24, LIST_H - 130)
    listScroll2:SetPoint("TOPLEFT", listHdr, "BOTTOMLEFT", 0, -6)

    local listContent = CreateFrame("Frame", nil, listScroll2)
    listContent:SetWidth(CAW - 40)
    listScroll2:SetScrollChild(listContent)
    self.spellListContent = listContent

    -- ── Spell sub-tab switching ──

    local function ShowDefault()
        defPanel:Show(); custPanel:Hide()
        tabDefault:SetEnabled(false); tabCustom:SetEnabled(true)
        for _, gb in ipairs(groupButtons) do gb:Show() end
        groupLbl:Show()
    end
    local function ShowCustom()
        defPanel:Hide(); custPanel:Show()
        tabDefault:SetEnabled(true); tabCustom:SetEnabled(false)
        for _, gb in ipairs(groupButtons) do gb:Hide() end
        groupLbl:Hide()
        CC:RefreshSpellList()
    end
    tabDefault:SetScript("OnClick", ShowDefault)
    tabCustom:SetScript("OnClick",  ShowCustom)
    redrawGroup()

    -- ══ Page 5: Plans, rotations and teams ════════════════════════════════

    local planScroll, pl = NewPage(true)
    pages[5] = planScroll
    y = -2

    local function NewEdit(parent, x, yy, w, text)
        local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        e:SetSize(w, 20)
        e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, yy)
        e:SetAutoFocus(false)
        e:SetMaxLetters(120)
        e:SetScript("OnEscapePressed", function(widget) widget:ClearFocus() end)
        if text then e:SetText(text) end
        return e
    end

    NewHeader(pl, y, L["Raid cooldown plan"]); y = y - 24
    local planLbl = pl:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    planLbl:SetPoint("TOPLEFT", pl, "TOPLEFT", 4, y - 3)
    planLbl:SetText(L["Plan:"])
    local planName = NewEdit(pl, 44, y, 130, "")
    local planSaved = pl:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local planStatus = pl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local function SayPlans()
        local names = {}
        for n in pairs(CC.db.plans or {}) do names[#names + 1] = n end
        table.sort(names)
        planSaved:SetText(string.format(L["Saved: %s"], #names > 0 and table.concat(names, ", ") or L["none"])
            .. (CC.db.activePlan and ("   " .. string.format(L["Active: %s"], tostring(CC.db.activePlan))) or ""))
    end
    local PLAN_ROWS = 14
    local planRows = {}
    local function PlanInputs()
        local inputs = {}
        for i = 1, PLAN_ROWS do
            local r = planRows[i]
            inputs[i] = { trigger = r.trigger:GetText(), player = r.player:GetText(), spell = r.spell:GetText() }
        end
        return inputs
    end
    local function ShowPlan(plan)
        local inputs = plan and CC:PlanInputsFromRows(plan.rows) or {}
        for i = 1, PLAN_ROWS do
            local r, v = planRows[i], inputs[i] or {}
            r.trigger:SetText(v.trigger or ""); r.player:SetText(v.player or ""); r.spell:SetText(v.spell or "")
        end
    end
    NewButton(pl, 180, y + 1, 52, L["Load"], function()
        local plan = CC.db.plans[Trim(planName:GetText())]
        ShowPlan(plan)
        planStatus:SetText(plan and L["Loaded."] or ("|cFFFF4444" .. L["No plan by that name."] .. "|r"))
    end)
    NewButton(pl, 234, y + 1, 52, L["Save"], function()
        local ok, n, skipped = CC:SavePlan(planName:GetText(), PlanInputs())
        local saved
        if ok then
            if skipped > 0 then
                saved = string.format(n == 1 and L["Saved %d row, %d skipped (a part is missing)."] or L["Saved %d rows, %d skipped (a part is missing)."], n, skipped)
            else
                saved = string.format(n == 1 and L["Saved %d row."] or L["Saved %d rows."], n)
            end
        end
        planStatus:SetText(saved or ("|cFFFF4444" .. L["Give the plan a name first."] .. "|r"))
        SayPlans()
    end)
    NewButton(pl, 288, y + 1, 56, L["Delete"], function()
        CC.db.plans[Trim(planName:GetText())] = nil
        if CC.db.activePlan == Trim(planName:GetText()) then CC.db.activePlan = false end
        SayPlans()
    end)
    NewButton(pl, 346, y + 1, 56, L["Share"], function()
        local name = Trim(planName:GetText())
        if CC.db.plans[name] then CC:SharePlan(name) end
        SayPlans()
    end)
    NewButton(pl, 404, y + 1, 84, L["Make active"], function()
        local name = Trim(planName:GetText())
        if CC.db.plans[name] then CC.db.activePlan = name end
        SayPlans()
    end)
    y = y - 26
    planSaved:SetPoint("TOPLEFT", pl, "TOPLEFT", 4, y)
    planSaved:SetWidth(CAW - 40)
    planSaved:SetJustifyH("LEFT")
    y = y - 16
    NewNote(pl, 4, y, CAW - 40, L["A row: when (a boss timer's text, or the time into the fight like 1:30), who, and which spell. The player gets a prompt as it comes up. Share sends it to the group (leader or assist)."])
    y = y - 42
    for _, h in ipairs({ { 4, L["When"] }, { 176, L["Player"] }, { 300, L["Spell"] } }) do
        local l = pl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", pl, "TOPLEFT", h[1] + 6, y)
        l:SetText(h[2])
    end
    y = y - 16
    for i = 1, PLAN_ROWS do
        planRows[i] = {
            trigger = NewEdit(pl, 4, y, 166), player = NewEdit(pl, 176, y, 118), spell = NewEdit(pl, 300, y, 150),
        }
        y = y - 22
    end
    planStatus:SetPoint("TOPLEFT", pl, "TOPLEFT", 4, y)
    y = y - 22
    SayPlans()

    NewHeader(pl, y, L["Rotation order"]); y = y - 24
    NewNote(pl, 4, y, CAW - 40, L["A spell several players take in turn. The panel numbers the rows in this order; the group gets it when you lead or assist."])
    y = y - 30
    local rotSpell = NewEdit(pl, 4, y, 170, "")
    local rotNames = NewEdit(pl, 180, y, 270, "")
    rotNames:SetMaxLetters(400)
    y = y - 22
    NewNote(pl, 4, y, CAW - 40, L["Left: the spell's name or ID. Right: the players in order, separated by commas."])
    y = y - 20
    local rotList = pl:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local function SayRotations()
        local lines = {}
        for sid, names in pairs(CC.db.rotations or {}) do
            local data = CC.SpellData[sid]
            local short = {}
            for _, n in ipairs(names) do short[#short + 1] = CC:ShortName(n) end
            lines[#lines + 1] = (data and data.name or tostring(sid)) .. ": " .. table.concat(short, " > ")
        end
        table.sort(lines)
        rotList:SetText(#lines > 0 and table.concat(lines, "\n") or L["No rotation orders saved."])
    end
    NewButton(pl, 4, y, 60, L["Save"], function()
        CC:SaveRotationFromText(rotSpell:GetText(), rotNames:GetText()); SayRotations()
    end)
    NewButton(pl, 68, y, 60, L["Clear"], function()
        CC:SaveRotationFromText(rotSpell:GetText(), ""); SayRotations()
    end)
    NewButton(pl, 132, y, 120, L["Fill from group"], function()
        local names = {}
        for name in pairs(CC:GetActiveGroupNames()) do names[#names + 1] = CC:ShortName(name) end
        table.sort(names)
        rotNames:SetText(table.concat(names, ", "))
    end)
    y = y - 28
    rotList:SetPoint("TOPLEFT", pl, "TOPLEFT", 4, y)
    rotList:SetWidth(CAW - 40)
    rotList:SetJustifyH("LEFT")
    SayRotations()
    y = y - 60

    NewHeader(pl, y, L["Teams"]); y = y - 24
    NewNote(pl, 4, y, CAW - 40, L["A team is a tab on the panel that lists only its members. Tick people in your group, or type names."])
    y = y - 30
    local teamName = NewEdit(pl, 4, y, 150, "")
    local teamTyped = NewEdit(pl, 160, y, 290, "")
    teamTyped:SetMaxLetters(400)
    y = y - 24
    local teamTicks = {}
    for i = 1, 20 do
        local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
        local cb = CreateFrame("CheckButton", nil, pl, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", pl, "TOPLEFT", 4 + col * 240, y - rowN * 20)
        cb.label = pl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        teamTicks[i] = cb
    end
    function CC:RefreshTeamTicks()
        local names = {}
        for name in pairs(self:GetActiveGroupNames()) do names[#names + 1] = name end
        table.sort(names)
        for i, cb in ipairs(teamTicks) do
            local name = names[i]
            cb.who = name
            cb:SetShown(name ~= nil)
            cb.label:SetShown(name ~= nil)
            cb.label:SetText(name and self:ShortName(name) or "")
            cb:SetChecked(false)
        end
    end
    CC:RefreshTeamTicks()
    y = y - 200
    local teamList = pl:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local function SayTeams()
        local lines = {}
        for _, n in ipairs(CC:TeamNames()) do
            lines[#lines + 1] = n .. ": " .. table.concat(CC.db.teams[n], ", ")
        end
        teamList:SetText(#lines > 0 and table.concat(lines, "\n") or L["No teams saved."])
    end
    NewButton(pl, 4, y, 80, L["Save team"], function()
        local members = NameList(teamTyped:GetText())
        for _, cb in ipairs(teamTicks) do
            if cb:IsShown() and cb:GetChecked() and cb.who then members[#members + 1] = CC:ShortName(cb.who) end
        end
        CC:SaveTeam(teamName:GetText(), members); SayTeams()
    end)
    NewButton(pl, 88, y, 80, L["Load team"], function()
        local members = CC.db.teams[Trim(teamName:GetText())]
        if members then teamTyped:SetText(table.concat(members, ", ")) end
    end)
    NewButton(pl, 172, y, 90, L["Remove team"], function()
        CC:RemoveTeam(Trim(teamName:GetText())); SayTeams()
    end)
    y = y - 28
    teamList:SetPoint("TOPLEFT", pl, "TOPLEFT", 4, y)
    teamList:SetWidth(CAW - 40)
    teamList:SetJustifyH("LEFT")
    SayTeams()
    y = y - 60
    pl:SetHeight(-y + 10)

    -- ══ Page 6: Profiles, setups and tools ════════════════════════════════

    local profScroll, pr = NewPage(true)
    pages[6] = profScroll
    y = -2

    NewHeader(pr, y, L["Profiles"]); y = y - 24
    local profLbl = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    profLbl:SetPoint("TOPLEFT", pr, "TOPLEFT", 4, y - 3)
    profLbl:SetText(L["Profile:"])
    local profName = NewEdit(pr, 60, y, 140, "")
    local profStatus = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    function CC:RefreshProfileStatus()
        local names = self:ProfileNames()
        profStatus:SetText(string.format(L["This character follows: %s.   Saved: %s."],
            self:CurrentProfile() or L["none"], #names > 0 and table.concat(names, ", ") or L["none"])
            .. (self.db.defaultProfile and ("   " .. string.format(L["New characters follow: %s"], tostring(self.db.defaultProfile))) or ""))
    end
    NewButton(pr, 206, y + 1, 74, L["Save as"], function()
        if CC:SaveProfile(profName:GetText()) then
            CC.db.charProfile[CC:FullName("player")] = Trim(profName:GetText())
        end
        CC:RefreshProfileStatus()
    end)
    NewButton(pr, 284, y + 1, 56, L["Use"], function()
        CC:UseProfile(Trim(profName:GetText())); CC:RefreshProfileStatus()
    end)
    NewButton(pr, 344, y + 1, 64, L["Delete"], function()
        CC:DeleteProfile(Trim(profName:GetText())); CC:RefreshProfileStatus()
    end)
    y = y - 26
    profStatus:SetPoint("TOPLEFT", pr, "TOPLEFT", 4, y)
    profStatus:SetWidth(CAW - 40)
    profStatus:SetJustifyH("LEFT")
    y = y - 32
    NewCheck(pr, 4, y, L["New characters follow the profile named above"],
        function() return CC.db.defaultProfile and CC.db.defaultProfile == Trim(profName:GetText()) or false end,
        function(v)
            CC.db.defaultProfile = (v and CC.db.profiles[Trim(profName:GetText())]) and Trim(profName:GetText()) or false
            CC:RefreshProfileStatus()
        end, L["Characters that haven't picked a profile follow this one."])
    y = y - 26
    NewCheck(pr, 4, y, L["This character keeps its own window places"],
        function() return CC:KeepsOwnPlaces() end, function(v) CC:SetKeepOwnPlaces(v) end,
        L["Whatever profile it follows, this character's windows stay where they are now."])
    y = y - 30
    CC:RefreshProfileStatus()

    NewHeader(pr, y, L["Export and import"]); y = y - 24
    NewNote(pr, 4, y, CAW - 40, L["A setup is your tracked and custom spells, ready alerts and window places, as text."])
    y = y - 30
    NewButton(pr, 4, y, 100, L["Export setup"], function()
        CC:ShowCopyBox(L["Your setup: copy this"], CC:ExportSetup(Trim(profName:GetText())))
    end)
    NewButton(pr, 108, y, 100, L["Import setup"], function() CC:ShowImportBox() end)
    NewButton(pr, 212, y, 150, L["Undo last setup"], function()
        print("|cFF54a3ffCDC|r " .. (CC:UndoSetup() and L["Back to what you had."] or L["Nothing to undo."]))
    end)
    y = y - 28
    NewButton(pr, 4, y, 230, L["Send my setup to the guild (officers)"], function() CC:SendOfficerSetup() end)
    y = y - 22
    NewNote(pr, 4, y, CAW - 40, L["Members see a box naming you and choose Accept, Not now or Never."])
    y = y - 34

    NewHeader(pr, y, L["Layouts"]); y = y - 24
    NewNote(pr, 4, y, CAW - 40, L["Window places are kept apart for a party and a raid and switch when your group type changes."])
    y = y - 30
    NewButton(pr, 4, y, 140, L["Reset all windows"], function() CC:ResetAllWindows() end)
    y = y - 34

    NewHeader(pr, y, L["Pulls, posting and new keys"]); y = y - 24
    NewCheck(pr, 4, y, L["After a boss, say the pull's log is ready"], function() return CC.db.lastPullOffer == true end,
        function(v) CC.db.lastPullOffer = v end, L["/cdc lastpull lists the tracked cooldowns used in the last pull."])
    y = y - 26
    NewCheck(pr, 4, y, L["On a key start, ask the group for its cooldowns again"], function() return CC.db.resetOnNewRun ~= false end,
        function(v) CC.db.resetOnNewRun = v end)
    y = y - 30
    NewButton(pr, 4, y, 110, L["Last pull"], function() CC:PrintLastPull() end)
    NewButton(pr, 118, y, 110, L["Post ready"], function() CC:PostReady() end)
    NewButton(pr, 232, y, 110, L["Support box"], function()
        CC:ShowCopyBox(L["Support: copy this into your report"], CC:SupportText())
    end)
    y = y - 34
    NewNote(pr, 4, y, CAW - 40, L["Post ready lists these spells and who has them in raid or party chat (none ticked: rez and lust):"])
    y = y - 30
    do
        local list = {}
        for id, data in pairs(CC.SpellData) do
            if not data.consumable and (data.kind == "rez" or data.kind == "lust" or data.kind == "raid"
                or data.kind == "external" or data.kind == "mana") then list[#list + 1] = id end
        end
        table.sort(list, function(a, c) return CC.SpellData[a].name < CC.SpellData[c].name end)
        for i, id in ipairs(list) do
            local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
            local cb, lb = NewCheck(pr, 4 + col * 240, y - rowN * 22, CC.SpellData[id].name,
                function() return CC.db.postSpells[id] == true end,
                function(v) CC.db.postSpells[id] = v or nil end)
            cb:SetSize(20, 20)
            lb:SetFontObject(GameFontHighlightSmall)
        end
        y = y - math.ceil(#list / 2) * 22
    end
    pr:SetHeight(-y + 10)

    -- Getting Started opens first
    ShowDefault()
    CC:RefreshDefaultSpellList()
    CC:RefreshSpellList()
    startPage.refresh()
    ShowPage(1)

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
    note:SetText(L["Click below to open the full settings window.\nYou can also right-click the minimap button or type /cdc settings."])

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(200, 26)
    openBtn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    openBtn:SetText(L["Open CooldownCollaborator Settings"])
    openBtn:SetScript("OnClick", function() CC:OpenOptions() end)

    -- The Settings panel where the client has it, else the old Interface
    -- Options list; neither is required (/cdc settings and the minimap button
    -- open the window), so a failure here never stops Init.
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "CooldownCollaborator")
        if ok and category then
            pcall(Settings.RegisterAddOnCategory, category)
            self.optionsCategoryID = category.ID
        end
    -- Older clients without the Settings API (Classic) use the interface options list.
    ---@diagnostic disable-next-line: undefined-global
    elseif InterfaceOptions_AddCategory then
        panel.name = "CooldownCollaborator"
        ---@diagnostic disable-next-line: undefined-global
        pcall(InterfaceOptions_AddCategory, panel)
    end
end
