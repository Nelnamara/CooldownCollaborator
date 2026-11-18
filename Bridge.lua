-- CDTL3 bridge: feeds group cooldowns onto CooldownTimeline3's lanes through
-- its timer-type API. Collaborator stays the group brain (sync, roster);
-- CDTL3 is the screen. Every call is guarded so CC works with no CDTL3 or an
-- older CDTL3 that lacks the API.

local TIMER_TYPE = "cdcGroup"
local ICON_PATH  = "Interface\\AddOns\\CooldownCollaborator\\Media\\icon.tga"

CC.bridgeRegistered = false

local function Api()
    -- CDTL3 is another addon's global, absent when it is not installed.
    ---@diagnostic disable-next-line: undefined-field
    local api = _G.CDTL3
    if type(api) ~= "table" then return nil end
    return api
end

-- True when CDTL3 is loaded and has the timer-type API.
function CC:BridgeAvailable()
    local api = Api()
    return api ~= nil and type(api.RegisterTimerType) == "function"
        and type(api.StartTimer) == "function" and type(api.StopTimer) == "function"
end

function CC:BridgeActive()
    return self.bridgeRegistered and self.db and self.db.showOnCDTL3 and true or false
end

-- Called from PLAYER_LOGIN, once both addons have loaded.
function CC:BridgeRegister()
    if self.bridgeRegistered or not self:BridgeAvailable() then return end
    local api = Api() --[[@as table]] -- BridgeAvailable just checked it
    local ok = pcall(api.RegisterTimerType, api, TIMER_TYPE, {
        name = "Group cooldowns",
        icon = ICON_PATH,
    })
    if ok then
        self.bridgeRegistered = true
        self:BridgeResync()
        if self.RefreshBridgeOption then self:RefreshBridgeOption() end
    end
end

function CC:BridgeStart(owner, spellID, usedAt, classTag)
    if not self:BridgeActive() then return end
    local data = CC.SpellData[spellID]
    if not data or not owner then return end
    -- Already over (e.g. an old sync of an expired cooldown): nothing to show.
    if (usedAt + data.duration) <= GetTime() then
        self:BridgeStop(owner, spellID)
        return
    end
    local api = Api()
    if not api or type(api.StartTimer) ~= "function" then return end
    pcall(api.StartTimer, api, TIMER_TYPE, owner .. ":" .. spellID, {
        name      = data.name,
        icon      = data.icon,
        duration  = data.duration,
        startedAt = usedAt,
        owner     = owner,
        class     = classTag or "UNKNOWN",
    })
end

function CC:BridgeStop(owner, spellID)
    if not self.bridgeRegistered or not owner then return end
    local api = Api()
    if not api or type(api.StopTimer) ~= "function" then return end
    pcall(api.StopTimer, api, TIMER_TYPE, owner .. ":" .. spellID)
end

-- Push every running timer (after the option is switched on / at register).
function CC:BridgeResync()
    for owner, entry in pairs(self.state) do
        for spellID, usedAt in pairs(entry.spells) do
            self:BridgeStart(owner, spellID, usedAt, entry.class)
        end
    end
end

-- Pull every timer back off (after the option is switched off).
function CC:BridgeClear()
    for owner, entry in pairs(self.state) do
        for spellID in pairs(entry.spells) do
            self:BridgeStop(owner, spellID)
        end
    end
end

function CC:SetShowOnCDTL3(on)
    self.db.showOnCDTL3 = on and true or false
    if self.db.showOnCDTL3 then
        self:BridgeResync()
    else
        self:BridgeClear()
    end
end
