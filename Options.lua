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

local WIDTH = 320 -- long hints are measured at this window width, without the scrollbar
local MIN_WIDTH = WIDTH + ns.OptionsScrollWidth -- default and minimum: WIDTH plus room for the scrollbar
local DEFAULT_HEIGHT = 580
local MAX_WIDTH = 700
local MIN_HEIGHT = 200
local BORDER = 8 -- the frame's border
local HEADER = 20 -- room at the top of the scrolling contents, above the pages, for a page's
-- bookmark sub-tabs (it scrolls with them); also keeps panels clear of the portrait
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
-- The Rotation tab's element list (left of its pages); the window's minimum width grows by this
-- much on that tab, so its pages keep the usual width, and on the Cooldown tab too (its frame controls).
local TREE_WIDTH = 236
local ELEMENT_ROW = 28 -- an element's row in that list: icon and name

local function RGB(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end
local WHITE = { 1, 1, 1, 1 }
local GOLD = { 1, 0.82, 0, 1 } -- GameFontNormal
local MUTED = RGB(163, 154, 138)
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
local HOVER_BLUE = RGB(116, 192, 255) -- hover, as the HUD's preview outlines (Preview.lua)
local SWITCH_ON_FILL = RGB(58, 45, 28)
local SWITCH_ON_EDGE = RGB(138, 106, 58)

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

-- A 1px outline round a frame, as four lines so a see-through fill inside stays see-through. Each
-- line is at least one screen pixel thick (PixelUtil) and isn't snapped to the pixel grid: snapped,
-- a line whose frame edge falls between pixels can round to zero height and vanish (the zone
-- buttons' top lines did, 2026-10-09); unsnapped it draws, a little softer at worst. Returns a
-- function that colours it.
local function Outline(frame)
    local lines = {}
    for i, ends in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local line = frame:CreateTexture(nil, "BORDER")
        if line.SetSnapToPixelGrid then
            line:SetSnapToPixelGrid(false)
            line:SetTexelSnappingBias(0)
        end
        line:SetPoint(ends[1])
        line:SetPoint(ends[2])
        local across = i <= 2 and "Height" or "Width" -- top and bottom: a height; sides: a width
        if PixelUtil and PixelUtil["Set" .. across] then
            PixelUtil["Set" .. across](line, 1, 1)
        else
            line["Set" .. across](line, 1)
        end
        lines[i] = line
    end
    return function(r, g, b, a)
        for _, line in ipairs(lines) do
            line:SetColorTexture(r, g, b, a)
        end
    end
end

-- Border lights up bronze on hover, back to `edge` after.
local function AddHover(frame, border, edge)
    frame:SetScript("OnEnter", function() border:SetColorTexture(unpack(BRONZE_HI)) end)
    frame:SetScript("OnLeave", function() border:SetColorTexture(unpack(edge)) end)
end

local window = art.CreateWindow("CatnipOptions", "Catnip")
window:SetSize(MIN_WIDTH, DEFAULT_HEIGHT) -- the saved size is applied once settings load
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

-- The pages live on `canvas`, scrolled inside `body`. A scrollbar (OptionsScroll.lua) at the
-- frame's right edge shows while the page is taller than the window, and the pages narrow to make
-- room for it.
local body = CreateFrame("ScrollFrame", nil, inner)
body:SetAllPoints()
local canvas = CreateFrame("Frame", nil, body)
canvas:SetSize(WIDTH, 1)
body:SetScrollChild(canvas)

local scroll = ns.OptionsScroll(body, canvas, SCROLL_STEP, ns.OptionsScrollWidth)
scroll.bar:SetPoint("TOPRIGHT", -2, -PAD)
scroll.bar:SetPoint("BOTTOMRIGHT", -2, 18) -- clear of the resize grip

local UpdateCanvas -- defined with the tabs; fits the page to the window, then the scrollbar
body:SetScript("OnSizeChanged", function() UpdateCanvas() end)

-- A size that fits: width MIN_WIDTH (plus the tree on the Rotation tab) up to MAX_WIDTH, height
-- MIN_HEIGHT up to a little less than the screen.
local hasTree = false -- whether the selected side tab has the element tree
local wide = false -- whether it needs the wider window (Rotation and Cooldown: their frame controls)
local function ClampSize(width, height)
    local maxHeight = math.max(MIN_HEIGHT, UIParent:GetHeight() - 40)
    local minWidth = wide and MIN_WIDTH + TREE_WIDTH or MIN_WIDTH
    return math.max(minWidth, math.min(MAX_WIDTH, width)), math.max(MIN_HEIGHT, math.min(maxHeight, height))
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
-- What controls hang from: the page's top, or after a Stretch, the stretching control's bottom (so
-- they ride down as it grows). originY is that edge's y on the page at its smallest.
local origin, originY, originLeft, originRight

local topTabs -- the side tabs (General, Rotation, Cooldown), set below

-- What a tab shows: itself, or (with sub-tabs) its selected sub-tab.
local function ShownTab(tab)
    while tab.subs do
        tab = tab.subs.selected
    end
    return tab
end

-- Sizes the canvas to the shown page, first growing the page's Stretch control (if it has one) to
-- fill the window, then fits the scrollbar.
function UpdateCanvas()
    if not (topTabs and topTabs.selected) then
        return -- still building
    end
    local shown = ShownTab(topTabs.selected)
    -- pageTop: room above a tab's sub-pages (the Rotation tab's HUD controls).
    local pageTop = topTabs.selected.pageTop or 0
    local height = math.max((shown.height or 0) + pageTop, topTabs.selected.treeHeight or 0)
    local stretch = shown.page.stretch
    if stretch then
        local extra = math.max(0, math.floor(body:GetHeight() - HEADER - height))
        stretch:SetHeight(stretch.minHeight + extra)
        height = height + extra
    end
    height = math.max(1, height)
    shown.page:SetHeight(math.max(1, height - pageTop))
    topTabs.selected.page:SetHeight(height)
    canvas:SetHeight(HEADER + height)
    scroll.Update()
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
        if group.onSelect then
            group.onSelect(tab)
        end
        if not group.keepScroll then -- e.g. the Rotation tab's element rows stay where they are
            scroll.ScrollTo(0)
        end
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
        origin, originY, originLeft, originRight = page, 0, "TOPLEFT", "TOPRIGHT"
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

-- The panel being filled (nil between panels).
local panel

-- What new controls are parented to: the open panel, so they draw above its background.
local function Host()
    return panel or page
end

-- Pinned to both sides of the page (inset further inside a panel), so it stretches with the window.
local function Place(widget, height, gap)
    local inset = panel and PAD + PANEL_PAD or PAD
    widget:SetPoint("TOPLEFT", origin, originLeft, inset, y - originY)
    widget:SetPoint("TOPRIGHT", origin, originRight, -inset, y - originY)
    widget:SetHeight(height)
    y = y - height - (gap or 8)
end

-- Like Place, but the widget grows to fill the window when the page is shorter than it (one per
-- page; UpdateCanvas does the growing). Controls placed after it, and the bottom of its panel, move
-- down with it.
local function Stretch(widget, minHeight)
    local inset = panel and PAD + PANEL_PAD or PAD
    local stretch = CreateFrame("Frame", nil, page) -- the widget's row, across the whole page
    stretch:SetPoint("TOPLEFT", origin, originLeft, 0, y - originY)
    stretch:SetPoint("TOPRIGHT", origin, originRight, 0, y - originY)
    stretch:SetHeight(minHeight)
    stretch.minHeight = minHeight
    page.stretch = stretch
    widget:SetPoint("TOPLEFT", stretch, "TOPLEFT", inset, 0)
    widget:SetPoint("BOTTOMRIGHT", stretch, "BOTTOMRIGHT", -inset, 0)
    y = y - minHeight
    origin, originY, originLeft, originRight = stretch, y, "BOTTOMLEFT", "BOTTOMRIGHT"
    y = y - 8
end

function ClosePanel()
    if not panel then
        return
    end
    y = y + 8 - PANEL_PAD - art.EDGE_INSET -- the last control's gap becomes the panel's bottom padding
    panel:SetPoint("BOTTOMRIGHT", origin, originRight, -PAD, y - originY)
    y = y - PAD -- between panels
    panel = nil
end

-- Starts a panel (art.Panel), with a gold header if `text` is given. Controls go inside it until
-- the next Section or the end of the tab. The first control sits clear of a selected tab's foot.
local function Section(text)
    ClosePanel()
    panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", origin, originLeft, PAD, y - originY) -- its bottom right is set by ClosePanel
    art.Panel(panel)
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
local SLIDER_HEIGHT = 38

-- The control itself, on `parent`, for the caller to place (SLIDER_HEIGHT tall).
local function SliderWidget(parent, label, min, max, step, format, get, set)
    local holder = CreateFrame("Frame", nil, parent)
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
    return holder
end

local function Slider(label, min, max, step, format, get, set)
    Place(SliderWidget(Host(), label, min, max, step, format, get, set), SLIDER_HEIGHT, 10)
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

-- A choice between a few values, laid out like a slider: the label above, then < [value] >. The
-- arrows step through `values` ({ value, text }, wrapping round); clicking the value opens a menu
-- of them all. `text` may be a function, re-read on every refresh. With fontOf, the value is
-- drawn in the font fontOf(entry) names (a key of ns.FONTS), so the font list previews itself.
local CHOICE_HEIGHT = 38

-- The control itself, on `parent`, for the caller to place (CHOICE_HEIGHT tall).
local function ChoiceWidget(parent, label, values, get, set, fontOf)
    local holder = CreateFrame("Frame", nil, parent)
    local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT")
    name:SetText(label)

    local less = Arrow(holder, -1)
    less:SetPoint("BOTTOMLEFT")
    local more = Arrow(holder, 1)
    more:SetPoint("BOTTOMRIGHT")

    local box = CreateFrame("Button", nil, holder)
    box:SetPoint("LEFT", less, "RIGHT", 2, 0)
    box:SetPoint("RIGHT", more, "LEFT", -2, 0)
    box:SetHeight(20)
    AddHover(box, Box(box, WELL, TRACK_EDGE), TRACK_EDGE)
    local valueText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("LEFT", 6, 0)
    valueText:SetPoint("RIGHT", -6, 0)
    valueText:SetWordWrap(false)

    local function Index()
        local current = get()
        for i, entry in ipairs(values) do
            if entry.value == current then
                return i
            end
        end
        return 1
    end
    local function Step(direction)
        set(values[(Index() - 1 + direction) % #values + 1].value)
    end
    less:SetScript("OnClick", function() Step(-1) end)
    more:SetScript("OnClick", function() Step(1) end)

    local function Text(entry)
        return type(entry.text) == "function" and entry.text() or entry.text
    end

    -- Clicking the value opens Blizzard's menu (as EllesmereUI does on Forever) listing every
    -- value, the current one marked; font names are drawn in their font. Without MenuUtil it steps.
    box:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            Step(1)
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, entry in ipairs(values) do
                local radio = root:CreateRadio(Text(entry),
                    function() return values[Index()] == entry end,
                    function()
                        set(entry.value)
                        return MenuResponse and MenuResponse.Close
                    end)
                if fontOf and radio.AddInitializer then
                    -- SetFontObject, not SetFont: the menu forbids SetFont on its labels.
                    radio:AddInitializer(function(button)
                        local label = button.fontString
                        if label then
                            local size = math.floor((select(2, label:GetFont())) or 12)
                            label:SetFontObject(ns.FontObject(fontOf(entry), size))
                        end
                    end)
                end
            end
        end)
    end)

    refreshers[#refreshers + 1] = function()
        local entry = values[Index()]
        if fontOf then
            ns.ApplyFont(valueText, fontOf(entry), 13, "none")
        end
        valueText:SetText(Text(entry))
        valueText:SetTextColor(unpack(GOLD))
    end
    return holder
end

local function Choice(label, values, get, set, fontOf)
    Place(ChoiceWidget(Host(), label, values, get, set, fontOf), CHOICE_HEIGHT, 10)
end

-- A red button on its own row, at its natural width.
local function Button(text, onClick)
    local holder = CreateFrame("Frame", nil, Host())
    local button = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(button:GetFontString():GetStringWidth() + 32, 22)
    button:SetPoint("LEFT")
    button:SetScript("OnClick", onClick)
    Place(holder, 22)
    return button
end

-- A white disc or ring from media/, tinted with SetVertexColor.
local function Shape(parent, file, size, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    texture:SetTexture(ns.MEDIA .. file)
    texture:SetSize(size, size)
    return texture
end

-- An on/off switch (Blizzard has none, so it's drawn): a pill-shaped track whose knob slides right
-- and turns gold when on, the label beside it and onText/offText under that. The edge lights blue
-- on hover. Returns the button for the caller to place.
local SWITCH_WIDTH, SWITCH_HEIGHT = 40, 20
local function Switch(parent, label, onText, offText, get, set)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(SWITCH_WIDTH + 8 + 130, 30)
    local track = CreateFrame("Frame", nil, button)
    track:SetSize(SWITCH_WIDTH, SWITCH_HEIGHT)
    track:SetPoint("LEFT")

    -- A pill: a disc at each end and a rectangle between, `inset` inside the track. Returns a
    -- function that colours it.
    local function Pill(inset, sublevel)
        local size = SWITCH_HEIGHT - 2 * inset
        local parts = {}
        for _, side in ipairs({ "LEFT", "RIGHT" }) do
            local cap = Shape(track, "circle_small", size, "BACKGROUND", sublevel)
            cap:SetPoint(side, side == "LEFT" and inset or -inset, 0)
            parts[#parts + 1] = cap
        end
        local middle = track:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        middle:SetColorTexture(1, 1, 1, 1)
        middle:SetPoint("TOPLEFT", inset + size / 2, -inset)
        middle:SetPoint("BOTTOMRIGHT", -(inset + size / 2), inset)
        parts[#parts + 1] = middle
        -- Not snapped to the pixel grid: snapped, the fill pill could round over the edge pill's
        -- 1-unit rim and hide it (its bottom went, 2026-10-09; see Outline).
        for _, part in ipairs(parts) do
            if part.SetSnapToPixelGrid then
                part:SetSnapToPixelGrid(false)
                part:SetTexelSnappingBias(0)
            end
        end
        return function(colour)
            for _, part in ipairs(parts) do
                part:SetVertexColor(unpack(colour))
            end
        end
    end
    local paintEdge, paintFill = Pill(0, 0), Pill(1, 1)
    local knob = Shape(track, "circle_small", SWITCH_HEIGHT - 6)

    local name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT", track, "TOPRIGHT", 10, 3)
    name:SetText(label)
    local state = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    state:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)

    local hovered = false
    local function Paint()
        local on = get() and true or false
        paintEdge(hovered and HOVER_BLUE or on and SWITCH_ON_EDGE or TRACK_EDGE)
        paintFill(on and SWITCH_ON_FILL or TRACK)
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
        knob:SetVertexColor(unpack(on and GOLD or ARROW))
        state:SetText(on and onText or offText)
        state:SetTextColor(unpack(on and BRONZE_HI or MUTED))
    end
    button:SetScript("OnEnter", function()
        hovered = true
        Paint()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        Paint()
    end)
    button:SetScript("OnClick", function() set(not get()) end)
    refreshers[#refreshers + 1] = Paint
    return button
end

-- An element's icon in the list (its `glyph` in Elements.lua): a small picture of its kind of art in
-- its colour, in a dark square.
local GLYPH_SIZE = 24
local function Glyph(parent, glyph)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    Box(holder, WELL, BRONZE_DIM)
    glyph = glyph or { kind = "disc", color = { MUTED[1], MUTED[2], MUTED[3] } }
    local r, g, b = unpack(glyph.color)
    local function Tinted(file, size, x, y)
        local texture = Shape(holder, file, size)
        texture:SetPoint("CENTER", x or 0, y or 0)
        texture:SetVertexColor(r, g, b)
        return texture
    end
    if glyph.kind == "ring" then
        Tinted("ring_rip", 18)
    elseif glyph.kind == "arc" then -- the bottom half of a ring
        local arc = Tinted("ring_rip", 18, 0, -2)
        arc:SetSize(18, 9)
        arc:SetTexCoord(0, 1, 0.5, 1)
    elseif glyph.kind == "dots" then
        Tinted("circle_small", 6, -6, -1)
        Tinted("circle_small", 6, 0, 1)
        Tinted("circle_small", 6, 6, -1)
    elseif glyph.kind == "text" then
        local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER", 0, 0)
        text:SetText("Aa")
        text:SetTextColor(r, g, b)
    else -- disc
        Tinted("circle_small", 16)
    end
    return holder
end

-- A zone's icon for its button, drawn from the HUD's own shapes (only the zone's part, so it reads
-- at this size): General three slider lines (the defaults), Above the arc of combo dots, Circle the
-- resource circle in its ring, Below an arc over a bar. Returns it and a function that colours it,
-- given whether the zone is selected.
local function ZonePicture(parent, zoneId)
    local picture = CreateFrame("Frame", nil, parent)
    picture:SetSize(32, 32)
    local textures = {}
    local function Add(texture, x, y)
        texture:SetPoint("CENTER", x, y)
        textures[#textures + 1] = texture
        return texture
    end
    local function Bar(width, height, x, y)
        local bar = picture:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(1, 1, 1, 1)
        bar:SetSize(width, height)
        return Add(bar, x, y)
    end
    if zoneId == "general" then
        for i, knobX in ipairs({ -4, 5, -1 }) do
            local y = 8 - (i - 1) * 8
            Bar(22, 2, 0, y)
            Add(Shape(picture, "circle_small", 7, "ARTWORK", 1), knobX, y)
        end
    elseif zoneId == "above" then
        -- Five dots on an arc, 14 out from a centre below them, 20 degrees apart.
        for _, offset in ipairs({ { -9, -1.3 }, { -4.8, 1.2 }, { 0, 2 }, { 4.8, 1.2 }, { 9, -1.3 } }) do
            Add(Shape(picture, "circle_small", 6), offset[1], offset[2])
        end
    elseif zoneId == "circle" then
        Add(Shape(picture, "ring_rip", 24), 0, 0)
        Add(Shape(picture, "circle_small", 12), 0, 0)
    else -- below: the bottom half of a ring, over a bar
        local arc = Add(Shape(picture, "ring_rip", 24), 0, 2)
        arc:SetSize(24, 12)
        arc:SetTexCoord(0, 1, 0.5, 1)
        Bar(14, 3, 0, -9)
    end
    return picture, function(selected)
        for _, texture in ipairs(textures) do
            texture:SetVertexColor(unpack(selected and GOLD or MUTED))
        end
    end
end

local SEGMENT_HEIGHT = 28 -- the preview strip's buttons (Rotation tab)

local function ChoiceText(values, value)
    for _, entry in ipairs(values) do
        if entry.value == value then
            return entry.text
        end
    end
    return tostring(value)
end

-- The control for one of an element's options (Elements.lua). Values equal to the default are
-- stored as nil, so a later change of default reaches them. An inherited choice gets a first entry
-- "General (<its value>)" that stores nil.
local function ElementOptionControl(element, option)
    local id, key = element.id, option.key
    local function Get() return ns.ElementOption(id, key) end
    local function Set(value)
        if value == option.default then
            value = nil
        end
        ns.SetElementOption(id, key, value)
    end
    if option.type == "slider" then
        Slider(option.label, option.min, option.max, option.step or 1, option.format or "%.0f", Get, Set)
    elseif option.type == "checkbox" then
        Checkbox(option.label, Get, Set)
    elseif option.type == "choice" then
        local values = option.values
        if option.inherit then
            values = { { text = function()
                return "General (" .. ChoiceText(option.values, ns.ElementOption("general", option.inherit)) .. ")"
            end } }
            for _, entry in ipairs(option.values) do
                values[#values + 1] = entry
            end
            Get = function() return ns.ElementStored(id, key) end
            Set = function(value)
                ns.SetElementOption(id, key, value)
            end
        end
        Choice(option.label, values, Get, Set, option.fontPreview and function(entry)
            return entry.value or ns.ElementOption(id, key)
        end)
    end
end

-- The controls for an element's options, skipping hidden ones (not offered for now, Elements.lua).
local function ElementControls(element)
    for _, option in ipairs(element.options or {}) do
        if not option.hidden then
            ElementOptionControl(element, option)
        end
    end
end

local function HalfWidth() return math.floor(UIParent:GetWidth() / 2) end
local function HalfHeight() return math.floor(UIParent:GetHeight() / 2) end

-- A frame over part of `parent` that catches the mouse while shown, passing the wheel on so the
-- page still scrolls. Hidden to start.
local function ScrollBlocker(parent, level)
    local blocker = CreateFrame("Frame", nil, parent)
    blocker:SetFrameLevel(level)
    blocker:EnableMouse(true)
    blocker:EnableMouseWheel(true)
    blocker:SetScript("OnMouseWheel", function(_, delta)
        scroll.ScrollTo(scroll.Target() - delta * SCROLL_STEP, true)
    end)
    blocker:Hide()
    return blocker
end

-- Frame controls, the panel across the top of the Rotation and Cooldown tabs: a switch turning the
-- frame on or off with Reset... and Move in Edit Mode on its right, then sliders in pairs. While the
-- switch is off, only it can be used (owner, 2026-10-09): the sliders dim, a blocker over them
-- catches the mouse, and both buttons are disabled. Reset... opens a confirmation, dropping down
-- over the page, before calling spec.reset.
-- spec: name (the switch's label, and "Reset <name>" on the confirmation), isOn, setOn, resetText,
-- reset, and sliders: SliderWidget's arguments after the parent, filling each row left then right.
-- The panel sits at the top of `parent`; returns it, with the confirmation as panel.confirm.
local function FramePanel(parent, spec)
    local INSET = art.EDGE_INSET + PANEL_PAD
    local SWITCH_ROW = 30
    local GAP = 22 -- between the two sliders of a row
    local CONFIRM_INSET = art.EDGE_INSET + 10
    local CONFIRM_WIDTH = 236

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", PAD, -PAD)
    panel:SetPoint("TOPRIGHT", -PAD, -PAD)
    panel:SetHeight(2 * INSET + SWITCH_ROW + math.ceil(#spec.sliders / 2) * (10 + SLIDER_HEIGHT))
    art.Panel(panel)

    local switch = Switch(panel, spec.name, "Enabled", "Disabled", spec.isOn, spec.setOn)
    switch:SetPoint("TOPLEFT", INSET, -INSET)

    local editButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    editButton:SetText("Move in Edit Mode")
    editButton:SetSize(editButton:GetFontString():GetStringWidth() + 32, 22)
    editButton:SetPoint("TOPRIGHT", -INSET, -(INSET + (SWITCH_ROW - 22) / 2))
    editButton:SetScript("OnClick", function() ns.OpenEditMode() end)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetText("Reset...")
    resetButton:SetSize(resetButton:GetFontString():GetStringWidth() + 32, 22)
    resetButton:SetPoint("RIGHT", editButton, "LEFT", -6, 0)

    local confirm = CreateFrame("Frame", nil, parent)
    confirm:SetWidth(CONFIRM_WIDTH)
    confirm:SetFrameLevel(parent:GetFrameLevel() + 60) -- over the rest of the page
    confirm:EnableMouse(true) -- clicks stop here, not on what's under it
    confirm:SetPoint("TOPRIGHT", resetButton, "BOTTOMRIGHT", 0, -6)
    art.Panel(confirm)
    confirm:Hide()
    local confirmTitle = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    confirmTitle:SetPoint("TOPLEFT", CONFIRM_INSET, -CONFIRM_INSET)
    confirmTitle:SetText("Reset " .. spec.name)
    local confirmText = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    confirmText:SetPoint("TOPLEFT", confirmTitle, "BOTTOMLEFT", 0, -6)
    confirmText:SetWidth(CONFIRM_WIDTH - 2 * CONFIRM_INSET)
    confirmText:SetJustifyH("LEFT")
    confirmText:SetTextColor(unpack(MUTED))
    confirmText:SetText(spec.resetText)
    local everything = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
    everything:SetText("Everything back to defaults")
    everything:SetSize(CONFIRM_WIDTH - 2 * CONFIRM_INSET, 22)
    everything:SetPoint("TOPLEFT", confirmText, "BOTTOMLEFT", 0, -10)
    everything:SetScript("OnClick", function()
        confirm:Hide()
        spec.reset()
    end)
    local cancel = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
    cancel:SetText("Cancel")
    cancel:SetSize(CONFIRM_WIDTH - 2 * CONFIRM_INSET, 22)
    cancel:SetPoint("TOPLEFT", everything, "BOTTOMLEFT", 0, -4)
    cancel:SetScript("OnClick", function() confirm:Hide() end)
    confirm:SetHeight(2 * CONFIRM_INSET + 14 + 6 + math.max(12, confirmText:GetStringHeight()) + 10 + 22 + 4 + 22)
    resetButton:SetScript("OnClick", function() confirm:SetShown(not confirm:IsShown()) end)
    panel.confirm = confirm

    -- Sliders in pairs under the switch: the left one ending short of the middle, the right one
    -- starting past it.
    local sliders = {}
    for i, args in ipairs(spec.sliders) do
        local top = -(INSET + SWITCH_ROW + 10 + (math.ceil(i / 2) - 1) * (SLIDER_HEIGHT + 10))
        local slider = SliderWidget(panel, unpack(args))
        if i % 2 == 0 then
            slider:SetPoint("TOPLEFT", panel, "TOP", GAP / 2, top)
            slider:SetPoint("TOPRIGHT", -INSET, top)
        else
            slider:SetPoint("TOPLEFT", INSET, top)
            slider:SetPoint("TOPRIGHT", panel, "TOP", -GAP / 2, top)
        end
        slider:SetHeight(SLIDER_HEIGHT)
        sliders[#sliders + 1] = slider
    end

    local blocker = ScrollBlocker(parent, panel:GetFrameLevel() + 20)
    blocker:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(INSET + SWITCH_ROW + 4))
    blocker:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
    refreshers[#refreshers + 1] = function()
        local on = spec.isOn() and true or false
        for _, slider in ipairs(sliders) do
            slider:SetAlpha(on and 1 or 0.45)
        end
        blocker:SetShown(not on)
        editButton:SetEnabled(on)
        resetButton:SetEnabled(on)
        if not on then
            confirm:Hide()
        end
    end
    return panel
end

-- General / Rotation / Cooldown: side tabs. Pages start under the header.
topTabs = TabGroup(SideTab, window, canvas, -HEADER)
-- The Rotation tab's tree needs a wider window: widen it if it's narrower than that.
-- Preview mode (Preview.lua) runs while the window is open on that tab.
local function UpdatePreview()
    ns.Preview.SetWanted(window:IsShown() and hasTree)
    -- And the cooldown box's preview (Cooldowns.lua) while it's on the Cooldown tab.
    ns.Cooldowns.SetSettingsPreview(window:IsShown() and topTabs.selected and topTabs.selected.cooldownPreview)
end
function topTabs.onSelect(tab)
    hasTree = tab.hasTree or false
    wide = tab.wide or false
    window:SetSize(ClampSize(window:GetSize()))
    UpdatePreview()
end
window:HookScript("OnHide", UpdatePreview) -- and on show, in the OnShow script at the end

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

-- Across the top, the HUD's on/off, scale and opacity (shared by every form), then the preview strip.
-- Under them two panes: on the left a strip of zones (General, then Elements.lua's ns.ZONES) and the shown
-- zone's elements; on the right the selected element's page. The element rows are the tabs of a
-- TabGroup, so each element's page is built like any sub-tab's. (docs/settings-plan.md)
local rotation = topTabs.Add("Rotation")
local elementTabs = {} -- element id -> its row (tab); ns.OpenElementSettings reads it

-- The tab is built in a block of its own so its many locals end with it: a Lua function, this
-- file's main chunk included, can hold at most 200 at once.
do
    rotation.hasTree, rotation.wide = true, true

    -- HUD controls: the switch with Reset... and Edit Mode, then scale and opacity, then position.
    -- Scale and opacity in percent, so the steps are whole numbers. Opacity fades the whole HUD; each
    -- element's own opacity multiplies with it. Position: an offset from the screen centre (0 / 0 is
    -- dead centre, range half the screen), or dragged in Edit Mode.
    local HUD_INSET = art.EDGE_INSET + PANEL_PAD -- the preview strip's, matching the HUD controls'
    local hudPanel = FramePanel(rotation.page, {
        name = "Rotation Frame",
        isOn = function() return ns.db.hudEnabled end,
        setOn = ns.SetHudEnabled,
        resetText = "Every element's settings, Scale, Overall opacity, position and the Rotation Frame switch go back to their defaults.",
        reset = function()
            ns.ResetAllElements()
            ns.ResetHudLook()
            ns.ResetHudPosition()
        end,
        sliders = {
            { "Scale", ns.MIN_SCALE * 100, ns.MAX_SCALE * 100, ns.SCALE_STEP * 100, "%.0f%%",
                function() return ns.db.scale * 100 end,
                function(percent) ns.SetHudScale(percent / 100) end },
            { "Overall opacity", ns.MIN_ALPHA * 100, 100, 5, "%.0f%%",
                function() return ns.db.hudAlpha * 100 end,
                function(percent) ns.SetHudAlpha(percent / 100) end },
            { "Horizontal position", function() return -HalfWidth() end, HalfWidth, 1, "%.0f",
                function() return ns.db.x end,
                function(x) ns.SetHudPosition(x, ns.db.y) end },
            { "Vertical position", function() return -HalfHeight() end, HalfHeight, 1, "%.0f",
                function() return ns.db.y end,
                function(y) ns.SetHudPosition(ns.db.x, y) end },
        },
    })
    local hudHeight = hudPanel:GetHeight()

    -- The preview strip, across the window under the HUD controls: what the HUD shows while this tab
    -- is open (Preview.lua's sample states). A form, and beside it a Stealth toggle laying stealth's
    -- look over Cat Form (Prowl) or Caster (Shadowmeld); Bear Form can't stealth, so it's dimmed
    -- there. A band of its own, apart from the panes, labelled "Preview", so it reads as changing
    -- only what the HUD shows, not settings per form (owner, 2026-10-09).
    local PREVIEW_LABEL = 66 -- the label's column
    local FORM_WIDTH, FORM_GAP = 72, 4 -- each of Caster, Bear and Cat
    local STEALTH_WIDTH = 110
    local previewPanel = CreateFrame("Frame", nil, rotation.page)
    previewPanel:SetPoint("TOPLEFT", PAD, -(PAD + hudHeight + PAD))
    previewPanel:SetPoint("TOPRIGHT", -PAD, -(PAD + hudHeight + PAD))
    previewPanel:SetHeight(2 * HUD_INSET + SEGMENT_HEIGHT)
    art.Panel(previewPanel)

    local previewLabel = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("LEFT", previewPanel, "TOPLEFT", HUD_INSET, -(HUD_INSET + SEGMENT_HEIGHT / 2))
    previewLabel:SetText("Preview")
    -- The buttons: rounded, in the Cooldown tab's bookmark look (owner, 2026-10-09). The picked one
    -- is bright with white text, the others darker with gold text, white on hover.
    local function PreviewButton(width)
        local button = CreateFrame("Button", nil, previewPanel)
        button:SetSize(width, SEGMENT_HEIGHT)
        button.SetShade = art.RoundTab(button)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("CENTER", 0, 1)
        return button
    end

    local previous
    for _, entry in ipairs(ns.Preview.STATES) do
        local button = PreviewButton(FORM_WIDTH)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", FORM_GAP, 0)
        else
            button:SetPoint("TOPLEFT", HUD_INSET + PREVIEW_LABEL, -HUD_INSET)
        end
        button.text:SetText(entry.short or entry.text)
        local hovered = false
        local function Paint()
            local on = ns.Preview.GetState() == entry.value
            button.SetShade(on)
            button.text:SetTextColor(unpack((on or hovered) and WHITE or GOLD))
        end
        button:SetScript("OnEnter", function()
            hovered = true
            Paint()
        end)
        button:SetScript("OnLeave", function()
            hovered = false
            Paint()
        end)
        button:SetScript("OnClick", function() ns.Preview.SetState(entry.value) end)
        refreshers[#refreshers + 1] = Paint
        previous = button
    end

    local stealthToggle = PreviewButton(STEALTH_WIDTH)
    stealthToggle:SetPoint("LEFT", previous, "RIGHT", 12, 0)
    local stealthText = stealthToggle.text
    local stealthHovered = false
    local function PaintStealth()
        local form, can, on = ns.Preview.GetState(), ns.Preview.CanStealth(), ns.Preview.GetStealthed()
        stealthText:SetText(form == "caster" and "Shadowmeld" or form == "cat" and "Prowl" or "Stealth")
        stealthToggle:SetAlpha(can and 1 or 0.4)
        stealthToggle.SetShade(on)
        stealthText:SetTextColor(unpack((on or stealthHovered and can) and WHITE or GOLD))
    end
    stealthToggle:SetScript("OnEnter", function()
        stealthHovered = true
        PaintStealth()
    end)
    stealthToggle:SetScript("OnLeave", function()
        stealthHovered = false
        PaintStealth()
    end)
    stealthToggle:SetScript("OnClick", function()
        if ns.Preview.CanStealth() then
            ns.Preview.SetStealthed(not ns.Preview.GetStealthed())
        end
    end)
    refreshers[#refreshers + 1] = PaintStealth

    -- The two panes, under the HUD controls and the preview strip.
    rotation.pageTop = PAD + hudHeight + PAD + previewPanel:GetHeight()
    local tree = CreateFrame("Frame", nil, rotation.page)
    tree:SetPoint("TOPLEFT", PAD, -(rotation.pageTop + PAD))
    tree:SetWidth(TREE_WIDTH - PAD)
    art.Panel(tree)

    -- Whether the Rotation Frame is on (true before the settings load, while this is being built).
    -- Off, the panes show no gold selection and their buttons are disabled (the refresher below).
    local function HudOn()
        return not ns.db or ns.db.hudEnabled
    end
    local paneButtons = {} -- the pages' red buttons (Reset to defaults)

    local detail = CreateFrame("Frame", nil, rotation.page) -- holds the pages, right of the list
    detail:SetPoint("TOPLEFT", TREE_WIDTH, -rotation.pageTop)
    detail:SetPoint("TOPRIGHT", 0, -rotation.pageTop)
    detail:SetHeight(1)

    -- While the Rotation Frame is off, only its switch can be used (owner, 2026-10-09): as well as
    -- FramePanel's sliders, the preview strip and both panes dim, and a blocker over them catches
    -- the mouse.
    local paneBlocker = ScrollBlocker(rotation.page, rotation.page:GetFrameLevel() + 40) -- under Reset...'s confirmation (+60)
    paneBlocker:SetPoint("TOPLEFT", previewPanel, "TOPLEFT") -- the preview strip too
    paneBlocker:SetPoint("BOTTOMRIGHT", rotation.page, "BOTTOMRIGHT")

    refreshers[#refreshers + 1] = function()
        local on = ns.db.hudEnabled and true or false
        local alpha = on and 1 or 0.45
        previewPanel:SetAlpha(alpha)
        tree:SetAlpha(alpha)
        detail:SetAlpha(alpha)
        paneBlocker:SetShown(not on)
        for _, button in ipairs(paneButtons) do
            button:SetEnabled(on)
        end
        -- Repaint the rows and zone buttons, whose gold selection shows only while on.
        for _, tab in ipairs(rotation.subs and rotation.subs.tabs or {}) do
            tab.SetSelected()
            tab.zone.button.SetSelected(tab.zone.button.selected)
        end
    end

    local TREE_INSET = art.EDGE_INSET + 8 -- inside the panel's painted edge
    local LIST_WIDTH = TREE_WIDTH - PAD - 2 * TREE_INSET
    local treeY = -TREE_INSET


    -- The zones: General (built here: the text defaults and the HUD's position), then ns.ZONES.
    local generalZone = { id = "general", name = "General" }
    local zones = { generalZone }
    for _, zone in ipairs(ns.ZONES) do
        zones[#zones + 1] = { id = zone.id, name = zone.name, groups = zone.groups }
    end

    -- The zone strip: a button per zone, its picture over its name. Clicking one opens its first page.
    local ZONE_GAP, ZONE_HEIGHT = 4, 56
    -- Whole units, so the edges don't start between pixels.
    local zoneWidth = math.floor((LIST_WIDTH - (#zones - 1) * ZONE_GAP) / #zones)
    for i, zone in ipairs(zones) do
        local button = CreateFrame("Button", nil, tree)
        button:SetSize(zoneWidth, ZONE_HEIGHT)
        button:SetPoint("TOPLEFT", TREE_INSET + (i - 1) * (zoneWidth + ZONE_GAP), treeY)
        local fill = button:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        local outline = Outline(button)
        local picture, paint = ZonePicture(button, zone.id)
        picture:SetPoint("TOP", 0, -4)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", 0, 4)
        label:SetText(zone.name)
        function button.SetSelected(selected)
            button.selected = selected
            local lit = selected and HudOn() -- no gold while the Rotation Frame is off
            outline(unpack(lit and GOLD or TRACK_EDGE))
            fill:SetColorTexture(unpack(lit and SWITCH_ON_FILL or WELL))
            label:SetTextColor(unpack(lit and GOLD or MUTED))
            paint(lit)
        end
        button:SetScript("OnEnter", function()
            outline(unpack(HOVER_BLUE))
            label:SetTextColor(unpack(WHITE))
        end)
        button:SetScript("OnLeave", function() button.SetSelected(button.selected) end)
        button:SetScript("OnClick", function() rotation.subs.Select(zone.first) end)
        button.SetSelected(false)
        zone.button = button
    end
    treeY = treeY - ZONE_HEIGHT - 10

    -- The shown zone's name (no description line under it: dropped, owner, 2026-10-09).
    local zoneTitle = tree:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    zoneTitle:SetPoint("TOPLEFT", TREE_INSET + 2, treeY)
    zoneTitle:SetJustifyH("LEFT")
    treeY = treeY - 20
    local listTop = treeY

    -- Each zone's rows go in a frame of their own (zone.list), shown while the zone is.
    local currentList, listY -- the zone list being filled, and the next row's y on it
    local function ZoneList(zone)
        local list = CreateFrame("Frame", nil, tree)
        list:SetPoint("TOPLEFT", TREE_INSET, listTop)
        list:SetWidth(LIST_WIDTH)
        list:Hide()
        zone.list = list
        currentList, listY = list, 0
    end

    local function GroupHeading(text)
        local heading = currentList:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        heading:SetPoint("TOPLEFT", 4, listY - 6)
        heading:SetText(string.upper(text))
        heading:SetTextColor(unpack(MUTED))
        listY = listY - 22
    end

    -- A makeTab for TabGroup: an element's row in the zone list being filled: its icon (added by
    -- SetGlyph) and name on one line. `dot` marks an element with settings changed. Hovering a row
    -- lights its element up on the HUD in preview mode (row.elementId).
    local ROW_TEXT = RGB(232, 225, 212)
    local function ElementRow(_, name)
        local row = CreateFrame("Button", nil, currentList)
        row:SetHeight(ELEMENT_ROW)
        row:SetPoint("TOPLEFT", 0, listY)
        row:SetPoint("TOPRIGHT", 0, listY)
        listY = listY - ELEMENT_ROW - 1
        local fill = row:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        local outline = Outline(row)
        local textWidth = LIST_WIDTH - 6 - GLYPH_SIZE - 8 - 18
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetWidth(textWidth)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.text:SetText(name)
        row.dot = Shape(row, "circle_small", 6, "OVERLAY")
        row.dot:SetPoint("RIGHT", -8, 0)
        row.dot:SetVertexColor(unpack(ACCENT))
        row.dot:Hide()

        local hovered = false
        local function Paint()
            local lit = row.selected and HudOn() -- no gold while the Rotation Frame is off
            if lit then
                outline(unpack(GOLD))
                fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
            elseif hovered then
                outline(HOVER_BLUE[1], HOVER_BLUE[2], HOVER_BLUE[3], 0.7)
                fill:SetColorTexture(HOVER_BLUE[1], HOVER_BLUE[2], HOVER_BLUE[3], 0.06)
            else
                outline(unpack(CLEAR))
                fill:SetColorTexture(unpack(CLEAR))
            end
            row.text:SetTextColor(unpack(lit and WHITE or ROW_TEXT))
        end
        function row.SetSelected()
            Paint() -- TabGroup sets row.selected first
        end
        function row.SetGlyph(glyph)
            local icon = Glyph(row, glyph)
            icon:SetPoint("LEFT", 6, 0)
            row.text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        end
        row:SetScript("OnEnter", function()
            hovered = true
            Paint()
            ns.Preview.SetListHover(row.elementId)
        end)
        row:SetScript("OnLeave", function()
            hovered = false
            Paint()
            ns.Preview.SetListHover(nil)
        end)
        return row
    end

    rotation.subs = TabGroup(ElementRow, tree, detail, 0)
    rotation.subs.keepScroll = true -- picking an element keeps the list where it's scrolled to

    -- Adds a row (in `zone`, under the last heading) and starts its page. The row's dot shows while
    -- the element has any setting changed.
    local function AddRow(zone, name, glyph, id)
        local tab = rotation.subs.Add(name)
        tab.zone, tab.elementId = zone, id
        tab.SetGlyph(glyph)
        zone.first = zone.first or tab
        if id then
            elementTabs[id] = tab
            refreshers[#refreshers + 1] = function()
                tab.dot:SetShown(ns.db.elements[id] ~= nil)
            end
        end
        return tab
    end

    -- An element's page: a panel named after it with its controls, and a reset button.
    local function ElementPage(element, zone)
        local tab = AddRow(zone, element.name, element.glyph, element.id)
        Section(element.name)
        ElementControls(element)
        paneButtons[#paneButtons + 1] = Button("Reset to defaults", function() ns.ResetElement(element.id) end)
        EndTab(tab)
    end

    -- General: the text defaults other elements inherit (unless hidden), and Stealth Mode. On/off,
    -- scale, opacity and position are the HUD controls above; Edit Mode just moves the HUD.
    ZoneList(generalZone)
    local generalElement = ns.GetElement("general")
    if not generalElement.hidden then
        local textPage = AddRow(generalZone, generalElement.name, generalElement.glyph, "general")
        Section("Text")
        Hint("Fonts and outline for all text, unless an element picks its own.")
        ElementControls(generalElement)
        paneButtons[#paneButtons + 1] = Button("Reset to defaults", function() ns.ResetElement("general") end)
        EndTab(textPage)
    end
    ElementPage(ns.GetElement("stealth"), generalZone) -- Stealth Mode (Layout.lua)
    generalZone.height = -listY

    -- Each zone's elements, group by group under the group's heading, by their `order` (e.g. the combo
    -- point they sit on), else as registered.
    for _, zone in ipairs(zones) do
        if zone.groups then
            ZoneList(zone)
            for _, group in ipairs(zone.groups) do
                local entries = {}
                for index, element in ipairs(ns.elements) do
                    if element.zone == group.zone and not element.hidden then
                        entries[#entries + 1] = { element = element, key = element.order or 1000 + index }
                    end
                end
                table.sort(entries, function(a, b) return a.key < b.key end)
                if #entries > 0 and group.name then
                    GroupHeading(group.name)
                end
                for _, entry in ipairs(entries) do
                    ElementPage(entry.element, zone)
                end
            end
            zone.height = -listY
        end
    end

    -- Shows a zone: its button lit, its name and rows, and the list's height.
    local shownZone
    local function ShowZone(zone)
        if zone == shownZone then
            return
        end
        shownZone = zone
        for _, other in ipairs(zones) do
            other.list:SetShown(other == zone)
            other.button.SetSelected(other == zone)
        end
        zoneTitle:SetText(zone.name)
        zone.list:SetHeight(math.max(1, zone.height))
        hudPanel.confirm:Hide()
        local treeHeight = -listTop + zone.height + TREE_INSET
        tree:SetHeight(treeHeight)
        rotation.treeHeight = rotation.pageTop + PAD + treeHeight + PAD
        UpdateCanvas()
    end

    -- The open page's zone shows, and its element is the selected one in preview mode.
    function rotation.subs.onSelect(tab)
        ShowZone(tab.zone)
        ns.Preview.SetSelected(tab.elementId)
    end

    rotation.subs.Select(generalZone.first)
end

-- Cooldown tab: Abilities and Layout sub-tabs ----------------------------------------------------

local cooldowns = topTabs.Add("Cooldown")
cooldowns.wide, cooldowns.cooldownPreview = true, true

-- Frame controls across the top, as on the Rotation tab (owner, 2026-10-09): the switch, Reset...
-- and Edit Mode, then size and position (size up to the whole screen; position as an offset from
-- the screen centre, like the HUD's). Opacity stays in Layout, with the icons.
do
    local function SetCooldownBox(changes)
        local db = ns.db
        ns.Cooldowns.SetLayout(changes.x or db.cdX, changes.y or db.cdY,
            changes.width or db.cdWidth, changes.height or db.cdHeight)
    end
    local cdPanel = FramePanel(cooldowns.page, {
        name = "Cooldown Frame",
        isOn = function() return ns.db.cdEnabled end,
        setOn = ns.Cooldowns.SetEnabled,
        resetText = "Width, Height, position, Opacity, Alignment and the Cooldown Frame switch go back to their defaults. Tracked abilities stay.",
        reset = ns.Cooldowns.ResetLayout,
        sliders = {
            { "Width", ns.Cooldowns.MIN_SIZE, function() return math.floor(UIParent:GetWidth()) end, 1, "%.0f",
                function() return ns.db.cdWidth end,
                function(width) SetCooldownBox({ width = width }) end },
            { "Height", ns.Cooldowns.MIN_SIZE, function() return math.floor(UIParent:GetHeight()) end, 1, "%.0f",
                function() return ns.db.cdHeight end,
                function(height) SetCooldownBox({ height = height }) end },
            { "Horizontal position", function() return -HalfWidth() end, HalfWidth, 1, "%.0f",
                function() return ns.db.cdX end,
                function(x) SetCooldownBox({ x = x }) end },
            { "Vertical position", function() return -HalfHeight() end, HalfHeight, 1, "%.0f",
                function() return ns.db.cdY end,
                function(y) SetCooldownBox({ y = y }) end },
        },
    })
    -- Room above the sub-pages: the frame controls, then the bookmarks' height.
    cooldowns.pageTop = PAD + cdPanel:GetHeight() + TAB_HEIGHT
end

-- Abilities / Layout: bookmarks standing on their page's first panel, under the frame controls.
cooldowns.subs = TabGroup(BookmarkTabs(cooldowns.page, PAD + 10, cooldowns.pageTop + PAD + art.EDGE_INSET,
    TAB_HEIGHT, cooldowns.page:GetFrameLevel() + 10), cooldowns.page, cooldowns.page, -cooldowns.pageTop)

-- Abilities ----------------------------------------------------------------------------------------

local abilities = cooldowns.subs.Add("Abilities")

Section()

Hint("Tick the abilities to show. Drag ticked ones up or down to set their priority: higher ones sit closer to the anchor point (chosen in Layout). Unticked items drop off the list.")

-- The list: one row per ability with a cooldown, in its own scrolling area. Rows are pooled and
-- rebuilt on every refresh from ns.Cooldowns.Candidates() (tracked first, in priority order). It
-- stretches to fill the window, at least LIST_ROWS rows tall.
local ROW_HEIGHT = 26
local LIST_ROWS = 6

local list = CreateFrame("ScrollFrame", nil, Host())
Box(list, WELL, BRONZE_DIM)
local content = CreateFrame("Frame", nil, list)
content:SetSize(CONTENT, 1)
list:SetScrollChild(content)

-- Its own scrollbar, inside the box's edge, with the rows narrowed to clear it.
local listScroll = ns.OptionsScroll(list, content, ROW_HEIGHT * 2, ns.OptionsScrollWidth + 4)
listScroll.bar:SetPoint("TOPRIGHT", -3, -3)
listScroll.bar:SetPoint("BOTTOMRIGHT", -3, 3)
list:SetScript("OnSizeChanged", listScroll.Update)
Stretch(list, ROW_HEIGHT * LIST_ROWS)

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

-- Held near (or past) the list's top or bottom edge, a dragged row scrolls the list, faster the
-- further out it is.
local function DragScroll(cursorY, elapsed)
    local intoTop = cursorY - (list:GetTop() - ROW_HEIGHT)
    local intoBottom = (list:GetBottom() + ROW_HEIGHT) - cursorY
    local push = intoTop > 0 and -intoTop or intoBottom > 0 and intoBottom or 0
    push = math.max(-2 * ROW_HEIGHT, math.min(2 * ROW_HEIGHT, push))
    if push ~= 0 then
        listScroll.ScrollTo(listScroll.Target() + push * elapsed * 10)
    end
end

local function FollowCursor(row, elapsed)
    local _, cursorY = GetCursorPosition()
    DragScroll(cursorY / list:GetEffectiveScale(), elapsed)
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
    -- Hovering a row also outlines its icon in the cooldown box's preview.
    row:SetScript("OnEnter", function(self)
        hoverEnter(self)
        highlight:Show()
        ns.Cooldowns.SetPreviewHighlight(self.entry)
    end)
    row:SetScript("OnLeave", function(self)
        hoverLeave(self)
        highlight:Hide()
        ns.Cooldowns.SetPreviewHighlight(nil)
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
    listScroll.Update()
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
    UpdateCanvas()
    UpdatePreview()
end)
ns.Preview.onStateChanged = function() -- the "Preview as" control follows switches made elsewhere
    if window:IsShown() then
        Refresh()
    end
end
ns.OnSettingsChanged(function()
    if window:IsShown() then
        Refresh()
    end
end)

ns.OnLoad(function()
    -- Clamped, so a saved size from a bigger screen (or a bad resize) can't hide the grip.
    window:SetSize(ClampSize(ns.db.optionsWidth or MIN_WIDTH, ns.db.optionsHeight or DEFAULT_HEIGHT))
end)

ns.commands[""] = function()
    window:SetShown(not window:IsShown())
end

-- Shows the settings window as last left (the AddOns page in Blizzard's settings uses this).
function ns.ShowSettings()
    window:Show()
end

-- /catnip edit: the settings window and Catnip Edit Mode together.
ns.commands.edit = function()
    window:Show()
    ns.OpenEditMode()
end

-- Opens the settings at a widget's position and size controls: "hud" (the Rotation tab, scrolled
-- to the HUD controls at its top) or "cooldowns" (the Cooldown tab, likewise). Used by clicking a
-- widget in unlock mode.
function ns.OpenSettings(where)
    if where == "cooldowns" then
        topTabs.Select(cooldowns) -- scrolls to the top
    else
        topTabs.Select(rotation) -- scrolls to the top
    end
    window:Show()
end

-- Opens the settings at an element's page (an id from Elements.lua).
function ns.OpenElementSettings(id)
    local tab = elementTabs[id]
    if not tab then
        return
    end
    topTabs.Select(rotation)
    rotation.subs.Select(tab)
    window:Show()
end

-- While the settings window is open, turns it to `where` ("hud" or "cooldowns") unless it's already
-- on that tab (so a Cooldown sub-tab stays put). Clicking a frame in Blizzard's Edit Mode calls this.
function ns.FollowSettings(where)
    if not window:IsShown() then
        return
    end
    local tab = where == "cooldowns" and cooldowns or rotation
    if topTabs.selected ~= tab then
        ns.OpenSettings(where)
    end
end
