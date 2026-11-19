-- Hovering a cooldown (P20, the "Game tooltip plus a line" pick): the game's own
-- spell tooltip, then one plain line on when it matters (from the spell's
-- `kind`), the owner and the time left, and what we know about that: dead or
-- offline, ready only as far as we know (P44), an old copy (P13).
--   CC:ShowCooldownTooltip(anchorFrame, ownerName, spellID[, extraLine])
--   CC:HideCooldownTooltip()
-- ownerName may be a list of names (a folded ready line). The panel, the
-- Essentials bar and the Lane view call these on their lines and icons.

local L = CC.L

local GREEN = { 0.30, 1.00, 0.30 }
local GOLD  = { 1.00, 0.82, 0.00 }
local GREY  = { 0.70, 0.70, 0.70 }

-- When it matters, by the spell's kind
local WHEN = {
    rez      = L["Brings a dead player back."],
    lust     = L["For the burn: haste for the whole group, once a fight."],
    external = L["For one player about to take a big hit."],
    raid     = L["For a big hit on the whole group."],
    personal = L["Its owner's own life saver; it can't be given to anyone else."],
    mana     = L["For a healer running low on mana."],
    utility  = L["Help that isn't a heal or a shield: movement, taunts, a burst and more."],
}

function CC:CooldownWhen(spellID)
    local data = CC.SpellData[spellID]
    return data and WHEN[data.kind]
end

-- "Ashka, Quillan and Sorella"
local function NameList(names)
    local short = {}
    for _, name in ipairs(names) do short[#short + 1] = CC:ShortName(name) end
    if #short <= 1 then return short[1] or "" end
    return string.format(L["%s and %s"], table.concat(short, ", ", 1, #short - 1), short[#short])
end

-- The lines under the game's spell tooltip: { text, r, g, b, wrap }, top down.
function CC:CooldownTooltipLines(ownerName, spellID)
    local lines = {}
    local function add(text, c, wrap)
        lines[#lines + 1] = { text = text, r = c[1], g = c[2], b = c[3], wrap = wrap and true or false }
    end
    local data = CC.SpellData[spellID]
    if not data then return lines end
    local when = WHEN[data.kind]
    if when then add(when, GREEN, true) end

    if type(ownerName) == "table" then
        if #ownerName > 1 then
            add(string.format(L["Ready: %s"], NameList(ownerName)), GREY, true)
            local guessed = {}
            for _, name in ipairs(ownerName) do
                if self:IsGuessedReady(name, spellID) then guessed[#guessed + 1] = name end
            end
            if #guessed > 0 then
                add(string.format(L["%s: ready as far as we know."], NameList(guessed)), GOLD, true)
            end
            return lines
        end
        ownerName = ownerName[1]
    end
    if not ownerName then return lines end

    local short = self:ShortName(ownerName)
    local remaining = self:GetRemaining(ownerName, spellID) or 0
    local state = self:OwnerState(ownerName)
    local guessed = remaining <= 0 and self:IsGuessedReady(ownerName, spellID)
    if state == "dead" then
        add(string.format(L["%s \194\183 dead"], short), GREY)
    elseif state == "offline" then
        add(string.format(L["%s \194\183 offline"], short), GREY)
    elseif remaining > 0 then
        add(string.format(L["%s \194\183 back in %s"], short, self:FormatTime(remaining)), GREY)
    elseif guessed then
        add(string.format(L["%s \194\183 ready as far as we know"], short), GREY)
    else
        add(string.format(L["%s \194\183 ready"], short), GREY)
    end

    -- the effect of an external or raid defensive that is still on
    local entry = self.state[ownerName]
    local usedAt = entry and entry.spells[spellID]
    if data.effect and usedAt and remaining > 0 then
        local left = data.effect - (GetTime() - usedAt)
        if left > 0 then add(string.format(L["Its effect: %s left"], self:FormatTime(left)), GOLD) end
    end

    if guessed then
        add(L["Ready as far as we know."], GOLD)
        if entry and entry.log and entry.log[spellID] then
            add(L["Seen in the combat log; their copy hasn't said it's back."], GREY, true)
        elseif entry and entry.restored and entry.restored[spellID] then
            add(L["Kept from before your /reload; nobody has said since."], GREY, true)
        else
            add(L["Doesn't run CooldownCollaborator and hasn't been seen casting."], GREY, true)
        end
    end

    local peer = self.peers and self.peers[ownerName]
    if peer and (peer.proto == 1 or self:IsOlderVersion(peer.version)) then
        if peer.proto == 1 then
            add(string.format(L["Runs an old 1.x copy; the current version is %s."], self.version), GOLD, true)
        else
            add(string.format(L["Runs %s; the current version is %s."], tostring(peer.version), self.version), GOLD, true)
        end
        add(L["Old copies can undo ready-now messages."], GREY, true)
    end
    return lines
end

function CC:ShowCooldownTooltip(anchorFrame, ownerName, spellID, extraLine)
    local data = CC.SpellData[spellID]
    if not anchorFrame or not data then return end
    GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    -- the game's own tooltip (a ranked spell's top rank); a spell the game can't
    -- show (a custom ID it doesn't know) gets its name instead
    local id = data.ranks and data.ranks[#data.ranks] or spellID
    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, id)
    if not ok or (GameTooltip:NumLines() or 0) == 0 then
        GameTooltip:SetText(data.name, 1, 1, 1)
    end
    for _, l in ipairs(self:CooldownTooltipLines(ownerName, spellID)) do
        GameTooltip:AddLine(l.text, l.r, l.g, l.b, l.wrap)
    end
    if extraLine then GameTooltip:AddLine(extraLine, GREY[1], GREY[2], GREY[3], true) end
    GameTooltip:Show()
    self.tooltipShown = { anchor = anchorFrame, owner = ownerName, spellID = spellID }
end

function CC:HideCooldownTooltip()
    self.tooltipShown = nil
    GameTooltip:Hide()
end
