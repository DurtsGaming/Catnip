-- Preview mode (docs/settings-plan.md): while the settings window is open on the Rotation tab, out
-- of combat and outside Edit Mode, the HUD's elements can be picked with the mouse. Every element
-- with a hit shape gets a faint Edit Mode blue outline; the one under the mouse (or under the mouse
-- in the settings tree) brightens and names itself in a tooltip; the one whose page is open is
-- Edit Mode's selected yellow. Clicking an element opens its page.
--
-- The HUD's circles and rings overlap, so one mouse catcher covers the whole HUD and works out
-- what's under the cursor from each element's hit shape (Elements.lua `hit`):
--   { kind = "circle", radius = r, x = 0, y = 0 } -- HUD units from the HUD's centre
--   { kind = "ring", inner = r1, outer = r2 }      -- a band round the HUD's centre
--     with angle = a, spread = s: only the part within s radians of maths angle a (counter-
--     clockwise from 3 o'clock; 6 o'clock is -pi/2), s under pi/2
--   { kind = "circles", radius = r, centres = function } -- several circles picked as one: centres()
--     returns the current { x, y } list (it may change, e.g. how many orbs show)
-- Circles and rings may have `visible = function` (pickable only while it returns true).
--   { kind = "text", region = fontString, anchor = frame, point = "TOP", y = 0 or function, chars = 10 }
-- A text's own rectangle can't be used: a FontString showing a secret value (the energy number)
-- has a secret size and position even out of combat, and maths on them errors (seen 2026-10-04).
-- So its box is our own frame at the text's anchor (`point` of `anchor`, the frame the text hangs
-- from, offset `y`), as tall as the element's Size option and `chars` characters wide (estimated).
-- It's pickable only while the text is shown. Texts are checked first, then circles from the
-- smallest, so the smaller thing on top wins.
local addonName, ns = ...

local hud = ns.hud
local BLUE = { 0.25, 0.65, 1 }
local GOLD = { 1, 0.82, 0 }
local IDLE_ALPHA = 0.4 -- outlines of elements not hovered or selected
local GLOW_ALPHA = 0.4 -- the additive copy that brightens a hovered outline, as in UnlockOverlay.lua
local TEXT_PAD = 4 -- around a text's box, for the hit and the outline
local CHAR_WIDTH = 0.55 -- a character's estimated width, as a fraction of the font size
local CATCHER_SIZE = 320 -- covers the HUD and the text under it

local atan2 = math.atan2 or atan2

local Preview = {}
ns.Preview = Preview

local wanted = false -- the settings window is showing the Rotation tab
local active = false
local selectedId, listHoverId, mouseHoverId

-- What the HUD shows while active: a sample state, not the game's. Each element with a `sample`
-- function draws it (sample(state)), and sample(nil) when preview ends puts back the real state.
-- Prowl also turns on stealth mode's look everywhere (ns.SetStealthPreview).
Preview.STATES = {
    { value = "cat", text = "Cat Form" },
    { value = "bear", text = "Bear Form" },
    { value = "caster", text = "Caster" }, -- shows a spell being cast
    { value = "prowl", text = "Prowl" },
}
local state = "cat"

-- Everything we draw goes on a layer above the HUD's elements, at full strength whatever the HUD's
-- opacity setting.
local layer = CreateFrame("Frame", nil, hud)
layer:SetAllPoints()
layer:SetFrameLevel(hud:GetFrameLevel() + 30)
if layer.SetIgnoreParentAlpha then
    layer:SetIgnoreParentAlpha(true)
end
layer:Hide()

local catcher = CreateFrame("Frame", nil, layer)
catcher:SetSize(CATCHER_SIZE, CATCHER_SIZE)
catcher:SetPoint("CENTER")
catcher:SetFrameLevel(layer:GetFrameLevel() + 10)
catcher:EnableMouse(false) -- only while over an element (SetMouseHover), so clicks and camera
-- turning elsewhere on the HUD's square still reach the world

-- Highlights ---------------------------------------------------------------------------------------

