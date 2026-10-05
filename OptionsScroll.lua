-- Scrollbars for the settings window (used by Options.lua). Our own rather than a Slider widget: a
-- vertical Slider ran the wrong way when dragged (reported 2026-10-04), so the thumb is a plain
-- frame and the drag maths is ours. The thumb is bevelled in the settings sliders' bronze, with a
-- grip, and lights up on hover and while held. Grabbing the thumb keeps it under the cursor where
-- it was taken; clicking the track glides there and keeps following while the button is held. The
-- mouse wheel glides too. Offsets are whole pixels, so text and boxes don't snap out of step.
--
-- ns.OptionsScroll(frame, child, step, gutter): a scrollbar (parented to `frame`, a ScrollFrame
-- showing `child`) plus mouse wheel scrolling of `step` pixels a notch. With `gutter`, the child
-- is made that much narrower than the frame while the bar shows, leaving it room. Returns a
-- scroller: `bar` (for the caller to anchor), Update() (after the frame or child changes size),
-- ScrollTo(offset, glide), Target() (where it is, or is gliding to).
local addonName, ns = ...

local function RGB(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end
-- Shared with the settings sliders (Options.lua): their groove and diamond thumb.
local TRACK = RGB(15, 16, 18)
local TRACK_EDGE = RGB(62, 51, 42)
local TRACK_HOVER = RGB(100, 86, 72)
local THUMB = RGB(141, 98, 66)
local THUMB_RIM = RGB(176, 128, 94)
local THUMB_EDGE = RGB(64, 47, 33)
-- The thumb lit up (hovered or held).
local THUMB_HOT = RGB(176, 125, 84)
local THUMB_RIM_HOT = RGB(222, 170, 124)

local WIDTH = 12
local MIN_THUMB = 24
local GLIDE_RATE = 18 -- how quickly a glide closes the gap: about a third of it each frame at 60 fps

-- Nested flat rectangles, outermost first ({ inset, colour }); returns the textures.
local function Bevel(frame, layer, layers)
    local textures = {}
    for i, part in ipairs(layers) do
        local texture = frame:CreateTexture(nil, layer, nil, i - 1)
        texture:SetPoint("TOPLEFT", part[1], -part[1])
        texture:SetPoint("BOTTOMRIGHT", -part[1], part[1])
        texture:SetColorTexture(unpack(part[2]))
        textures[i] = texture
    end
    return textures
end

function ns.OptionsScroll(frame, child, step, gutter)
    local scroller = {}
    local offset, target = 0, 0
    local thumbTop = 0 -- the thumb's distance below the bar's top
    local held -- while dragging: the cursor's distance below the thumb's top
    local smooth -- while dragging: glide after the cursor (a track click) rather than stick to it

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetWidth(WIDTH)
    bar:SetFrameLevel(frame:GetFrameLevel() + 20)
    bar:EnableMouse(true)
    bar:Hide()
    scroller.bar = bar
    local trackEdge = Bevel(bar, "BACKGROUND", { { 0, TRACK_EDGE }, { 1, TRACK } })[1]

    local thumb = CreateFrame("Frame", nil, bar) -- placed by Apply
    thumb:SetHeight(MIN_THUMB)
    thumb:EnableMouse(true)
    local thumbEdge, thumbRim, thumbFill = unpack(Bevel(thumb, "ARTWORK",
        { { 0, THUMB_EDGE }, { 1, THUMB_RIM }, { 2, THUMB } }))
    for i = -1, 1 do -- grip: three short lines across the middle
        local line = thumb:CreateTexture(nil, "OVERLAY")
        line:SetSize(6, 1)
        line:SetPoint("CENTER", 0, i * 3)
        line:SetColorTexture(unpack(THUMB_EDGE))
    end

    -- Lit while held, or while the mouse is over it (the track edge: over the bar).
    local function Paint()
        local hot = held or thumb:IsMouseOver()
        thumbRim:SetColorTexture(unpack(hot and THUMB_RIM_HOT or THUMB_RIM))
        thumbFill:SetColorTexture(unpack(hot and THUMB_HOT or THUMB))
        trackEdge:SetColorTexture(unpack((held or bar:IsMouseOver()) and TRACK_HOVER or TRACK_EDGE))
    end
    for _, region in ipairs({ bar, thumb }) do
        region:SetScript("OnEnter", Paint)
        region:SetScript("OnLeave", Paint)
    end

    local function MaxScroll()
        return math.max(0, child:GetHeight() - frame:GetHeight())
    end

    local function Travel()
        return math.max(0, bar:GetHeight() - thumb:GetHeight())
    end

    local function Apply(value)
        offset = value
        frame:SetVerticalScroll(math.floor(value + 0.5))
        local maxScroll = MaxScroll()
        thumbTop = maxScroll > 0 and math.floor(Travel() * math.min(1, value / maxScroll) + 0.5) or 0
        thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -thumbTop)
        thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -thumbTop)
    end

    -- Eases toward the target over a few frames. On its own frame, so it can't clash with dragging.
    local glider = CreateFrame("Frame", nil, bar)
    local function Glide(_, elapsed)
        local gap = target - offset
        if math.abs(gap) < 0.5 then
            Apply(target)
            glider:SetScript("OnUpdate", nil)
        else
            Apply(offset + gap * math.min(1, elapsed * GLIDE_RATE))
        end
    end

    function scroller.ScrollTo(value, glide)
        target = math.max(0, math.min(MaxScroll(), value))
        if glide then
            glider:SetScript("OnUpdate", Glide)
        else
            glider:SetScript("OnUpdate", nil)
            Apply(target)
        end
    end

    function scroller.Target()
        return target
    end

    -- Shows the bar only while there's something to scroll, and sizes the thumb to the share showing.
    function scroller.Update()
        local visible, total = frame:GetHeight(), child:GetHeight()
        local shown = visible > 0 and total > visible
        bar:SetShown(shown)
        if gutter then
            child:SetWidth(frame:GetWidth() - (shown and gutter or 0))
        end
        if shown then
            thumb:SetHeight(math.max(MIN_THUMB, math.floor(bar:GetHeight() * visible / total)))
        end
        target = math.min(target, MaxScroll())
        Apply(math.min(offset, MaxScroll()))
    end

    local function Wheel(_, delta)
        scroller.ScrollTo(target - delta * step, true)
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", Wheel)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", Wheel)

    -- Dragging ---------------------------------------------------------------------------------------

    local function CursorY() -- below the bar's top
        local _, y = GetCursorPosition()
        return bar:GetTop() - y / bar:GetEffectiveScale()
    end

    -- Puts the thumb's top `held` above the cursor, as far as it goes.
    local function Follow()
        local travel = Travel()
        if travel > 0 then
            scroller.ScrollTo((CursorY() - held) / travel * MaxScroll(), smooth)
        end
    end

    local function StopDrag()
        bar:SetScript("OnUpdate", nil)
        held = nil
        Paint()
    end

    local function StartDrag(grab, glide)
        held, smooth = grab, glide
        Follow()
        bar:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then -- released somewhere we didn't hear about
                StopDrag()
            else
                Follow()
            end
        end)
        Paint()
    end

    -- The thumb: stays where it was grabbed. The track: the thumb glides to centre on the cursor.
    thumb:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            StartDrag(CursorY() - thumbTop, false)
        end
    end)
    bar:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            StartDrag(thumb:GetHeight() / 2, true)
        end
    end)
    thumb:SetScript("OnMouseUp", StopDrag)
    bar:SetScript("OnMouseUp", StopDrag)
    bar:SetScript("OnHide", StopDrag)

    return scroller
end

ns.OptionsScrollWidth = WIDTH
