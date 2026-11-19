-- Two small icon strips over the spells' `kind` (the Data rows):
--   Externals (P32): an icon per external (kind "external") an owner in the
--     group has, the owner's name under it and a time on the cooling ones; ready
--     ones first. Retail's list has Blessing of Sacrifice.
--   Mana (P24): an icon per mana spell (kind "mana") someone in the group has,
--     how many are ready ("1 of 2") and the next owner, and an Ask button anyone
--     may press: it whispers the next ready owner "<spell> on me please" (the one
--     who asks is the one in need, the owner's note).
-- Who has a spell goes by class (and spec where the data has one), like the
-- Essentials bar's providers; ourselves by our spellbook. A ready one nobody has
-- confirmed (no copy, no cast seen) carries the "?" (P44); a dead or offline
-- owner's icon is greyed with a mark.

local L = CC.L

local EXT_TILE, EXT_GAP, EXT_COLS, EXT_ROWS = 46, 8, 5, 4
local MANA_TILE, MANA_GAP = 64, 14
local ICON = 28
local TITLE_H, PAD_TOP, PAD_BOTTOM, PAD_SIDE, ROW_GAP = 20, 6, 7, 7, 6
local EXT_TILE_H = ICON + 3 + 12
local MANA_TILE_H = ICON + 3 + 12 + 12
local ASK_H = 22

-- Online and alive, as far as the game says (an unreadable answer counts as yes).
local function Presence(unit)
    if not unit then return true, true end
    local okC, on = pcall(function() return UnitIsConnected(unit) and true or false end)
    local okD, dead = pcall(function() return UnitIsDeadOrGhost(unit) and true or false end)
    return (not okC) or on, (not okD) or not dead
end

-- A spell only one specialization has (`spec` on its row) counts for a groupmate
-- once we know they are that spec.
local function SpecFits(data, name)
    if not data.spec then return true end
    local ok, same = pcall(function() return CC.rosterSpecs[name] == data.spec end)
    return ok and same == true
end

-- Every group member who could cast spellID, with where it stands:
-- { name, class, spellID, remaining, ready, online, alive, guessed }, ready first,
-- then the soonest back, then by name.
function CC:SpellOwners(spellID)
    local data = CC.SpellData[spellID]
    local out = {}
    if not data or not self.roster then return out end
    local me = self:FullName("player")
    for name, info in pairs(self.roster) do
        local isMe = name == me
        if info.class == data.class and ((isMe and self:KnownRank(spellID)) or (not isMe and SpecFits(data, name))) then
            local remaining = isMe and self:GetLocalReadiness(spellID) or nil
            if remaining == nil then remaining = self:GetRemaining(name, spellID) or 0 end
            local online, alive = Presence(self:UnitTokenFor(name, info.unit))
            local entry = self.state[name]
            local peer = self.peers and self.peers[name]
            local confirmed = isMe or (entry and entry.spells[spellID] ~= nil) or (peer and (peer.proto or 0) >= 2)
            out[#out + 1] = {
                name = name, class = info.class, spellID = spellID, remaining = remaining,
                ready = online and remaining <= 0, online = online, alive = alive, guessed = not confirmed,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.ready ~= b.ready then return a.ready end
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.name < b.name
    end)
    return out
end

-- The tracked spells of one kind, by name.
function CC:SpellsOfKind(kind)
    local ids = {}
    for id, data in pairs(CC.SpellData) do
        if data.kind == kind and not data.consumable then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local na, nb = CC.SpellData[a].name or "", CC.SpellData[b].name or ""
        if na ~= nb then return na < nb end
        return a < b
    end)
    return ids
end

-- A strip tile: a ring icon with lines of text under it.
local function NewTile(parent, width, lines)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(width, ICON + 3 + 12 * lines)
    t.icon = CC:CreateRingIcon(t, ICON)
    t.icon:SetPoint("TOP", t, "TOP", 0, 0)
    t.lines = {}
    for i = 1, lines do
        local fs = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOP", t, "TOP", 0, -(ICON + 3 + 12 * (i - 1)))
        fs:SetWidth(width)
        fs:SetWordWrap(false)
        t.lines[i] = fs
    end
    t:Hide()
    return t
end