-- Circle: a soft disc with a ring at its edge, tinted blue, or gold when selected.
local function CircleHighlight(hit)
    local frame = CreateFrame("Frame", nil, layer)
    local size = 2 * hit.radius + 4
    frame:SetSize(size, size)
    frame:SetPoint("CENTER", hud, "CENTER", hit.x or 0, hit.y or 0)
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(ns.MEDIA .. "circle_feather")
    fill:SetAllPoints()
    local edge = frame:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(ns.MEDIA .. "ring_thin")
    edge:SetAllPoints()
    function frame.SetState(state)
        local colour = state == "selected" and GOLD or BLUE
        fill:SetVertexColor(colour[1], colour[2], colour[3], state == "idle" and 0.15 or 0.3)
        edge:SetVertexColor(colour[1], colour[2], colour[3], 1)
        frame:SetAlpha(state == "idle" and IDLE_ALPHA or 1)
    end
    return frame
end

-- Circles: CircleHighlight's look on each centre, re-placed on every refresh (Place).
local function CirclesHighlight(hit)
    local frame = CreateFrame("Frame", nil, layer)
    frame:SetAllPoints(hud)
    local pool = {}
    function frame.Place()
        local centres = hit.centres()
        for i, centre in ipairs(centres) do
            local circle = pool[i]
            if not circle then
                circle = CircleHighlight({ radius = hit.radius })
                circle:SetParent(frame)
                pool[i] = circle
            end
            circle:ClearAllPoints()
            circle:SetPoint("CENTER", hud, "CENTER", centre[1], centre[2])
            circle:Show()
        end
        for i = #centres + 1, #pool do
            pool[i]:Hide()
        end
    end
    function frame.SetState(state)
        for _, circle in ipairs(pool) do
            circle.SetState(state)
        end
        frame:SetAlpha(1) -- each circle sets its own
    end
    return frame
end

