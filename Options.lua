-- Settings window (/catnip). Our own frames and textures rather than Blizzard's widget templates,
-- for a Catnip look and to avoid relying on templates that may differ in Forever. Each control
-- reads and writes ns.db through the owning module's functions, and every control refreshes
-- whenever ns.SettingsChanged() fires (so slash commands and dragging in Edit Mode stay in sync).
--
-- Controls are grouped into tabs (and a tab can have sub-tabs); each tab is a page laid out top to
-- bottom. Pages sit in a scroll area, so the window can be resized smaller than its content: drag
-- the bottom-right corner (size saved in CatnipDB.optionsWidth/optionsHeight). Controls stretch to
-- the window's width.
local addonName, ns = ...

local WIDTH = 300 -- default and minimum width; long hints are measured at this width
local DEFAULT_HEIGHT = 560
local MAX_WIDTH = 700
local MIN_HEIGHT = 200
local PAD = 16
local INNER = WIDTH - 2 * PAD
local PAGE_TOP = 72 -- below the title and the tab row
local SUB_TOP = 30 -- below a sub-tab row
local SCROLL_STEP = 40
local ACCENT = { 0.2, 1, 0.6 } -- the chat prefix colour
local BACKGROUND = { 0.06, 0.06, 0.07, 0.95 }
local EDGE = { 0.25, 0.25, 0.28, 1 }
local CONTROL = { 0.14, 0.14, 0.16, 1 }
local MUTED = { 0.6, 0.6, 0.6 }

local refreshers = {}

-- Flat fill with a 1px border. Returns the border so hover effects can recolour it.
local function Box(frame, fill, edge)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(unpack(edge))
    local inside = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    inside:SetPoint("TOPLEFT", 1, -1)
    inside:SetPoint("BOTTOMRIGHT", -1, 1)
    inside:SetColorTexture(unpack(fill))
    return border
end

-- Border lights up in the accent colour on hover.
local function AddHover(frame, border)
    frame:SetScript("OnEnter", function()
        border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    end)
    frame:SetScript("OnLeave", function()
        border:SetColorTexture(unpack(EDGE))
    end)
end

local window = CreateFrame("Frame", "CatnipOptions", UIParent)
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
Box(window, BACKGROUND, EDGE)
table.insert(UISpecialFrames, "CatnipOptions") -- Esc closes it

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", PAD, -PAD)
title:SetText("Catnip")
title:SetTextColor(unpack(ACCENT))

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
version:SetText(GetMetadata and GetMetadata(addonName, "Version") or "")
version:SetTextColor(unpack(MUTED))

-- Close button: an X from two rotated bars (no reliance on a font glyph).
local close = CreateFrame("Button", nil, window)
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -8, -8)
local closeBars = {}
for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
    local bar = close:CreateTexture(nil, "ARTWORK")
    bar:SetSize(14, 2)
    bar:SetPoint("CENTER")
    bar:SetColorTexture(unpack(MUTED))
    bar:SetRotation(angle)
    closeBars[i] = bar
end
close:SetScript("OnEnter", function()
    for _, bar in ipairs(closeBars) do
        bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    end
end)
close:SetScript("OnLeave", function()
    for _, bar in ipairs(closeBars) do
        bar:SetColorTexture(MUTED[1], MUTED[2], MUTED[3], 1)
    end
end)
close:SetScript("OnClick", function()
    window:Hide()
end)

-- Scroll area ------------------------------------------------------------------------------------

-- The pages live on `canvas`, scrolled inside `body`. A thin scrollbar in the right margin shows
-- while the page is taller than the window.
local body = CreateFrame("ScrollFrame", nil, window)
body:SetPoint("TOPLEFT", 0, -PAGE_TOP)
body:SetPoint("BOTTOMRIGHT", 0, PAD)
local canvas = CreateFrame("Frame", nil, body)
canvas:SetSize(WIDTH, 1)
body:SetScrollChild(canvas)

