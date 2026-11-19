-- Burst line (P29, "Shared time line"): your own big cooldowns above a 2-minute
-- line and the group's lust and Power Infusion below it, with a gold band where
-- they meet: the earliest time the group's lust (and PI, where the group has
-- one) and at least one of your counted spells are all back.
-- Your counted spells: your own tracked spells of kind "personal" or "raid" with a
-- cooldown of 90 s or more, unless db.burstSpells lists them ([spellID] = true).
-- An icon's place on the line comes from what we can read: our own cooldown where
-- the game shows it, else the cast we saw. Your icons also carry the game's own
-- cooldown as a swipe; on Retail and Forever that value can be hidden, and a hidden
-- value only ever goes into that widget.

local L = CC.L

local WIDTH, HEIGHT = 312, 100
local LEFT, SPAN, SECONDS = 54, 240, 120   -- "now" at LEFT, 2:00 at LEFT + SPAN
local TOP = 20                             -- room for the band's gold time above it
local ICON = 20
local OWN_Y, GROUP_Y, AXIS_Y, TICK_Y = 8, 42, 35, 64   -- below TOP, as the drawing has them
local MAX_OWN = 8
local PI_ID = 10060

local function X(secs)
    return LEFT + math.min(SECONDS, math.max(0, secs)) / SECONDS * SPAN
end

-- Our own spells the line counts, by name.
function CC:BurstSpells()
    local _, class = UnitClass("player")
    local chosen = self.db.burstSpells
    local useList = type(chosen) == "table" and next(chosen) ~= nil
    -- lust and PI are the group's line
    local skip = { [PI_ID] = true }
    local lust = CC.CAPABILITIES.BLOODLUST
    for _, ids in pairs(lust and lust.classes or {}) do
        for _, id in ipairs(ids) do skip[id] = true end
    end
    local ids = {}
    for id, data in pairs(CC.SpellData) do
        if data.class == class and not data.consumable and not skip[id] and self:KnownRank(id) then
            local counts
            if useList then
                counts = chosen[id] or chosen[tostring(id)]
            else
                counts = (data.kind == "personal" or data.kind == "raid") and (data.duration or 0) >= 90
            end
            if counts then ids[#ids + 1] = id end
        end
    end
    table.sort(ids, function(a, b) return (CC.SpellData[a].name or "") < (CC.SpellData[b].name or "") end)
    return ids
end

-- The group's next lust and next PI: the soonest live owner of each, or nil.
local function Soonest(list)
    for _, e in ipairs(list) do
        if e.online ~= false and e.alive ~= false then return e end
    end
end

function CC:BurstGroup()
    local out = {}
    if CC.CAPABILITIES.BLOODLUST then
        local lust = Soonest(self:GetCapabilityStatus("BLOODLUST"))
        if lust then out[#out + 1] = lust end
    end
    if CC.SpellData[PI_ID] then
        local pi = Soonest(self:SpellOwners(PI_ID))
        if pi then out[#out + 1] = pi end
    end
    return out
end

-- When they meet: the earliest time every group icon and one of ours are back, or nil.
function CC:BurstMeet(own, group)
    if #own == 0 or #group == 0 then return nil end
    local t = own[1].remaining
    for _, e in ipairs(own) do t = math.min(t, e.remaining) end
    for _, e in ipairs(group) do t = math.max(t, e.remaining) end
    return t
end

-- The game's own cooldown into the swipe. Readable: a GCD is no cooldown. Hidden:
-- the compare throws inside the pcall, and the values go straight into the widget.
local function Swipe(cd, spellID)
    local id = CC:KnownRank(spellID) or spellID
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
    if not info then
        cd:Clear()
        return
    end
    local readable, gcd = pcall(function() return info.duration <= 1.5 end)
    if readable and gcd then
        cd:Clear()
    else
        pcall(cd.SetCooldown, cd, info.startTime, info.duration)
    end
end

local function NewIcon(f)
    local w = CC:CreateRingIcon(f, ICON)
    local cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawEdge(false)
    w.cooldown = cd
    w:Hide()
    return w
end

local function Label(f, text, x, y, r, g, b)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("CENTER", f, "TOPLEFT", x, -y)
    fs:SetText(text)
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

function CC:BuildBurstLine()
    local f = self:NewLookWindow({
        width = WIDTH, height = HEIGHT, xKey = "burstX", yKey = "burstY",
        onClose = function()
            CC.db.burstEnabled = false
            CC.burstFrame:Hide()
        end,
    })
    local axis = f:CreateTexture(nil, "BORDER")
    axis:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, -(TOP + AXIS_Y))
    axis:SetSize(SPAN, 2)
    axis:SetColorTexture(0.2, 0.2, 0.25, 0.9)
    local band = f:CreateTexture(nil, "BORDER", nil, 1)
    band:SetSize(22, GROUP_Y + ICON - 2)
    band:SetColorTexture(1, 0.82, 0, 0.55)
    band:Hide()
    f.band = band
    f.bandTime = Label(f, "", LEFT, TOP - 8, 1, 0.82, 0)
    f.bandTime:Hide()

    local youLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    youLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(TOP + 12))
    youLabel:SetText(L["You"])
    local groupLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    groupLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(TOP + GROUP_Y + 4))
    groupLabel:SetText(L["Group"])
    Label(f, L["now"], LEFT, TOP + TICK_Y + 5)
    Label(f, "1:00", LEFT + SPAN / 2, TOP + TICK_Y + 5)
    Label(f, "2:00", LEFT + SPAN, TOP + TICK_Y + 5)

    f.own, f.group = {}, {}
    for i = 1, MAX_OWN do f.own[i] = NewIcon(f) end
    for i = 1, 2 do f.group[i] = NewIcon(f) end
    self.burstFrame = f
    C_Timer.NewTicker(0.5, function() CC:RefreshView("RefreshBurstLine") end)