-- Ring: the band filled (ring_bar, the swing ring's band, sized so its outer edge is `outer`) with
-- thin rings at both edges, tinted blue, or gold when selected.
local RING_BAR_OUTER = 127 / 256 -- ring_bar's band reaches this far out on its canvas (Swing.lua)
local function RingHighlight(hit)
    local frame = CreateFrame("Frame", nil, layer)
    frame:SetAllPoints(hud)
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(ns.MEDIA .. "ring_bar")
    local fillSize = hit.outer / RING_BAR_OUTER
    fill:SetSize(fillSize, fillSize)
    fill:SetPoint("CENTER")
    local edges = {}
    for i, radius in ipairs({ hit.inner, hit.outer }) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        edge:SetTexture(ns.MEDIA .. "ring_thin")
        edge:SetSize(2 * radius + 2, 2 * radius + 2)
        edge:SetPoint("CENTER")
        edges[i] = edge
    end
    -- A part ring: everything masked to the wedge between angle - spread and angle + spread, by two
    -- half_plane masks (SegmentedArc.lua's technique; half_plane shows its left half and
    -- SetRotation turns it counter-clockwise).
    if hit.angle then
        local function Mask(rotation)
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(ns.MEDIA .. "half_plane", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(frame)
            mask:SetRotation(rotation)
            return mask
        end
        local from, to = hit.angle - hit.spread, hit.angle + hit.spread
        local above = Mask(from - math.pi / 2) -- shows from .. from + 180 degrees
        local below = Mask(to - 3 * math.pi / 2) -- shows to - 180 degrees .. to
        for _, texture in ipairs({ fill, edges[1], edges[2] }) do
            texture:AddMaskTexture(above)
            texture:AddMaskTexture(below)
        end
    end
    function frame.SetState(state)
        local colour = state == "selected" and GOLD or BLUE
        fill:SetVertexColor(colour[1], colour[2], colour[3], state == "idle" and 0.15 or 0.35)
        for _, edge in ipairs(edges) do
            edge:SetVertexColor(colour[1], colour[2], colour[3], 1)
        end
        frame:SetAlpha(state == "idle" and IDLE_ALPHA or 1)
    end
    return frame
end

-- Text: Edit Mode's own nine-slice around the text's box, blue (with an additive copy on hover) or
-- yellow. The frame is the box (see the top of the file), re-placed on every refresh, since the
-- size and offsets follow settings.
local function TextHighlight(hit, element)
    local frame = CreateFrame("Frame", nil, layer)
    function frame.Place()
        local size = ns.ElementOption(element.id, "size") or 14
        local y = type(hit.y) == "function" and hit.y() or hit.y or 0
        if hit.point:find("TOP") then
            y = y + TEXT_PAD
        elseif hit.point:find("BOTTOM") then
            y = y - TEXT_PAD
        end
        frame:SetSize(hit.chars * size * CHAR_WIDTH + 2 * TEXT_PAD, size + 2 * TEXT_PAD)
        frame:ClearAllPoints()
        frame:SetPoint(hit.point, hit.anchor, hit.point, 0, y)
    end
    local blue = CreateFrame("Frame", nil, frame)
    blue:SetAllPoints()
    ns.ApplyEditModeLook(blue)
    local glow = CreateFrame("Frame", nil, frame)
    glow:SetAllPoints()
    ns.ApplyEditModeLook(glow)
    for _, region in ipairs({ glow:GetRegions() }) do
        if region.SetBlendMode then
            region:SetBlendMode("ADD")
        end
    end
    glow:SetAlpha(GLOW_ALPHA)
    local yellow = CreateFrame("Frame", nil, frame)
    yellow:SetAllPoints()
    ns.ApplyEditModeLook(yellow, true)
    function frame.SetState(state)
        blue:SetShown(state ~= "selected")
        glow:SetShown(state == "hover")
        yellow:SetShown(state == "selected")
        frame:SetAlpha(state == "idle" and IDLE_ALPHA or 1)
    end
    return frame
end

-- The pickable elements, in hit-test order: { element, highlight }. Built on first use, after
-- every module has registered.
local targets

local function Targets()
    if targets then
        return targets
    end
    targets = {}
    for _, element in ipairs(ns.elements) do
        local hit = element.hit
        if hit then
            local highlight
            if hit.kind == "circle" then
                highlight = CircleHighlight(hit)
            elseif hit.kind == "circles" then
                highlight = CirclesHighlight(hit)
            elseif hit.kind == "ring" then
                highlight = RingHighlight(hit)
            else
                highlight = TextHighlight(hit, element)
            end
            targets[#targets + 1] = { element = element, highlight = highlight, order = #targets }
        end
    end
    -- Texts first, then by how far out the shape reaches; ties keep registration order.
    local function Reach(target)
        local hit = target.element.hit
        return hit.kind == "text" and 0 or hit.outer or hit.radius
    end
    table.sort(targets, function(a, b)
        local ra, rb = Reach(a), Reach(b)
        if ra ~= rb then
            return ra < rb
        end
        return a.order < b.order
    end)
    return targets
end

-- Whether a target is on screen: a text only while it (and its frame) is shown; others while
-- their `visible` says so, if they have one.
local function Visible(target)
    local hit = target.element.hit
    if hit.kind == "text" then
        return hit.region:IsVisible()
    end
    return not hit.visible or hit.visible() and true or false
end

-- Hit testing --------------------------------------------------------------------------------------

local function Contains(target)
    local hit = target.element.hit
    if hit.kind == "text" then
        return target.highlight:IsMouseOver()
    end
    local scale = hud:GetEffectiveScale()
    local cx, cy = hud:GetCenter()
    local x, y = GetCursorPosition()
    if hit.kind == "circles" then
        local r2 = hit.radius * hit.radius
        for _, centre in ipairs(hit.centres()) do
            local dx, dy = x / scale - cx - centre[1], y / scale - cy - centre[2]
            if dx * dx + dy * dy <= r2 then
                return true
            end
        end
        return false
    end
    local dx, dy = x / scale - cx - (hit.x or 0), y / scale - cy - (hit.y or 0)
    local distance = dx * dx + dy * dy
    if hit.kind == "ring" then
        if distance < hit.inner * hit.inner or distance > hit.outer * hit.outer then
            return false
        end
        if not hit.angle then
            return true
        end
        local off = (atan2(dy, dx) - hit.angle + math.pi) % (2 * math.pi) - math.pi -- -pi .. pi
        return math.abs(off) <= hit.spread
    end
    return distance <= hit.radius * hit.radius
end

-- The element under the cursor, or nil.
local function HitTest()
    if not catcher:IsMouseOver() then
        return nil
    end
    for _, target in ipairs(Targets()) do
        if Visible(target) and Contains(target) then
            return target.element
        end
    end
end

-- Drawing ------------------------------------------------------------------------------------------

local function Refresh()
    local hoverId = listHoverId or mouseHoverId
    for _, target in ipairs(Targets()) do
        local id = target.element.id
        local state = id == selectedId and "selected" or id == hoverId and "hover" or "idle"
        if target.highlight.Place then
            target.highlight.Place()
        end
        target.highlight.SetState(state)
        target.highlight:SetShown(Visible(target))
    end
end

local function SetMouseHover(element)
    local id = element and element.id
    if id == mouseHoverId then
        return
    end
    mouseHoverId = id
    catcher:EnableMouse(element ~= nil)
    if element then
        GameTooltip:SetOwner(catcher, "ANCHOR_CURSOR")
        GameTooltip:SetText(element.name)
        GameTooltip:AddLine("Click to edit", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    elseif GameTooltip:IsOwned(catcher) then
        GameTooltip:Hide()
    end
    Refresh()
end

-- Each frame while active: what's under the mouse, and whether texts have come or gone.
layer:SetScript("OnUpdate", function()
    SetMouseHover(HitTest())
    Refresh()
end)

catcher:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and mouseHoverId then
        ns.OpenElementSettings(mouseHoverId)
    end
end)

-- Samples ------------------------------------------------------------------------------------------

-- Draws `to` (a state, or nil for the real one) on every element.
local function ApplySamples(to)
    for _, element in ipairs(ns.elements) do
        if element.sample then
            element.sample(to)
        end
    end
    if to then
        ns.SetStealthPreview(to == "prowl")
    else
        ns.SetStealthPreview(nil)
    end
end

-- The state matching what the player is in now, to start the preview from.
local function CurrentState()
    if ns.IsStealthMode() then
        return "prowl"
    end
    local powerType = UnitPowerType("player")
    if ns.IsSecret(powerType) then
        return "cat"
    end
    if powerType == Enum.PowerType.Energy then
        return "cat"
    elseif powerType == Enum.PowerType.Rage then
        return "bear"
    end
    return "caster"
end

local function ListHas(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

-- On and off ---------------------------------------------------------------------------------------

-- Edit Mode (Blizzard's or Catnip's) owns the HUD's mouse while it's open.
local function Editing()
    return (ns.IsHudUnlocked and ns.IsHudUnlocked())
        or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

-- From the events: PLAYER_REGEN_DISABLED fires just before InCombatLockdown() turns true.
local inCombat = false

-- Switches to `to` (drawn now if active) and tells the settings window (Preview.onStateChanged).
local function SetState(to)
    if to == state then
        return
    end
    state = to
    if active then
        ApplySamples(state)
    end
    if Preview.onStateChanged then
        Preview.onStateChanged()
    end
end

-- If `states` (an element's or option's list of states it shows in) doesn't have the current one,
-- switches to its first.
local function FitStates(states)
    if states and not ListHas(states, state) then
        SetState(states[1])
    end
end

local function FitSelected()
    local element = selectedId and ns.GetElement(selectedId)
    FitStates(element and element.states)
end

local function Update()
    local now = wanted and not inCombat and not InCombatLockdown() and not Editing()
    if now == active then
        return
    end
    if now then
        SetState(CurrentState()) -- before turning on, so it's read from the game
        FitSelected()
    end
    active = now
    if not now then
        SetMouseHover(nil)
    end
    ApplySamples(now and state or nil)
    layer:SetShown(now)
    if now then
        Refresh()
    end
end

-- While wanted, Edit Mode opening or closing is noticed by polling (no event for Catnip's own).
local poll = CreateFrame("Frame")
poll:Hide()
local sincePoll = 0
poll:SetScript("OnUpdate", function(_, elapsed)
    sincePoll = sincePoll + elapsed
    if sincePoll >= 0.25 then
        sincePoll = 0
        Update()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    Update()
end)

-- The settings window calls these (Options.lua).
function Preview.SetWanted(on)
    wanted = on and true or false
    poll:SetShown(wanted)
    Update()
end

-- The element whose page is open (nil for none, or one without a hit shape).
-- Switches the sample state if that element doesn't show in the current one (Cast time: Caster).
function Preview.SetSelected(id)
    selectedId = id
    FitSelected()
    if active then
        Refresh()
    end
end

-- The sample state, and choosing one (the "Preview as" control).
function Preview.GetState()
    return state
end

function Preview.SetState(to)
    SetState(to)
end

-- An option was changed: switch to a state where its effect shows, if it lists any.
function Preview.FitStates(states)
    FitStates(states)
end

-- The element whose row the mouse is over in the settings tree, or nil.
function Preview.SetListHover(id)
    listHoverId = id
    if active then
        Refresh()
    end
end

function Preview.IsActive()
    return active
end
