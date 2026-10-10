-- Radial StatusBars: a StatusBar in radial render mode reveals its texture around its centre, over
-- any arc, and Blizzard times it from a duration object (SetTimerDuration), secret or not, with no
-- Lua running per frame. Used by SegmentedArc.lua (the cooldown arcs and rings) and Cast.lua.
--
-- How the client reads the settings (measured 2026-10-10, docs/api-research.md): the start offset
-- is where the bar is anchored, 0 = 6 o'clock running clockwise (0.5 = 12); the end offset is how
-- much of the turn is cut off, so the bar covers `1 - end` of it from the anchor: clockwise, or
-- counter-clockwise with SetRadialProgressBarReverse(true) (the arc is mirrored about its anchor;
-- verified 2026-10-10 on Growl's arc, which showed nothing while Reverse was taken to change only
-- the fill direction).
-- ElapsedTime grows the bar from the anchor; RemainingTime shrinks it back toward the anchor.
local addonName, ns = ...

local TWO_PI = 2 * math.pi

-- A radial bar on `parent` showing `art` (a file in media/), filling `parent`.
function ns.CreateRadialBar(parent, art, layer)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetAllPoints(parent)
    local texture = bar:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(ns.MEDIA .. art)
    texture:SetAllPoints(bar) -- unanchored, it has no size and nothing draws (seen 2026-10-10)
    bar:SetRenderMode(Enum.StatusBarRenderMode.Radial)
    bar:SetStatusBarTexture(texture)
    texture:SetRadialProgressBarFeather(0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar, texture
end

-- Shapes the bar as an arc whose moving edge starts at `from` (maths radians: counter-clockwise
-- from 3 o'clock) and runs `span` radians (2 pi: a full ring), clockwise or not. fill: the bar grows
-- behind the moving edge (else it starts full and the edge eats it). Filling, the bar is anchored
-- at `from` and grows along the way the edge moves; draining, it's anchored at the far end and
-- shrinks back toward it, so it runs the opposite way.
function ns.ShapeRadialBar(texture, from, span, fill, clockwise)
    local towardEdge = clockwise and -1 or 1 -- maths angles grow counter-clockwise
    local anchor, runsClockwise
    if fill then
        anchor, runsClockwise = from, clockwise
    else
        anchor, runsClockwise = from + towardEdge * span, not clockwise
    end
    texture:SetRadialProgressBarStartOffset(((-math.pi / 2 - anchor) / TWO_PI) % 1)
    texture:SetRadialProgressBarEndOffset(math.max(0, 1 - span / TWO_PI))
    texture:SetRadialProgressBarReverse(not runsClockwise)
end

-- Runs the bar over `duration` (a duration object), growing (fill) or shrinking, as shaped by
-- ns.ShapeRadialBar.
function ns.RunRadialBar(bar, duration, fill)
    bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        fill and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
end

-- Stops any timer and holds the bar at `value` (0 empty, 1 full), as ForeverAuras clears its bars.
local emptyDuration
function ns.SetRadialBarValue(bar, value)
    emptyDuration = emptyDuration or C_DurationUtil.CreateDuration()
    pcall(bar.SetTimerDuration, bar, emptyDuration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.RemainingTime)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(value)
end

-- A duration object for a plain-number timer (previews, the Omen ring's own clock).
function ns.Duration(start, seconds)
    local duration = C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(start, seconds)
    return duration
end