local scrollbar = CreateFrame("Slider", nil, window)
scrollbar:SetPoint("TOPRIGHT", -5, -PAGE_TOP)
scrollbar:SetPoint("BOTTOMRIGHT", -5, 22) -- clear of the resize grip
scrollbar:SetWidth(6)
scrollbar:SetOrientation("VERTICAL")
scrollbar:SetMinMaxValues(0, 0)
scrollbar:SetValueStep(1)
local scrollTrack = scrollbar:CreateTexture(nil, "BACKGROUND")
scrollTrack:SetAllPoints()
scrollTrack:SetColorTexture(unpack(CONTROL))
local scrollThumb = scrollbar:CreateTexture(nil, "OVERLAY")
scrollThumb:SetSize(6, 40)
scrollThumb:SetColorTexture(unpack(EDGE))
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
scrollbar:SetScript("OnEnter", function() scrollThumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1) end)
scrollbar:SetScript("OnLeave", function() scrollThumb:SetColorTexture(unpack(EDGE)) end)

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

local topTabs -- the General/Cooldowns row, set below

-- Height of what a tab shows: its page, or its sub-tab row plus the selected sub-tab's page.
local function VisibleHeight(tab)
    if tab.subs then
        return SUB_TOP + VisibleHeight(tab.subs.selected)
    end
    return tab.height or 0
end

local function UpdateCanvas()
    if not (topTabs and topTabs.selected) then
        return -- still building
    end
    local tab = topTabs.selected
    tab.page:SetHeight(math.max(1, VisibleHeight(tab)))
    canvas:SetHeight(math.max(1, VisibleHeight(tab)))
    UpdateScroll()
end

-- A row of tab labels (buttons on buttonParent at buttonTop), each with a page (on pageParent at
-- pageTop). The selected label is underlined in the accent colour.
local function TabGroup(buttonParent, buttonTop, pageParent, pageTop)
    local group = { tabs = {} }

    function group.Select(tab)
        group.selected = tab
        for _, other in ipairs(group.tabs) do
            local selected = other == tab
            other.page:SetShown(selected)
            other.underline:SetShown(selected)
            other.text:SetTextColor(unpack(selected and ACCENT or MUTED))
        end
        scrollbar:SetValue(0)
        UpdateCanvas()
    end

    -- Adds a tab and starts laying out its page (Place calls go to it until the next Add).
    function group.Add(name)
        local tab = CreateFrame("Button", nil, buttonParent)
        tab:SetSize(80, 20)
        tab:SetPoint("TOPLEFT", PAD + #group.tabs * 88, buttonTop)
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        tab.text:SetPoint("LEFT")
        tab.text:SetText(name)
        tab.underline = tab:CreateTexture(nil, "ARTWORK")
        tab.underline:SetHeight(2)
        tab.underline:SetPoint("BOTTOMLEFT", tab.text, "BOTTOMLEFT", 0, -4)
        tab.underline:SetPoint("BOTTOMRIGHT", tab.text, "BOTTOMRIGHT", 0, -4)
        tab.underline:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        tab:SetScript("OnClick", function() group.Select(tab) end)
        tab:SetScript("OnEnter", function() tab.text:SetTextColor(unpack(ACCENT)) end)
        tab:SetScript("OnLeave", function()
            tab.text:SetTextColor(unpack(tab == group.selected and ACCENT or MUTED))
        end)

        tab.page = CreateFrame("Frame", nil, pageParent)
        tab.page:SetPoint("TOPLEFT", pageParent, "TOPLEFT", 0, pageTop)
        tab.page:SetPoint("TOPRIGHT", pageParent, "TOPRIGHT", 0, pageTop)
        tab.page:SetHeight(1)
        tab.page:Hide()
        group.tabs[#group.tabs + 1] = tab
        page, y = tab.page, 0
        return tab
    end

    return group
end

local function EndTab(tab)
    tab.height = -y - 8
    tab.page:SetHeight(tab.height)
end

-- Controls ---------------------------------------------------------------------------------------

-- Pinned to both sides of the page, so it stretches with the window.
local function Place(widget, height, gap)
    widget:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    widget:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD, y)
    widget:SetHeight(height)
    y = y - height - (gap or 8)
end

local function Section(text)
    y = y - 6
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    label:SetText(text:upper())
    label:SetTextColor(unpack(ACCENT))
    Place(label, 12, 4)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(EDGE))
    Place(line, 1, 8)
end

