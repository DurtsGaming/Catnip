-- Settings window (/catnip). Our own frames and textures rather than Blizzard's widget templates,
-- for a Catnip look and to avoid relying on templates that may differ in Forever. Each control
-- reads and writes ns.db through the owning module's functions, and every control refreshes
-- whenever ns.SettingsChanged() fires (so slash commands and mouse-wheel scaling stay in sync).
local addonName, ns = ...

local WIDTH = 300
local PAD = 16
local INNER = WIDTH - 2 * PAD
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
window:SetWidth(WIDTH) -- height set once the controls are laid out
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

-- Vertical layout: each Place puts a control under the previous one.
local y = -48
local function Place(widget, height, gap)
    widget:SetPoint("TOPLEFT", PAD, y)
    y = y - height - (gap or 8)
end

local function Section(text)
    y = y - 6
    local label = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(text:upper())
    label:SetTextColor(unpack(ACCENT))
    Place(label, 12, 4)
    local line = window:CreateTexture(nil, "ARTWORK")
    line:SetSize(INNER, 1)
    line:SetColorTexture(unpack(EDGE))
    Place(line, 1, 8)
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

local function Checkbox(label, get, set)
    local row = CreateFrame("Button", nil, window)
    row:SetSize(INNER, 18)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    AddHover(row, Box(box, CONTROL, EDGE))
    local check = box:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 4, -4)
    check:SetPoint("BOTTOMRIGHT", -4, 4)
    check:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 8, 0)
    text:SetText(label)
    row:SetScript("OnClick", function()
        set(not get())
        ns.SettingsChanged()
    end)
    refreshers[#refreshers + 1] = function()
        check:SetShown(get() and true or false)
    end
    Place(row, 18)
end

-- min and max may be functions, re-read on every refresh (e.g. screen size for position).
local function Slider(label, min, max, step, format, get, set)
    local holder = CreateFrame("Frame", nil, window)
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

-- Controls ---------------------------------------------------------------------------------------

Section("HUD")

local row = CreateFrame("Frame", nil, window)
row:SetSize(INNER, 22)
local HALF = (INNER - 8) / 2
local unlock = Button(row, HALF, function()
    return ns.IsHudUnlocked() and "Lock HUD" or "Unlock HUD"
end, function()
    ns.SetHudUnlocked(not ns.IsHudUnlocked())
end)
unlock:SetPoint("LEFT")
local reset = Button(row, HALF, function()
    return "Reset position"
end, ns.ResetHudLayout)
reset:SetPoint("RIGHT")
Place(row, 22)

local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetWidth(INNER)
hint:SetJustifyH("LEFT")
hint:SetText("While unlocked, drag the HUD to move it and scroll over it to resize.")
hint:SetTextColor(unpack(MUTED))
Place(hint, 12, 12)

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

window:SetHeight(-y + PAD - 8)

-- Wiring -----------------------------------------------------------------------------------------

local function Refresh()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
end

window:SetScript("OnShow", Refresh)
ns.OnSettingsChanged(function()
    if window:IsShown() then
        Refresh()
    end
end)

ns.commands[""] = function()
    window:SetShown(not window:IsShown())
end
