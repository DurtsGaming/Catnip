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

-- The real rings around the dots (DotRings.lua's AuraContainers, CooldownRings.lua's arcs) live in
-- comboLive; preview mode hides it while its stand-ins show in comboSample. Both at the group's
-- level, so frames placed in them keep the levels they had in the group.
local live = CreateFrame("Frame", nil, group)
live:SetAllPoints()
live:SetFrameLevel(group:GetFrameLevel())
ns.comboLive = live

local sampleHolder = CreateFrame("Frame", nil, group)
sampleHolder:SetAllPoints()
sampleHolder:SetFrameLevel(group:GetFrameLevel())
sampleHolder:Hide()
ns.comboSample = sampleHolder

-- A frame for a ring's layer in one of those holders, at the holder's level (for an opacity setting).
function ns.ComboRingGate(holder)
    local gate = CreateFrame("Frame", nil, holder)
    gate:SetAllPoints()
    gate:SetFrameLevel(holder:GetFrameLevel())
    return gate
end

-- Preview mode's hit for a ring around dot i: its band (ring_rip's, 47-63 of 128 on a canvas
-- DOT_SIZE + 8 across) from just inside the dot's edge, so the dot keeps its middle.
function ns.ComboRingHit(i, visible)
    local x, y = ns.ComboDotOffset(i)
    return { kind = "ring", x = x, y = y, inner = DOT_SIZE / 2 - 2, outer = (DOT_SIZE + 8) * 63 / 128 + 2,
        visible = visible }
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

-- Preview mode's state (Preview.lua), nil when live: a fixed count, the dots shown in every state
-- but Caster, and the rings' stand-ins in Cat and Bear (not Prowl: no DoTs before the opener).
local SAMPLE_POINTS = 3
local sampleState

local function Update()
    if sampleState then
        group:SetShown(sampleState ~= "caster")
        for _, bar in ipairs(bars) do
            bar:SetValue(SAMPLE_POINTS)
        end
        return
    end
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

-- Settings (Elements.lua). Opacity is each dot's alpha (the group's would fade the rings too).
-- Picked as one group by the dots' middles; the rings around them have their own elements.
local centres = {}
for i = 1, COUNT do
    centres[i] = { ns.ComboDotOffset(i) }
end

ns.RegisterElement({
    id = "combo.points",
    zone = "combo",
    name = "Combo points",
    glyph = { kind = "dots", color = { 0.96, 0.77, 0.26 } },
    order = 0,
    hit = { kind = "circles", radius = DOT_SIZE / 2 - 2, centres = function() return centres end,
        visible = function() return group:IsVisible() end },
    options = {
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        for _, bar in ipairs(bars) do
            bar:SetAlpha(get("opacity") / 100)
        end
    end,
    sample = function(state)
        sampleState = state
        live:SetShown(state == nil)
        sampleHolder:SetShown(state == "cat" or state == "bear")
        Update()
    end,
})
