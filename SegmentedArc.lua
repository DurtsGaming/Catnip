-- ns.CreateSegmentedArc(options): an arc (or full ring) of segments that fills from one end to the
-- other, each segment pulsing as it fills, then flashing and fading out. Visuals only; the timing is
-- SegmentedCooldown.lua's. Used by ShiftingPower.lua and CooldownRings.lua.
--
-- The art is a coloured ring texture that stays put (its colour is baked by angle). Each segment is
-- a copy of it masked to a wedge by two half_plane masks, rotated so their edges sit at the
-- segment's ends: the intersection of two half planes is a wedge under 180 degrees. The fill moves
-- one of those edges. So the segment count is just a number here, and the gaps between segments
-- can be cut here too (options.gap), on a plain ring; or the art can have them drawn in already
-- (Shifting Power's sp_arc), with gap = 0 so the wedges meet in the middle of its gaps.
--
-- options:
--   parent, size (the canvas, a square centred on parent's centre plus x, y), level (above parent)
--   art          coloured texture file in media/
--   from, span   start angle and length, radians (maths angles: counter-clockwise from 3 o'clock)
--   clockwise    fill direction from `from`
--   segments     how many; each must span under 180 degrees
--   gap          radians cut out at each segment boundary (and both outer ends), default 0
--   outline      optional texture file drawn under everything, always shown while the arc is
--   outlineColor optional { r, g, b } tint for the outline ({ 0, 0, 0 } for a black rim)
--   track        optional alpha for a dim copy of each segment, so empty ones still show
--   drain        start full and empty instead: the front eats each segment from its start, and
--                as each segment empties the next one pulses (not the last one left)
--   noFlash      at the end just hide, without flashing the whole arc
--
-- arc.SetArt(art, gap) swaps the art and gap, even mid-run (ComboRings.lua's segment shapes).
-- arc.onShownChanged(shown), if set, is called when the arc itself shows or hides (its fade-out
-- included), whatever its parents are doing: GrowlArc.lua decides which of two arcs shows from it.
local addonName, ns = ...
local CreateFrame = ns.Profiled("SegmentedArc") -- timed by /catnip perf (Profiler.lua)

local HALF_PI = math.pi / 2
local SEGMENT_PULSE = 0.55 -- peak brightness of the small pulse as each segment fills
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
    local count = options.segments
    local dir = options.clockwise and -1 or 1
    local gap = options.gap or 0
    local art = options.art
    assert(options.span / count < math.pi, "SegmentedArc: each segment must span under 180 degrees")

    local frame = CreateFrame("Frame", nil, options.parent)
    frame:SetSize(options.size, options.size)
    frame:SetPoint("CENTER", options.parent, "CENTER", options.x or 0, options.y or 0)
    frame:SetFrameLevel(options.parent:GetFrameLevel() + (options.level or 4))
    frame:Hide()

    local arts = {} -- every copy of the art, for SetArt
    local function Art(layer, sublevel)
        local texture = frame:CreateTexture(nil, layer, nil, sublevel)
        arts[#arts + 1] = texture
        texture:SetTexture(ns.MEDIA .. art)
        texture:SetAllPoints(frame)
        return texture
    end

    if options.outline then
        local outline = frame:CreateTexture(nil, "BORDER")
        outline:SetTexture(ns.MEDIA .. options.outline)
        outline:SetAllPoints(frame)
        if options.outlineColor then
            outline:SetVertexColor(unpack(options.outlineColor))
        end
    end

    -- half_plane shows its left half (maths angles 90-270 degrees); SetRotation turns it
    -- counter-clockwise. An edge mask shows everything on the segment's side of `angle`.
    local function EdgeMask()
        local mask = frame:CreateMaskTexture()
        mask:SetTexture(ns.MEDIA .. "half_plane", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(frame)
        return mask
    end
    local function ShowAbove(mask, angle) -- shows angle .. angle + 180 degrees
        mask:SetRotation(angle - HALF_PI)
    end
    local function ShowBelow(mask, angle) -- shows angle - 180 degrees .. angle
        mask:SetRotation(angle - 3 * HALF_PI)
    end
    -- A segment's start edge has the segment above it when filling counter-clockwise.
    local SetStart = dir == 1 and ShowAbove or ShowBelow
    local SetEnd = dir == 1 and ShowBelow or ShowAbove

    local function Angle(progress)
        return options.from + dir * options.span * progress
    end

    local segments = {}
    local flashStops, pulseStops = {}, {}
    local flashPlays = {}
    for i = 1, count do
        local startMask, endMask, front = EdgeMask(), EdgeMask(), EdgeMask()
        local segment = { startMask = startMask, endMask = endMask } -- its ends are set by Cut
        -- Filling, the front is the visible part's end; draining, its start.
        local function Wedge(texture, toFront)
            texture:AddMaskTexture(toFront and options.drain and front or startMask)
            texture:AddMaskTexture(toFront and not options.drain and front or endMask)
            return texture
        end

        if options.track then
            Wedge(Art("BORDER", 1)):SetAlpha(options.track)
        end
        segment.fill = Wedge(Art("ARTWORK"), true)
        segment.front = front

        -- Draining, the pulsing segment is already shrinking, so the pulse follows the front too
        -- (a whole-segment pulse left a ghost of the part already gone).
        local pulse = Wedge(Art("OVERLAY"), options.drain)
        pulse:SetBlendMode("ADD")
        segment.pulse, pulseStops[i] = OneShot(pulse, ns.PulseAnimation(pulse, SEGMENT_PULSE, 0.08, 0.35))

        local flash = Wedge(Art("OVERLAY", 1)) -- brightens the full arc as it fades out
        flash:SetBlendMode("ADD")
        flashPlays[i], flashStops[i] = OneShot(flash, AlphaAnimation(flash, 0.7, 0, FADE_OUT, "OUT"))

        segments[i] = segment
    end

    -- Sets each segment's ends, `gap` apart at the boundaries.
    local function Cut()
        for i, segment in ipairs(segments) do
            segment.startAngle = Angle((i - 1) / count) + dir * gap / 2
            segment.endAngle = Angle(i / count) - dir * gap / 2
            SetStart(segment.startMask, segment.startAngle)
            SetEnd(segment.endMask, segment.endAngle)
        end
    end
    Cut()

    local fadeOut = AlphaAnimation(frame, 1, 0, FADE_OUT, "IN")

    local function StopEffects()
        for i = 1, count do
            flashStops[i]()
            pulseStops[i]()
        end
    end

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
        StopEffects() -- the flash may have a frame left; it mustn't be paused mid-fade while hidden
        SetShown(false)
    end)

    local filled = 0 -- segments done so far (full, or empty when draining), for their pulses
    local drawn = 0 -- the progress last drawn, for SetArt
    local shares = {} -- each segment's share as last drawn

    -- progress 0-1. Each segment fills (or empties) over its own share of the time, edge to edge,
    -- so it's full (or empty) exactly as its share ends.
    -- The clock calls this every frame, so it only touches the segments whose share changed
    -- (usually just the one at the front), and nothing while the arc can't be seen (its slot or
    -- gate hidden): the next call once it shows catches up. `force` redraws every segment, for
    -- when the arc is about to show or its ends moved.
    local function Draw(progress, force)
        drawn = progress
        if not force and not frame:IsVisible() then
            return
        end
        for i, segment in ipairs(segments) do
            local share = math.min(math.max(progress * count - (i - 1), 0), 1)
            if force or share ~= shares[i] then
                shares[i] = share
                local frontAngle = segment.startAngle + (segment.endAngle - segment.startAngle) * share
                if options.drain then
                    segment.fill:SetShown(share < 1)
                    SetStart(segment.front, frontAngle)
                else
                    segment.fill:SetShown(share > 0)
                    SetEnd(segment.front, frontAngle)
                end
            end
        end
    end

    -- Moves the front. Filling, each segment pulses as it fills (the last one gets the flash
    -- instead); draining, the next one pulses as one empties, except the last one left.
    function arc.SetProgress(progress)
        progress = math.min(progress, 1)
        Draw(progress)
        local now = math.floor(progress * count)
        if now > filled then
            filled = now
            local pulsing = options.drain and now + 1 or now
            if pulsing < count then
                segments[pulsing].pulse()
            end
        end
    end

    -- Shows the arc at `progress`, without pulses for segments already full.
    function arc.Start(progress)
        fadeOut:Stop()
        StopEffects()
        frame:SetAlpha(1)
        progress = math.min(progress, 1)
        filled = math.floor(progress * count)
        Draw(progress, true)
        SetShown(true)
    end

    function arc.SetArt(newArt, newGap)
        if newArt == art and newGap == gap then
            return
        end
        art, gap = newArt, newGap
        for _, texture in ipairs(arts) do
            texture:SetTexture(ns.MEDIA .. art)
        end
        Cut()
        Draw(drawn, true)
    end

    function arc.IsFading()
        return fadeOut:IsPlaying()
    end

    -- Ends it (full, or empty when draining), flashes the whole arc and fades out.
    function arc.Finish()
        Draw(1, true)
        if options.noFlash then
            arc.Hide()
            return
        end
        for i = 1, count do
            flashPlays[i]()
        end
        fadeOut:Play()
    end

    function arc.Hide()
        fadeOut:Stop()
        StopEffects()
        SetShown(false)
    end

    return arc
end

-- Preview mode's looping run of an arc (a sample copy, not one a cooldown drives): fills over
-- `seconds` with its pulses, finishes (flash and fade; onReady() is called then), rests, and
-- starts again. Returns Start() and Stop().
local SAMPLE_REST = 1.2 -- seconds between the finish and the next run, so the fade-out shows
function ns.ArcSampler(arc, seconds, onReady)
    local driver = CreateFrame("Frame")
    driver:Hide()
    local started, finishedAt
    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        if finishedAt then
            if now - finishedAt >= SAMPLE_REST then
                finishedAt, started = nil, now
                arc.Start(0)
            end
            return
        end
        local progress = (now - started) / seconds
        if progress >= 1 then
            finishedAt = now
            arc.Finish()
            if onReady then
                onReady()
            end
        else
            arc.SetProgress(progress)
        end
    end)
    local function Start()
        started, finishedAt = GetTime(), nil
        arc.Start(0)
        driver:Show()
    end
    local function Stop()
        driver:Hide()
        arc.Hide()
    end
    return Start, Stop
end
