-- Shifting Power cooldown: a four-segment arc under the swing ring that fills left to right over
-- the cooldown, each segment a quarter (4s, 3s or 2s), coloured blue, blue to white, white to
-- yellow, yellow. Each segment has a thin black outline; unfilled parts are clear inside it (a dim
-- copy of their colour was tried and dropped).
-- Each segment pulses briefly as it fills (at 4s, 8s, 12s of a 16s cooldown). At zero the arc
-- flashes and fades out, and in Cat Form a blue light pulses once inside the resource circle, if
-- your mana pays for a cast.
--
-- Growl's arc (GrowlArc.lua) shares the spot; it decides which shows (Growl in Bear Form, this one
-- otherwise) by hiding this arc's parent (ns.shiftingPowerArcGate). The clock keeps running
-- underneath, so the arc comes back where it should be; the ready pulse isn't in the gate and
-- still plays.
--
-- The arc is a SegmentedArc.lua arc timed by SegmentedCooldown.lua (our own clock from the cast,
-- length learned out of combat in CatnipDB.spLength: 16s, or 12s/8s with talents). Its segments
-- and gaps are drawn into sp_arc and sp_arc_outline (make_textures.py sp_arc_geometry, and
-- sp_colour colours each of the four), so changing the segment count means redrawing those too.
local addonName, ns = ...
local CreateFrame = ns.Profiled("ShiftingPower") -- timed by /catnip perf (Profiler.lua)

-- Geometry, in step with make_textures.py (SP_CANVAS, SP_SPAN): the arc textures are drawn on a
-- canvas CANVAS units across, centred on the HUD's centre.
local CANVAS = 164
local SEGMENTS = 4 -- drawn into the art
local SPAN = math.pi / 4.2 -- either side of 6 o'clock
local PULSE_COLOR = { 60 / 255, 150 / 255, 1 } -- the mana bar's blue, brightened
local PULSE_ADD = 1 -- an additive copy on top, for a brighter core
local PULSE_WASH = 0.3 -- a blue tint over the whole circle under the rim light
local PULSE_IN, PULSE_OUT = 0.01, 0.5 -- a quick pop (a 1.2s fade felt slow)

local hud = ns.hud

-- Both cooldown arcs' gates (this one's and GrowlArc.lua's) sit in this holder, at the HUD's own
-- level so the gates stay one above it. Preview mode hides it while its sample arcs show; the
-- clocks keep running.
local liveArcs = CreateFrame("Frame", nil, hud)
liveArcs:SetAllPoints()
liveArcs:SetFrameLevel(hud:GetFrameLevel())
ns.cooldownArcHolder = liveArcs

local arcGate = CreateFrame("Frame", nil, liveArcs)
arcGate:SetAllPoints()
ns.shiftingPowerArcGate = arcGate

local function ArcOptions(parent)
    return {
        parent = parent,
        size = CANVAS,
        level = 3, -- the gate is one above the HUD, so 4 above it as before
        art = "sp_arc",
        outline = "sp_arc_outline", -- a black rim around each segment, like the combo points
        outlineColor = { 0, 0, 0 }, -- in its own colours it read as a neon glow
        from = 1.5 * math.pi - SPAN, -- left end
        span = 2 * SPAN,
        segments = SEGMENTS, -- the gaps are in the art
    }
end

local arc = ns.CreateSegmentedArc(ArcOptions(arcGate))
ns.shiftingPowerArc = arc -- GrowlArc.lua watches it (onShownChanged)

-- Ready pulse ---------------------------------------------------------------------------------------

-- The pulse's animation drives its own alpha, so "only if mana pays for a cast" goes on a parent:
-- ShiftOrbs.lua sets the gate's alpha to 0 or 1 from a mana curve. Without the mana the
-- pulse still plays, unseen; it doesn't flash later when the mana arrives.
local gate = CreateFrame("Frame", nil, hud)
gate:SetAllPoints()
gate:SetFrameLevel(hud:GetFrameLevel() + 3)
ns.shiftingPowerPulseGate = gate

local pulse = CreateFrame("Frame", nil, gate)
pulse:SetSize(ns.RESOURCE_SIZE, ns.RESOURCE_SIZE)
pulse:SetPoint("CENTER", hud)
pulse:SetFrameLevel(hud:GetFrameLevel() + 3) -- over the resource fill, under its number
pulse:Hide()

