-- Dead list (P3): a small window of the dead group members in the leader's
-- order (healers, tanks, damage), how long each has been dead, a Call button on
-- each, and who would answer (the best living rezzer with a ready rez). A call
-- goes through Request Rez (CooldownCollaborator.lua): who may call (anyone in a
-- 5-player group, the leader or an assist in a raid), its channel (instance chat
-- in finder groups, R16) and its no-charges line. Opens when someone dies in
-- combat, closes when nobody is dead. /cdc rez with nobody targeted calls the top.

local L = CC.L

local WIDTH    = 240
local TITLE_H  = 20
local HEAD_H   = 18
local ROW_H    = 24
local MORE_H   = 16
local FOOT_H   = 24
local MAX_ROWS = 10   -- after a wipe the rest are "+N more"

local ROLE_ORDER = { HEALER = 1, TANK = 2, DAMAGER = 3 }
local ROLE_LABEL = { HEALER = L["Healer"], TANK = L["Tank"], DAMAGER = L["Damage"] }

CC.deaths = CC.deaths or {}   -- [Name-Realm] = GetTime() we first saw them dead

local function Hex(rgb)
    return string.format("%02x%02x%02x", math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5))
end

function CC:ClassColorName(name, class)
    local c = CC.ClassColors[class] or CC.ClassColors.UNKNOWN
    return "|cFF" .. Hex(c) .. self:ShortName(name) .. "|r"
end

-- Each group member once: { unit, name } (in a raid we are a raidN unit as well).
local function Members()
    local out, seen = {}, {}
    local function add(unit)
        local name = CC:FullName(unit)
        if name and not seen[name] then
            seen[name] = true
            out[#out + 1] = { unit = unit, name = name }
        end
    end
    add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do add("party" .. i) end
    end
    return out
end

-- Dead or a ghost, as far as the game says; an answer we can't read counts as alive.
local function IsDead(unit)
    local ok, dead = pcall(function() return UnitIsDeadOrGhost(unit) and true or false end)
    return ok and dead == true
end

local function Role(unit)
    if not UnitGroupRolesAssigned then return "NONE" end
    local ok, role = pcall(function()
        local r = UnitGroupRolesAssigned(unit)
        if ROLE_ORDER[r] then return r end
    end)
    return ok and role or "NONE"
end

-- The group is fighting: a boss, our own combat, or anyone in the group in combat
-- (a player who has just died is out of combat, so we can't go by them alone).
local function InCombat(members)
    if CC.inEncounter or InCombatLockdown() then return true end
    for _, m in ipairs(members) do
        local ok, yes = pcall(function() return UnitAffectingCombat(m.unit) and true or false end)
        if ok and yes then return true end
    end
    return false
end

-- Who is dead now, kept with when we first saw it. A death seen while the group
-- is fighting opens the window (CC.deathInCombat, read by its refresh).
function CC:ScanDeaths(members)
    local now, here = GetTime(), {}
    members = members or Members()
    local fighting
    for _, m in ipairs(members) do
        here[m.name] = true
        if IsDead(m.unit) then
            if not self.deaths[m.name] then
                self.deaths[m.name] = now
                if fighting == nil then fighting = InCombat(members) end
                if fighting then self.deathInCombat = true end
            end
        else
            self.deaths[m.name] = nil
        end
    end
    for name in pairs(self.deaths) do
        if not here[name] then self.deaths[name] = nil end
    end
end

-- The dead in the leader's order: healers, tanks, damage, then anyone without a
-- role; the longest dead first. { name, unit, class, role, diedAt }
function CC:DeadList()
    local members = Members()   -- one pass over the group serves the scan and the list
    self:ScanDeaths(members)
    local list = {}
    for _, m in ipairs(members) do
        local diedAt = self.deaths[m.name]
        if diedAt then
            local _, class = UnitClass(m.unit)
            list[#list + 1] = { name = m.name, unit = m.unit, class = class or "UNKNOWN", role = Role(m.unit), diedAt = diedAt }
        end
    end
    table.sort(list, function(a, b)
        local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
        if ra ~= rb then return ra < rb end
        if a.diedAt ~= b.diedAt then return a.diedAt < b.diedAt end
        return a.name < b.name
    end)
    return list
end

local function NewRow(f, i)
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(WIDTH - 8, ROW_H)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(TITLE_H + HEAD_H + (i - 1) * ROW_H))

    local hi = row:CreateTexture(nil, "BACKGROUND")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.07)
    local edge = row:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    edge:SetWidth(2)
    edge:SetColorTexture(1, 0.82, 0, 1)
    row.hi, row.edge = hi, edge

    local role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    role:SetPoint("LEFT", row, "LEFT", 6, 0)
    role:SetWidth(40)
    role:SetJustifyH("LEFT")
    role:SetTextColor(0.7, 0.7, 0.7)
    row.role = role

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", role, "RIGHT", 6, 0)
    name:SetWidth(120)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local call = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    call:SetSize(50, 16)
    call:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    call:SetText(L["Call"])
    call:GetFontString():SetFontObject("GameFontHighlightSmall")
    call:SetScript("OnClick", function(widget)
        if widget.target then CC:CallRez(widget.target) end
    end)
    row.call = call
    row:Hide()
    return row
end

function CC:BuildDeadList()
    local f = self:NewLookWindow({
        width = WIDTH, height = TITLE_H + HEAD_H + ROW_H + FOOT_H + 6, xKey = "deadListX", yKey = "deadListY",
        title = "|cFF54a3ff" .. L["Dead list"] .. "|r",
        onClose = function()
            CC.deadOpen = false
            CC.deadFrame:Hide()
        end,
    })

    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(TITLE_H + 3))
    head:SetTextColor(0.6, 0.8, 1)
    f.head = head

    f.rows = {}
    for i = 1, MAX_ROWS do f.rows[i] = NewRow(f, i) end

    local more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    more:Hide()
    f.more = more

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(0.3, 0.3, 0.5, 0.6)
    f.footLine = line
    local foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    foot:SetJustifyH("LEFT")
    foot:SetWidth(WIDTH - 18)
    foot:SetWordWrap(false)
    foot:SetTextColor(0.85, 0.85, 0.85)
    f.foot = foot

    self.deadFrame = f
    -- Every half second while the window shows, someone is dead or the group is fighting; hidden
    -- with nobody dead and no fight, a look every 2 seconds is enough to notice the next death.
    local idle = 0
    C_Timer.NewTicker(0.5, function()
        if not (f:IsShown() or next(CC.deaths) or CC.deadOpen or CC.deathInCombat
            or CC.inEncounter or CC.inCombat or InCombatLockdown()) then
            idle = idle + 1
            if idle < 4 then return end
        end
        idle = 0
        CC:RefreshView("RefreshDeadList")
    end)
