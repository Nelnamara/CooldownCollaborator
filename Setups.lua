-- Setups, profiles, layouts and the smaller tools around them (settings lane, part 2):
--   P15  setups as text: export / import with a copy box, named profiles a character picks
--   P42  officer setups over the guild channel (O kind), with Accept / Not now / Never
--   P21  window places saved separately for a party and a raid, and Reset all windows
--   P33  the last pull's cooldown log (/cdc lastpull)
--   P38  /cdc post: what's ready for the spells you pick, to the group's chat
--   P45  a new key or dungeon: the cooldowns the game resets go back to ready
--   P19  /cdc support: a box with what to paste into a bug report
--   P34  CC.API, a small public feed for other addons (docs/API.md)
-- A setup is { disabled = { spellID, ... }, custom = { [id] = { name, duration, icon } },
-- alerts = { [id] = { sound, flash, midscreen, warn } }, places = { [windowKey] = { x, y } } }.

local L = CC.L

local SETUP_FORMAT = "1"
local CHUNK = 200
local MAX_PARTS = 64

-------------------------------------------------------------------------------
-- Text form: a version, then key=value pairs (";" between); the values' ":" ";"
-- "," "=" "%" and line breaks are written %XX.
--   1;k=setup;n=<name>;d=<id>,<id>;c=<id>,<name>,<seconds>,<icon>;a=<id>,<sound>,<flash>,<mid>,<warn>;w=<key>,<x>,<y>
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

function CC:SnapshotPlaces()
    local places = {}
    for _, w in ipairs(CC.WINDOWS or {}) do
        local x, y = self.db[w.xKey], self.db[w.yKey]
        if type(x) == "number" and type(y) == "number" then places[w.key] = { x, y } end
    end
    return places
end

-- Put windows where a places table says (only the windows it names), moving the live frames too.
function CC:ApplyPlaces(places)
    for _, w in ipairs(CC.WINDOWS or {}) do
        local p = places and places[w.key]
        if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then
            local x, y = tonumber(p[1]), tonumber(p[2])
            self.db[w.xKey], self.db[w.yKey] = x, y
            local f = self[w.frame]
            if f then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER", x, y)
            end
        end
    end
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
        parts[#parts + 1] = string.format("w=%s,%d,%d", Quote(key), math.floor(p[1] + 0.5), math.floor(p[2] + 0.5))
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
                    setup.places[f[1]] = { x, y }
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
        if not q or q[1] ~= p[1] or q[2] ~= p[2] then moved = moved + 1 end
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
-- Profiles: db.profiles[name] = a setup; db.charProfile[character] = its name;
-- db.defaultProfile = the one characters follow when they haven't picked
-------------------------------------------------------------------------------

function CC:ProfileNames()
    local names = {}
    for name in pairs(self.db.profiles or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function CC:SaveProfile(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return false end
    self.db.profiles = self.db.profiles or {}
    local old = self.db.profiles[name]
    local keep = self:KeepsOwnPlaces()
    local snap = self:SnapshotSetup(keep)
    if keep and old then snap.places = old.places or {} end
    self.db.profiles[name] = snap
    return true
end

function CC:UseProfile(name)
    local p = self.db.profiles and self.db.profiles[name]
    if not p then return false end
    self.db.charProfile = self.db.charProfile or {}
    self.db.charProfile[self:FullName("player")] = name
    self:ApplySetup(p)
    return true
end

function CC:DeleteProfile(name)
    if not (self.db.profiles and self.db.profiles[name]) then return false end
    self.db.profiles[name] = nil
    for who, pn in pairs(self.db.charProfile or {}) do
        if pn == name then self.db.charProfile[who] = nil end
    end
    if self.db.defaultProfile == name then self.db.defaultProfile = false end
    return true
end

function CC:CurrentProfile()
    local me = self:FullName("player")
    local name = self.db.charProfile and self.db.charProfile[me] or self.db.defaultProfile
    if name and self.db.profiles and self.db.profiles[name] then return name end
    return nil
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

-- At login: the profile this character follows is put in place (no undo kept: it is the normal way in).
function CC:ApplyCharacterProfile()
    local name = self:CurrentProfile()
    if name then self:ApplySetup(self.db.profiles[name], { noUndo = true }) end
    self.profileApplied = true
end

-- At logout the profile in use keeps what was changed since.
function CC:SaveCurrentProfile()
    -- never before this character's own profile went in: the live settings may be another character's
    if not self.profileApplied then return end
    local name = self:CurrentProfile()
    if name then
        local keep = self:KeepsOwnPlaces()
        local snap = self:SnapshotSetup(keep)
        if keep then snap.places = self.db.profiles[name].places or {} end   -- the profile's own places stay
        self.db.profiles[name] = snap
    end
    if self:KeepsOwnPlaces() then self.db.charPlaces[self:FullName("player")] = self:SnapshotPlaces() end
end

-------------------------------------------------------------------------------
-- The copy box: a box of text, selected, to copy out of (and, for import, to paste into)
-------------------------------------------------------------------------------

function CC:ShowCopyBox(title, text, onAccept, acceptLabel)
    local f = self.copyBox
    if not f then
        f = CreateFrame("Frame", "CCCopyBox", UIParent, CC.BackdropTemplate)
        f:SetSize(440, 260)
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
            if name and (name == fullName or self:ShortName(name) == short) then return rankName end
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
            if name and (name == fullName or self:ShortName(name) == short) then return rankIndex end
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
-- /cdc support (P19)
-------------------------------------------------------------------------------

CC.sendErrors = CC.sendErrors or {}

function CC:SupportText()
    -- debug begin: the support report is read by the developer, so it stays in English
    local lines = {
        "CooldownCollaborator " .. self.version,
        string.format("Client: %s (interface %s), retailAPI %s", tostring(self:ClientTag()), tostring(self.tocversion), tostring(self.retailAPI)),
        "Group: " .. (self:GroupKind() or "none") .. ", " .. tostring(GetNumGroupMembers()) .. " players",
    }
    local heard = {}
    for name, p in pairs(self.peers or {}) do
        heard[#heard + 1] = string.format("%s %s%s", self:ShortName(name), tostring(p.version or "?"), p.client and (" " .. p.client) or "")
    end
    table.sort(heard)
    lines[#lines + 1] = "Heard from (" .. #heard .. "): " .. (#heard > 0 and table.concat(heard, ", ") or "nobody")
    local off = {}
    for id, v in pairs(self.db.disabledSpells or {}) do
        local d = v and CC.SpellData[id]
        if d then off[#off + 1] = d.name end
    end
    table.sort(off)
    lines[#lines + 1] = "Unticked spells (" .. #off .. "): " .. (#off > 0 and table.concat(off, ", ") or "none")
    lines[#lines + 1] = "Show: " .. tostring(self.db.showPreset) .. ", windows " .. tostring(self.db.showWindows)
        .. ", lighter " .. tostring(self.db.lighterMode) .. ", guild sharing " .. tostring(self.db.guildSync)
    local errs = {}
    for i = math.max(1, #self.sendErrors - 9), #self.sendErrors do errs[#errs + 1] = self.sendErrors[i] end
    lines[#lines + 1] = "Recent send errors (" .. #errs .. "): " .. (#errs > 0 and table.concat(errs, ", ") or "none")
    -- debug end
    return table.concat(lines, "\n")
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
