-- Sample windows and the first-run tour.
--
-- Sample (CC:ShowSample(key) / CC:HideSample()): one window shows itself with made-up players and
-- this client's real spells, for a short while, even solo. It is drawn by the window's own refresh,
-- so it looks exactly like the real window. Nothing real is touched: for the length of each refresh
-- the data the windows read (CC.state, CC.roster, CC.peers, the rez charges, the group's names) is
-- swapped for the sample's and put back at once, and a real group event (a cast heard, a roster
-- change, combat) ends the sample, so the two never mix. Nothing is sent: asking for a cooldown,
-- Rez, Call and Ask on a sample only say it is a sample.

local L = CC.L

local SAMPLE_SECONDS = 20

-- window key -> the method that draws it
local REFRESH = {
    main = "RefreshRows", essentials = "RefreshEssentials", lanes = "RefreshLanes", dead = "RefreshDeadList",
    externals = "RefreshExternalsStrip", mana = "RefreshManaStrip", burst = "RefreshBurstLine",
}

-- Made-up players: name, class, role. A class this client has no spell for is left out.
local PEOPLE = {
    { "Sylwen",   "DRUID",       "HEALER" },
    { "Brannock", "PALADIN",     "TANK" },
    { "Mirella",  "PRIEST",      "HEALER" },
    { "Kaelith",  "SHAMAN",      "DAMAGER" },
    { "Ozren",    "WARLOCK",     "DAMAGER" },
    { "Veyra",    "MAGE",        "DAMAGER" },
    { "Thorgrim", "WARRIOR",     "TANK" },
    { "Isolde",   "DEATHKNIGHT", "DAMAGER" },
    { "Calla",    "MONK",        "HEALER" },
    { "Aerion",   "EVOKER",      "DAMAGER" },
}
local REALM = "Sample"

-- Which of a class's spells the sample shows first.
local KIND_ORDER = { rez = 1, lust = 2, external = 3, mana = 4, raid = 5, personal = 6, utility = 7 }

local function ClassSpells(class)
    local ids = {}
    for id, data in pairs(CC.SpellData) do
        if data.class == class and not data.consumable then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local ka, kb = KIND_ORDER[CC.SpellData[a].kind] or 9, KIND_ORDER[CC.SpellData[b].kind] or 9
        if ka ~= kb then return ka < kb end
        return a < b
    end)
    return ids
end

local function ProviderCap(class, id)
    for _, capKey in ipairs(CC.CAPABILITY_ORDER or {}) do
        for _, sid in ipairs((CC.Providers and CC.Providers[capKey] and CC.Providers[capKey][class]) or {}) do
            if sid == id then return capKey end
        end
    end
end

