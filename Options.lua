-- Settings window (/catnip), styled like WoW Forever's Professions frame: its frame, background
-- and panels (OptionsArt.lua), gold headers, Blizzard-style arrow sliders, and the same stock
-- checkboxes and red buttons as Catnip Edit Mode (EditMode.lua). Each control reads and writes
-- ns.db through the owning module's functions, and every control refreshes whenever
-- ns.SettingsChanged() fires (so slash commands and dragging in Edit Mode stay in sync).
--
-- Controls are grouped into tabs (and a tab can have sub-tabs); each tab is a page laid out top to
-- bottom. Pages sit in a scroll area, so the window can be resized smaller than its content: drag
-- the bottom-right corner (size saved in CatnipDB.optionsWidth/optionsHeight). Controls stretch to
-- the window's width.
local addonName, ns = ...

local art = ns.OptionsArt

local WIDTH = 320 -- default and minimum width; long hints are measured at this width
local DEFAULT_HEIGHT = 580
local MAX_WIDTH = 700
local MIN_HEIGHT = 200
local BORDER = 8 -- the frame's border
local HEADER = 20 -- room at the top of the scrolling contents, above the pages, for the Edit Mode
-- button and a page's bookmark sub-tabs (it scrolls with them); also keeps panels clear of the portrait
local PAD = 6 -- frame to a panel, and between panels (as in the Professions frame)
local PANEL_PAD = 12 -- panel edge to its controls
local CONTENT = WIDTH - 2 * (BORDER + PAD + PANEL_PAD) -- a panel's control width at the minimum window width
local TAB_HEIGHT = 24 -- bookmark sub-tabs, above the panel edge they stand on
-- Side tabs down the window's right edge, spaced as on Blizzard's Character window and starting as
-- far down as on the Professions window (measured from screenshots side by side, in UI units; the
-- tab art has clear space above and below, which neighbouring tabs overlap): the first
-- SIDE_TAB_TOP below the window's top, one every SIDE_TAB_STEP, tucked SIDE_TAB_TUCK under the
-- frame's right border.
local SIDE_TAB_TOP = 58
local SIDE_TAB_STEP = 57
local SIDE_TAB_TUCK = 2
local SCROLL_STEP = 40

local function RGB(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end
local WHITE = { 1, 1, 1, 1 }
local GOLD = { 1, 0.82, 0, 1 } -- GameFontNormal
local MUTED = RGB(163, 154, 138)
local BRONZE = RGB(125, 102, 52)
local BRONZE_HI = RGB(200, 163, 79)
local BRONZE_DIM = RGB(74, 61, 38)
local GROUND = art.GROUND
local WELL = RGB(5, 4, 3)
-- Sliders, sampled from Blizzard's own minimal slider in Forever's settings: muted, not shiny.
local ARROW = RGB(100, 86, 72)
local ARROW_HOVER = RGB(160, 136, 110)
local TRACK = RGB(15, 16, 18)
local TRACK_EDGE = RGB(62, 51, 42)
local TRACK_HOVER = RGB(100, 86, 72)
local THUMB = RGB(141, 98, 66)
local THUMB_RIM = RGB(176, 128, 94) -- a lighter bevel just inside the outline
local THUMB_EDGE = RGB(64, 47, 33)
local CLEAR = { 0, 0, 0, 0 }
local ACCENT = { 0.2, 1, 0.6, 1 } -- Catnip green, the chat prefix colour

local refreshers = {}

-- Nested flat rectangles, outermost first: one { inset, colour } per layer. Returns the textures.
local function Bevel(frame, layers)
    local textures = {}
    for i, layer in ipairs(layers) do
        local texture = frame:CreateTexture(nil, "BACKGROUND", nil, i - 1)
        texture:SetPoint("TOPLEFT", layer[1], -layer[1])
        texture:SetPoint("BOTTOMRIGHT", -layer[1], layer[1])
        texture:SetColorTexture(unpack(layer[2]))
        textures[i] = texture
    end
    return textures
end

-- Flat fill with a 1px border. Returns the border so hover effects can recolour it.
local function Box(frame, fill, edge)
    return Bevel(frame, { { 0, edge }, { 1, fill } })[1]
end

-- Border lights up bronze on hover, back to `edge` after.
local function AddHover(frame, border, edge)
    frame:SetScript("OnEnter", function() border:SetColorTexture(unpack(BRONZE_HI)) end)
    frame:SetScript("OnLeave", function() border:SetColorTexture(unpack(edge)) end)
end

local window = art.CreateWindow("CatnipOptions", "Catnip")
window:SetSize(WIDTH, DEFAULT_HEIGHT) -- the saved size is applied once settings load
window:SetPoint("CENTER")
window:SetFrameStrata("DIALOG")
window:SetClampedToScreen(true)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
if window.SetDontSavePosition then
    window:SetDontSavePosition(true)
end
window:Hide()
table.insert(UISpecialFrames, "CatnipOptions") -- Esc closes it

-- The area under the tab row, inside the frame, holding the scrolling pages.
local inner = CreateFrame("Frame", nil, window)
inner:SetPoint("TOPLEFT", BORDER, -window.contentTop)
inner:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)

-- The frame's border, portrait, title and close button stay above the contents scrolling under them.
for i, overlay in ipairs(window.overlays) do
    overlay:SetFrameLevel(window:GetFrameLevel() + 100 + i)