end

-- Icons along one line at their times; one that would sit on the one before moves just past it.
local function PlaceRow(f, icons, entries, y, own)
    local lastX
    for i, w in ipairs(icons) do
        local e = entries[i]
        if e then
            local x = X(e.remaining)
            if lastX and x < lastX + ICON + 1 then x = lastX + ICON + 1 end
            lastX = x
            w:ClearAllPoints()
            w:SetPoint("TOP", f, "TOPLEFT", x, -(TOP + y))
            CC:SetRingIcon(w, { spellID = e.spellID, owner = e.name, class = e.class, ring = "none",
                state = CC:OwnerState(e), guessed = e.guessed and e.remaining <= 0 })
            if own then Swipe(w.cooldown, e.spellID) else w.cooldown:Clear() end
        else
            w:Hide()
        end
    end
end

function CC:RefreshBurstLine()
    local f = self.burstFrame
    if not f then return end
    if not self.db.burstEnabled or not IsInGroup() then
        f:Hide()
        return
    end
    local me = self:FullName("player")
    local _, class = UnitClass("player")
    local own = {}
    for _, id in ipairs(self:BurstSpells()) do
        local remaining = self:GetLocalReadiness(id)
        if remaining == nil then remaining = self:GetRemaining(me, id) or 0 end
        own[#own + 1] = { spellID = id, name = me, class = class, remaining = remaining }
    end
    table.sort(own, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.spellID < b.spellID
    end)
    local group = self:BurstGroup()
    table.sort(group, function(a, b) return a.remaining < b.remaining end)

    PlaceRow(f, f.own, own, OWN_Y, true)
    PlaceRow(f, f.group, group, GROUP_Y, false)

    local meet = self:BurstMeet(own, group)
    if meet and meet <= SECONDS then
        f.band:ClearAllPoints()
        f.band:SetPoint("TOP", f, "TOPLEFT", X(meet), -(TOP + OWN_Y - 4))
        f.band:Show()
        f.bandTime:ClearAllPoints()
        f.bandTime:SetPoint("CENTER", f, "TOPLEFT", X(meet), -(TOP - 8))
        f.bandTime:SetText(self:LookClock(math.ceil(meet)))
        f.bandTime:Show()
    else
        f.band:Hide()
        f.bandTime:Hide()
    end
    f.meet = meet
    f:SetShown(#own > 0 or #group > 0)
end
