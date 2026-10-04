-- Five combo point dots along the arc above the resource circle. Shown in Cat and Bear Form, so
-- points and DoTs left over from Cat stay visible while tanking.
local addonName, ns = ...

local COUNT = 5
local DOT_SIZE = 38
local RING_THICKNESS = DOT_SIZE * 3 / 64 -- ring_small is 3px thick in a 64px texture
local ARC_RADIUS = 93 -- distance of the dot centres from the HUD centre
local ANGLES = { 150, 120, 90, 60, 30 } -- degrees, left to right; 90 is straight up
local FILL = ns.MEDIA .. "combo_fill"
local STEALTH_FILL = ns.MEDIA .. "combo_fill_prowl" -- periwinkle, in stealth mode (Stealth.lua)

local group = CreateFrame("Frame", nil, ns.hud)
group:SetAllPoints()

-- Shared with DotRings.lua, whose rings sit around dots 4 and 5 and hides with the dots outside Cat and Bear Form.
ns.comboGroup = group
ns.COMBO_DOT_SIZE = DOT_SIZE
function ns.ComboDotOffset(i)
    local angle = math.rad(ANGLES[i])
    return ARC_RADIUS * math.cos(angle), ARC_RADIUS * math.sin(angle)
end

-- Each fill is a StatusBar ranging i-1..i, fed the raw count: full when points >= i, empty below.
-- A StatusBar takes secret values, so this works even if the count is secret (EllesmereUI's
-- technique; Blood in the Water found GetComboPoints secret in combat).
local bars = {}
for i = 1, COUNT do
    local x, y = ns.ComboDotOffset(i)

    -- Tucks ~0.5px under the ring's inner edge (the ring sits 1/64 in from the texture edge), so
    -- there's no gap but the whole ring still shows. Any bigger and the fill covers the thin ring.
    -- combo_fill is the full energy fill cut to a circle (colour baked in, so untinted).
    local bar = CreateFrame("StatusBar", nil, group)
    local fillSize = DOT_SIZE - 2 * RING_THICKNESS
    bar:SetSize(fillSize, fillSize)
    bar:SetPoint("CENTER", group, "CENTER", x, y)
    bar:SetStatusBarTexture(FILL)
    bar:SetMinMaxValues(i - 1, i)
    bar:SetValue(0)

    -- Border draws above the fill (same frame, higher layer), so a filled dot keeps its outline.
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetTexture(ns.MEDIA .. "ring_small")
    border:SetSize(DOT_SIZE, DOT_SIZE)
    border:SetPoint("CENTER")
    border:SetVertexColor(0, 0, 0)

    bars[i] = bar
end

-- Stealth mode: periwinkle fill (the black outlines stay).
ns.OnStealthChanged(function(stealthed)
    for _, bar in ipairs(bars) do
        bar:SetStatusBarTexture(stealthed and STEALTH_FILL or FILL)
    end
end)

-- Forever keeps classic per-target combo points: UnitPower doesn't reset on a target switch or
-- when the target dies (Blood in the Water, EllesmereUI). GetComboPoints reads the current target.
local function ReadPoints()
    if GetComboPoints then
        return GetComboPoints("player", "target") or 0
    end
    return UnitPower("player", Enum.PowerType.ComboPoints)
end

local function Update()
    local powerType = UnitPowerType("player")
    group:SetShown(powerType == Enum.PowerType.Energy or powerType == Enum.PowerType.Rage)

    local points = ReadPoints()
    for _, bar in ipairs(bars) do
        bar:SetValue(points)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:RegisterUnitEvent("UNIT_HEALTH", "target") -- catches the target dying
ns.TryRegisterEvent(events, "UNIT_COMBO_POINTS") -- classic's event; unverified on Forever
events:SetScript("OnEvent", Update)
