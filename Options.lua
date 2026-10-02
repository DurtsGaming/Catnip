-- Settings window (/catnip). Our own frames and textures rather than Blizzard's widget templates,
-- for a Catnip look and to avoid relying on templates that may differ in Forever. Each control
-- reads and writes ns.db through the owning module's functions, and every control refreshes
-- whenever ns.SettingsChanged() fires (so slash commands and mouse-wheel scaling stay in sync).
-- Controls are grouped into tabs; each tab is a page frame laid out top to bottom.
local addonName, ns = ...

local WIDTH = 300
local PAD = 16
local INNER = WIDTH - 2 * PAD
local PAGE_TOP = 72 -- below the title and the tab row
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
window:SetWidth(WIDTH) -- height set by the shown tab
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

-- Tabs: a row of labels under the title; the selected one is underlined in the accent colour.
local tabs = {}
local selectedTab

local function SelectTab(tab)
    selectedTab = tab
    for _, other in ipairs(tabs) do
        local selected = other == tab
        other.page:SetShown(selected)
        other.underline:SetShown(selected)
        other.text:SetTextColor(unpack(selected and ACCENT or MUTED))
    end
    window:SetHeight(PAGE_TOP + tab.height + PAD)
end

-- Vertical layout: each Place puts a control under the previous one on the page being built.
local page, y

