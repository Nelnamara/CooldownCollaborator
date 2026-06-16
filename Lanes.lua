-- Lane View — alternate renderer over the same capability data Essentials.lua
-- uses, but as icons sliding along a bar (0% = just used, 100% = ready)
-- instead of a text row. Inspired by the classic "Cooldown Timeline" visual
-- language, but written from scratch for CooldownCollaborator's multiplayer
-- case (multiple players' icons sharing one lane) rather than ported from
-- CDTL3, which is single-player and deeply tied to its own AceDB schema.

local LANE_WIDTH  = 240
local LANE_HEIGHT = 28
local ICON_SIZE   = 22
local LANE_GAP    = 6

function CC:BuildLaneView()
    local db = self.db

    local f = CreateFrame("Frame", "CCLaneFrame", UIParent, "BackdropTemplate")
    f:SetSize(LANE_WIDTH + 16, LANE_HEIGHT * 2 + LANE_GAP + 30)
    f:SetPoint("CENTER", UIParent, "CENTER", db.laneX or 0, db.laneY or -200)
    f:SetScale(db.laneScale or 1.0)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    f:SetBackdropBorderColor(0.3, 0.5, 0.7, 0.85)

    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not CC.db.laneLocked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        CC:SaveLanePosition()
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -4)
    title:SetText("|cFF54a3ffLanes|r")

    self.lanes = {}
    local y = -22
    for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
        local cap = CC.CAPABILITIES[capKey]

        local lane = CreateFrame("Frame", nil, f)
        lane:SetSize(LANE_WIDTH, LANE_HEIGHT)
        lane:SetPoint("TOP", f, "TOP", 0, y)

        local track = lane:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT", lane, "LEFT", 0, 0)
        track:SetSize(LANE_WIDTH, 4)
        track:SetColorTexture(0.2, 0.2, 0.25, 0.9)
        lane.track = track

        local label = lane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("BOTTOMLEFT", lane, "TOPLEFT", 0, 0)
        label:SetText(cap.label)
        lane.label = label

        lane.icons = {}
        for i = 1, 6 do
            local icon = lane:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:Hide()
            lane.icons[i] = icon

            local border = lane:CreateTexture(nil, "OVERLAY")
            border:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)
            border:SetColorTexture(0, 0, 0, 0)
            border:Hide()
            lane.icons[i].border = border
        end

        self.lanes[capKey] = lane
        y = y - (LANE_HEIGHT + LANE_GAP)
    end

    f:Hide()
    self.laneFrame = f
    self:UpdateLaneLock()

    C_Timer.NewTicker(0.2, function()
        if CC.laneFrame and CC.laneFrame:IsShown() then
            CC:RefreshLanes()
        end
    end)
end

function CC:RefreshLanes()
    if not self.laneFrame then return end
    if not self.db.laneEnabled then
        self.laneFrame:Hide()
        return
    end

    for _, capKey in ipairs(CC.CAPABILITY_ORDER) do
        local lane = self.lanes[capKey]
        local status = self:GetCapabilityStatus(capKey)

        -- Sort by remaining descending so the soonest-ready icon ends up
        -- rightmost without fighting for the same slot as others mid-slide.
        table.sort(status, function(a, b) return a.remaining > b.remaining end)

        -- Greedy bin-pack into vertical levels: for each icon, find the
        -- lowest level where it doesn't x-overlap anything already placed
        -- there. A simple "offset if it overlaps the previous icon" approach
        -- breaks for non-transitive chains (A overlaps B, B overlaps C, but
        -- A and C don't overlap each other) - this does not.
        local levelOccupants = {}  -- level -> { xPos, xPos, ... }

        for i, icon in ipairs(lane.icons) do
            local entry = status[i]
            if not entry then
                icon:Hide()
                icon.border:Hide()
            else
                local data = CC.SpellData[entry.spellID]
                local duration = data and data.duration or 300
                local progress = entry.ready and 1 or (1 - (entry.remaining / duration))
                progress = math.max(0, math.min(1, progress))

                local xPos = progress * (LANE_WIDTH - ICON_SIZE)

                local level = 0
                while true do
                    local occupants = levelOccupants[level]
                    local fits = true
                    if occupants then
                        for _, ox in ipairs(occupants) do
                            if math.abs(ox - xPos) < ICON_SIZE then
                                fits = false
                                break
                            end
                        end
                    end
                    if fits then break end
                    level = level + 1
                end
                levelOccupants[level] = levelOccupants[level] or {}
                table.insert(levelOccupants[level], xPos)
                local yOffset = -level * (ICON_SIZE - 4)

                icon:ClearAllPoints()
                icon:SetPoint("LEFT", lane, "LEFT", xPos, yOffset)
                if data then icon:SetTexture(data.icon) end
                icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                icon:Show()

                local c = entry.ready and { 0.3, 1.0, 0.3 } or (CC.ClassColors[entry.class] or CC.ClassColors.UNKNOWN)
                icon.border:ClearAllPoints()
                icon.border:SetPoint("CENTER", icon, "CENTER", 0, 0)
                icon.border:SetColorTexture(c[1], c[2], c[3], 0.6)
                icon.border:Show()
            end
        end
    end

    if IsInGroup() and self.db.laneEnabled then
        self.laneFrame:Show()
    end
end

function CC:UpdateLaneLock()
    if self.laneFrame then
        self.laneFrame:SetMovable(not self.db.laneLocked)
    end
end

function CC:SaveLanePosition()
    if not self.laneFrame then return end
    local x, y   = self.laneFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if x and y and ux and uy then
        self.db.laneX = x - ux
        self.db.laneY = y - uy
    end
end
