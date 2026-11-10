-- Minimap button for CooldownCollaborator
-- Left-click: toggle panel | Right-click: open settings | Drag: reposition

-- Orbit radius follows the minimap's live size (the Forever minimap is larger
-- than retail's, and Edit Mode can rescale it), so the button rides the rim
-- instead of sitting inside the map. Same fix as CDTL3 v3.0.9.
local function AngleToOffset(angle)
    local radius = (Minimap:GetWidth() / 2) + 4
    return radius * math.cos(math.rad(angle)), radius * math.sin(math.rad(angle))
end

local function Place(btn)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", AngleToOffset(CC.db.minimapAngle or 225))
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