local function TileLook(e, ready)
    local state = CC:OwnerState(e)
    if ready then
        return { spellID = e.spellID, owner = e.name, class = e.class, ring = "ready", state = state, guessed = e.guessed }
    end
    return { spellID = e.spellID, owner = e.name, class = e.class, ring = "none", state = state, dim = true,
        time = e.remaining > 0 and CC:LookIconTime(e.remaining) or nil }
end

-- Lay tiles out in centred rows of `cols`; returns the window's size.
local function LayoutTiles(f, tiles, count, cols, tileW, tileH, gap)
    local width = math.max(130, math.min(count, cols) * tileW + (math.min(count, cols) - 1) * gap + PAD_SIDE * 2)
    local rows = math.ceil(count / cols)
    for i = 1, count do
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        local inRow = math.min(cols, count - r * cols)
        local rowW = inRow * tileW + (inRow - 1) * gap
        local t = tiles[i]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", (width - rowW) / 2 + c * (tileW + gap), -(TITLE_H + PAD_TOP + r * (tileH + ROW_GAP)))
        t:Show()
    end
    for i = count + 1, #tiles do tiles[i]:Hide() end
    return width, TITLE_H + PAD_TOP + rows * tileH + math.max(0, rows - 1) * ROW_GAP + PAD_BOTTOM
end

-------------------------------------------------------------------------------
-- Externals
-------------------------------------------------------------------------------

function CC:BuildExternalsStrip()
    local f = self:NewLookWindow({
        width = 130, height = 60, xKey = "externalsX", yKey = "externalsY", title = "|cFF54a3ff" .. L["Externals"] .. "|r",
        onClose = function()
            CC.db.externalsEnabled = false
            CC.externalsFrame:Hide()
        end,
    })
    f.tiles = {}
    for i = 1, EXT_COLS * EXT_ROWS do f.tiles[i] = NewTile(f, EXT_TILE, 1) end
    local more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    more:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    more:Hide()
    f.more = more
    self.externalsFrame = f
    C_Timer.NewTicker(0.5, function() CC:RefreshView("RefreshExternalsStrip") end)
end

