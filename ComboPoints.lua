-- Five dots along the arc above the resource circle, shown in Cat and Bear Form: combo points in
-- Cat, Lacerate's stacks on the target in Bear. The rings around them (DoTs left over from Cat
-- included) stay visible in both.
local addonName, ns = ...
local L = ns.L
local CreateFrame = ns.Profiled("ComboPoints") -- timed by /catnip perf (Profiler.lua)

local COUNT = 5
local DOT_SIZE = 38
local RING_THICKNESS = DOT_SIZE * 3 / 64 -- ring_small is 3px thick in a 64px texture
local ARC_RADIUS = 93 -- distance of the dot centres from the HUD centre
local ANGLES = { 150, 120, 90, 60, 30 } -- degrees, left to right; 90 is straight up
local FILL = ns.MEDIA .. "combo_fill"
local STEALTH_FILL = ns.MEDIA .. "combo_fill_prowl" -- periwinkle, in stealth mode (Stealth.lua)
local RAGE_FILL = ns.MEDIA .. "combo_fill_rage" -- the full rage fill cut to a circle: Lacerate's stacks

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
-- tick(), if given, returns the box of a marker standing at the ring's 12 o'clock (width, bottom,
-- top from the dot's centre; nil for none), added to the hit as `notch` (see Preview.lua).
function ns.ComboRingHit(i, visible, tick)
    local x, y = ns.ComboDotOffset(i)
    local notch = tick and function()
        local width, bottom, top = tick()
        if width then
            return x - width / 2, y + bottom, width, top - bottom
        end
    end
    return { kind = "ring", x = x, y = y, inner = DOT_SIZE / 2 - 2, outer = (DOT_SIZE + 8) * 63 / 128 + 2,
        visible = visible, notch = notch }
end

-- Frame levels above the HUD: combo fills (the group's, +1), Lacerate's fills (+2), the dots'
-- outlines (+3), then the rings around the dots (cooldowns +5, DoTs above).
local LACERATE_LEVEL = 1 -- Lacerate's AuraContainers
local LACERATE_FILL_LEVEL = 2
local OUTLINE_LEVEL = 3

-- One black outline per dot, shared by the combo points and Lacerate's stacks. Lacerate's dots used
-- to draw their own on top of these, and the AuraContainer may place its button on whole pixels
-- while these sit on fractional ones, so the two outlines could land a fraction of a pixel apart
-- and soften the edge.
local outlines = CreateFrame("Frame", nil, group)
outlines:SetAllPoints()
outlines:SetFrameLevel(ns.hud:GetFrameLevel() + OUTLINE_LEVEL)

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

    -- On the outline frame, above both kinds of fill, so a filled dot keeps its outline.
    local border = outlines:CreateTexture(nil, "OVERLAY")
    border:SetTexture(ns.MEDIA .. "ring_small")
    border:SetSize(DOT_SIZE, DOT_SIZE)
    border:SetPoint("CENTER", bar, "CENTER")
    border:SetVertexColor(0, 0, 0)

    bars[i] = bar
end

-- Bear Form: the dots fill with Lacerate's stacks on the target. The count is secret in combat, so
-- our code never reads it. Each dot is its own AuraContainer (AuraContainer.lua) watching Lacerate:
-- dot 1 is on the button, which Blizzard shows while Lacerate is up at all; dots 2-5 are on a
-- StatusBar registered with button:SetApplicationBar(bar, { minApplications = n }), which Blizzard
-- shows only at n stacks or more (see docs/api-research.md, "Aura stacks"). Each dot's fill is a
-- vertical StatusBar Blizzard runs from the debuff's real time left: every stack shown drains top to
-- bottom together, and full again when a new stack refreshes it. Buttons can't be touched after setup, so
-- each carries its own fill (under the shared outlines above), and doesn't follow stealth mode.
-- Every rank's aura has its own ID: ranks 1-5 (checked on Wowhead's Forever data, 2026-11-23), and
-- whichever rank the player knows, added as it's learned, in case a rank changes.
local LACERATE = { ns.SPELL.LACERATE, 1328616, 414644, 1235826, 1235827 }
local CAN_COUNT = C_AuraContainerUtil and C_AuraContainerUtil.ProcessCustomAuraButtonApplicationBarOptions and true or false

local lacerate = ns.ComboRingGate(live) -- hidden outside Bear Form; carries the dots' Opacity

-- A stack's dot, centred on holder: a vertical StatusBar (0-1, full) that fills from the bottom, so
-- the level falls as its value does. Shared by the real dots and preview mode's stand-ins.
local function LacerateFill(holder)
    local fill = CreateFrame("StatusBar", nil, holder)
    fill:SetSize(DOT_SIZE - 2 * RING_THICKNESS, DOT_SIZE - 2 * RING_THICKNESS)
    fill:SetPoint("CENTER", holder, "CENTER")
    fill:SetFrameLevel(ns.hud:GetFrameLevel() + LACERATE_FILL_LEVEL) -- under the outlines, whatever its depth
    fill:SetOrientation("VERTICAL")
    fill:SetStatusBarTexture(RAGE_FILL) -- coloured, so untinted
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(1)
    return fill
end

local function AddLacerateDot(button, stacks)
    ns.HideAuraButtonArt(button)
    local holder = button
    if stacks > 1 then
        local bar = CreateFrame("StatusBar", nil, button) -- no fill texture: only whether it shows matters
        bar:SetAllPoints()
        local ok, err = pcall(button.SetApplicationBar, button, bar, { minApplications = stacks, maxApplications = COUNT })
        if not ok then
            ns.Debug("lacerate: stack", stacks, "bar refused:", err)
            bar:Hide()
            return
        end
        holder = bar
    end
    -- Full until Blizzard runs it with the aura's real (secret) timing; if it refuses, the dot
    -- still shows the stack, without the drain.
    local fill = LacerateFill(holder)
    local ok, err = pcall(button.SetDurationBar, button, fill, {
        interpolation = Enum.StatusBarInterpolation.Immediate,
        direction = Enum.StatusBarTimerDirection.RemainingTime,
    })
    if not ok then
        ns.Debug("lacerate: stack", stacks, "duration bar refused:", err)
    end
end

if ns.HAS_AURA_CONTAINER then
    local containers = {}
    for stacks = 1, CAN_COUNT and COUNT or 1 do
        local x, y = ns.ComboDotOffset(stacks)
        containers[stacks] = ns.CreateAuraContainer({
            label = "Lacerate " .. stacks,
            unit = "target",
            filter = "HARMFUL",
            spellIDs = LACERATE,
            width = DOT_SIZE,
            height = DOT_SIZE,
            x = x,
            y = y,
            level = LACERATE_LEVEL,
            parent = lacerate,
            initialize = function(button)
                AddLacerateDot(button, stacks)
            end,
        })
    end

    local ranks = CreateFrame("Frame")
    ranks:RegisterEvent("PLAYER_ENTERING_WORLD")
    ranks:RegisterEvent("SPELLS_CHANGED")
    ranks:SetScript("OnEvent", function()
        local known = ns.FindKnownSpell({ ns.SPELL.LACERATE })
        if known and not tContains(LACERATE, known) then
            LACERATE[#LACERATE + 1] = known
            for _, container in ipairs(containers) do
                container.SetSpellIDs(LACERATE)
            end
        end
    end)
end

-- Preview mode's state (Preview.lua), nil when live: a fixed count, the dots shown in every state
-- but Caster, and the rings' stand-ins in Cat and Bear (not Prowl: no DoTs before the opener).
local SAMPLE_POINTS = 3
local sampleState

-- Bear's preview: SAMPLE_POINTS stacks as the real dots draw them, all draining together over
-- Lacerate's duration and full again, in a loop (plain numbers here, so our code sets the value).
local LACERATE_DURATION = 15
local sampleStacks = CreateFrame("Frame", nil, sampleHolder)
sampleStacks:SetAllPoints()
sampleStacks:Hide()
local sampleFills = {}
for i = 1, SAMPLE_POINTS do
    local x, y = ns.ComboDotOffset(i)
    local holder = CreateFrame("Frame", nil, sampleStacks)
    holder:SetSize(DOT_SIZE, DOT_SIZE)
    holder:SetPoint("CENTER", group, "CENTER", x, y)
    sampleFills[i] = LacerateFill(holder)
end
local sampleStart = 0
sampleStacks:SetScript("OnShow", function()
    sampleStart = GetTime()
end)
sampleStacks:SetScript("OnUpdate", function()
    local left = 1 - ((GetTime() - sampleStart) % LACERATE_DURATION) / LACERATE_DURATION
    for _, fill in ipairs(sampleFills) do
        fill:SetValue(left)
    end
end)

-- Stealth mode: periwinkle fill (the black outlines stay).
local function StyleFills()
    local art = ns.IsStealthMode() and STEALTH_FILL or FILL
    for _, bar in ipairs(bars) do
        bar:SetStatusBarTexture(art)
    end
end
ns.OnStealthChanged(StyleFills)

-- Forever keeps classic per-target combo points: UnitPower doesn't reset on a target switch or
-- when the target dies (Blood in the Water, EllesmereUI). GetComboPoints reads the current target.
local function ReadPoints()
    if GetComboPoints then
        return GetComboPoints("player", "target") or 0
    end
    return UnitPower("player", Enum.PowerType.ComboPoints)
end

local function Update()
    if sampleState then
        group:SetShown(sampleState ~= "caster")
        local bear = sampleState == "bear"
        sampleStacks:SetShown(bear)
        for _, bar in ipairs(bars) do
            bar:SetValue(bear and 0 or SAMPLE_POINTS) -- in Bear the plain dots stay empty, as live
        end
        return
    end
    local powerType = UnitPowerType("player")
    local bear = powerType == Enum.PowerType.Rage
    group:SetShown(powerType == Enum.PowerType.Energy or bear)
    lacerate:SetShown(bear)

    local points = bear and 0 or ReadPoints() -- in Bear the plain dots stay empty, under Lacerate's
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
    name = L["Combo Points"],
    glyph = { kind = "dots", color = { 0.96, 0.77, 0.26 } },
    order = 0,
    hit = { kind = "circles", radius = DOT_SIZE / 2 - 2, centres = function() return centres end,
        visible = function() return group:IsVisible() end },
    options = {
        { key = "opacity", type = "slider", label = L["Opacity"], min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        for _, bar in ipairs(bars) do
            bar:SetAlpha(get("opacity") / 100)
        end
        outlines:SetAlpha(get("opacity") / 100)
        lacerate:SetAlpha(get("opacity") / 100)
        sampleStacks:SetAlpha(get("opacity") / 100)
    end,
    sample = function(state)
        sampleState = state
        StyleFills()
        live:SetShown(state == nil)
        sampleHolder:SetShown(state == "cat" or state == "bear")
        Update()
    end,
})