-- The sample's world: the tables the windows read, and who is dead.
function CC:BuildSample()
    local now = GetTime()
    local me = self:FullName("player")
    local d = { state = {}, roster = {}, peers = {}, stones = {}, rotations = {}, names = {}, people = {}, dead = {}, own = {} }
    local owners = {}   -- capability -> how many made-up providers so far
    for _, p in ipairs(PEOPLE) do
        local short, class, role = p[1], p[2], p[3]
        local ids = ClassSpells(class)
        if #ids > 0 then
            local name = short .. "-" .. REALM
            local person = { name = name, class = class, role = role }
            d.people[#d.people + 1] = person
            d.names[name] = true
            d.peers[name] = { version = self.version, client = self:ClientTag(), proto = 2 }
            local caps = {}
            for _, capKey in ipairs(CC.CAPABILITY_ORDER or {}) do
                local list = CC.Providers and CC.Providers[capKey] and CC.Providers[capKey][class]
                if list then caps[capKey] = { unpack(list) } end
            end
            d.roster[name] = { class = class, capabilities = caps }
            local entry = { class = class, spells = {} }
            d.state[name] = entry
            local shown = 0
            for _, id in ipairs(ids) do
                local data = CC.SpellData[id]
                if shown < 2 and self:PanelShowsSpell(id, data) then
                    shown = shown + 1
                    local frac
                    local cap = ProviderCap(class, id)
                    if cap then
                        owners[cap] = (owners[cap] or 0) + 1
                        if owners[cap] == 2 then frac = 0.4 end   -- one is cooling, so a lane has something running
                    elseif data.kind == "mana" then
                        frac = nil   -- a mana spell is ready, so the Mana window has an owner to ask
                    else
                        local pattern = { 0.30, false, 0.65, 0.10 }
                        frac = pattern[(#d.people + shown) % 4 + 1]
                    end
                    entry.spells[id] = frac and (now - data.duration * frac) or (now - data.duration)
                end
            end
        end
    end

    -- the dead, in the leader's order: the first healer and the first tank who bring no rez or lust
    local provider = {}
    for _, capKey in ipairs(CC.CAPABILITY_ORDER or {}) do
        for class in pairs((CC.Providers and CC.Providers[capKey]) or {}) do provider[class] = true end
    end
    for _, role in ipairs({ "HEALER", "TANK" }) do
        for _, person in ipairs(d.people) do
            if person.role == role and not provider[person.class] and not person.dead then
                person.dead = true
                d.dead[#d.dead + 1] = { name = person.name, class = person.class, role = role,
                    diedAt = now - (role == "HEALER" and 14 or 6) }
                break
            end
        end
    end

    -- "you" on the burst line: the first made-up player with big cooldowns of their own
    for _, person in ipairs(d.people) do
        if not d.you then
            local picks = {}
            for _, id in ipairs(ClassSpells(person.class)) do
                local data = CC.SpellData[id]
                if (data.kind == "personal" or data.kind == "raid") and (data.duration or 0) >= 90 and not ProviderCap(person.class, id) then
                    picks[#picks + 1] = id
                end
            end
            if #picks > 0 then
                d.you = person
                local fracs = { false, 0.35, 0.8 }
                for i = 1, math.min(3, #picks) do
                    local data = CC.SpellData[picks[i]]
                    d.own[#d.own + 1] = { spellID = picks[i], name = person.name, class = person.class,
                        usedAt = fracs[i] and (now - data.duration * fracs[i]) or (now - data.duration) }
                end
            end
        end
    end

    -- the raid's rez charges, where the client has a pool (Retail and MoP)
    if (self.tocversion or 0) >= 50000 then
        d.rezCharges = { charges = 1, max = 3, nextAt = now + 90, from = me, heardAt = now }
    end

    -- flask and food counts for the Essentials bar
    local total = #d.people
    local counts = {}
    for key, c in pairs(self.BuffCounts or {}) do
        local have = (key == "flask") and (total - 2) or (key == "food") and (total - 1) or (total - 3)
        counts[key] = { key = key, label = c.label, name = c.name, have = math.max(0, have), missing = {}, unknown = {} }
    end
    d.buffs = { total = total, flask = total - 2, food = total - 1, missingFlask = {}, missingFood = {}, counts = counts }
    return d
end

function CC:IsSampleName(name)
    return self.sample ~= nil and name ~= nil and self.sample.data.names[name] == true
end

-- The sample's own icons for the burst line: { spellID, name, class, remaining }.
function CC:SampleBurstOwn()
    local out = {}
    local data = self.sample and self.sample.data
    if not data then return out end
    local now = GetTime()
    for _, o in ipairs(data.own) do
        local dur = CC.SpellData[o.spellID].duration
        out[#out + 1] = { spellID = o.spellID, name = o.name, class = o.class, remaining = math.max(0, o.usedAt + dur - now) }
    end
    table.sort(out, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.spellID < b.spellID
    end)
    return out
end

-- Run fn with the sample's data in place of the group's (and put the group's back, whatever happens).
local SWAPPED = { "state", "roster", "peers", "stones", "rotations", "rezCharges" }
local METHODS = { "GetActiveGroupNames", "MemberByName", "UnitTokenFor", "CanRequestRez", "GetGroupBuffStatus",
    "WindowsWanted", "PanelTab", "DeadList" }

function CC:WithSample(fn, ...)
    local s = self.sample
    if not s or self.sampling then return fn(...) end
    local d = s.data
    local savedData, savedMethods = {}, {}
    for _, k in ipairs(SWAPPED) do savedData[k] = self[k]; self[k] = d[k] end
    for _, k in ipairs(METHODS) do savedMethods[k] = self[k]; self[k] = s.methods[k] end
    self.sampling = true
    local ok, r1, r2 = pcall(fn, ...)
    self.sampling = nil
    for _, k in ipairs(SWAPPED) do self[k] = savedData[k] end
    for _, k in ipairs(METHODS) do self[k] = savedMethods[k] end
    if not ok then error(r1, 0) end
    return r1, r2
end

local function SampleMethods(d)
    local m = {}
    m.GetActiveGroupNames = function()
        local out = {}
        for name in pairs(d.names) do out[name] = true end
        return out
    end
    m.MemberByName = function(self, given)
        if type(given) ~= "string" then return nil end
        for name in pairs(d.names) do
            if name == given or self:ShortName(name) == given then return name end
        end
    end
    m.UnitTokenFor = function() return nil end
    m.CanRequestRez = function() return true end
    m.GetGroupBuffStatus = function() return d.buffs end
    m.WindowsWanted = function() return true end
    m.PanelTab = function() return "all" end
    m.DeadList = function()
        local list = {}
        for _, e in ipairs(d.dead) do
            list[#list + 1] = { name = e.name, class = e.class, role = e.role, diedAt = e.diedAt }
        end
        return list
    end
    return m
end

local function Say(text)
    print("|cFF54a3ffCDC|r " .. text)
end

function CC:ShowSample(key, seconds)
    local method = REFRESH[key]
    local window
    for _, w in ipairs(CC.WINDOWS) do if w.key == key then window = w end end
    if not (method and window and self[method] and self[window.frame]) then return false end
    if self.sample then self:HideSample() end

    local data = self:BuildSample()
    local s = { key = key, window = window, data = data, methods = SampleMethods(data), method = method,
        wrapped = {}, wasShown = self[window.frame]:IsShown() }
    self.sample = s

    local function wrap(name, make)
        local orig = self[name]
        if not orig then return end
        s.wrapped[name] = orig
        self[name] = make(orig)
    end
    -- the window is drawn from the sample, whoever calls its refresh
    wrap(method, function(orig) return function(me, ...) return me:WithSample(orig, me, ...) end end)
    -- a real event from the group ends it
    wrap("SetRemoteCooldown", function(orig) return function(me, ...) me:HideSample(); return orig(me, ...) end end)
    -- nothing goes to the group or to a player from a sample
    wrap("CallRez", function(orig) return function(me, name, ...)
        if me:IsSampleName(name) then Say(L["That is a sample, so nothing was sent."]) return end
        return orig(me, name, ...)
    end end)
    wrap("RequestRez", function(orig) return function(me, ...)
        if key == "essentials" or key == "dead" then Say(L["That is a sample, so nothing was sent."]) return end
        return orig(me, ...)
    end end)
    wrap("AskForMana", function(orig) return function(me, ...)
        if key == "mana" then Say(L["That is a sample, so nothing was sent."]) return end
        return orig(me, ...)
    end end)
    wrap("AskForCooldown", function(orig) return function(me, info, ...)
        local who = info and (info.name or (info.owners and info.owners[1] and info.owners[1].name))
        if me:IsSampleName(who) then Say(L["That is a sample, so nothing was sent."]) return false end
        return orig(me, info, ...)
    end end)

    self:RefreshView(method)
    local token = s
    C_Timer.After(seconds or SAMPLE_SECONDS, function()
        if CC.sample == token then CC:HideSample() end
    end)
    return true
end

function CC:HideSample()
    local s = self.sample
    if not s then return end
    self.sample = nil
    for name, orig in pairs(s.wrapped) do self[name] = orig end
    local frame = self[s.window.frame]
    if frame and not s.wasShown then frame:Hide() end
    self:RefreshView(s.method)
end

-- A combat start or a roster change in a real group ends it; a cast heard ends it too (SetRemoteCooldown above).
do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if not CC.sample then return end
        if event == "PLAYER_REGEN_DISABLED" or IsInGroup() then CC:HideSample() end
    end)
end

-------------------------------------------------------------------------------
-- The tour: one step for each window that is on, in the window list's order. The window shows (the real
-- one in a group when it is showing, else its sample), gets a gold edge, and a bubble next to it says in
-- one sentence what it is for. The last step offers Lock in place and Open settings. It starts by itself
-- once per account, the first time you are in a group with the windows showing (db.tourDone, not part of
-- a profile), and on demand (Take the tour on Getting Started, /cdc tour). Never in combat: a combat
-- start ends it quietly.
-------------------------------------------------------------------------------

local TOUR_SAMPLE_SECONDS = 600   -- a step's sample stays until the next step or the end
local BUBBLE_W, BUBBLE_GAP = 300, 14
local GOLD = { 1, 0.82, 0 }

local function InCombat()
    return (CC.inCombat or (InCombatLockdown and InCombatLockdown())) and true or false
end

local function TourSteps()
    local steps = {}
    for _, w in ipairs(CC.WINDOWS) do
        if CC:WindowIsOn(w) and CC[w.frame] then steps[#steps + 1] = w end
    end
    return steps
end

-- Is the window up for real: in a group and showing?
local function ShowsForReal(w)
    local frame = CC[w.frame]
    return IsInGroup() and frame and frame:IsShown() and true or false
end

local function FitButton(b, minW)
    local tw = b.GetTextWidth and b:GetTextWidth() or 0
    b:SetSize(math.max(minW or 0, math.ceil(tw or 0) + 24), 22)
end

function CC:BuildTourFrame()
    if self.tourFrame then return self.tourFrame end
    local f = CreateFrame("Frame", "CCTourFrame", UIParent, CC.BackdropTemplate)
    f:SetSize(BUBBLE_W, 120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    f:EnableMouse(true)
    -- Escape closes it, as it closes Settings
    tinsert(UISpecialFrames, "CCTourFrame")
    f:SetScript("OnHide", function() if CC.tour then CC:EndTour() end end)

    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.head:SetWidth(BUBBLE_W - 44)
    f.head:SetJustifyH("LEFT")
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    f.body:SetWidth(BUBBLE_W - 24)
    f.body:SetJustifyH("LEFT")

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    f.close:SetScript("OnClick", function() CC:EndTour() end)

    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetText(L["Next"])
    FitButton(f.next, 70)
    f.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    f.next:SetScript("OnClick", function() CC:TourNext() end)

    f.settings = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.settings:SetText(L["Open settings"])
    FitButton(f.settings, 96)
    f.settings:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    f.settings:SetScript("OnClick", function()
        CC:EndTour()
        if not (CC.optionsFrame and CC.optionsFrame:IsShown()) then CC:OpenOptions() end
    end)
    f.lock = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.lock:SetText(L["Lock in place"])
    FitButton(f.lock, 96)
    f.lock:SetPoint("RIGHT", f.settings, "LEFT", -6, 0)
    f.lock:SetScript("OnClick", function()
        CC:SetWindowsLocked(true)
        CC:EndTour()
    end)

    -- the gold edge round the window it is about
    local edge = CreateFrame("Frame", nil, UIParent)
    edge:SetFrameStrata("DIALOG")
    edge.sides = {}
    for i = 1, 4 do
        local t = edge:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        edge.sides[i] = t
    end
    edge:Hide()
    f.edge = edge

    f:Hide()
    self.tourFrame = f
    return f
end

local function PlaceEdge(edge, target)
    local s = edge.sides
    for _, t in ipairs(s) do t:ClearAllPoints() end
    s[1]:SetPoint("TOPLEFT", target, "TOPLEFT", -3, 3);         s[1]:SetPoint("TOPRIGHT", target, "TOPRIGHT", 3, 3);         s[1]:SetHeight(2)
    s[2]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -3, -3);  s[2]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3, -3);  s[2]:SetHeight(2)
    s[3]:SetPoint("TOPLEFT", target, "TOPLEFT", -3, 3);         s[3]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -3, -3);   s[3]:SetWidth(2)
    s[4]:SetPoint("TOPRIGHT", target, "TOPRIGHT", 3, 3);        s[4]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3, -3);  s[4]:SetWidth(2)
    edge:Show()
end

-- The bubble beside the window, on whichever side has room: right, left, below, above.
local function PlaceBubble(f, target)
    local scale = (target:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local l, r, t, b = target:GetLeft(), target:GetRight(), target:GetTop(), target:GetBottom()
    f:ClearAllPoints()
    if not (l and r and t and b) then
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return "center"
    end
    l, r, t, b = l * scale, r * scale, t * scale, b * scale
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local bh = f:GetHeight()
    if r + BUBBLE_GAP + BUBBLE_W <= sw then
        f:SetPoint("TOPLEFT", target, "TOPRIGHT", BUBBLE_GAP, 0)
        return "right"
    elseif l - BUBBLE_GAP - BUBBLE_W >= 0 then
        f:SetPoint("TOPRIGHT", target, "TOPLEFT", -BUBBLE_GAP, 0)
        return "left"
    elseif b - BUBBLE_GAP - bh >= 0 then
        f:SetPoint("TOP", target, "BOTTOM", 0, -BUBBLE_GAP)
        return "below"
    end
    f:SetPoint("BOTTOM", target, "TOP", 0, BUBBLE_GAP)
    return "above"
end

function CC:TourStep(i)
    local tour = self.tour
    if not tour then return end
    local w = tour.steps[i]
    if not w then return self:EndTour() end
    tour.i = i
    self:HideSample()
    local frame = self[w.frame]
    if not ShowsForReal(w) then self:ShowSample(w.key, TOUR_SAMPLE_SECONDS) end

    local f = self:BuildTourFrame()
    local total = #tour.steps
    local help = CC.WINDOW_HELP[w.key]
    f.head:SetText(string.format(L["%d of %d \194\183 %s"], i, total, w.label))
    f.body:SetText(help and help.line or "")
    local last = i == total
    f.next:SetShown(not last)
    f.lock:SetShown(last)
    f.settings:SetShown(last)
    -- the bubble is as tall as its sentence (13 pixels a line at 7.4 pixels a character is what the font needs, or more)
    local text = help and help.line or ""
    local lines = math.max(1, math.ceil(#text * 7.4 / (BUBBLE_W - 24)))
    f:SetHeight(32 + math.max(f.body:GetStringHeight() or 0, lines * 15) + 12 + 22 + 12)
    f:Show()
    f.edge:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
    PlaceEdge(f.edge, frame)
    PlaceBubble(f, frame)
end

function CC:TourNext()
    local tour = self.tour
    if tour then self:TourStep(tour.i + 1) end
end

function CC:EndTour()
    local tour = self.tour
    if not tour then return end
    self.tour = nil
    if tour.ticker then tour.ticker:Cancel() end
    local f = self.tourFrame
    if f then
        f:Hide()
        f.edge:Hide()
    end
    self:HideSample()
end

-- manual: Take the tour or /cdc tour. Returns true when it started.
function CC:StartTour(manual)
    if self.tour then return false end
    if InCombat() then
        if manual then print("|cFF54a3ffCDC|r " .. L["The tour waits until you are out of combat."]) end
        return false
    end
    local steps = TourSteps()
    if #steps == 0 then
        if manual then print("|cFF54a3ffCDC|r " .. L["Every window is off. Switch one on in Settings, then take the tour."]) end
        return false
    end
    -- Settings would sit over the windows; Open settings at the end brings it back
    if self.optionsFrame and self.optionsFrame:IsShown() then self.optionsFrame:Hide() end
    self.db.tourDone = true
    self.tour = { steps = steps, i = 0 }
    self.tour.ticker = C_Timer.NewTicker(0.5, function()
        local tour = CC.tour
        if not tour then return end
        if InCombat() then CC:EndTour() return end
        local w = tour.steps[tour.i]
        local frame = w and CC[w.frame]
        if not frame then return end
        -- the sample ended (a real event from the group) and the window is not up: draw it again
        if not frame:IsShown() and not CC.sample then CC:ShowSample(w.key, TOUR_SAMPLE_SECONDS) end
        if CC.tourFrame and CC.tourFrame:IsShown() then PlaceBubble(CC.tourFrame, frame) end
    end)
    self:TourStep(1)
    return true
end

-- By itself, once per account: in a group, out of combat, with at least one of the windows showing.
function CC:TryAutoTour()
    if not self.db or self.db.tourDone or self.tour or not IsInGroup() or InCombat() then return end
    if self.optionsFrame and self.optionsFrame:IsShown() then return end
    for _, w in ipairs(TourSteps()) do
        if ShowsForReal(w) then
            self:StartTour(false)
            return
        end
    end
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            CC:EndTour()   -- quietly
        else
            -- the windows open a moment after the roster does
            C_Timer.After(2, function() CC:TryAutoTour() end)
        end
    end)
end