end

-- Scroll area ------------------------------------------------------------------------------------

-- The pages live on `canvas`, scrolled inside `body`. A thin scrollbar in the gap between the
-- panels and the frame's right edge shows while the page is taller than the window.
local body = CreateFrame("ScrollFrame", nil, inner)
body:SetAllPoints()
local canvas = CreateFrame("Frame", nil, body)
canvas:SetSize(WIDTH, 1)
body:SetScrollChild(canvas)

local scrollbar = CreateFrame("Slider", nil, inner)
scrollbar:SetPoint("TOPRIGHT", -1, -PAD)
scrollbar:SetPoint("BOTTOMRIGHT", -1, 18) -- clear of the resize grip
scrollbar:SetWidth(4)
scrollbar:SetOrientation("VERTICAL")
scrollbar:SetMinMaxValues(0, 0)
scrollbar:SetValueStep(1)
local scrollTrack = scrollbar:CreateTexture(nil, "BACKGROUND")
scrollTrack:SetAllPoints()
scrollTrack:SetColorTexture(unpack(WELL))
local scrollThumb = scrollbar:CreateTexture(nil, "OVERLAY")
scrollThumb:SetSize(4, 40)
scrollThumb:SetColorTexture(unpack(BRONZE))
scrollbar:SetThumbTexture(scrollThumb)
-- The wheel glides to a target (gliding below); dragging the scrollbar moves straight there.
-- Offsets are whole pixels, so text and boxes don't snap out of step.
local scrollTarget, gliding = 0, false
scrollbar:SetScript("OnValueChanged", function(_, value)
    body:SetVerticalScroll(math.floor(value + 0.5))
    if not gliding then
        scrollTarget = value
    end
end)
scrollbar:SetScript("OnEnter", function() scrollThumb:SetColorTexture(unpack(BRONZE_HI)) end)
scrollbar:SetScript("OnLeave", function() scrollThumb:SetColorTexture(unpack(BRONZE)) end)

local function MaxScroll()
    return math.max(0, canvas:GetHeight() - body:GetHeight())
end

local function UpdateScroll()
    local visible, total = body:GetHeight(), canvas:GetHeight()
    local maxScroll = MaxScroll()
    scrollbar:SetMinMaxValues(0, maxScroll)
    scrollTarget = math.min(scrollTarget, maxScroll)
    scrollbar:SetValue(math.min(scrollbar:GetValue(), maxScroll))
    scrollbar:SetShown(maxScroll > 0)
    if total > 0 then
        scrollThumb:SetHeight(math.max(20, scrollbar:GetHeight() * visible / total))
    end
end

-- Eases the scroll position toward scrollTarget over a few frames.
local function Glide(_, elapsed)
    local current = scrollbar:GetValue()
    local gap = scrollTarget - current
    gliding = true
    if math.abs(gap) < 1 then
        scrollbar:SetValue(scrollTarget)
        body:SetScript("OnUpdate", nil)
    else
        scrollbar:SetValue(current + gap * math.min(1, elapsed * 18))
    end
    gliding = false
end

body:EnableMouseWheel(true)
body:SetScript("OnMouseWheel", function(_, delta)
    scrollTarget = math.max(0, math.min(MaxScroll(), scrollTarget - delta * SCROLL_STEP))
    body:SetScript("OnUpdate", Glide)
end)
body:SetScript("OnSizeChanged", function(_, width)
    canvas:SetWidth(width)
    UpdateScroll()
end)

-- A size that fits: width WIDTH..MAX_WIDTH, height MIN_HEIGHT up to a little less than the screen.
local function ClampSize(width, height)
    local maxHeight = math.max(MIN_HEIGHT, UIParent:GetHeight() - 40)
    return math.max(WIDTH, math.min(MAX_WIDTH, width)), math.max(MIN_HEIGHT, math.min(maxHeight, height))
end

-- Resize grip: drag the bottom-right corner. Our own drag rather than StartSizing, which made the
-- window jump to odd sizes here (seen 2026-10-02): the size is the size at the press plus how far
-- the cursor has moved, with the top-left corner pinned.
local grip = CreateFrame("Button", nil, window)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(inner:GetFrameLevel() + 5)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
local function CursorInWindowUnits()
    local x, y = GetCursorPosition()
    local scale = window:GetEffectiveScale()
    return x / scale, y / scale
end

local function FollowGrip(self)
    if not IsMouseButtonDown("LeftButton") then -- released somewhere we didn't hear about
        self:GetScript("OnMouseUp")(self)
        return
    end
    local x, y = CursorInWindowUnits()
    window:SetSize(ClampSize(self.startWidth + (x - self.startX), self.startHeight + (self.startY - y)))
end

grip:SetScript("OnMouseDown", function(self)
    -- Pin the top-left corner: anchored by its centre, the window would grow both ways.
    local left, top = window:GetLeft(), window:GetTop()
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    self.startX, self.startY = CursorInWindowUnits()
    self.startWidth, self.startHeight = window:GetSize()
    self:SetScript("OnUpdate", FollowGrip)
end)
grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    ns.db.optionsWidth = math.floor(window:GetWidth() + 0.5)
    ns.db.optionsHeight = math.floor(window:GetHeight() + 0.5)
