-- Setups, profiles, layouts and the smaller tools around them (settings lane, part 2):
--   P15  setups as text: export / import with a copy box, named profiles a character picks
--   P42  officer setups over the guild channel (O kind), with Accept / Not now / Never
--   P21  window places saved separately for a party and a raid, and Reset all windows
--   P33  the last pull's cooldown log (/cdc lastpull)
--   P38  /cdc post: what's ready for the spells you pick, to the group's chat
--   P45  a new key or dungeon: the cooldowns the game resets go back to ready
--   P19  /cdc report: a box with what to paste into a new issue
--   P34  CC.API, a small public feed for other addons (docs/API.md)
-- A setup is { disabled = { spellID, ... }, custom = { [id] = { name, duration, icon } },
-- alerts = { [id] = { sound, flash, midscreen, warn } }, places = { [windowKey] = { x, y [, slot] }, block = { x, y } } }
-- (slot: a joined window's place in the block, 0 = loose; see Joined windows below).

local L = CC.L

local SETUP_FORMAT = "1"
local CHUNK = 200
local MAX_PARTS = 64

-------------------------------------------------------------------------------
-- Text form: a version, then key=value pairs (";" between); the values' ":" ";"
-- "," "=" "%" and line breaks are written %XX.
--   1;k=setup;n=<name>;d=<id>,<id>;c=<id>,<name>,<seconds>,<icon>;a=<id>,<sound>,<flash>,<mid>,<warn>;w=<key>,<x>,<y>[,<slot>]
-------------------------------------------------------------------------------

local function Quote(s)
    return (tostring(s):gsub("[%%:;,=\r\n|]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unquote(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function Split(s)
    local out = {}
    for piece in (s .. ","):gmatch("([^,]*),") do out[#out + 1] = Unquote(piece) end
    return out
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-------------------------------------------------------------------------------
-- Joined windows (settings pass pick "Joined together", 19 Nov): the Essentials bar, the main panel
-- and the Lane view start as one block, edge to edge, top down in that order. Each joined window
-- hangs from the bottom of the shown one above it, so a window that grows or shrinks moves the ones
-- under it, and a hidden one (off, solo, combat-only) is skipped. Unlocked, dragging the block's top
-- shown window moves the block; dragging another joined window pulls it loose, a free window where it
-- is dropped. A loose window dropped within SNAP of the block's top or bottom edge, or onto a block
-- window, joins the block at that edge; no window of the three lands on another. Reset puts a window
-- back in its slot. The other four windows stay free windows (their places as before).
-- db.blockOrder = the joined windows' keys, top down; db.blockX / blockY = the block's top-left in
-- UIParent units from UIParent's top centre. A loose window's place is db[xKey] / db[yKey] as before:
-- its centre from UIParent's centre, in the window's own scale (what SetPoint takes).
-- In a places table (layouts, profiles, setups) a joined window's entry carries its slot as a third
-- number (0 = loose) and places.block = { blockX, blockY }; an entry without the third number comes
-- from before joined windows and joins only if it is still at the start place.
-------------------------------------------------------------------------------

CC.BLOCK_KEYS = { "essentials", "main", "lanes" }
local SNAP = 12   -- UIParent units: a loose window dropped this close to the block's top or bottom joins it

local function WindowByKey(key)
    for _, w in ipairs(CC.WINDOWS or {}) do
        if w.key == key then return w end
    end
end

local function HomeSlot(key)
    for i, k in ipairs(CC.BLOCK_KEYS) do
        if k == key then return i end
    end
end

-- UIParent units per unit of f's own scale
local function UIScaleOf(f)
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- f's rect in UIParent units { left, bottom, right, top }, or nil while it has none
local function RectOf(f)
    local l, b, w, h = f:GetRect()
    if not (l and b and w and h) then return nil end
    local s = UIScaleOf(f)
    return { l * s, b * s, (l + w) * s, (b + h) * s }
end

local function Overlap(a, b)
    return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5
end

local function SideBySide(a, b)
    return a[1] < b[3] and b[1] < a[3]
end

-- a saved x / y still at the window's start place (never moved by the player; GetCenter rounding allowed)
function CC:AtStartPlace(w, x, y)
    local dx, dy = CC.DEFAULTS[w.xKey], CC.DEFAULTS[w.yKey]
    return type(x) == "number" and type(y) == "number" and dx ~= nil and dy ~= nil
        and math.abs(x - dx) <= 2 and math.abs(y - dy) <= 2
end

-- Start places of the dead list, externals, mana and burst windows (settings pass, owner's look board
-- "Joined together", places). Each is a share of UIParent's width and height, so it holds at any UI scale
-- and screen shape, turned into the centre offset the saved x / y have always been (a window's centre
-- from UIParent's centre): left / top are the window's top-left (burst: horizontally centred) as a share
-- of the screen, w / h the window's size when it opens (its smallest: it grows from its centre as it fills).
-- Dead list beside the party frames, externals and mana in a column under it, burst just above the action bars.
CC.START_PLACES = {
    dead      = { left = 0.13, top = 0.20, w = 240, h = 92 },
    externals = { left = 0.13, top = 0.39, w = 130, h = 76 },
    mana      = { left = 0.13, top = 0.48, w = 130, h = 110 },
    burst     = { centre = true, top = 0.72, w = 312, h = 100 },
}
-- where those four started before (CENTER offsets); a save still there moves to the new place
CC.OLD_PLACES = {
    dead = { -300, 60 }, externals = { -300, -60 }, mana = { -300, -170 }, burst = { 330, -60 },
}

local function Round(v) return math.floor(v + 0.5) end

-- the start x, y of one of the four for a screen uw by uh UIParent units
function CC:StartPlaceFor(key, uw, uh)
    local sp = CC.START_PLACES[key]
    if not sp then return nil end
    local x = sp.centre and 0 or (sp.left * uw + sp.w / 2 - uw / 2)
    local y = uh / 2 - (sp.top * uh + sp.h / 2)
    return Round(x), Round(y)
end

-- DEFAULTS for the four, from this screen (before the saved settings take their defaults)
function CC:ComputeStartPlaces()
    local uw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
    local uh = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
    if not (uw and uh and uw > 0 and uh > 0) then return end
    for _, w in ipairs(CC.WINDOWS or {}) do
        local x, y = self:StartPlaceFor(w.key, uw, uh)
        if x then CC.DEFAULTS[w.xKey], CC.DEFAULTS[w.yKey] = x, y end
    end
end

-- The dead list, externals and mana windows are a column at the left (beside the party frames). One
-- still at its start place keeps its top on its mark (START_PLACES.top) but never closer than COLUMN_GAP to
-- the bottom of the shown one above it, so a growing dead list or a tall externals strip pushes the ones
-- below down instead of lying on them; its x / y stay the start place's (Reset and "at the start" are
-- the same test). One the player moved is loose at its own place. The burst line is not in the column.
CC.COLUMN_KEYS = { "dead", "externals", "mana" }
local COLUMN_GAP = 8

local function WatchColumn(f)
    if f.ccColumnWatched then return end
    f.ccColumnWatched = true
    local function again() CC:LayoutColumn() end
    f:HookScript("OnShow", again)
    f:HookScript("OnHide", again)
    f:HookScript("OnSizeChanged", again)
end

function CC:LayoutColumn()
    local db = self.db
    if not db or self.layingOutColumn then return end
    self.layingOutColumn = true
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local prevBottom
    for _, key in ipairs(CC.COLUMN_KEYS) do
        local w = WindowByKey(key)
        local f = w and self[w.frame]
        local sp = CC.START_PLACES[key]
        if f and sp and uw and uh and uw > 0 and uh > 0 then
            WatchColumn(f)
            local k = 1 / UIScaleOf(f)
            if self:AtStartPlace(w, db[w.xKey], db[w.yKey]) then
                if f:IsShown() then
                    local top = sp.top * uh
                    if prevBottom then top = math.max(top, prevBottom + COLUMN_GAP) end
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sp.left * uw * k, -top * k)
                    f:SetClampedToScreen(true)
                    prevBottom = top + (f:GetHeight() or 0) / k
                end
            else
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", db[w.xKey] or 0, db[w.yKey] or 0)
            end
        end
    end
    self.layingOutColumn = nil
end

-- A saved place of one of the four still at its old start moves to the new one (a places table entry or
-- the live x / y); a window the player moved stays. Returns true when it moved.
local function AtOld(key, x, y)
    local o = CC.OLD_PLACES[key]
    return o and type(x) == "number" and type(y) == "number" and math.abs(x - o[1]) <= 2 and math.abs(y - o[2]) <= 2
end

local function MovePlaces(places)
    if type(places) ~= "table" then return end
    for _, w in ipairs(CC.WINDOWS or {}) do
        local p = places[w.key]
        if type(p) == "table" and AtOld(w.key, tonumber(p[1]), tonumber(p[2])) then
            p[1], p[2] = CC.DEFAULTS[w.xKey], CC.DEFAULTS[w.yKey]
        end
    end
end

-- Once, at the first load after the new start places: the live places, the layouts, the characters' own
-- places and every profile's places and layouts.
function CC:MoveOldPlaces()
    local db = self.db
    if db.startPlacesV2 then return end
    db.startPlacesV2 = true
    for _, w in ipairs(CC.WINDOWS or {}) do
        if CC.OLD_PLACES[w.key] and AtOld(w.key, db[w.xKey], db[w.yKey]) then
            db[w.xKey], db[w.yKey] = CC.DEFAULTS[w.xKey], CC.DEFAULTS[w.yKey]
        end
    end
    local function layouts(t)
        for _, places in pairs(type(t) == "table" and t or {}) do MovePlaces(places) end
    end
    layouts(db.layouts)
    layouts(db.charPlaces)
    for _, snap in pairs(type(db.profiles) == "table" and db.profiles or {}) do
        if type(snap) == "table" then
            MovePlaces(snap.places)
            layouts(snap.layouts)
        end
    end
end

-- The joined windows, top down. A save from before joined windows has none: the windows still at their
-- start places join, a window the player moved stays loose where it was.
function CC:BlockOrder()
    local db = self.db
    if type(db.blockOrder) ~= "table" then
        local order = {}
        for _, key in ipairs(CC.BLOCK_KEYS) do
            local w = WindowByKey(key)
            if w and self:AtStartPlace(w, db[w.xKey], db[w.yKey]) then order[#order + 1] = key end
        end
        db.blockOrder = order
    end
    return db.blockOrder
end

function CC:IsJoined(key)
    for _, k in ipairs(self:BlockOrder()) do
        if k == key then return true end
    end
    return false
end

local function Unjoin(order, key)
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) end
    end
end

local function BlockFrames(self)
    local list = {}
    for _, key in ipairs(self:BlockOrder()) do
        local w = WindowByKey(key)
        local f = w and self[w.frame]
        if f and f:IsShown() then list[#list + 1] = { key = key, w = w, f = f } end
    end
    return list
end

-- the key of the block's top shown window
function CC:BlockTop()
    local list = BlockFrames(self)
    return list[1] and list[1].key or nil
end

-- Layout runs again when one of the three shows, hides or changes size (the block's fit on screen).
local function Watch(self, f)
    if f.ccBlockWatched then return end
    f.ccBlockWatched = true
    local function again() CC:LayoutBlock() end
    f:HookScript("OnShow", again)
    f:HookScript("OnHide", again)
    f:HookScript("OnSizeChanged", again)
end

-- Anchor the three windows: the joined ones hanging one from another, the loose ones at their places.
-- The block keeps on the screen: it moves left or up (for now, not in its saved place) when its widest
-- window or its height would pass the screen's edge.
function CC:LayoutBlock()
    local db = self.db
    if not db or self.layingOutBlock then return end
    self.layingOutBlock = true
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local left = uw / 2 + (tonumber(db.blockX) or CC.DEFAULTS.blockX)
    local top = uh + (tonumber(db.blockY) or CC.DEFAULTS.blockY)
    local widest, tall = 0, 0
    for _, item in ipairs(BlockFrames(self)) do
        local s = UIScaleOf(item.f)
        widest = math.max(widest, (item.f:GetWidth() or 0) * s)
        tall = tall + (item.f:GetHeight() or 0) * s
    end
    if uw and uw > 0 then left = math.max(0, math.min(left, uw - widest)) end
    if uh and uh > 0 then top = math.min(uh, math.max(top, math.min(uh, tall))) end

    local joined, prev = {}, nil
    for _, key in ipairs(self:BlockOrder()) do
        local w = WindowByKey(key)
        local f = w and self[w.frame]
        if f then
            joined[key] = true
            Watch(self, f)
            f:ClearAllPoints()
            if prev then
                f:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
            else
                local k = 1 / UIScaleOf(f)
                f:SetPoint("TOPLEFT", UIParent, "TOP", (left - uw / 2) * k, (top - uh) * k)
            end
            -- a hanging window is never pushed onto the one above it by the screen's edge
            f:SetClampedToScreen(prev == nil)
            if f:IsShown() then prev = f end
        end
    end
    for _, key in ipairs(CC.BLOCK_KEYS) do
        local w = WindowByKey(key)
        local f = w and self[w.frame]
        if f and not joined[key] then
            Watch(self, f)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", db[w.xKey] or 0, db[w.yKey] or 0)
            f:SetClampedToScreen(true)
        end
    end
    self.layingOutBlock = nil
end

-- A loose window's place from where its frame is now: its centre from UIParent's centre, in its own scale.
function CC:SaveWindowPlace(key)
    local w = WindowByKey(key)
    local f = w and self[w.frame]
    if not f or (HomeSlot(key) and self:IsJoined(key)) then return end
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        local k = 1 / UIScaleOf(f)
        self.db[w.xKey], self.db[w.yKey] = x - ux * k, y - uy * k
    end
end

-- Put a window in the block at its top or bottom; joining at the top keeps the block where it is
-- (the window goes above it).
function CC:JoinBlock(key, edge)
    local order = self:BlockOrder()
    local list = BlockFrames(self)
    Unjoin(order, key)
    if edge == "top" then
        local w = WindowByKey(key)
        local f = w and self[w.frame]
        local first = list[1] and list[1].key ~= key and RectOf(list[1].f)
        if first and f then
            local h = (f:GetHeight() or 0) * UIScaleOf(f)
            self.db.blockX = first[1] - UIParent:GetWidth() / 2
            self.db.blockY = math.min(0, first[4] + h - UIParent:GetHeight())
        end
        table.insert(order, 1, key)
    else
        order[#order + 1] = key
    end
end

-- After a drop: a loose window on a block window (or the dropped one near the block's top or bottom
-- edge) joins the block at the nearer edge (for the dropped one, the edge nearer its top); the dropped window on another loose one goes edge to edge
-- with it. Until nothing of the three lies on another.
function CC:SettleWindows(dropped)
    for _ = 1, 4 do
        local changed = false
        local list = BlockFrames(self)
        local firstR = list[1] and RectOf(list[1].f)
        local lastR = list[#list] and RectOf(list[#list].f)
        for _, key in ipairs(CC.BLOCK_KEYS) do
            local w = WindowByKey(key)
            local f = w and self[w.frame]
            local r = f and f:IsShown() and not self:IsJoined(key) and RectOf(f)
            if r and firstR and lastR then
                local edge
                for _, item in ipairs(list) do
                    local br = RectOf(item.f)
                    if br and Overlap(r, br) then
                        -- the dropped window goes by where its top lands (it is held by its top part),
                        -- one the block landed on by its middle
                        local y = key == dropped and r[4] or (r[2] + r[4]) / 2
                        edge = y > (firstR[4] + lastR[2]) / 2 and "top" or "bottom"
                    end
                end
                if not edge and key == dropped then
                    if SideBySide(r, firstR) and math.abs(r[2] - firstR[4]) <= SNAP then edge = "top"
                    elseif SideBySide(r, lastR) and math.abs(r[4] - lastR[2]) <= SNAP then edge = "bottom" end
                end
                if edge then
                    self:JoinBlock(key, edge)
                    self:LayoutBlock()
                    changed = true
                    break
                end
            end
        end
        if not changed and dropped and not self:IsJoined(dropped) then
            local w = WindowByKey(dropped)
            local f = w and self[w.frame]
            local r = f and RectOf(f)
            for _, key in ipairs(CC.BLOCK_KEYS) do
                local ow = WindowByKey(key)
                local o = key ~= dropped and ow and self[ow.frame]
                local orr = o and o:IsShown() and RectOf(o)
                if r and orr and Overlap(r, orr) then
                    -- under it, or over it when there is no room under
                    local h = r[4] - r[2]
                    local cy = orr[2] - h / 2
                    if orr[2] - h < 0 then cy = orr[4] + h / 2 end
                    local cx = orr[1] + (r[3] - r[1]) / 2
                    local k = 1 / UIScaleOf(f)
                    self.db[w.xKey] = (cx - UIParent:GetWidth() / 2) * k
                    self.db[w.yKey] = (cy - UIParent:GetHeight() / 2) * k
                    self:LayoutBlock()
                    changed = true
                    break
                end
            end
        end
        if not changed then return end
    end
end

-- Dragging one of the three (its frame, or a line on it that passes the drag on). The block's top
-- window takes the block; another joined window comes loose first and the ones under it close up.
function CC:StartWindowDrag(key)
    local w = WindowByKey(key)
    local f = w and self[w.frame]
    if not f or self.db[w.lockKey] then return end
    -- a drag that never heard its end (its window hidden mid-drag) ends here
    if self.windowDrag then self:StopWindowDrag(self.windowDrag) end
    if self:IsJoined(key) and self:BlockTop() ~= key then
        local x, y = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and ux then
            local k = 1 / UIScaleOf(f)
            self.db[w.xKey], self.db[w.yKey] = x - ux * k, y - uy * k
        end
        Unjoin(self:BlockOrder(), key)
        self:LayoutBlock()
    end
    self.windowDrag = key
    f:StartMoving()
end

function CC:StopWindowDrag(key)
    if self.windowDrag ~= key then return end
    self.windowDrag = nil
    local w = WindowByKey(key)
    local f = w and self[w.frame]
    if not f then return end
    f:StopMovingOrSizing()
    -- the addon keeps this place; the game's own layout cache stays out of it
    f:SetUserPlaced(false)
    if self:IsJoined(key) then
        local r = RectOf(f)
        if r then
            self.db.blockX = r[1] - UIParent:GetWidth() / 2
            self.db.blockY = r[4] - UIParent:GetHeight()
        end
    else
        self:SaveWindowPlace(key)
    end
    self:LayoutBlock()
    self:SettleWindows(key)
end

-- Reset: a joined window back into the block in its own slot.
function CC:RejoinWindow(key)
    local home = HomeSlot(key)
    if not home then return end
    local order = self:BlockOrder()
    Unjoin(order, key)
    local at = #order + 1
    for i, k in ipairs(order) do
        if (HomeSlot(k) or 0) > home then at = i; break end
    end
    table.insert(order, at, key)
    self:LayoutBlock()
    self:SettleWindows(nil)
end

function CC:SnapshotPlaces()
    local places = {}
    local order = self:BlockOrder()
    for _, w in ipairs(CC.WINDOWS or {}) do
        local x, y = self.db[w.xKey], self.db[w.yKey]
        if type(x) == "number" and type(y) == "number" then
            local p = { x, y }
            if HomeSlot(w.key) then
                p[3] = 0
                for i, k in ipairs(order) do
                    if k == w.key then p[3] = i end
                end
            end
            places[w.key] = p
        end
    end
    places.block = { tonumber(self.db.blockX) or CC.DEFAULTS.blockX, tonumber(self.db.blockY) or CC.DEFAULTS.blockY }
    return places
end

-- Put windows where a places table says (only the windows it names), moving the live frames too.
function CC:ApplyPlaces(places)
    if type(places) ~= "table" then return end
    local rank = {}
    for i, key in ipairs(self:BlockOrder()) do rank[key] = i end
    for _, w in ipairs(CC.WINDOWS or {}) do
        local p = places[w.key]
        if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then
            local x, y = tonumber(p[1]), tonumber(p[2])
            self.db[w.xKey], self.db[w.yKey] = x, y
            if HomeSlot(w.key) then
                local slot = tonumber(p[3])
                if not slot then slot = self:AtStartPlace(w, x, y) and HomeSlot(w.key) or 0 end
                rank[w.key] = slot > 0 and slot or nil
            else
                local f = self[w.frame]
                if f then
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
                end
            end
        end
    end
    local order = {}
    for _, key in ipairs(CC.BLOCK_KEYS) do
        if rank[key] then order[#order + 1] = key end
    end
    table.sort(order, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        return HomeSlot(a) < HomeSlot(b)
    end)
    self.db.blockOrder = order
    local b = places.block
    if type(b) == "table" and tonumber(b[1]) and tonumber(b[2]) then
        self.db.blockX, self.db.blockY = tonumber(b[1]), tonumber(b[2])
    end
    self:LayoutBlock()
    self:LayoutColumn()
end

function CC:SnapshotSetup(skipPlaces)
    local db = self.db
    local setup = { disabled = {}, custom = {}, alerts = {}, places = skipPlaces and {} or self:SnapshotPlaces() }
    for id, off in pairs(db.disabledSpells or {}) do
        if off then setup.disabled[#setup.disabled + 1] = tonumber(id) end
    end
    table.sort(setup.disabled)
    for idStr, c in pairs(db.customSpells or {}) do
        local id = tonumber(idStr)
        if id and type(c) == "table" then
            setup.custom[id] = { name = c.name, duration = c.duration, icon = c.icon }
        end
    end
    for key, a in pairs(db.alerts or {}) do
        local id = tonumber(key)
        if id and type(a) == "table" then
            setup.alerts[id] = { sound = a.sound, flash = a.flash, midscreen = a.midscreen, warn = a.warn }
        end
    end
    return setup
end

local function SoundText(s)
    if s == true then return "t" elseif not s then return "f" end
    return tostring(s)
end

local function SoundValue(t)
    if t == "t" then return true elseif t == "f" or t == "" then return false end
    return tonumber(t) or t
end

function CC:EncodeSetup(setup, name)
    local parts = { SETUP_FORMAT, "k=setup", "n=" .. Quote(name or "") }
    local ids = {}
    for _, id in ipairs(setup.disabled or {}) do ids[#ids + 1] = tostring(id) end
    if #ids > 0 then parts[#parts + 1] = "d=" .. table.concat(ids, ",") end
    for _, id in ipairs(SortedKeys(setup.custom or {})) do
        local c = setup.custom[id]
        parts[#parts + 1] = string.format("c=%d,%s,%d,%d", id, Quote(c.name or ""), c.duration or 0, tonumber(c.icon) or 134400)
    end
    for _, id in ipairs(SortedKeys(setup.alerts or {})) do
        local a = setup.alerts[id]
        parts[#parts + 1] = string.format("a=%d,%s,%s,%s,%d", id, Quote(SoundText(a.sound)),
            a.flash == false and "0" or "1", a.midscreen and "1" or "0", tonumber(a.warn) or 0)
    end
    for _, key in ipairs(SortedKeys(setup.places or {})) do
        local p = setup.places[key]
        local slot = tonumber(p[3]) and string.format(",%d", p[3]) or ""   -- a joined window's slot, 0 = loose
        parts[#parts + 1] = string.format("w=%s,%d,%d", Quote(key), math.floor(p[1] + 0.5), math.floor(p[2] + 0.5)) .. slot
    end
    return table.concat(parts, ";")
end

-- setup, name from text, or nil when it isn't a setup of this format. Numbers are checked
-- and bounded: the text may come from another player.
function CC:DecodeSetup(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local setup, name, kind, version = { disabled = {}, custom = {}, alerts = {}, places = {} }, "", nil, nil
    local rows = 0
    for item in text:gmatch("[^;]+") do
        if not version then
            version = item
            if version ~= SETUP_FORMAT then return nil end
        else
            local key, value = item:match("^(%a+)=(.*)$")
            rows = rows + 1
            if rows > 600 then return nil end
            if key == "k" then
                kind = value
            elseif key == "n" then
                name = Unquote(value):sub(1, 40)
            elseif key == "d" then
                for _, v in ipairs(Split(value)) do
                    local id = tonumber(v)
                    if id and id > 0 then setup.disabled[#setup.disabled + 1] = id end
                end
            elseif key == "c" then
                local f = Split(value)
                local id, dur = tonumber(f[1]), tonumber(f[3])
                if id and id > 0 and dur and dur > 0 and dur <= 86400 then
                    setup.custom[id] = { name = (f[2] or ""):sub(1, 60), duration = dur, icon = tonumber(f[4]) or 134400 }
                end
            elseif key == "a" then
                local f = Split(value)
                local id = tonumber(f[1])
                if id and id > 0 then
                    setup.alerts[id] = { sound = SoundValue(f[2] or "f"), flash = f[3] ~= "0", midscreen = f[4] == "1",
                        warn = math.max(0, math.min(600, tonumber(f[5]) or 0)) }
                end
            elseif key == "w" then
                local f = Split(value)
                local x, y = tonumber(f[2]), tonumber(f[3])
                if f[1] and x and y and math.abs(x) <= 4000 and math.abs(y) <= 4000 then
                    local slot = tonumber(f[4])
                    if slot and (slot < 0 or slot > #CC.BLOCK_KEYS or slot ~= math.floor(slot)) then slot = nil end
                    setup.places[f[1]] = { x, y, slot }
                end
            end
        end
    end
    if kind ~= "setup" then return nil end
    return setup, name
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- What applying a setup would change, one plain line each (the import and officer dialogs show these).
function CC:DescribeSetup(setup)
    local now = self:SnapshotSetup()
    local lines = {}
    local function Differs(a, b)
        local d = 0
        for k in pairs(a) do if not b[k] then d = d + 1 end end
        for k in pairs(b) do if not a[k] then d = d + 1 end end
        return d
    end
    local offNow, offNew = {}, {}
    for _, id in ipairs(now.disabled) do offNow[id] = true end
    for _, id in ipairs(setup.disabled) do offNew[id] = true end
    local d = Differs(offNow, offNew)
    if d > 0 then lines[#lines + 1] = string.format(d == 1 and L["%d default spell ticked or unticked (%d unticked afterwards)"] or L["%d default spells ticked or unticked (%d unticked afterwards)"], d, Count(offNew)) end
    d = Differs(now.custom, setup.custom)
    if d > 0 then lines[#lines + 1] = string.format(d == 1 and L["%d custom spell added or removed (%d afterwards)"] or L["%d custom spells added or removed (%d afterwards)"], d, Count(setup.custom)) end
    d = Differs(now.alerts, setup.alerts)
    if d > 0 then lines[#lines + 1] = string.format(d == 1 and L["%d ready alert added or removed (%d afterwards)"] or L["%d ready alerts added or removed (%d afterwards)"], d, Count(setup.alerts)) end
    local moved = 0
    for key, p in pairs(setup.places) do
        local q = now.places[key]
        if not q or q[1] ~= p[1] or q[2] ~= p[2] or (p[3] ~= nil and q[3] ~= p[3]) then moved = moved + 1 end
    end
    if moved > 0 then lines[#lines + 1] = string.format(moved == 1 and L["%d window moved"] or L["%d windows moved"], moved) end
    if #lines == 0 then lines[1] = L["Nothing changes: this is what you have now."] end
    return lines
end

-- Make the live settings match a setup. opts.noUndo skips keeping what was replaced.
function CC:ApplySetup(setup, opts)
    opts = opts or {}
    local db = self.db
    if not opts.noUndo then db.setupUndo = self:SnapshotSetup() end
    db.disabledSpells = {}
    for _, id in ipairs(setup.disabled or {}) do db.disabledSpells[id] = true end
    for idStr in pairs(db.customSpells or {}) do
        local id = tonumber(idStr)
        if id and not (setup.custom or {})[id] then self:RemoveCustomSpell(id) end
    end
    for id, c in pairs(setup.custom or {}) do
        db.customSpells[tostring(id)] = { name = c.name, duration = c.duration, icon = c.icon }
    end
    self:LoadCustomSpells()
    db.alerts = {}
    for id, a in pairs(setup.alerts or {}) do
        db.alerts[id] = { sound = a.sound, flash = a.flash, midscreen = a.midscreen, warn = a.warn }
    end
    local places = setup.places
    local own = db.charPlaces and db.charPlaces[self:FullName("player")]
    self:ApplyPlaces(own or places)
    db.showPreset = "custom"
    self:RefreshView("RefreshRows")
    if self.RefreshDefaultSpellList then self:RefreshDefaultSpellList() end
    if self.RefreshSpellList then self:RefreshSpellList() end
end

function CC:UndoSetup()
    local undo = self.db.setupUndo
    if not undo then return false end
    self.db.setupUndo = nil
    self:ApplySetup(undo, { noUndo = true })
    return true
end

function CC:ExportSetup(name)
    return self:EncodeSetup(self:SnapshotSetup(), name)
end

-- A setup in text, applied at once (the dialogs ask first, then call this).
function CC:ImportSetup(text)
    local setup = self:DecodeSetup(text)
    if not setup then return false end
    self:ApplySetup(setup)
    return true
end

-------------------------------------------------------------------------------
-- Profiles, as in every Ace addon: db.profiles[name] = the settings below plus `places`;
-- db.charProfile[Name-Realm] = the profile that character follows. A profile named Default always
-- exists and every character follows it until it picks another. The live settings stay where the
-- rest of the addon reads them (CC.db); the profile in use is written back at logout and when you
-- switch, and put in place at login and on a switch.
-- Not in a profile (they are about your account or guild, or are wire and bookkeeping state): guild
-- sharing, who setups are accepted from, "Never" marks, the undo, the profiles themselves,
-- /cdc consumable entries, the minimap button, the panel's open tab and the party and raid pull log.
-------------------------------------------------------------------------------

local DEFAULT_PROFILE = "Default"

CC.PROFILE_KEYS = {
    -- what is tracked, custom spells, ready alerts
    "disabledSpells", "customSpells", "alerts", "showPreset", "spellGroupBy",
    -- the panel
    "showReady", "panelStyle", "alpha", "scale", "minDuration",
    -- when the windows show, lighter mode, locks, which windows are on
    "showWindows", "lighterMode", "locked", "essentialsLocked", "laneLocked", "deadListLocked",
    "externalsLocked", "manaLocked", "burstLocked", "essentialsEnabled", "laneEnabled", "deadListEnabled",
    "externalsEnabled", "manaEnabled", "burstEnabled", "essentialsScale", "laneScale", "showOnCDTL3",
    -- Bars & Lists
    "essentialsBuffCounts", "essentialsBuffAim", "essentialsDefensives", "burstSpells", "rezSkip",
    -- Plans, rotation order, teams
    "plans", "activePlan", "planLead", "planBarX", "planBarY", "teams", "rotations",
    -- window places for a party and a raid, pulls and posting, key starts
    "layouts", "lastPullOffer", "postSpells", "resetOnNewRun",
}

local function CopyValue(v)
    if type(v) == "table" then return CopyTable(v) end
    return v
end

-- The settings a profile holds, as they are now. Places are left out when this character keeps its own.
function CC:SnapshotProfile(skipPlaces)
    local snap = { places = skipPlaces and {} or self:SnapshotPlaces() }
    for _, k in ipairs(CC.PROFILE_KEYS) do
        if self.db[k] ~= nil then snap[k] = CopyValue(self.db[k]) end
    end
    return snap
end

-- What a new or reset profile holds: the addon's own defaults, windows where they start.
function CC:DefaultProfile()
    local snap = { places = {} }
    for _, k in ipairs(CC.PROFILE_KEYS) do
        if CC.DEFAULTS[k] ~= nil then snap[k] = CopyValue(CC.DEFAULTS[k]) end
    end
    for _, w in ipairs(CC.WINDOWS or {}) do
        local x, y = CC.DEFAULTS[w.xKey], CC.DEFAULTS[w.yKey]
        if x and y then snap.places[w.key] = { x, y, HomeSlot(w.key) } end
    end
    snap.places.block = { CC.DEFAULTS.blockX, CC.DEFAULTS.blockY }
    return snap
end

-- Make the live settings what a profile holds (a setting it lacks goes back to its default).
function CC:ApplyProfile(snap)
    local db = self.db
    local defaults = self:DefaultProfile()
    -- custom spells first: the ones the profile doesn't have leave the spell list
    local want = type(snap.customSpells) == "table" and snap.customSpells or {}
    for idStr in pairs(db.customSpells or {}) do
        if not want[idStr] then self:RemoveCustomSpell(idStr) end
    end
    local showOnCDTL3 = db.showOnCDTL3
    for _, k in ipairs(CC.PROFILE_KEYS) do
        local v = snap[k]
        if v == nil then v = defaults[k] end
        db[k] = CopyValue(v)
    end
    self:LoadCustomSpells()
    local own = db.charPlaces and db.charPlaces[self:FullName("player")]
    self:ApplyPlaces(own or snap.places or defaults.places)
    if self.frame then
        self.frame:SetScale(db.scale or 1.0)
        self.frame:SetAlpha(db.alpha or 0.9)
    end
    self:LayoutBlock()   -- the panel's scale may have changed under the block's place
    if db.showOnCDTL3 ~= showOnCDTL3 and self.SetShowOnCDTL3 then self:SetShowOnCDTL3(db.showOnCDTL3) end
    for _, update in ipairs({ "UpdateLock", "UpdateEssentialsLock", "UpdateLaneLock" }) do
        if self[update] then self:RefreshView(update) end
    end
    for _, w in ipairs(CC.WINDOWS or {}) do
        if w.refresh then self:RefreshView(w.refresh) end
    end
    self:RefreshView("RefreshRows")
    self:RefreshAllViews()
    if self.RefreshOptions then self:RefreshOptions() end
end

local function Clean(name)
    return type(name) == "string" and (name:gsub("^%s+", ""):gsub("%s+$", "")) or ""
end

-- The default profile exists from the first login. It starts as what is set now (a character that
-- follows another profile leaves the live settings to that one, so Default starts as the defaults).
function CC:EnsureDefaultProfile()
    self.db.profiles = self.db.profiles or {}
    if not self.db.profiles[DEFAULT_PROFILE] then
        local me = self:FullName("player")
        local follows = self.db.charProfile and self.db.charProfile[me]
        local mine = not follows or follows == DEFAULT_PROFILE or not self.db.profiles[follows]
        self.db.profiles[DEFAULT_PROFILE] = mine and self:SnapshotProfile() or self:DefaultProfile()
    end
end

-- Default first, then the rest in order.
function CC:ProfileNames()
    self:EnsureDefaultProfile()
    local names = {}
    for name in pairs(self.db.profiles) do
        if name ~= DEFAULT_PROFILE then names[#names + 1] = name end
    end
    table.sort(names)
    table.insert(names, 1, DEFAULT_PROFILE)
    return names
end

-- The profile this character follows: the one it picked, else Default.
function CC:CurrentProfile()
    self:EnsureDefaultProfile()
    local name = self.db.charProfile and self.db.charProfile[self:FullName("player")]
    if name and self.db.profiles[name] then return name end
    return DEFAULT_PROFILE
end

-- This character keeps its own window places whatever profile it follows.
function CC:KeepsOwnPlaces()
    local own = self.db.charPlaces
    return own and own[self:FullName("player")] ~= nil or false
end

function CC:SetKeepOwnPlaces(on)
    self.db.charPlaces = self.db.charPlaces or {}
    self.db.charPlaces[self:FullName("player")] = on and self:SnapshotPlaces() or nil
end

-- The profile in use keeps what was changed since (never before this character's own profile went in:
-- the live settings may be another character's).
function CC:SaveCurrentProfile()
    if not self.profileApplied then return end
    local name = self:CurrentProfile()
    local keep = self:KeepsOwnPlaces()
    local snap = self:SnapshotProfile(keep)
    if keep then snap.places = self.db.profiles[name].places or {} end   -- the profile's own places stay
    self.db.profiles[name] = snap
    if keep then self.db.charPlaces[self:FullName("player")] = self:SnapshotPlaces() end
end

-- At login: the profile this character follows is put in place.
function CC:ApplyCharacterProfile()
    self:EnsureDefaultProfile()
    self:ApplyProfile(self.db.profiles[self:CurrentProfile()])
    self.profileApplied = true
end

-- Change to another profile (the one in use is kept first).
function CC:UseProfile(name)
    if not (self.db.profiles and self.db.profiles[name]) then return false end
    if name == self:CurrentProfile() then return true end
    self:SaveCurrentProfile()
    self.db.charProfile = self.db.charProfile or {}
    self.db.charProfile[self:FullName("player")] = name
    self:ApplyProfile(self.db.profiles[name])
    return true
end

-- A new profile with the default settings, and this character switches to it.
-- Returns false (and says why as a second value) for an empty name or one already there.
function CC:NewProfile(name)
    name = Clean(name)
    self:EnsureDefaultProfile()
    if name == "" then return false, "empty" end
    if self.db.profiles[name] then return false, "exists" end
    self:SaveCurrentProfile()
    self.db.profiles[name] = self:DefaultProfile()
    return self:UseProfile(name)
end

-- The settings of another profile go into the one in use.
function CC:CopyProfile(from)
    local src = self.db.profiles and self.db.profiles[from]
    if not src or from == self:CurrentProfile() then return false end
    self:ApplyProfile(src)
    return true
end

-- The profile in use goes back to the addon's defaults.
function CC:ResetProfile()
    self:ApplyProfile(self:DefaultProfile())
    return true
end

-- Never the one in use and never Default.
function CC:DeleteProfile(name)
    if not (self.db.profiles and self.db.profiles[name]) then return false end
    if name == DEFAULT_PROFILE or name == self:CurrentProfile() then return false end
    self.db.profiles[name] = nil
    for who, pn in pairs(self.db.charProfile or {}) do
        if pn == name then self.db.charProfile[who] = nil end
    end
    return true
end

-------------------------------------------------------------------------------
-- The copy box: a box of text, selected, to copy out of (and, for import, to paste into)
-------------------------------------------------------------------------------

function CC:ShowCopyBox(title, text, onAccept, acceptLabel)
    local f = self.copyBox
    if not f then
        f = CreateFrame("Frame", "CCCopyBox", UIParent, CC.BackdropTemplate)
        f:SetSize(440, 296)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 20, insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
        tinsert(UISpecialFrames, "CCCopyBox")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetSize(390, 160)
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -40)
        f.edit = CreateFrame("EditBox", nil, scroll)
        f.edit:SetMultiLine(true)
        f.edit:SetAutoFocus(false)
        f.edit:SetFontObject(GameFontHighlightSmall)
        f.edit:SetWidth(380)
        f.edit:SetScript("OnEscapePressed", function(widget) widget:ClearFocus(); f:Hide() end)
        scroll:SetScrollChild(f.edit)
        f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.note:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -8)
        f.note:SetWidth(390)
        f.note:SetJustifyH("LEFT")
        f.accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.accept:SetSize(110, 22)
        f.accept:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
        f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.close:SetSize(80, 22)
        f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
        f.close:SetText(L["Close"])
        f.close:SetScript("OnClick", function() f:Hide() end)
        self.copyBox = f
    end
    f.title:SetText(title)
    f.edit:SetText(text or "")
    f.onAccept = onAccept
    f.accept:SetShown(onAccept ~= nil)
    f.accept:SetText(acceptLabel or L["Import"])
    f.accept:SetScript("OnClick", function()
        if f.onAccept then f.onAccept(f.edit:GetText()) end
    end)
    f.note:SetText("")
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    return f
end

-- Import: paste text, then see what it would change and confirm.
function CC:ShowImportBox()
    local box
    box = self:ShowCopyBox(L["Import a setup: paste it here"], "", function(text)
        local setup = CC:DecodeSetup(text)
        if not setup then
            box.note:SetText("|cFFFF4444" .. L["That isn't a CooldownCollaborator setup."] .. "|r")
            return
        end
        if box.pending ~= text then
            box.pending = text
            box.note:SetText(string.format(L["It will change:\n- %s\nClick Import again to do it."], table.concat(CC:DescribeSetup(setup), "\n- ")))
            return
        end
        CC:ApplySetup(setup)
        box.pending = nil
        box:Hide()
        print("|cFF54a3ffCDC|r " .. L["Setup imported. Settings > Profiles can undo it."])
    end, L["Import"])
    box.pending = nil
    return box
end

-------------------------------------------------------------------------------
-- Officer setups (P42): the O kind on the guild channel. Sent whatever the guild sharing setting
-- says (an officer's act), read always; a member gets a dialog and decides.
-------------------------------------------------------------------------------

function CC:IsOfficer()
    if not IsInGuild or not IsInGuild() then return false end
    local ok, yes = pcall(function()
        if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then return C_GuildInfo.CanEditOfficerNote() end
        ---@diagnostic disable-next-line: undefined-global
        return CanEditOfficerNote and CanEditOfficerNote() or false
    end)
    return ok and yes == true
end

function CC:SendOfficerSetup()
    if not self:IsOfficer() then
        print("|cFF54a3ffCDC|r " .. L["Only a guild officer can send a setup to the guild."])
        return false
    end
    local data = self:ExportSetup("Guild setup")
    local parts = math.ceil(#data / CHUNK)
    if parts > MAX_PARTS then
        print("|cFF54a3ffCDC|r " .. L["That setup is too long to send."])
        return false
    end
    local id = "s" .. tostring(time())
    for i = 1, parts do
        self:QueueSend(self.PREFIX, string.format("O:2:%s:%d/%d:%s", id, i, parts, data:sub((i - 1) * CHUNK + 1, i * CHUNK)),
            { kind = "setup", channel = "GUILD", always = true })
    end
    return true
end

-- Called by Comms.lua when the last part of an O message is in.
function CC:OnOfficerSetup(owner, id)
    local payload = self.payloads and self.payloads.O and self.payloads.O[owner] and self.payloads.O[owner][id]
    if not payload then return end
    if self.db.setupNever and self.db.setupNever[owner] then return end
    if not (self:GuildSyncOn() and self:AcceptsSetupsFrom(owner)) then return end
    -- one dialog at a time, and one per sender per 10 minutes: what was read is what Accept applies
    if self.pendingSetup then return end
    self.setupShownAt = self.setupShownAt or {}
    local last = self.setupShownAt[owner]
    if last and GetTime() - last < 600 then return end
    local setup = self:DecodeSetup(payload.data)
    if not setup then return end
    self.setupShownAt[owner] = GetTime()
    self.pendingSetup = { owner = owner, setup = setup, id = id }
    self:ShowSetupDialog()
end

-- The guild rank name of a guildmate (Name-Realm), from the guild roster, or nil when the roster
-- doesn't have them (yet).
function CC:GuildRankOf(fullName)
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
    local short = self:ShortName(fullName)
    local ok, rank = pcall(function()
        for i = 1, GetNumGuildMembers() do
            local name, rankName = GetGuildRosterInfo(i)
            if name and (name == fullName or self:NormalizeSender(name) == fullName or self:ShortName(self:NormalizeSender(name) or name) == short) then return rankName end
        end
    end)
    return ok and rank or nil
end

-- The guild rank index (0 = guild master) of a guildmate, from the guild roster, or nil.
function CC:GuildRankIndexOf(fullName)
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return nil end
    local short = self:ShortName(fullName)
    local ok, index = pcall(function()
        for i = 1, GetNumGuildMembers() do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name and (name == fullName or self:NormalizeSender(name) == fullName or self:ShortName(self:NormalizeSender(name) or name) == short) then return rankIndex end
        end
    end)
    return ok and index or nil
end

-- May a setup from this guildmate reach the dialog? Per the "Accept setups from" setting: the guild
-- master and the next rank (rank index 0 or 1) by default, any rank, or nobody.
function CC:AcceptsSetupsFrom(owner)
    local mode = self.db.setupFrom or "officers"
    if mode == "nobody" then return false end
    if mode == "any" then return true end
    local index = self:GuildRankIndexOf(owner)
    return index == 0 or index == 1
end

function CC:ShowSetupDialog()
    local pending = self.pendingSetup
    if not pending then return end
    local f = self.setupDialog
    if not f then
        f = CreateFrame("Frame", "CCSetupDialog", UIParent, CC.BackdropTemplate)
        f:SetSize(380, 190)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 20, insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
        f.text:SetWidth(350)
        f.text:SetJustifyH("LEFT")
        local function Button(x, label, onClick)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(100, 22)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 14)
            b:SetText(label)
            b:SetScript("OnClick", onClick)
        end
        Button(16, L["Accept"], function() CC:AnswerSetup("accept") end)
        Button(140, L["Not now"], function() CC:AnswerSetup("later") end)
        Button(264, L["Never"], function() CC:AnswerSetup("never") end)
        self.setupDialog = f
    end
    local rank = self:GuildRankOf(pending.owner)
    pending.rank = rank
    f.text:SetText(string.format(L["%s%s sent a setup to the guild.\nIt will change:\n- %s\n\nAccept it, not now, or never from this person?"],
        self:ShortName(pending.owner), rank and (" (" .. rank .. ")") or "",
        table.concat(self:DescribeSetup(pending.setup), "\n- ")))
    f:Show()
end

function CC:AnswerSetup(answer)
    local pending = self.pendingSetup
    self.pendingSetup = nil
    if self.setupDialog then self.setupDialog:Hide() end
    if not pending then return end
    if answer == "accept" then
        self:ApplySetup(pending.setup)
        print("|cFF54a3ffCDC|r " .. string.format(L["Setup from %s accepted. Settings > Profiles can undo it."], self:ShortName(pending.owner)))
    elseif answer == "never" then
        self.db.setupNever = self.db.setupNever or {}
        self.db.setupNever[pending.owner] = true
    end
end

-------------------------------------------------------------------------------
-- Party and raid layouts (P21)
-------------------------------------------------------------------------------

function CC:GroupKind()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return nil
end

-- When the group type changes: the places we had go under the old type, and the new type's saved
-- places (if it has some) come back.
function CC:CheckLayoutChange()
    local kind, prev = self:GroupKind(), self.layoutKind
    if kind == prev then return end
    self.db.layouts = self.db.layouts or {}
    if prev then self.db.layouts[prev] = self:SnapshotPlaces() end
    self.layoutKind = kind
    if kind and self.db.layouts[kind] then self:ApplyPlaces(self.db.layouts[kind]) end
end

function CC:ResetAllWindows()
    self.db.blockOrder = {}
    self.db.blockX, self.db.blockY = CC.DEFAULTS.blockX, CC.DEFAULTS.blockY
    for _, w in ipairs(CC.WINDOWS or {}) do self:ResetWindow(w) end
    self.db.layouts = {}
end

-------------------------------------------------------------------------------
-- The last pull (P33)
-------------------------------------------------------------------------------

CC.pullLog = CC.pullLog or { active = false, entries = {} }
CC.lastPull = CC.lastPull or nil

function CC:BeginPull()
    self.pullLog = { active = true, start = GetTime(), entries = {} }
end

function CC:EndPull(boss, success)
    local p = self.pullLog
    if not p or not p.active then return end
    p.active, p.boss, p.success, p.length = false, boss or p.boss, success, GetTime() - p.start
    self.lastPull = p
end

function CC:NotePullUse(owner, spellID)
    local p = self.pullLog
    if not p or not p.active or not owner then return end
    local data = CC.SpellData[spellID]
    if not data or data.consumable then return end
    local t = GetTime() - p.start
    for _, e in ipairs(p.entries) do
        if e.owner == owner and e.spellID == spellID and math.abs(e.t - t) < 5 then return end
    end
    p.entries[#p.entries + 1] = { t = t, owner = owner, spellID = spellID }
end

-- "3 tracked cooldowns used"
local function UsedText(n)
    return string.format(n == 1 and L["%d tracked cooldown used"] or L["%d tracked cooldowns used"], n)
end

function CC:PullLines()
    local p = self.lastPull
    if not p then return {} end
    local lines = {}
    for _, e in ipairs(p.entries) do
        local data = CC.SpellData[e.spellID]
        lines[#lines + 1] = string.format("%s  %s  %s", CC:LookClock(math.floor(e.t)), CC:ShortName(e.owner), data and data.name or tostring(e.spellID))
    end
    return lines
end

function CC:PrintLastPull()
    local p = self.lastPull
    if not p then
        print("|cFF54a3ffCDC|r " .. L["No pull logged yet."])
        return
    end
    local lines = self:PullLines()
    local clock = CC:LookClock(math.floor(p.length or 0))
    if p.boss then
        print("|cFF54a3ffCDC|r " .. string.format(L["Last pull (%s): %s, %s."], p.boss, clock, UsedText(#lines)))
    else
        print("|cFF54a3ffCDC|r " .. string.format(L["Last pull: %s, %s."], clock, UsedText(#lines)))
    end
    for _, l in ipairs(lines) do print("    " .. l) end
end

-------------------------------------------------------------------------------
-- /cdc post (P38): what's ready for the spells you pick, to the group's chat
-------------------------------------------------------------------------------

-- The spells to post: the saved picks, or Battle Rez and Bloodlust spells when none are saved.
function CC:PostSpellIDs()
    local ids = {}
    local picked = self.db.postSpells
    if type(picked) == "table" and next(picked) then
        for id, on in pairs(picked) do if on and CC.SpellData[tonumber(id)] then ids[#ids + 1] = tonumber(id) end end
    else
        for id, data in pairs(CC.SpellData) do
            if (data.kind == "rez" or data.kind == "lust") and not data.consumable then ids[#ids + 1] = id end
        end
    end
    table.sort(ids, function(a, b) return (CC.SpellData[a].name or "") < (CC.SpellData[b].name or "") end)
    return ids
end

-- One line per spell somebody in the group has: "Name ready" or "Name 2:10".
function CC:PostLines()
    local lines = {}
    for _, id in ipairs(self:PostSpellIDs()) do
        local data = CC.SpellData[id]
        local who = {}
        local empty = data.kind == "rez" and self:RezPool() == 0   -- no Battle Rez charges left
        for name in pairs(self:GetActiveGroupNames()) do
            if self:MemberHasSpell(name, id) then
                local rem = self:GetRemaining(name, id)
                who[#who + 1] = self:ShortName(name) .. " " .. ((rem and rem > 0) and self:LookClock(math.ceil(rem)) or (empty and L["no charge"] or L["ready"]))
            end
        end
        table.sort(who)
        if #who > 0 then lines[#lines + 1] = (data.name .. ": " .. table.concat(who, ", ")):sub(1, 250) end
    end
    return lines
end

function CC:PostReady()
    local channel = self:GroupChannel()
    if not channel then
        print("|cFF54a3ffCDC|r " .. L["Join a group first."])
        return false
    end
    local lines = self:PostLines()
    if #lines == 0 then
        print("|cFF54a3ffCDC|r " .. L["Nothing to post for the spells picked."])
        return false
    end
    ---@diagnostic disable-next-line: deprecated
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, l in ipairs(lines) do pcall(send, l, channel) end
    return true
end

-------------------------------------------------------------------------------
-- A new key (P45)
-------------------------------------------------------------------------------

-- A key starts: players who left are dropped, and after a short wait we ask for everyone's state, so
-- each owner's own client reports its real cooldowns (a cooldown the game itself resets is announced by
-- that owner's ready-now poll). Nothing is guessed about what the game resets.
function CC:OnKeyStart()
    self:PruneState()
    self:RefreshAllViews()
    self:SendStateRequest(2 + math.random() * 2)
end

-------------------------------------------------------------------------------
-- /cdc report (P19): a copy box with what to paste into a new issue
-------------------------------------------------------------------------------

CC.sendErrors = CC.sendErrors or {}

local CLIENT_NAME = { retail = "Retail", mists = "MoP Classic", tbc = "TBC Anniversary", era = "Classic Era", forever = "WoW: Forever" }
local ROLE_NAME = { everything = "Everything", simple = "Basics", healer = "Healer", tank = "Tank", dps = "DPS", custom = "My own" }

-- The role and how many spells were ticked or unticked against it, in English words.
function CC:ReportTracking()
    local role = self.db.showPreset or "everything"
    local preset = CC.PRESETS and CC.PRESETS[role]
    local plus, minus = 0, 0
    for id, data in pairs(CC.SpellData) do
        if not data.custom and not data.consumable then
            -- what the role alone would show (a spell with no kind stays as it was, so it never counts)
            local wanted = true
            if preset and preset.kinds and data.kind and not preset.kinds[data.kind] then wanted = false end
            local on = not (self.db.disabledSpells and self.db.disabledSpells[id])
            if data.kind or not preset then
                if on and not wanted then plus = plus + 1 elseif wanted and not on then minus = minus + 1 end
            end
        end
    end
    local text = ROLE_NAME[role] or tostring(role)
    if plus == 0 and minus == 0 then return text .. ", no spells changed" end
    local parts = {}
    if plus > 0 then parts[#parts + 1] = "plus " .. plus end
    if minus > 0 then parts[#parts + 1] = "minus " .. minus end
    return text .. ", " .. table.concat(parts, " and ") .. " spells you changed"
end

-- The report body: plain sentences for the developer, so it stays in English.
function CC:ReportText()
    -- debug begin: read by the developer, not the player
    local lines = { string.format("CooldownCollaborator %s on %s", self.version, CLIENT_NAME[self:ClientTag()] or tostring(self:ClientTag())) }
    local kind = self:GroupKind()
    lines[#lines + 1] = kind and string.format("In a %s of %d.", kind, GetNumGroupMembers()) or "Not in a group."
    local heard, me = {}, self:FullName("player")
    for name, p in pairs(self.peers or {}) do
        if name ~= me then heard[#heard + 1] = string.format("%s %s", self:ShortName(name), tostring(p.version or "?")) end
    end
    table.sort(heard)
    lines[#lines + 1] = #heard > 0 and ("Heard from: " .. table.concat(heard, ", ")) or "Heard from nobody."
    lines[#lines + 1] = "Tracking: " .. self:ReportTracking()
    local errs = {}
    for i = math.max(1, #self.sendErrors - 9), #self.sendErrors do errs[#errs + 1] = self.sendErrors[i] end
    lines[#lines + 1] = "Messages the game refused lately: " .. (#errs > 0 and table.concat(errs, ", ") or "none")
    -- debug end
    return table.concat(lines, "\n")
end

-- The copy box with the report; /cdc report opens it.
function CC:ShowReport()
    local box = self:ShowCopyBox(L["Report a problem"], self:ReportText())
    box.note:SetText(L["Copy this (Ctrl+C) and paste it into a new issue at https://github.com/Nelnamara/CooldownCollaborator/issues, with what you were doing."])
    return box
end

-- Comms.lua calls this when the game refuses a send.
function CC:NoteSendError(result)
    local list = self.sendErrors
    list[#list + 1] = string.format("%s at %s", tostring(result), self:LookClock(math.floor(GetTime())))
    while #list > 30 do table.remove(list, 1) end
end

-------------------------------------------------------------------------------
-- The public feed (P34): CC.API, documented in docs/API.md
-------------------------------------------------------------------------------

local API = { version = 1 }
CC.API = API
_G.CooldownCollaboratorAPI = API   -- how other addons reach it
local callbacks = { start = {}, ready = {}, ["end"] = {} }
local running = {}   -- ["Name\tspellID"] = when we told about it, while it is running

function API.RegisterCallback(owner, event, fn)
    if not callbacks[event] or owner == nil or type(fn) ~= "function" then return false end
    callbacks[event][owner] = fn
    return true
end

function API.UnregisterCallback(owner, event)
    if callbacks[event] then callbacks[event][owner] = nil end
end

function CC:FireAPI(event, ...)
    for _, fn in pairs(callbacks[event] or {}) do xpcall(fn, geterrorhandler(), ...) end
end

-- Seconds until the player's spell is back, or nil when it is ready (or not tracked for them).
function API.GetCooldown(name, spellID)
    local rem = CC:GetRemaining(name, CC:BaseSpellID(spellID))
    return (rem and rem > 0) and rem or nil
end

-- { { name, class, online, alive, spells = { { spellID, name, ready, remaining }, ... } }, ... }
function API.GetGroup()
    local out = {}
    for name in pairs(CC:GetActiveGroupNames()) do
        local info = CC.roster and CC.roster[name]
        if info then
            local member = { name = name, class = info.class, spells = {} }
            for id, data in pairs(CC.SpellData) do
                if not data.consumable and CC:MemberHasSpell(name, id) then
                    local rem = API.GetCooldown(name, id)
                    member.spells[#member.spells + 1] = { spellID = id, name = data.name, ready = rem == nil, remaining = rem }
                end
            end
            table.sort(member.spells, function(a, b) return a.name < b.name end)
            out[#out + 1] = member
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- One note of a cooldown starting, for the pull log and the feed.
function CC:NoteCooldownStart(owner, spellID)
    local data = CC.SpellData[spellID]
    if not data or data.consumable or not owner then return end
    -- a second report of the same cast within 5 s is the same cast
    local key, now = owner .. "\t" .. spellID, GetTime()
    if running[key] and now - running[key] < 5 then return end
    self:NotePullUse(owner, spellID)
    running[key] = now
    self:FireAPI("start", owner, spellID, data.duration)
end

hooksecurefunc(CC, "RecordCooldown", function(self, unitToken, spellID)
    if unitToken == "player" then self:NoteCooldownStart(self:FullName("player"), self:BaseSpellID(spellID)) end
end)

hooksecurefunc(CC, "RecordCooldownFromComm", function(self, playerName, spellID)
    self:NoteCooldownStart(playerName, self:BaseSpellID(spellID))
end)

-- A cooldown we told about that is back: told once.
function CC:CheckAPIReady()
    for key in pairs(running) do
        local owner, id = key:match("^(.-)\t(%d+)$")
        id = tonumber(id)
        local rem = owner and id and self:GetRemaining(owner, id)
        if not rem or rem <= 0 then
            running[key] = nil
            self:FireAPI("ready", owner, id)
        end
    end
end

C_Timer.NewTicker(1, function() if next(running) then CC:CheckAPIReady() end end)

-------------------------------------------------------------------------------
-- Events for all of the above
-------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END",
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT" }) do
    ev:RegisterEvent(e)
end
-- Retail only; a client without it just doesn't take the registration
pcall(ev.RegisterEvent, ev, "CHALLENGE_MODE_START")

ev:SetScript("OnEvent", function(_, event, ...)
    local db = CC.db
    if not db then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if not CC.pullLog.active then CC:BeginPull() end
    elseif event == "ENCOUNTER_START" then
        if not CC.pullLog.active then CC:BeginPull() end
        local _, name = ...
        CC.pullLog.boss = name
    elseif event == "ENCOUNTER_END" then
        local _, name, _, _, success = ...
        CC:EndPull(name, success == 1)
        CC:FireAPI("end", name, success == 1)
        if db.lastPullOffer and CC.lastPull then
            print("|cFF54a3ffCDC|r " .. string.format(L["%s %s: %s. /cdc lastpull to see them."],
                name or L["Fight"], success == 1 and L["kill"] or L["wipe"], UsedText(#CC.lastPull.entries)))
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if CC.pullLog.active and not CC.inEncounter then
            CC:EndPull(nil, nil)
            CC:FireAPI("end", nil, nil)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        CC:CheckLayoutChange()
    elseif event == "PLAYER_ENTERING_WORLD" then
        CC:CheckLayoutChange()
        CC:LayoutBlock()
    elseif event == "CHALLENGE_MODE_START" then
        if db.resetOnNewRun ~= false then CC:OnKeyStart() end
    elseif event == "PLAYER_LOGOUT" then
        if CC.layoutKind then
            db.layouts = db.layouts or {}
            db.layouts[CC.layoutKind] = CC:SnapshotPlaces()
        end
        CC:SaveCurrentProfile()
    end
end)
