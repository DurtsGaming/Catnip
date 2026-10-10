-- ns.CreateSegmentedArc(options): an arc (or full ring) of segments that fills from one end to the
-- other over a duration (or starts full and empties), then flashes and fades out. Used by
-- ShiftingPower.lua, GrowlArc.lua, CooldownRings.lua and OmenRing.lua; SegmentedCooldown.lua times
-- the cooldown ones.
--
-- Since 2026-10-10 the arc is a radial StatusBar (RadialBar.lua) showing coloured art that stays put
-- (its colour is baked by angle, its segments and gaps drawn in). Blizzard times it from a duration
-- object, exact even when the timing is secret in combat, with no Lua running per frame. Until then
-- each segment was a copy of the art masked to a wedge by two rotated half_plane masks, moved every
-- frame by our own clock; the segments pulsed as they filled, which can't be timed in combat, so the
-- pulses were dropped with it (owner, 2026-10-10).
--
-- options:
--   parent, size (the canvas, a square centred on parent's centre plus x, y), level (above parent)
--   art          coloured texture file in media/, segments and gaps drawn in
--   from, span   start angle and length, radians (maths angles: counter-clockwise from 3 o'clock)
--   clockwise    fill direction from `from`
--   outline      optional texture file drawn under everything, always shown while the arc is
--   outlineColor optional { r, g, b } tint for the outline ({ 0, 0, 0 } for a black rim)
--   drain        start full and empty instead, the empty part growing from `from`
--   noFlash      at the end just hide, without flashing the whole arc
--
-- arc.Start(duration) shows it running over a duration object (ns.Duration for plain numbers);
-- arc.SetDuration(duration) changes the timing of a running arc; arc.Finish() ends it (full, or
-- empty when draining), flashes and fades; arc.Hide(); arc.IsFading(); arc.SetArt(art) swaps the
-- art, even mid-run (ComboRings.lua's segment shapes). arc.onShownChanged(shown), if set, is called
-- when the arc itself shows or hides (its fade-out included), whatever its parents are doing:
-- GrowlArc.lua decides which of two arcs shows from it.
local addonName, ns = ...
local CreateFrame = ns.Profiled("SegmentedArc") -- timed by /catnip perf (Profiler.lua)

local FADE_OUT = 0.45

local function AlphaAnimation(region, from, to, duration, smoothing)
    local group = region:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(from)
    fade:SetToAlpha(to)
    fade:SetDuration(duration)
    fade:SetSmoothing(smoothing)
    return group
end

-- A quick rise and fall; returns the group.
function ns.PulseAnimation(region, peak, rise, fall)
    local group = region:CreateAnimationGroup()
    local up = group:CreateAnimation("Alpha")
    up:SetFromAlpha(0)
    up:SetToAlpha(peak)
    up:SetDuration(rise)
    up:SetSmoothing("OUT")
    up:SetOrder(1)
    local down = group:CreateAnimation("Alpha")
    down:SetFromAlpha(peak)
    down:SetToAlpha(0)
    down:SetDuration(fall)
    down:SetSmoothing("IN")
    down:SetOrder(2)
    return group
end

-- A one-shot effect on an additive texture: shown only while its animation plays. Leaving it to
-- the animation to put the alpha back left the ready flash stuck at 70% over the next cooldown
-- (seen 2026-10-03), so the texture is hidden outright whenever the animation isn't running.
-- Returns play and stop functions.
local function OneShot(texture, group)
    texture:Hide()
    group:SetScript("OnFinished", function()
        texture:Hide()
    end)
    local function Play()
        group:Stop()
        texture:Show()
        group:Play()
    end
    local function Stop()
        group:Stop()
        texture:Hide()
    end
    return Play, Stop
end

function ns.CreateSegmentedArc(options)
    local art = options.art
    local clockwise = options.clockwise and true or false
    local fill = not options.drain

    local frame = CreateFrame("Frame", nil, options.parent)
    frame:SetSize(options.size, options.size)
    frame:SetPoint("CENTER", options.parent, "CENTER", options.x or 0, options.y or 0)
    frame:SetFrameLevel(options.parent:GetFrameLevel() + (options.level or 4))
    frame:Hide()

    if options.outline then
        local outline = frame:CreateTexture(nil, "BORDER")
        outline:SetTexture(ns.MEDIA .. options.outline)
        outline:SetAllPoints(frame)
        if options.outlineColor then
            outline:SetVertexColor(unpack(options.outlineColor))
        end
    end

    local bar, texture = ns.CreateRadialBar(frame, art)
    ns.ShapeRadialBar(texture, options.from, options.span, fill, clockwise)

    -- Brightens the whole arc as it fades out. On its own frame above the bar, so it draws over it.
    local flashLayer = CreateFrame("Frame", nil, frame)
    flashLayer:SetAllPoints()
    flashLayer:SetFrameLevel(bar:GetFrameLevel() + 1)
    local flash = flashLayer:CreateTexture(nil, "OVERLAY")
    flash:SetTexture(ns.MEDIA .. art)
    flash:SetAllPoints()
    flash:SetBlendMode("ADD")
    local playFlash, stopFlash = OneShot(flash, AlphaAnimation(flash, 0.7, 0, FADE_OUT, "OUT"))

    local fadeOut = AlphaAnimation(frame, 1, 0, FADE_OUT, "IN")

    local arc = { frame = frame }

    local function SetShown(shown)
        if frame:IsShown() == shown then
            return
        end
        frame:SetShown(shown)
        if arc.onShownChanged then
            arc.onShownChanged(shown)
        end
    end

    fadeOut:SetScript("OnFinished", function()
        stopFlash() -- the flash may have a frame left; it mustn't be paused mid-fade while hidden
        SetShown(false)
    end)

    function arc.SetDuration(duration)
        ns.RunRadialBar(bar, duration, fill)
    end

    function arc.Start(duration)
        fadeOut:Stop()
        stopFlash()
        frame:SetAlpha(1)
        arc.SetDuration(duration)
        SetShown(true)
    end

    function arc.SetArt(newArt)
        if newArt == art then
            return
        end
        art = newArt
        texture:SetTexture(ns.MEDIA .. art)
        flash:SetTexture(ns.MEDIA .. art)
    end

    function arc.IsFading()
        return fadeOut:IsPlaying()
    end

    function arc.Hide()
        fadeOut:Stop()
        stopFlash()
        SetShown(false)
    end

    -- Ends it (full, or empty when draining), flashes the whole arc and fades out.
    function arc.Finish()
        ns.SetRadialBarValue(bar, fill and 1 or 0)
        if options.noFlash then
            arc.Hide()
            return
        end
        playFlash()
        fadeOut:Play()
    end

    return arc
end

-- Preview mode's looping run of an arc (a sample copy, not one a cooldown drives): runs over
-- `seconds`, finishes (flash and fade; onReady() is called then), rests, and starts again.
-- Returns Start() and Stop().
local SAMPLE_REST = 1.2 -- seconds between the finish and the next run, so the fade-out shows
function ns.ArcSampler(arc, seconds, onReady)
    local driver = CreateFrame("Frame")
    driver:Hide()
    local started, finishedAt
    local function Run()
        started, finishedAt = GetTime(), nil
        arc.Start(ns.Duration(started, seconds))
    end
    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        if finishedAt then
            if now - finishedAt >= SAMPLE_REST then
                Run()
            end
        elseif now - started >= seconds then
            finishedAt = now
            arc.Finish()
            if onReady then
                onReady()
            end
        end
    end)
    local function Start()
        Run()
        driver:Show()
    end
    local function Stop()
        driver:Hide()
        arc.Hide()
    end
    return Start, Stop
end