end)

-- Tabs -------------------------------------------------------------------------------------------

-- Vertical layout: each Place puts a control under the previous one on the page being built.
local page, y

local topTabs -- the side tabs (General, Rotation, Cooldown), set below

-- Height of what a tab shows: its page, or (with sub-tabs) the selected sub-tab's page.
local function VisibleHeight(tab)
    if tab.subs then
        return VisibleHeight(tab.subs.selected)
    end
    return tab.height or 0
end

local function UpdateCanvas()
    if not (topTabs and topTabs.selected) then
        return -- still building
    end
    local tab = topTabs.selected
    tab.page:SetHeight(math.max(1, VisibleHeight(tab)))
    canvas:SetHeight(HEADER + math.max(1, VisibleHeight(tab)))
    UpdateScroll()
end

-- Text width for sizing a tab; a fallback in case the font hasn't measured yet.
local function TextWidth(text)
    local width = text:GetStringWidth()
    return (width and width > 0) and width or 60
end

-- Bookmark tabs standing on a panel, drawn above it. The selected one reaches TAB_COVER past the
-- panel's visible top edge, covering the edge lines and the shadow under them so tab and panel
-- read as one; the others stop on the edge, darker, with the panel's edge line under them.
-- Returns a makeTab for TabGroup: tabs in a row from `firstX`, their feet `edge` below the top of
-- `anchor`, `height` tall above the edge, at frame level `level`.
local TAB_COVER = 10
local function BookmarkTabs(anchor, firstX, edge, height, level)
    return function(parent, name, previous)
        local tab = CreateFrame("Button", nil, parent)
        tab:SetFrameLevel(level)
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetText(name)
        tab:SetWidth(TextWidth(tab.text) + 28)
        tab.x = previous and (previous.x + previous:GetWidth() + 2) or firstX
        local setArt = art.Tab(tab)
        function tab.SetSelected(selected)
            local cover = selected and TAB_COVER or 0
            tab:ClearAllPoints()
            tab:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", tab.x, -(edge + cover))
            tab:SetHeight(height + cover)
            tab.text:ClearAllPoints()
            tab.text:SetPoint("CENTER", 0, cover / 2 + 1) -- centred on the part above the edge
            setArt(selected, cover)
            tab.text:SetTextColor(unpack(selected and WHITE or GOLD))
        end
        tab:SetScript("OnEnter", function() tab.text:SetTextColor(unpack(WHITE)) end)
        tab:SetScript("OnLeave", function() tab.SetSelected(tab.selected) end)
        return tab
    end
end

-- Side tab icons: classic WoW icons by path, and Shifting Power's (a blue spirit cat) looked up by
-- spell name once spell data has loaded, with a cat's face (SIDE_TAB_FALLBACKS) until then or if
-- it isn't found.
local function ShiftingPowerIcon()
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo("Shifting Power")
    return info and info.iconID
end

local SIDE_TAB_FALLBACKS = { Rotation = "Interface\\Icons\\Ability_Hunter_Pet_Cat" }
local SIDE_TAB_ICONS = {
    General = "Interface\\Icons\\INV_Misc_Gear_01", -- a cog
    Rotation = ShiftingPowerIcon,
    Cooldown = "Interface\\Icons\\INV_Misc_PocketWatch_01", -- a pocket watch
}

-- A makeTab for TabGroup: side tabs down the window's right edge, as on Blizzard's Character
-- window. They sit under the frame (its border stays whole), and show their name in a tooltip.
local function SideTab(parent, name, previous)
    local tab = CreateFrame("Button", nil, parent) -- below window.overlays: under the frame's border
    tab:SetSize(art.SIDE_TAB_WIDTH, art.SIDE_TAB_HEIGHT)
    tab.index = previous and previous.index + 1 or 0
    tab:SetPoint("TOPLEFT", window, "TOPRIGHT", -SIDE_TAB_TUCK, -(SIDE_TAB_TOP + tab.index * SIDE_TAB_STEP))
    tab.SetSelected = art.SideTab(tab, SIDE_TAB_ICONS[name], SIDE_TAB_FALLBACKS[name])
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

local ClosePanel -- defined with the controls

