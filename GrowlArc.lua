-- Growl cooldown: Shifting Power's arc (ShiftingPower.lua) in its spot under the swing ring, in
-- Growl's colours: four segments that fill left to right over the cooldown (2s each of ~8s), brown
-- through red to orange, each with a thin black outline. Each segment pulses as it fills; at zero
-- the arc flashes and fades out. In every form.
--
-- When both are cooling (should be rare), one arc shows: Growl in Bear Form, Shifting Power
-- otherwise (Cat Form and out of form). The other's gate (a parent frame) is hidden while the
-- winner shows, fade included; its clock keeps running, so it reappears at the right point if it's
-- still cooling. (It was a
-- ring around combo point 2 until 2026-10-04: Growl isn't pressed on cooldown, so it moved off the
-- rotation's dots. Over the top of the swing ring, its band crossed the combo point rings.)
--
-- Timed by SegmentedCooldown.lua like the others (CatnipDB.growlLength, learned from the first
-- cast). The art is make_textures.py's Shifting Power arc in Growl's colours (growl_arc), with
-- Shifting Power's own outline, so the two stay in step.
local addonName, ns = ...

local CANVAS = 164 -- as ShiftingPower.lua
local SPAN = math.pi / 4.2 -- either side of 6 o'clock

local gate = CreateFrame("Frame", nil, ns.cooldownArcHolder) -- ShiftingPower.lua's; preview mode hides it
gate:SetAllPoints()

local function ArcOptions(parent)
    return {
        parent = parent,
        size = CANVAS,
        level = 3, -- the gate is one above the HUD: level with Shifting Power's arc
        art = "growl_arc",
        outline = "sp_arc_outline", -- same shape
        outlineColor = { 0, 0, 0 },
        from = 1.5 * math.pi - SPAN, -- left end
        span = 2 * SPAN,
        segments = 4, -- drawn into the art
    }
end

local arc = ns.CreateSegmentedArc(ArcOptions(gate))

-- Priority ------------------------------------------------------------------------------------------

local spArc, spGate = ns.shiftingPowerArc, ns.shiftingPowerArcGate

-- The Cooldown Arc setting's switches (below): an arc switched off never shows, so the other has the
-- spot in every form; its clock keeps running, so it shows at the right point if switched back on.
local spEnabled, growlEnabled = true, true

local function UpdatePriority()
    local growlFirst = UnitPowerType("player") == Enum.PowerType.Rage -- Bear Form
    local spOn = spEnabled and spArc.frame:IsShown()
    local growlOn = growlEnabled and arc.frame:IsShown()
    local hideSp = not spEnabled or (growlFirst and growlOn)
    local hideGrowl = not growlEnabled or (not growlFirst and spOn)
    -- Animations pause under a hidden parent, so a fade there would never finish and the arc would
    -- stay "shown": a loser mid-fade just ends (its Hide calls back here to set the gates).
    if hideSp and spArc.IsFading() then
        spArc.Hide()
        return
    end
    if hideGrowl and arc.IsFading() then
        arc.Hide()
        return
    end
    spGate:SetShown(not hideSp)
    gate:SetShown(not hideGrowl)
end

arc.onShownChanged = UpdatePriority
spArc.onShownChanged = UpdatePriority

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") -- into and out of Bear Form
events:SetScript("OnEvent", UpdatePriority)

-- Timing --------------------------------------------------------------------------------------------

ns.CreateSegmentedCooldown({
    label = "Growl",
    names = { "Growl" },
    castNames = { ["Growl"] = true },
    defaultLength = 8, -- ~8s seen 2026-10-04 (Classic's 10s ran long); learned from the first cast
    command = "growl", -- /catnip growl [seconds]
    arc = arc,
})

-- Preview mode and settings -------------------------------------------------------------------------

-- A copy of the arc that preview mode loops (ns.ArcSampler) in Bear Form, 2s a segment, while the
-- real one is hidden with ShiftingPower.lua's holder.
local sampleGate = CreateFrame("Frame", nil, ns.hud)
sampleGate:SetAllPoints()
local sampleArc = ns.CreateSegmentedArc(ArcOptions(sampleGate))
local StartSample, StopSample = ns.ArcSampler(sampleArc, 8)

-- Registered for its preview sample; its settings are the combined arc's (below).
ns.RegisterElement({
    id = "under.growl",
    zone = "under",
    name = "Growl arc",
    hidden = true, -- offered as one setting with the Shifting Power arc: "Cooldown Arc" (below)
    sample = function(state)
        if state == "bear" then
            StartSample()
        else
            StopSample()
        end
    end,
})

-- Cooldown Arc, the arc under the ring as one setting: Shifting Power's and Growl's arcs share the
-- spot (one shows: Growl in Bear Form, Shifting Power otherwise), so one opacity covers whichever
-- is drawn, plus Shifting Power's ready pulse (owner, 2026-10-09). Picked on the HUD by the shared
-- band.
ns.RegisterElement({
    id = "under.arc",
    zone = "under",
    name = "Cooldown Arc",
    glyph = { kind = "arc", color = { 0.42, 0.66, 1 } },
    hit = { kind = "ring", inner = ns.ARC_HIT.inner, outer = ns.ARC_HIT.outer, angle = ns.ARC_HIT.angle,
        spread = ns.ARC_HIT.spread,
        visible = function()
            return ns.ShiftingPowerArcShown() or arc.frame:IsVisible() or sampleArc.frame:IsVisible()
        end },
    options = {
        { key = "shiftingPower", type = "checkbox", label = "Shifting Power", default = true },
        { key = "growl", type = "checkbox", label = "Growl", default = true },
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
        { key = "readyPulse", type = "checkbox", label = "Shifting Power ready pulse",
            default = true },
    },
    apply = function(get) -- the gates' alpha; UpdatePriority only shows and hides `gate`
        local alpha = get("opacity") / 100
        gate:SetAlpha(alpha)
        sampleGate:SetAlpha(alpha)
        ns.SetShiftingPowerArcOpacity(alpha)
        spEnabled, growlEnabled = get("shiftingPower") and true or false, get("growl") and true or false
        ns.SetShiftingPowerArcEnabled(spEnabled)
        sampleGate:SetShown(growlEnabled)
        UpdatePriority()
    end,
})
