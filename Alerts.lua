-- Ready alerts (P1; the owner's pick "Row flash", plus his note "Icon mid
-- screen as additional option").
--   db.alerts[spellID] = { sound = <a SoundKit ID, a sound file path, or true
--       for the raid warning sound; false or nil for none>, flash = true,
--       midscreen = false, warn = 0 }
-- When a tracked cooldown with an entry comes back (ours or a groupmate's: a
-- ready-now, their state message, or its timer running out), the watcher below
-- calls CC:FireReadyAlert(owner, spellID) once: the sound, its panel row (and
-- its Essentials line, through CC:FlashEssentialsFor where that exists)
-- flashing green twice, and with midscreen on its icon, name and owner in the
-- middle of the screen, fading after 2 s. warn = N fires the same alert N
-- seconds before it is back (the mid-screen text then says "in Ns").

local L = CC.L

local DEFAULT_SOUND  = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
local MIDSCREEN_TIME = 2
local FADE_TIME      = 0.5
local CHECK_EVERY    = 0.2

local last = {}   -- ["Name-Realm\tspellID"] = the seconds left at the last check

function CC:FireReadyAlert(owner, spellID, secondsLeft)
    local alerts = self.db and self.db.alerts
    local cfg = alerts and alerts[spellID]
    local data = CC.SpellData[spellID]
    if type(cfg) ~= "table" or not data or not owner then return end
    if cfg.sound then
        local sound = cfg.sound == true and DEFAULT_SOUND or cfg.sound
        if type(sound) == "number" then
            pcall(PlaySound, sound, "Master")
        elseif type(sound) == "string" then
            pcall(PlaySoundFile, sound, "Master")
        end
    end
    if cfg.flash ~= false then
        if self.FlashPanelRow then self:FlashPanelRow(owner, spellID) end
        local flashEssentials = self.FlashEssentialsFor
        if flashEssentials then
            xpcall(function() flashEssentials(self, owner, spellID) end, geterrorhandler())
        end
    end
    if cfg.midscreen then self:ShowMidscreenAlert(owner, spellID, secondsLeft) end
    self.lastAlert = { owner = owner, spellID = spellID, secondsLeft = secondsLeft, at = GetTime() }
end

-- Every spell with an alert, for everyone in the group: a timer that was
-- running and now isn't fires once; one crossing its warn mark fires once too.
function CC:CheckReadyAlerts()
    local alerts = self.db and self.db.alerts
    if type(alerts) ~= "table" or not next(alerts) then
        wipe(last)
        return
    end
    local active = self:GetActiveGroupNames()
    local seen = {}
    for name, entry in pairs(self.state) do
        if active[name] then
            for key, cfg in pairs(alerts) do
                local spellID = tonumber(key)
                if spellID and type(cfg) == "table" and entry.spells[spellID] then
                    local id = name .. "\t" .. spellID
                    local now = self:GetRemaining(name, spellID) or 0
                    local before = last[id]
                    if before then
                        local warn = tonumber(cfg.warn) or 0
                        if before > 0 and now <= 0 then
                            self:FireReadyAlert(name, spellID)
                        elseif warn > 0 and before > warn and now <= warn and now > 0 then
                            self:FireReadyAlert(name, spellID, now)
                        end
                    end
                    last[id] = now
                    seen[id] = true
                end
            end
        end
    end
    for id in pairs(last) do
        if not seen[id] then last[id] = nil end
    end
end

C_Timer.NewTicker(CHECK_EVERY, function() CC:CheckReadyAlerts() end)

-------------------------------------------------------------------------------
-- The mid-screen icon
-------------------------------------------------------------------------------

local function MidscreenFrame()
    if CC.midscreenFrame then return CC.midscreenFrame end
    local f = CreateFrame("Frame", "CCReadyAlertFrame", UIParent)
    f:SetSize(240, 84)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", f, "TOP", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    f.nameText = name
    local owner = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    owner:SetPoint("TOP", name, "BOTTOM", 0, -2)
    f.ownerText = owner
    f:Hide()
    CC.midscreenFrame = f
    return f
end

function CC:ShowMidscreenAlert(owner, spellID, secondsLeft)
    local data = CC.SpellData[spellID]
    if not data then return end
    local f = MidscreenFrame()
    f.icon:SetTexture(data.icon)
    if secondsLeft then
        f.nameText:SetText(string.format(L["%s in %ds"], data.name, math.ceil(secondsLeft)))
    else
        f.nameText:SetText(data.name)
    end
    local entry = self.state[owner]
    local c = CC.ClassColors[entry and entry.class or "UNKNOWN"] or CC.ClassColors.UNKNOWN
    f.ownerText:SetText(self:ShortName(owner))
    f.ownerText:SetTextColor(c[1], c[2], c[3])
    local shownAt = GetTime()
    f.shownAt = shownAt
    f:SetAlpha(1)
    f:Show()
    -- full for 2 s, then a half-second fade
    f:SetScript("OnUpdate", function(widget)
        local t = GetTime() - widget.shownAt
        if t >= MIDSCREEN_TIME then widget:SetAlpha(math.max(0, 1 - (t - MIDSCREEN_TIME) / FADE_TIME)) end
    end)
    C_Timer.After(MIDSCREEN_TIME + FADE_TIME, function()
        if f.shownAt == shownAt then
            f:SetScript("OnUpdate", nil)
            f:Hide()
        end
    end)
end