-- Measured at the minimum width, so it never needs more lines than it was given.
local function Hint(text)
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetWidth(INNER)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetText(text)
    hint:SetTextColor(unpack(MUTED))
    Place(hint, math.max(12, hint:GetStringHeight()), 12)
end

local function Button(parent, getText, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(22)
    AddHover(button, Box(button, CONTROL, EDGE))
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    button:SetScript("OnClick", onClick)
    refreshers[#refreshers + 1] = function()
        text:SetText(getText())
    end
    return button
end

-- A 16px checkbox; returns the box and a function to show the tick or not.
local function CheckboxBox(parent, hoverFrame)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(16, 16)
    AddHover(hoverFrame, Box(box, CONTROL, EDGE))
    local check = box:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 4, -4)
    check:SetPoint("BOTTOMRIGHT", -4, 4)
    check:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    return box, function(checked)
        check:SetShown(checked and true or false)
    end
end

local function Checkbox(label, get, set)
    local row = CreateFrame("Button", nil, page)
    local box, setChecked = CheckboxBox(row, row)
    box:SetPoint("LEFT")
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 8, 0)
    text:SetText(label)
    row:SetScript("OnClick", function()
        set(not get())
        ns.SettingsChanged()
    end)
    refreshers[#refreshers + 1] = function()
        setChecked(get())
    end
    Place(row, 18)
end

-- min and max may be functions, re-read on every refresh (e.g. screen size for position).
-- No mouse wheel: it would fight with scrolling the page.
local function Slider(label, min, max, step, format, get, set)
    local holder = CreateFrame("Frame", nil, page)
    local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT")
    name:SetText(label)

    -- The value, as a box you can click and type into. Enter applies, Esc cancels.
    local input = CreateFrame("EditBox", nil, holder)
    input:SetSize(56, 18)
    input:SetPoint("TOPRIGHT")
    input:SetAutoFocus(false)
    input:SetFontObject("GameFontHighlight")
    input:SetJustifyH("RIGHT")
    input:SetTextInsets(4, 4, 0, 0)
    input:SetMaxLetters(6)
    AddHover(input, Box(input, CONTROL, EDGE))

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetPoint("BOTTOMLEFT")
    slider:SetPoint("BOTTOMRIGHT")
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    local function Range()
        return type(min) == "function" and min() or min, type(max) == "function" and max() or max
    end
    slider:SetMinMaxValues(Range())
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(unpack(EDGE))
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 16)
    thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    slider:SetThumbTexture(thumb)

    local refreshing = false -- our own SetValue also fires OnValueChanged
    slider:SetScript("OnValueChanged", function(_, raw)
        if refreshing then
            return
        end
        set(math.floor(raw / step + 0.5) * step)
    end)

    local function ShowValue()
        input:SetText(string.format(format, get()))
    end
    -- Typed values are clamped to the range and rounded to whole numbers (finer than the drag step).
    input:SetScript("OnEnterPressed", function(self)
        local typed = tonumber((self:GetText():gsub("[%%%s]", "")))
        self:ClearFocus()
        if typed then
            local low, high = Range()
            set(math.floor(math.min(high, math.max(low, typed)) + 0.5))
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
    end)
    input:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
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
    Place(holder, 34)
end

-- A label with a 3x3 grid of buttons, one per anchor point (corners, middle of each side, centre);
-- the selected one is filled in.
local ANCHOR_POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local GRID_CELL, GRID_GAP = 18, 5
local GRID_SIZE = 3 * GRID_CELL + 4 * GRID_GAP

