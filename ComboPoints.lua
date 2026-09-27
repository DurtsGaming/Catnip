-- Five combo point dots along the arc above the resource circle. Only shown in Cat Form.
local addonName, ns = ...

local COUNT = 5
local DOT_SIZE = 22
local ARC_RADIUS = ns.RESOURCE_SIZE / 2 + DOT_SIZE / 2 + 8
local ANGLES = { 150, 120, 90, 60, 30 } -- degrees, left to right; 90 is straight up
local COLOR = { 1, 0.82, 0 }

local group = CreateFrame("Frame", nil, ns.hud)
group:SetAllPoints()

local fills = {}
for i = 1, COUNT do
    local angle = math.rad(ANGLES[i])
    local x, y = ARC_RADIUS * math.cos(angle), ARC_RADIUS * math.sin(angle)

    local border = group:CreateTexture(nil, "ARTWORK")
    border:SetTexture(ns.MEDIA .. "ring_thin_small")
    border:SetSize(DOT_SIZE, DOT_SIZE)
    border:SetPoint("CENTER", group, "CENTER", x, y)
    border:SetVertexColor(0.1, 0.1, 0.1)

    local fill = group:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(ns.MEDIA .. "circle_hard")
    fill:SetSize(DOT_SIZE - 2, DOT_SIZE - 2)
    fill:SetPoint("CENTER", border)
    fill:SetVertexColor(COLOR[1], COLOR[2], COLOR[3])
    fill:Hide()

    local fadeIn = fill:CreateAnimationGroup()
    local alpha = fadeIn:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.15)
    fill.fadeIn = fadeIn

    fills[i] = fill
end

local warnedSecret = false

local function Update()
    group:SetShown(UnitPowerType("player") == Enum.PowerType.Energy)

    local points = UnitPower("player", Enum.PowerType.ComboPoints)
    if ns.IsSecret(points) then
        -- Research says combo points aren't secret; flag it if Forever disagrees.
        if not warnedSecret then
            print("|cff33ff99Catnip|r: combo points are secret here; combo display disabled.")
            warnedSecret = true
        end
        return
    end

    for i, fill in ipairs(fills) do
        local active = i <= points
        if active and not fill:IsShown() then
            fill:Show()
            fill.fadeIn:Play()
        elseif not active then
            fill:Hide()
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", Update)