local function Tab(name)
    local tab = CreateFrame("Button", nil, window)
    tab:SetSize(80, 20)
    tab:SetPoint("TOPLEFT", PAD + #tabs * 88, -44)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tab.text:SetPoint("LEFT")
    tab.text:SetText(name)
    tab.underline = tab:CreateTexture(nil, "ARTWORK")
    tab.underline:SetHeight(2)
    tab.underline:SetPoint("BOTTOMLEFT", tab.text, "BOTTOMLEFT", 0, -4)
    tab.underline:SetPoint("BOTTOMRIGHT", tab.text, "BOTTOMRIGHT", 0, -4)
    tab.underline:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    tab:SetScript("OnClick", function() SelectTab(tab) end)
    tab:SetScript("OnEnter", function() tab.text:SetTextColor(unpack(ACCENT)) end)
    tab:SetScript("OnLeave", function()
        tab.text:SetTextColor(unpack(tab == selectedTab and ACCENT or MUTED))
    end)

    tab.page = CreateFrame("Frame", nil, window)
    tab.page:SetPoint("TOPLEFT", 0, -PAGE_TOP)
    tab.page:SetPoint("TOPRIGHT", 0, -PAGE_TOP)
    tab.page:SetHeight(1)
    tabs[#tabs + 1] = tab
    page, y = tab.page, 0
    return tab
end

local function EndTab(tab)
    tab.height = -y - 8
    tab.page:SetHeight(tab.height)
end

local function Place(widget, height, gap)
    widget:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, y)
    y = y - height - (gap or 8)
end

local function Section(text)
    y = y - 6
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(text:upper())
    label:SetTextColor(unpack(ACCENT))
    Place(label, 12, 4)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetSize(INNER, 1)
    line:SetColorTexture(unpack(EDGE))
    Place(line, 1, 8)
end

local function Hint(text)
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetWidth(INNER)
    hint:SetJustifyH("LEFT")
    hint:SetText(text)
    hint:SetTextColor(unpack(MUTED))
    Place(hint, math.max(12, hint:GetStringHeight()), 12) -- long hints wrap onto more lines
end

local function Button(parent, width, getText, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 22)
    AddHover(button, Box(button, CONTROL, EDGE))
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    button:SetScript("OnClick", onClick)
    refreshers[#refreshers + 1] = function()
        text:SetText(getText())
    end
    return button
end

-- Two buttons side by side.
local function ButtonRow(leftText, leftClick, rightText, rightClick)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(INNER, 22)
    local half = (INNER - 8) / 2
    Button(row, half, leftText, leftClick):SetPoint("LEFT")
    Button(row, half, rightText, rightClick):SetPoint("RIGHT")
    Place(row, 22)
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
    row:SetSize(INNER, 18)
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
local function Slider(label, min, max, step, format, get, set)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(INNER, 34)
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
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)

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

local function UnlockText()
    return ns.IsHudUnlocked() and "Lock" or "Unlock"
end

local function ToggleUnlock()
    ns.SetHudUnlocked(not ns.IsHudUnlocked())
end

-- General tab ------------------------------------------------------------------------------------

local general = Tab("General")

Section("HUD")

ButtonRow(UnlockText, ToggleUnlock, function() return "Reset position" end, ns.ResetHudLayout)
Hint("While unlocked, drag the HUD to move it and scroll over it to resize.")

-- In percent, so the steps are whole numbers.
Slider("Scale", ns.MIN_SCALE * 100, ns.MAX_SCALE * 100, ns.SCALE_STEP * 100, "%.0f%%",
    function() return ns.db.scale * 100 end,
    function(percent) ns.SetHudScale(percent / 100) end)

-- Position: offset from the screen centre, so 0 / 0 is dead centre. Range is half the screen.
local function HalfWidth() return math.floor(UIParent:GetWidth() / 2) end
local function HalfHeight() return math.floor(UIParent:GetHeight() / 2) end
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

Section("Troubleshooting")

Checkbox("Debug messages in chat",
    function() return ns.db.debug end,
    function(debug) ns.db.debug = debug end)

EndTab(general)

-- Cooldowns tab ----------------------------------------------------------------------------------

local cooldowns = Tab("Cooldowns")

Section("Cooldown widget")

ButtonRow(UnlockText, ToggleUnlock, function() return "Reset position" end, ns.Cooldowns.ResetLayout)
Hint("While unlocked, drag the box to move it and drag its corners to resize it.")

-- Blizzard draws the countdown numbers, and only while this game option is on.
Checkbox("Show cooldown numbers (WoW option)",
    function() return GetCVarBool("countdownForCooldowns") end,
    function(show) SetCVar("countdownForCooldowns", show and "1" or "0") end)

Section("Abilities")

Hint("Tick the abilities to show. Drag ticked ones up or down to set their priority: the top one shows first. Unticked items drop off the list.")

-- The list: one row per ability with a cooldown, in a scrolling area. Rows are pooled and rebuilt
-- on every refresh from ns.Cooldowns.Candidates() (tracked first, in priority order).
local ROW_HEIGHT = 24
local LIST_ROWS = 10

local list = CreateFrame("ScrollFrame", nil, page)
list:SetSize(INNER, ROW_HEIGHT * LIST_ROWS)
Box(list, CONTROL, EDGE)
local content = CreateFrame("Frame", nil, list)
content:SetSize(INNER, 1)
list:SetScrollChild(content)
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
dropLine:SetSize(INNER - 8, 2)
dropLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
dropLine:Hide()

local rows = {}
local trackedCount = 0
local dragging -- the row being dragged

local function RowTop(index)
    return -(index - 1) * ROW_HEIGHT
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
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(offset - ROW_HEIGHT / 2))
    local target = DropIndex()
    -- Above the target row when moving up, below it when moving down.
    local lineY = target <= row.index and RowTop(target) or RowTop(target + 1)
    dropLine:ClearAllPoints()
    dropLine:SetPoint("LEFT", content, "TOPLEFT", 4, lineY)
    dropLine:Show()
end

local RefreshList -- defined below

local function CreateRow()
    local row = CreateFrame("Button", nil, content)
    row:SetSize(INNER, ROW_HEIGHT)
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
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, RowTop(i))
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
drop:SetSize(INNER, DROP_HEIGHT)
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

EndTab(cooldowns)

-- Wiring -----------------------------------------------------------------------------------------

local function Refresh()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
end

SelectTab(general)
window:SetScript("OnShow", Refresh)
ns.OnSettingsChanged(function()
    if window:IsShown() then
        Refresh()
    end
end)

ns.commands[""] = function()
    window:SetShown(not window:IsShown())
end