local function AnchorGrid(label, get, set)
    local holder = CreateFrame("Frame", nil, page)
    local name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("TOPLEFT")
    name:SetText(label)
    local grid = CreateFrame("Frame", nil, holder)
    grid:SetSize(GRID_SIZE, GRID_SIZE)
    grid:SetPoint("TOPRIGHT")
    Box(grid, CONTROL, EDGE)
    for index, point in ipairs(ANCHOR_POINTS) do
        local row, column = math.floor((index - 1) / 3), (index - 1) % 3
        local cell = CreateFrame("Button", nil, grid)
        cell:SetSize(GRID_CELL, GRID_CELL)
        cell:SetPoint("TOPLEFT", GRID_GAP + column * (GRID_CELL + GRID_GAP), -(GRID_GAP + row * (GRID_CELL + GRID_GAP)))
        AddHover(cell, Box(cell, BACKGROUND, EDGE))
        local fill = cell:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", -3, 3)
        fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        cell:SetScript("OnClick", function() set(point) end)
        refreshers[#refreshers + 1] = function()
            fill:SetShown(get() == point)
        end
    end
    Place(holder, GRID_SIZE)
end

-- Edit Mode button, on the title row above the tabs: unlocks the widgets and shows the Edit Mode
-- panel (EditMode.lua). The settings window stays open alongside it.
local editMode = Button(window, function() return "Edit Mode" end, ns.OpenEditMode)
editMode:SetSize(90, 22)
editMode:SetPoint("TOPRIGHT", -34, -12)

local function HalfWidth() return math.floor(UIParent:GetWidth() / 2) end
local function HalfHeight() return math.floor(UIParent:GetHeight() / 2) end

topTabs = TabGroup(window, -44, canvas, 0)

-- General tab ------------------------------------------------------------------------------------

local general = topTabs.Add("General")

Section("HUD")

Hint("In Edit Mode (top of this window), drag the HUD to move it, or click it to come back here.")

-- In percent, so the steps are whole numbers.
Slider("Scale", ns.MIN_SCALE * 100, ns.MAX_SCALE * 100, ns.SCALE_STEP * 100, "%.0f%%",
    function() return ns.db.scale * 100 end,
    function(percent) ns.SetHudScale(percent / 100) end)

-- Position: offset from the screen centre, so 0 / 0 is dead centre. Range is half the screen.
Slider("Horizontal position", function() return -HalfWidth() end, HalfWidth, 1, "%.0f",
    function() return ns.db.x end,
    function(x) ns.SetHudPosition(x, ns.db.y) end)
Slider("Vertical position", function() return -HalfHeight() end, HalfHeight, 1, "%.0f",
    function() return ns.db.y end,
    function(y) ns.SetHudPosition(ns.db.x, y) end)

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

-- Cooldowns tab: Abilities and Layout sub-tabs ---------------------------------------------------

local cooldowns = topTabs.Add("Cooldowns")
cooldowns.subs = TabGroup(cooldowns.page, -4, cooldowns.page, -SUB_TOP)

-- Abilities ----------------------------------------------------------------------------------------

local abilities = cooldowns.subs.Add("Abilities")

Hint("Tick the abilities to show. Drag ticked ones up or down to set their priority: the top one shows first. Unticked items drop off the list.")

-- The list: one row per ability with a cooldown, in its own scrolling area. Rows are pooled and
-- rebuilt on every refresh from ns.Cooldowns.Candidates() (tracked first, in priority order).
local ROW_HEIGHT = 24
local LIST_ROWS = 10

local list = CreateFrame("ScrollFrame", nil, page)
Box(list, CONTROL, EDGE)
local content = CreateFrame("Frame", nil, list)
content:SetSize(INNER, 1)
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
dropLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
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
    highlight:SetColorTexture(1, 1, 1, 0.06)
    highlight:Hide()

    local box, setChecked = CheckboxBox(row, row)
    box:SetPoint("LEFT", 6, 0)
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

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", box, "RIGHT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the icon's baked-in border

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
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
        row.name:SetTextColor(unpack(candidate.tracked and { 1, 1, 1 } or MUTED))
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
local drop = CreateFrame("Button", nil, page)
local dropBorder = Box(drop, CONTROL, EDGE)
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
        dropBorder:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        dropText:SetTextColor(unpack(ACCENT))
    end
end)
drop:SetScript("OnLeave", function()
    dropBorder:SetColorTexture(unpack(EDGE))
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

-- Opens the settings at a widget's position and size controls: "hud" (General) or "cooldowns"
-- (Cooldowns → Layout). Used by clicking a widget in unlock mode.
function ns.OpenSettings(where)
    if where == "cooldowns" then
        topTabs.Select(cooldowns)
        cooldowns.subs.Select(layout)
    else
        topTabs.Select(general)
    end
    window:Show()
end
