-- The big middle circle: energy / rage / mana, filling from the bottom, with the raw value in the middle.
local addonName, ns = ...

local SIZE = ns.RESOURCE_SIZE
local DEFAULT_COLOR = { 0.7, 0.7, 0.7 }
local POWER_COLORS = {
    [Enum.PowerType.Energy] = { 1, 0.82, 0 },
    [Enum.PowerType.Rage] = { 0.9, 0.1, 0.1 },
    [Enum.PowerType.Mana] = { 0.2, 0.45, 1 },
}
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local hud = ns.hud

-- #2 soft circle as a dark backdrop
local backdrop = hud:CreateTexture(nil, "BACKGROUND")
backdrop:SetTexture(ns.MEDIA .. "circle_soft")
backdrop:SetSize(SIZE * 1.3, SIZE * 1.3)
backdrop:SetPoint("CENTER")
backdrop:SetVertexColor(0, 0, 0, 0.4) -- light enough for the GCD shading to show over the empty part

-- #1 hard circle: a square vertical bar, masked to a circle so it fills from the bottom
local bar = CreateFrame("StatusBar", nil, hud)
bar:SetSize(SIZE, SIZE)
bar:SetPoint("CENTER")
bar:SetFrameLevel(hud:GetFrameLevel() + 2) -- leaves +1 for the Enrage tint behind it (Enrage.lua)
bar:SetOrientation("VERTICAL")
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")

local mask = bar:CreateMaskTexture()
mask:SetTexture(ns.MEDIA .. "circle_hard", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
mask:SetAllPoints(bar)
bar:GetStatusBarTexture():AddMaskTexture(mask)

-- #3 thin ring as the border
local border = bar:CreateTexture(nil, "OVERLAY")
border:SetTexture(ns.MEDIA .. "ring_thin")
border:SetSize(SIZE + 6, SIZE + 6)
border:SetPoint("CENTER")
border:SetVertexColor(0, 0, 0)

-- The number sits on its own higher layer, so the GCD shading (Gcd.lua) never dims it.
local textLayer = CreateFrame("Frame", nil, bar)
textLayer:SetAllPoints()
textLayer:SetFrameLevel(bar:GetFrameLevel() + 5)
local text = textLayer:CreateFontString(nil, "OVERLAY")
text:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
text:SetPoint("CENTER")

-- Mana shows as a percentage. Mana is secret in combat, so we can't divide it ourselves:
-- UnitPowerPercent works it out engine-side, and the ScaleTo100 curve makes it 0-100.
-- string.format accepts secrets, so it can add the "%".
local SCALE_TO_100 = CurveConstants and CurveConstants.ScaleTo100
local CAN_SHOW_PERCENT = UnitPowerPercent ~= nil and SCALE_TO_100 ~= nil

local function PowerText(powerType, power)
    if powerType == Enum.PowerType.Mana and CAN_SHOW_PERCENT then
        return string.format("%d%%", UnitPowerPercent("player", powerType, false, SCALE_TO_100))
    end
    return power
end

local function Update()
    local powerType = UnitPowerType("player")
    local knownType = not ns.IsSecret(powerType)
    local color = (knownType and POWER_COLORS[powerType]) or DEFAULT_COLOR
    bar:SetStatusBarColor(color[1], color[2], color[3])

    -- Current and max power may be secret in combat; StatusBar and FontString accept secrets as-is.
    local power = UnitPower("player", powerType)
    bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
    bar:SetValue(power, SMOOTH)
    text:SetText(knownType and PowerText(powerType, power) or power)
end

ns.OnLoad(function()
    ns.Debug("mana as percent:", CAN_SHOW_PERCENT, "| UnitPowerPercent:", UnitPowerPercent ~= nil,
        "| CurveConstants.ScaleTo100:", SCALE_TO_100 ~= nil)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", Update)