end

-- Who would answer a call for the top of the list, as the foot line says it.
function CC:DeadListFoot(top)
    local noCharges = self:NoRezChargesText()
    if noCharges then return "|cFFFF6666" .. noCharges .. "|r" end
    local rezzer = top and self:BestRezzer(top.name)
    if not rezzer then return "|cFF808080" .. L["Nobody living has a Battle Rez ready"] .. "|r" end
    local data = CC.SpellData[rezzer.spellID]
    return string.format(L["Answers: %s, %s |cFF4DFF4DREADY|r"], self:ClassColorName(rezzer.name, rezzer.class),
        data and data.name or L["Battle Rez"])
end

function CC:RefreshDeadList()
    local f = self.deadFrame
    if not f then return end
    if not self.db.deadListEnabled or not IsInGroup() then
        self.deadOpen, self.deathInCombat = false, nil
        f:Hide()
        return
    end
    local list = self:DeadList()
    if #list == 0 then
        self.deadOpen, self.deathInCombat = false, nil
        f:Hide()
        return
    end
    if self.deathInCombat then
        self.deathInCombat = nil
        self.deadOpen = true
    end
    if not self.deadOpen then
        f:Hide()
        return
    end

    f.head:SetText(UnitIsGroupLeader("player") and string.format(L["Dead (%d), in your order"], #list) or string.format(L["Dead (%d)"], #list))
    local canCall = self:CanRequestRez()
    local now = GetTime()
    local shown = math.min(#list, MAX_ROWS)
    for i, row in ipairs(f.rows) do
        local d = list[i]
        if d and i <= shown then
            row.role:SetText(ROLE_LABEL[d.role] or "")
            row.name:SetText(self:ClassColorName(d.name, d.class) .. "  |cFF808080" .. self:LookClock(now - d.diedAt) .. "|r")
            row.hi:SetShown(i == 1)
            row.edge:SetShown(i == 1)
            row.call.target = d.name
            row.call:SetShown(canCall)
            row:Show()
        else
            row.call.target = nil
            row:Hide()
        end
    end

    local y = TITLE_H + HEAD_H + shown * ROW_H
    if #list > shown then
        f.more:ClearAllPoints()
        f.more:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(y + 2))
        f.more:SetText(string.format(L["+%d more"], #list - shown))
        f.more:Show()
        y = y + MORE_H
    else
        f.more:Hide()
    end
    f.footLine:ClearAllPoints()
    f.footLine:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(y + 3))
    f.footLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -(y + 3))
    f.foot:ClearAllPoints()
    f.foot:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -(y + 8))
    f.foot:SetText(self:DeadListFoot(list[1]))
    f:SetHeight(y + FOOT_H + 6)
    f:Show()
end