-- A row of tabs (made by makeTab on buttonParent), each with a page (on pageParent at pageTop).
local function TabGroup(makeTab, buttonParent, pageParent, pageTop)
    local group = { tabs = {} }

    function group.Select(tab)
        group.selected = tab
        for _, other in ipairs(group.tabs) do
            local selected = other == tab
            other.page:SetShown(selected)
            other.selected = selected
            other.SetSelected(selected)
        end
        scrollbar:SetValue(0)
        UpdateCanvas()
    end

    -- Adds a tab and starts laying out its page (Place calls go to it until the next Add).
    function group.Add(name)
        local tab = makeTab(buttonParent, name, group.tabs[#group.tabs])
        tab:SetScript("OnClick", function() group.Select(tab) end)
        tab.page = CreateFrame("Frame", nil, pageParent)
        tab.page:SetPoint("TOPLEFT", pageParent, "TOPLEFT", 0, pageTop)
        tab.page:SetPoint("TOPRIGHT", pageParent, "TOPRIGHT", 0, pageTop)
        tab.page:SetHeight(1)
        tab.page:Hide()
        group.tabs[#group.tabs + 1] = tab
        page, y = tab.page, -PAD
        return tab
    end

    return group
end

local function EndTab(tab)
    ClosePanel()
    tab.height = -y
    tab.page:SetHeight(tab.height)
end

-- Controls ---------------------------------------------------------------------------------------

-- The panel being filled (nil between panels), and the y it started at.
local panel, panelTop

-- What new controls are parented to: the open panel, so they draw above its background.
local function Host()
    return panel or page
end

-- Pinned to both sides of the page (inset further inside a panel), so it stretches with the window.
local function Place(widget, height, gap)
    local inset = panel and PAD + PANEL_PAD or PAD
    widget:SetPoint("TOPLEFT", page, "TOPLEFT", inset, y)
    widget:SetPoint("TOPRIGHT", page, "TOPRIGHT", -inset, y)
    widget:SetHeight(height)
    y = y - height - (gap or 8)
end

function ClosePanel()
    if not panel then
        return
    end
    y = y + 8 - PANEL_PAD - art.EDGE_INSET -- the last control's gap becomes the panel's bottom padding
    panel:SetHeight(panelTop - y)
    y = y - PAD -- between panels
    panel = nil
end

-- Starts a panel (art.Panel), with a gold header if `text` is given. Controls go inside it until
-- the next Section or the end of the tab. The first control sits clear of a selected tab's foot.
local function Section(text)
    ClosePanel()
    panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    panel:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, y)
    art.Panel(panel)
    panelTop = y
    y = y - (art.EDGE_INSET + TAB_COVER + 2)
    if text then
        local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetJustifyH("LEFT")
        header:SetText(text)
        Place(header, 14, 8)
    end
end

-- Measured at the minimum width, so it never needs more lines than it was given.
local function Hint(text)
    local hint = Host():CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetWidth(panel and CONTENT or CONTENT + 2 * PANEL_PAD)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetText(text)
    hint:SetTextColor(unpack(MUTED))
    Place(hint, math.max(12, hint:GetStringHeight()), 10)
end

-- Blizzard's checkbox art (as in Catnip Edit Mode); returns the box and a function to show the
-- tick or not. It glows while the mouse is over hoverFrame (the whole row).
local function CheckboxBox(parent, hoverFrame)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(24, 24)
    local normal = box:CreateTexture(nil, "ARTWORK")
    normal:SetAllPoints()
    normal:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    local glow = box:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    glow:SetBlendMode("ADD")
    glow:Hide()
    local check = box:CreateTexture(nil, "OVERLAY", nil, 1)
    check:SetAllPoints()
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    hoverFrame:SetScript("OnEnter", function() glow:Show() end)
    hoverFrame:SetScript("OnLeave", function() glow:Hide() end)
    return box, function(checked)
        check:SetShown(checked and true or false)
    end
end

local function Checkbox(label, get, set)
    local row = CreateFrame("Button", nil, Host())
    local box, setChecked = CheckboxBox(row, row)
    box:SetPoint("LEFT", -3, 0) -- the art has a little transparent margin
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    row:SetScript("OnClick", function()
        set(not get())
        ns.SettingsChanged()
    end)
    refreshers[#refreshers + 1] = function()
        setChecked(get())
    end
    Place(row, 24, 4)
end

-- A < or > button for a slider (direction -1 or 1): two short bars meeting at a point, like the
-- close X used to be (no reliance on a font glyph).
local function Arrow(parent, direction)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(14, 20)
    local bars = {}
    for i, side in ipairs({ 1, -1 }) do -- upper arm, lower arm
        local bar = button:CreateTexture(nil, "ARTWORK")
        bar:SetSize(8, 2)
        bar:SetPoint("CENTER", -direction * 1.4, side * 2.8)
        bar:SetColorTexture(unpack(ARROW))
        bar:SetRotation(-direction * side * math.pi / 4)
        bars[i] = bar
    end
    local function Colour(colour)
        for _, bar in ipairs(bars) do
            bar:SetColorTexture(unpack(colour))
        end
    end
    button:SetScript("OnEnter", function() Colour(ARROW_HOVER) end)
    button:SetScript("OnLeave", function() Colour(ARROW) end)
    return button
end

-- Blizzard's minimal slider look: the label above; under it < arrow, a thin groove with a diamond
-- thumb, > arrow, and the value in gold. The value can be clicked and typed into; its box only
-- shows while hovered or typing in.
-- min and max may be functions, re-read on every refresh (e.g. screen size for position).
-- No mouse wheel: it would fight with scrolling the page.
local function Slider(label, min, max, step, format, get, set)
    local holder = CreateFrame("Frame", nil, Host())
    local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT")
    name:SetText(label)

    local function Range()
        return type(min) == "function" and min() or min, type(max) == "function" and max() or max
    end
    local function Clamp(value)
        local low, high = Range()
        return math.min(high, math.max(low, value))
    end

    -- The value: Enter applies, Esc cancels.
    local input = CreateFrame("EditBox", nil, holder)
    input:SetSize(52, 20)
    input:SetPoint("BOTTOMRIGHT")
    input:SetAutoFocus(false)
    input:SetFontObject("GameFontNormal")
    input:SetJustifyH("CENTER")
    input:SetTextInsets(2, 2, 0, 0)
    input:SetMaxLetters(6)
    local inputBorder, inputFill = unpack(Bevel(input, { { 0, CLEAR }, { 1, CLEAR } }))
    local function ShowBox(shown)
        inputBorder:SetColorTexture(unpack(shown and BRONZE_DIM or CLEAR))
        inputFill:SetColorTexture(unpack(shown and WELL or CLEAR))
    end
    input:SetScript("OnEnter", function() ShowBox(true) end)
    input:SetScript("OnLeave", function(self) ShowBox(self:HasFocus()) end)

    local less = Arrow(holder, -1)
    less:SetPoint("BOTTOMLEFT")
    local more = Arrow(holder, 1)
    more:SetPoint("RIGHT", input, "LEFT", -4, 0)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetPoint("LEFT", less, "RIGHT", 2, 0)
    slider:SetPoint("RIGHT", more, "LEFT", -2, 0)
    slider:SetHeight(20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(Range())
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- The groove: near black, with a dull brown edge that lightens on hover.
    local trackEdge = slider:CreateTexture(nil, "BACKGROUND")
    trackEdge:SetPoint("LEFT")
    trackEdge:SetPoint("RIGHT")
    trackEdge:SetHeight(12)
    trackEdge:SetColorTexture(unpack(TRACK_EDGE))
    local track = slider:CreateTexture(nil, "BACKGROUND", nil, 1)
    track:SetPoint("TOPLEFT", trackEdge, "TOPLEFT", 1, -1)
    track:SetPoint("BOTTOMRIGHT", trackEdge, "BOTTOMRIGHT", -1, 1)
    track:SetColorTexture(unpack(TRACK))
    slider:SetScript("OnEnter", function() trackEdge:SetColorTexture(unpack(TRACK_HOVER)) end)
    slider:SetScript("OnLeave", function() trackEdge:SetColorTexture(unpack(TRACK_EDGE)) end)

    -- The thumb: squares turned 45 degrees, a matte brown-orange diamond with a dark outline and a
    -- lighter bevelled rim.
    local thumb = slider:CreateTexture(nil, "OVERLAY", nil, 2)
    thumb:SetSize(9, 9)
    thumb:SetColorTexture(unpack(THUMB))
    thumb:SetRotation(math.pi / 4)
    slider:SetThumbTexture(thumb)
    for _, part in ipairs({ { 14, THUMB_EDGE, 0 }, { 12, THUMB_RIM, 1 } }) do
        local texture = slider:CreateTexture(nil, "OVERLAY", nil, part[3])
        texture:SetSize(part[1], part[1])
        texture:SetPoint("CENTER", thumb)
        texture:SetColorTexture(unpack(part[2]))
        texture:SetRotation(math.pi / 4)
    end

    local refreshing = false -- our own SetValue also fires OnValueChanged
    slider:SetScript("OnValueChanged", function(_, raw)
        if refreshing then
            return
        end
        set(math.floor(raw / step + 0.5) * step)
    end)

    -- Arrows move one step from the current value (rounded to the step first).
    local function Nudge(direction)
        set(Clamp(math.floor(get() / step + 0.5) * step + direction * step))
    end
    less:SetScript("OnClick", function() Nudge(-1) end)
    more:SetScript("OnClick", function() Nudge(1) end)

    local function ShowValue()
        input:SetText(string.format(format, get()))
    end
    -- Typed values are clamped to the range and rounded to whole numbers (finer than the drag step).
    input:SetScript("OnEnterPressed", function(self)
        local typed = tonumber((self:GetText():gsub("[%%%s]", "")))
        self:ClearFocus()
        if typed then
            set(math.floor(Clamp(typed) + 0.5))
        end
        ShowValue() -- also covers invalid input, and values the setter clamped
    end)
    input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ShowValue()
    end)
    input:SetScript("OnHide", input.ClearFocus) -- never keep the keyboard once the window closes
    input:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        ShowBox(true)
    end)
    input:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        ShowBox(self:IsMouseOver())
        ShowValue()
    end)

    refreshers[#refreshers + 1] = function()
        refreshing = true
        slider:SetMinMaxValues(Range())
        slider:SetValue(get())
        refreshing = false
        if not input:HasFocus() then -- don't overwrite what's being typed
            ShowValue()
        end
    end
    Place(holder, 38, 10)
end

-- A label with a 3x3 grid of buttons, one per anchor point (corners, middle of each side, centre);
-- the selected one is filled in.
local ANCHOR_POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local GRID_CELL, GRID_GAP = 18, 4
local GRID_SIZE = 3 * GRID_CELL + 4 * GRID_GAP

local function AnchorGrid(label, get, set)
    local holder = CreateFrame("Frame", nil, Host())
    local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT")
    name:SetText(label)
    local grid = CreateFrame("Frame", nil, holder)
    grid:SetSize(GRID_SIZE, GRID_SIZE)
    grid:SetPoint("TOPRIGHT")
    Box(grid, WELL, TRACK_EDGE)
    for index, point in ipairs(ANCHOR_POINTS) do
        local row, column = math.floor((index - 1) / 3), (index - 1) % 3
        local cell = CreateFrame("Button", nil, grid)
        cell:SetSize(GRID_CELL, GRID_CELL)
        cell:SetPoint("TOPLEFT", GRID_GAP + column * (GRID_CELL + GRID_GAP), -(GRID_GAP + row * (GRID_CELL + GRID_GAP)))
        AddHover(cell, Box(cell, GROUND, BRONZE_DIM), BRONZE_DIM)
        local fill = cell:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", -3, 3)
        fill:SetColorTexture(unpack(ACCENT))
        cell:SetScript("OnClick", function() set(point) end)
        refreshers[#refreshers + 1] = function()
            fill:SetShown(get() == point)
        end
    end
    Place(holder, GRID_SIZE)
end

-- Edit Mode button (Blizzard's red button), right of the tabs: unlocks the widgets and shows the
-- Edit Mode panel (EditMode.lua). The settings window stays open alongside it.
local editMode = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate") -- scrolls with the tabs
editMode:SetSize(96, 22)
editMode:SetPoint("BOTTOMRIGHT", canvas, "TOPRIGHT", -PAD, -(HEADER + PAD + art.EDGE_INSET - 2)) -- level with the tabs
editMode:SetText("Edit Mode")
editMode:SetScript("OnClick", ns.OpenEditMode)

local function HalfWidth() return math.floor(UIParent:GetWidth() / 2) end
local function HalfHeight() return math.floor(UIParent:GetHeight() / 2) end

-- General / Rotation / Cooldown: side tabs. Pages start under the header.
topTabs = TabGroup(SideTab, window, canvas, -HEADER)

-- General tab ------------------------------------------------------------------------------------

local general = topTabs.Add("General")

Section("Blizzard UI")

Checkbox("Hide Blizzard's cast bar",
    function() return ns.db.hideBlizzardCastBar end,
    function(hide)
        ns.db.hideBlizzardCastBar = hide
        if InCombatLockdown() then
            ns.Print("the Blizzard cast bar will update after combat.")
        end
        ns.UpdateBlizzardCastBar()
    end)

Checkbox("Hide Action Bar 1",
    function() return ns.db.hideActionBar1 end,
    function(hide)
        ns.db.hideActionBar1 = hide
        ns.UpdateBlizzardBars()
    end)

Checkbox("Hide Stance Bar",
    function() return ns.db.hideStanceBar end,
    function(hide)
        ns.db.hideStanceBar = hide
        ns.UpdateBlizzardBars()
    end)
Hint("Hidden bars' keybinds still work.")

Section("Troubleshooting")

Checkbox("Debug messages in chat",
    function() return ns.db.debug end,
    function(debug) ns.db.debug = debug end)

EndTab(general)

-- Rotation tab: the HUD (the Rotation Frame) --------------------------------------------------------

local rotation = topTabs.Add("Rotation")

Section("HUD")

Hint("In Edit Mode (top of this window), drag the HUD to move it, or click it to come back here.")

-- In percent, so the steps are whole numbers.
Slider("Scale", ns.MIN_SCALE * 100, ns.MAX_SCALE * 100, ns.SCALE_STEP * 100, "%.0f%%",
    function() return ns.db.scale * 100 end,
    function(percent) ns.SetHudScale(percent / 100) end)
Slider("Opacity", ns.MIN_ALPHA * 100, 100, 5, "%.0f%%",
    function() return ns.db.hudAlpha * 100 end,
    function(percent) ns.SetHudAlpha(percent / 100) end)

-- Position: offset from the screen centre, so 0 / 0 is dead centre. Range is half the screen.
Slider("Horizontal position", function() return -HalfWidth() end, HalfWidth, 1, "%.0f",
    function() return ns.db.x end,
    function(x) ns.SetHudPosition(x, ns.db.y) end)
Slider("Vertical position", function() return -HalfHeight() end, HalfHeight, 1, "%.0f",
    function() return ns.db.y end,
    function(y) ns.SetHudPosition(ns.db.x, y) end)

EndTab(rotation)

-- Cooldown tab: Abilities and Layout sub-tabs ----------------------------------------------------

local cooldowns = topTabs.Add("Cooldown")

-- Abilities / Layout: bookmarks standing on their page's first panel, right of the portrait, up in
-- the header (so above the panels: page, panel, controls).
cooldowns.subs = TabGroup(BookmarkTabs(cooldowns.page, art.PORTRAIT - 8, PAD + art.EDGE_INSET, TAB_HEIGHT,
    cooldowns.page:GetFrameLevel() + 10), cooldowns.page, cooldowns.page, 0)

-- Abilities ----------------------------------------------------------------------------------------

local abilities = cooldowns.subs.Add("Abilities")

Section()

Hint("Tick the abilities to show. Drag ticked ones up or down to set their priority: the top one shows first. Unticked items drop off the list.")

-- The list: one row per ability with a cooldown, in its own scrolling area. Rows are pooled and
-- rebuilt on every refresh from ns.Cooldowns.Candidates() (tracked first, in priority order).
local ROW_HEIGHT = 26
local LIST_ROWS = 10

local list = CreateFrame("ScrollFrame", nil, Host())
Box(list, WELL, BRONZE_DIM)
local content = CreateFrame("Frame", nil, list)
content:SetSize(CONTENT, 1)
list:SetScrollChild(content)
list:SetScript("OnSizeChanged", function(_, width)
    content:SetWidth(width)
end)
list:EnableMouseWheel(true)
list:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * ROW_HEIGHT * 2)))
end)
Place(list, ROW_HEIGHT * LIST_ROWS)

local empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
empty:SetPoint("CENTER")
empty:SetTextColor(unpack(MUTED))
empty:SetText("No abilities with a cooldown found.")

-- Where a dragged row would land: a line between rows.
local dropLine = content:CreateTexture(nil, "OVERLAY")
dropLine:SetHeight(2)
dropLine:SetColorTexture(unpack(GOLD))
dropLine:Hide()

local rows = {}
local trackedCount = 0
local dragging -- the row being dragged

local function RowTop(index)
    return -(index - 1) * ROW_HEIGHT
end

-- Pins a row across the list's width, `top` below the list's top.
local function PinRow(row, top)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, top)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, top)
end

-- Tracked position the cursor is over (1 to trackedCount).
local function DropIndex()
    local _, cursorY = GetCursorPosition()
    local offset = content:GetTop() - cursorY / content:GetEffectiveScale()
    return math.max(1, math.min(trackedCount, math.floor(offset / ROW_HEIGHT) + 1))
end

local function FollowCursor(row)
    local _, cursorY = GetCursorPosition()
    local offset = content:GetTop() - cursorY / content:GetEffectiveScale()
    PinRow(row, -(offset - ROW_HEIGHT / 2))
    local target = DropIndex()
    -- Above the target row when moving up, below it when moving down.
    local lineY = target <= row.index and RowTop(target) or RowTop(target + 1)
    dropLine:ClearAllPoints()
    dropLine:SetPoint("LEFT", content, "TOPLEFT", 4, lineY)
    dropLine:SetPoint("RIGHT", content, "TOPRIGHT", -4, lineY)
    dropLine:Show()