local function GlowLayer(file, blendMode, alpha, sublevel)
    local glow = pulse:CreateTexture(nil, "ARTWORK", nil, sublevel)
    glow:SetTexture(ns.MEDIA .. file)
    glow:SetAllPoints(pulse)
    glow:SetVertexColor(PULSE_COLOR[1], PULSE_COLOR[2], PULSE_COLOR[3], alpha)
    glow:SetBlendMode(blendMode)
end
GlowLayer("circle_feather", "BLEND", PULSE_WASH, 0) -- same soft edge as the resource fill
GlowLayer("rim_glow", "BLEND", 1, 1)
GlowLayer("rim_glow", "ADD", PULSE_ADD, 2)

local pulseOnce = ns.PulseAnimation(pulse, 1, PULSE_IN, PULSE_OUT)
pulseOnce:SetScript("OnFinished", function()
    pulse:Hide()
end)

local function HidePulse()
    pulseOnce:Stop()
    pulse:Hide()
end

local arcEnabled = true -- the Cooldown Arc setting's Shifting Power switch (GrowlArc.lua)

local function PlayPulse()
    if not arcEnabled or not ns.ElementOption("under.arc", "readyPulse") then -- GrowlArc.lua's setting
        return -- turned off in the settings
    end
    pulseOnce:Stop()
    pulse:Show()
    pulseOnce:Play()
end

-- Timing --------------------------------------------------------------------------------------------

ns.CreateSegmentedCooldown({
    label = "Shifting Power",
    names = { "Shifting Power" },
    castNames = { ["Shifting Power"] = true },
    defaultLength = 16,
    arc = arc,
    command = "sp", -- /catnip sp [seconds]
    onStart = HidePulse,
    onHide = HidePulse,
    onReady = function(animate)
        if animate and UnitPowerType("player") == Enum.PowerType.Energy then -- Cat Form only
            PlayPulse()
        end
    end,
})

-- Preview mode and settings -------------------------------------------------------------------------

-- A copy of the arc that preview mode runs in a loop (ns.ArcSampler), 2s a segment, with the
-- ready pulse at the end, while the real one (in liveArcs) is hidden.
local SAMPLE_SECONDS = 8
local sampleGate = CreateFrame("Frame", nil, hud)
sampleGate:SetAllPoints()
local sampleArc = ns.CreateSegmentedArc(ArcOptions(sampleGate))
local StartSample, StopSample = ns.ArcSampler(sampleArc, SAMPLE_SECONDS, PlayPulse)

-- The arc's hit band: its 3.8-unit band at radius 71 and outline, with some room either side (the
-- swing ring ends at 66.5, the shift orbs start at 77.6).
ns.ARC_HIT = { inner = 67, outer = 76, angle = -math.pi / 2, spread = SPAN + 0.03 }

-- For GrowlArc.lua's combined "Cooldown Arc" setting: whether this arc shows (real or
-- sample), and its opacity (the gates' alpha: nothing else sets it; GrowlArc.lua only shows and
-- hides them).
function ns.ShiftingPowerArcShown()
    return arc.frame:IsVisible() or sampleArc.frame:IsVisible()
end

function ns.SetShiftingPowerArcOpacity(alpha)
    arcGate:SetAlpha(alpha)
    sampleGate:SetAlpha(alpha)
end

-- The setting's Shifting Power switch: off, the sample arc and the ready pulse don't show (the real
-- arc's gate is GrowlArc.lua's to show or hide). Its clock keeps running either way.
function ns.SetShiftingPowerArcEnabled(on)
    arcEnabled = on and true or false
    sampleGate:SetShown(arcEnabled)
    if not arcEnabled then
        HidePulse()
    end
end

-- Registered for its preview sample; its settings are the combined arc's (GrowlArc.lua).
ns.RegisterElement({
    id = "under.sp",
    zone = "under",
    name = "Shifting Power arc",
    hidden = true, -- offered as one setting with the Growl arc: "Cooldown Arc" (GrowlArc.lua)
    -- Cat Form and Caster run the sample (Shifting Power shows in both); Bear shows Growl's
    -- (GrowlArc.lua).
    sample = function(state)
        liveArcs:SetShown(state == nil)
        if state == "cat" or state == "caster" then
            StartSample()
        else
            StopSample()
        end
    end,
})
