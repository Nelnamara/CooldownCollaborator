-- Minimap button for CooldownCollaborator
-- Left-click: toggle panel | Right-click: open settings | Drag: reposition

local RADIUS = 80

local function AngleToOffset(angle)
    return RADIUS * math.cos(math.rad(angle)), RADIUS * math.sin(math.rad(angle))
end

function CC:BuildMinimapButton()
    local db = self.db

    local btn = CreateFrame("Button", "CCMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(false)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("AnyUp")

    -- Icon (Rallying Cry)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture(132351)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Circular mask so the icon looks like other minimap buttons
    local mask = btn:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    -- Border ring
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Initial position
    btn:SetPoint("CENTER", Minimap, "CENTER", AngleToOffset(db.minimapAngle or 225))

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
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", AngleToOffset(angle))
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    if db.minimapHide then btn:Hide() end
    self.minimapBtn = btn
end
