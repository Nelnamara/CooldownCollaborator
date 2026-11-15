-- Minimap button for CooldownCollaborator
-- Left-click: toggle panel | Right-click: open settings | Drag: reposition

-- The orbit follows the minimap's live size (the Forever minimap is larger than the old one,
-- and Edit Mode can rescale it): the button's center sits just past the rim, so it rides the
-- border instead of floating inside the map. Same rule as CooldownTimeline3's button.
local function AngleToOffset(angle)
    local radius = (Minimap:GetWidth() / 2) + 4
    return radius * math.cos(math.rad(angle)), radius * math.sin(math.rad(angle))
end

local function Place(btn)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", AngleToOffset(CC.db.minimapAngle or 225))
end

-- Placed again at PLAYER_LOGIN: the button is built at ADDON_LOADED, when Forever's minimap
-- still reports the old size, and it grows without OnSizeChanged reaching the hook (test 3
-- showed the button where a 140-wide map puts it). CooldownTimeline3 builds its at login.
function CC:PlaceMinimapButton()
    if self.minimapBtn then
        Place(self.minimapBtn)
    end
end

function CC:BuildMinimapButton()
    local db = self.db

    local btn = CreateFrame("Button", "CCMinimapButton", Minimap)
    btn:SetSize(24, 24)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(false)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("AnyUp")

    -- Self-contained round icon (gold ring baked in) — SetAllPoints centers it cleanly.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\CooldownCollaborator\\Media\\minimap.tga")

    -- Initial position, and again whenever the minimap changes size
    Place(btn)
    Minimap:HookScript("OnSizeChanged", function() Place(btn) end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFF54a3ffCooldownCollaborator|r " .. CC.version)
        GameTooltip:AddLine("Left-click: Toggle panel", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Open settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: Reposition button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            CC:OpenOptions()
        else
            if CC.frame then
                CC.frame:SetShown(not CC.frame:IsShown())
            end
        end
    end)

    -- Drag to reposition around minimap edge
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local angle = math.deg(math.atan2(py / s - my, px / s - mx))
            CC.db.minimapAngle = angle
            Place(self)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    if db.minimapHide then btn:Hide() end
    self.minimapBtn = btn
end