end

local RefreshList -- defined below

local function CreateRow()
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForDrag("LeftButton")

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.07)
    highlight:Hide()

    local box, setChecked = CheckboxBox(row, row)
    box:SetPoint("LEFT", 2, 0)
    row.setChecked = setChecked
    local hoverEnter, hoverLeave = row:GetScript("OnEnter"), row:GetScript("OnLeave")
    row:SetScript("OnEnter", function(self)
        hoverEnter(self)
        highlight:Show()
    end)
    row:SetScript("OnLeave", function(self)
        hoverLeave(self)
        highlight:Hide()
    end)

    -- The icon in a thin bronze frame.
    local iconEdge = row:CreateTexture(nil, "ARTWORK")
    iconEdge:SetSize(22, 22)
    iconEdge:SetPoint("LEFT", box, "RIGHT", 4, 0)
    iconEdge:SetColorTexture(unpack(BRONZE_DIM))
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("CENTER", iconEdge)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the icon's baked-in border

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", iconEdge, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", -28, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Drag grip: three short lines, on tracked rows only.
    row.grip = CreateFrame("Frame", nil, row)
    row.grip:SetSize(12, 10)
    row.grip:SetPoint("RIGHT", -10, 0)
    for i = 0, 2 do
        local line = row.grip:CreateTexture(nil, "ARTWORK")
        line:SetSize(12, 2)
        line:SetPoint("TOP", 0, -i * 4)
        line:SetColorTexture(unpack(MUTED))
    end

    -- A drag ends with a mouse-up over the row, which also counts as a click; don't toggle then.
    row:SetScript("OnMouseDown", function(self)
        self.dragged = false
    end)
    row:SetScript("OnClick", function(self)
        if self.dragged then
            return
        end
        ns.Cooldowns.SetTracked(self.entry, not self.tracked)
    end)
    row:SetScript("OnDragStart", function(self)
        if not self.tracked or trackedCount < 2 then
            return
        end
        self.dragged = true
        dragging = self
        self:SetFrameLevel(content:GetFrameLevel() + 10)
        self:SetScript("OnUpdate", FollowCursor)
    end)
    row:SetScript("OnDragStop", function(self)
        if dragging ~= self then
            return
        end
        self:SetScript("OnUpdate", nil)
        self:SetFrameLevel(content:GetFrameLevel() + 1)
        dropLine:Hide()
        dragging = nil
        local from, to = self.index, DropIndex()
        if from == to then
            RefreshList() -- put the row back in place
        else
            ns.Cooldowns.Move(from, to) -- refreshes via ns.SettingsChanged
        end
    end)
    return row