-- Every external someone else in the group has (the ones that can reach us):
-- ready ones first (by owner), then the cooling ones (soonest back first), then
-- a dead or offline owner's.
function CC:ExternalTiles()
    local me = self:FullName("player")
    local tiles = {}
    for _, id in ipairs(self:SpellsOfKind("external")) do
        for _, e in ipairs(self:SpellOwners(id)) do
            if e.name ~= me then tiles[#tiles + 1] = e end
        end
    end
    local function rank(e)
        if self:OwnerState(e) then return 2 end
        return e.ready and 0 or 1
    end
    table.sort(tiles, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        if ra == 1 and a.remaining ~= b.remaining then return a.remaining < b.remaining end
        if a.name ~= b.name then return a.name < b.name end
        return a.spellID < b.spellID
    end)
    return tiles
end

function CC:RefreshExternalsStrip()
    local f = self.externalsFrame
    if not f then return end
    if not self.db.externalsEnabled or not IsInGroup() then
        f:Hide()
        return
    end
    local list = self:ExternalTiles()
    local count = math.min(#list, #f.tiles)
    for i = 1, count do
        local e, t = list[i], f.tiles[i]
        self:SetRingIcon(t.icon, TileLook(e, e.ready))
        local c = CC.ClassColors[e.class] or CC.ClassColors.UNKNOWN
        t.lines[1]:SetText(self:ShortName(e.name))
        t.lines[1]:SetTextColor(c[1], c[2], c[3])
    end
    local width, height = LayoutTiles(f, f.tiles, count, EXT_COLS, EXT_TILE, EXT_TILE_H, EXT_GAP)
    if #list > count then
        f.more:SetText(string.format(L["+%d more"], #list - count))
        f.more:Show()
        height = height + 12
    else
        f.more:Hide()
    end
    f:SetSize(width, height)
    f:SetShown(count > 0)
end

-------------------------------------------------------------------------------
-- Mana, with Ask
-------------------------------------------------------------------------------

-- One tile per mana spell someone in the group has: { spellID, owners, ready
-- (live owners off cooldown), total, next (who'd answer, else the soonest back), ask
-- (the next ready owner who isn't us) }.
function CC:ManaTiles()
    local me = self:FullName("player")
    local tiles = {}
    for _, id in ipairs(self:SpellsOfKind("mana")) do
        local owners = self:SpellOwners(id)
        if #owners > 0 then
            local ready, ask, first = 0, nil, nil
            for _, e in ipairs(owners) do
                if e.ready and e.alive then
                    ready = ready + 1
                    first = first or e
                    if not ask and e.name ~= me then ask = e end
                end
            end
            tiles[#tiles + 1] = { spellID = id, owners = owners, ready = ready, total = #owners,
                next = ask or first or owners[1], ask = ask }
        end
    end
    return tiles
end

-- The one asking is the one in need: whisper the first mana spell's next ready
-- owner (not ourselves). Returns who was asked and for what, or nil.
function CC:AskForMana()
    for _, tile in ipairs(self:ManaTiles()) do
        local e = tile.ask
        if e then
            local data = CC.SpellData[tile.spellID]
            local spellName = data and data.name or L["Mana"]
            local sent = pcall(C_ChatInfo.SendChatMessage, string.format(L["%s on me please"], spellName), "WHISPER", nil, e.name)
            if sent then
                print(string.format("|cFF54a3ffCDC|r " .. L["asked %s for %s."], self:ShortName(e.name), spellName))
                return e.name, tile.spellID
            end
        end
    end
    print("|cFF54a3ffCDC|r " .. L["Nobody else in the group has a mana spell ready."])
    return nil
end

function CC:BuildManaStrip()
    local f = self:NewLookWindow({
        width = 130, height = 80, xKey = "manaX", yKey = "manaY", title = "|cFF54a3ff" .. L["Mana"] .. "|r",
        onClose = function()
            CC.db.manaEnabled = false
            CC.manaFrame:Hide()
        end,
    })
    f.tiles = {}
    for i = 1, 8 do f.tiles[i] = NewTile(f, MANA_TILE, 2) end

    local ask = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ask:SetSize(50, 16)
    ask:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
    ask:SetText(L["Ask"])
    ask:GetFontString():SetFontObject("GameFontHighlightSmall")
    ask:SetScript("OnClick", function() CC:AskForMana() end)
    ask:SetScript("OnEnter", function(widget)
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        local who
        for _, tile in ipairs(CC:ManaTiles()) do
            if tile.ask then who = tile break end
        end
        if who then
            local data = CC.SpellData[who.spellID]
            GameTooltip:AddLine(string.format(L["Whisper %s:"], CC:ShortName(who.ask.name)))
            GameTooltip:AddLine(string.format(L["%s on me please"], data and data.name or L["Mana"]), 1, 1, 1)
        else
            GameTooltip:AddLine(L["Nobody else in the group has a mana spell ready."])
        end
        GameTooltip:Show()
    end)
    ask:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.ask = ask

    self.manaFrame = f
    C_Timer.NewTicker(0.5, function() CC:RefreshView("RefreshManaStrip") end)
end

function CC:RefreshManaStrip()
    local f = self.manaFrame
    if not f then return end
    if not self.db.manaEnabled or not IsInGroup() then
        f:Hide()
        return
    end
    local list = self:ManaTiles()
    local count = math.min(#list, #f.tiles)
    local anyAsk = false
    for i = 1, count do
        local tile, t = list[i], f.tiles[i]
        local e = tile.next
        self:SetRingIcon(t.icon, TileLook(e, tile.ready > 0))
        t.lines[1]:SetText(string.format(L["%d of %d"], tile.ready, tile.total))
        t.lines[1]:SetTextColor(0.7, 0.7, 0.7)
        local c = CC.ClassColors[e.class] or CC.ClassColors.UNKNOWN
        t.lines[2]:SetText(self:ShortName(e.name))
        t.lines[2]:SetTextColor(c[1], c[2], c[3])
        if tile.ask then anyAsk = true end
    end
    local width, height = LayoutTiles(f, f.tiles, count, #f.tiles, MANA_TILE, MANA_TILE_H, MANA_GAP)
    f.ask:SetEnabled(anyAsk)
    f:SetSize(width, height + ASK_H)
    f:SetShown(count > 0)
end