end

function RefreshList()
    if dragging then
        return -- rebuilding now would pull the row out from under the cursor
    end
    local candidates = ns.Cooldowns.Candidates()
    trackedCount = 0
    for i, candidate in ipairs(candidates) do
        local row = rows[i] or CreateRow()
        rows[i] = row
        row.index, row.entry, row.tracked = i, candidate.entry, candidate.tracked
        row.icon:SetTexture(candidate.icon)
        row.name:SetText(candidate.tracked and (i .. ".  " .. candidate.name) or candidate.name)
        row.name:SetTextColor(unpack(candidate.tracked and WHITE or MUTED))
        row.icon:SetDesaturated(not candidate.tracked)
        row.setChecked(candidate.tracked)
        row.grip:SetShown(candidate.tracked)
        PinRow(row, RowTop(i))
        row:SetFrameLevel(content:GetFrameLevel() + 1)
        row:Show()
        if candidate.tracked then
            trackedCount = i
        end
    end
    for i = #candidates + 1, #rows do
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #candidates * ROW_HEIGHT))
    empty:SetShown(#candidates == 0)
end
refreshers[#refreshers + 1] = RefreshList

-- Drop box: drag an item from the bags (or a worn trinket) onto it to track it.
local DROP_HEIGHT = 40
local drop = CreateFrame("Button", nil, Host())
local dropBorder = Box(drop, WELL, BRONZE_DIM)
local dropText = drop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
dropText:SetPoint("CENTER")
dropText:SetText("Drop an item here to track it")
dropText:SetTextColor(unpack(MUTED))

local function CursorItem()
    local kind, itemID = GetCursorInfo()
    return kind == "item" and itemID or nil
end

local function ReceiveItem()
    local itemID = CursorItem()
    if itemID then
        ClearCursor()
        ns.Cooldowns.AddItem(itemID)
    end
end

drop:SetScript("OnReceiveDrag", ReceiveItem)
drop:SetScript("OnMouseUp", ReceiveItem) -- picked up with a click instead of a drag
drop:SetScript("OnEnter", function()
    if CursorItem() then -- only light up while actually holding an item
        dropBorder:SetColorTexture(unpack(GOLD))
        dropText:SetTextColor(unpack(GOLD))
    end
end)
drop:SetScript("OnLeave", function()
    dropBorder:SetColorTexture(unpack(BRONZE_DIM))
    dropText:SetTextColor(unpack(MUTED))
end)
y = y - 4
Place(drop, DROP_HEIGHT)
Hint("Items with a Use: effect (Hearthstone, trinkets) get their own icon. Every potion shares one Potions icon; a dropped potion's buff (e.g. Mighty Rage Potion) shows as Potions being active.")

EndTab(abilities)

-- Layout -------------------------------------------------------------------------------------------

local layout = cooldowns.subs.Add("Layout")

Section("Position")

Hint("In Edit Mode (top of this window), drag the box to move it, drag its corners to resize it, or click it to come back here.")

-- Size up to the whole screen; position as an offset from the screen centre, like the HUD's.
local function ScreenWidth() return math.floor(UIParent:GetWidth()) end
local function ScreenHeight() return math.floor(UIParent:GetHeight()) end
local function SetCooldownBox(changes)
    local db = ns.db
    ns.Cooldowns.SetLayout(changes.x or db.cdX, changes.y or db.cdY,
        changes.width or db.cdWidth, changes.height or db.cdHeight)
end
Slider("Width", ns.Cooldowns.MIN_SIZE, ScreenWidth, 1, "%.0f",
    function() return ns.db.cdWidth end,
    function(width) SetCooldownBox({ width = width }) end)
Slider("Height", ns.Cooldowns.MIN_SIZE, ScreenHeight, 1, "%.0f",
    function() return ns.db.cdHeight end,
    function(height) SetCooldownBox({ height = height }) end)
Slider("Horizontal position", function() return -HalfWidth() end, HalfWidth, 1, "%.0f",
    function() return ns.db.cdX end,
    function(x) SetCooldownBox({ x = x }) end)
Slider("Vertical position", function() return -HalfHeight() end, HalfHeight, 1, "%.0f",
    function() return ns.db.cdY end,
    function(y) SetCooldownBox({ y = y }) end)

Section("Icons")

Slider("Opacity", ns.MIN_ALPHA * 100, 100, 5, "%.0f%%",
    function() return ns.db.cdAlpha * 100 end,
    function(percent) ns.Cooldowns.SetAlpha(percent / 100) end)

AnchorGrid("Alignment", function() return ns.db.cdAlign end, ns.Cooldowns.SetAlignment)
Hint("Where the shown icons gather in the box: a corner, the middle of a side, or the centre.")

-- No checkbox for the countdownForCooldowns CVar: SetCVar from our code was the likely source of a
-- taint error in Blizzard's chat (2026-10-02; see docs/api-research.md). Players change it in WoW's options.
Hint("Countdown numbers follow WoW's own setting: Options > Action Bars > Show Numbers for Cooldowns.")

EndTab(layout)

cooldowns.subs.Select(abilities)

-- Wiring -----------------------------------------------------------------------------------------

local function Refresh()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
end

topTabs.Select(general)
window:SetScript("OnShow", function()
    Refresh()
    UpdateScroll()
end)
ns.OnSettingsChanged(function()
    if window:IsShown() then
        Refresh()
    end
end)

ns.OnLoad(function()
    -- Clamped, so a saved size from a bigger screen (or a bad resize) can't hide the grip.
    window:SetSize(ClampSize(ns.db.optionsWidth or WIDTH, ns.db.optionsHeight or DEFAULT_HEIGHT))
end)

ns.commands[""] = function()
    window:SetShown(not window:IsShown())
end

-- /catnip edit: the settings window and Catnip Edit Mode together.
ns.commands.edit = function()
    window:Show()
    ns.OpenEditMode()
end

-- Opens the settings at a widget's position and size controls: "hud" (Rotation) or "cooldowns"
-- (Cooldown → Layout). Used by clicking a widget in unlock mode.
function ns.OpenSettings(where)
    if where == "cooldowns" then
        topTabs.Select(cooldowns)
        cooldowns.subs.Select(layout)
    else
        topTabs.Select(rotation)
    end
    window:Show()
end
