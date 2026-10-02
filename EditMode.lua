-- Catnip Edit Mode: a panel styled like Blizzard's "HUD Edit Mode" dialog, shown while the widgets
-- are unlocked (the settings window's Edit Mode button, or /catnip edit). Checkboxes turn each
-- widget on or off; closing the panel locks them again. Built from Blizzard's stock textures and
-- templates (dialog border, checkbox, red panel buttons) to match its look.
local addonName, ns = ...

local WIDTH, HEIGHT = 360, 186
local LABEL_FONT = _G.GameFontHighlightMedium and "GameFontHighlightMedium" or "GameFontHighlight"

local panel = CreateFrame("Frame", "CatnipEditMode", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(WIDTH, HEIGHT)
panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
panel:SetFrameStrata("DIALOG")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
if panel.SetDontSavePosition then
    panel:SetDontSavePosition(true)
end
panel:Hide()
table.insert(UISpecialFrames, "CatnipEditMode") -- Esc closes it (and locks)
if panel.SetBackdrop then
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("Catnip Edit Mode")

-- Blizzard's red X; a plain text button if the template is missing.
local ok, close = pcall(CreateFrame, "Button", nil, panel, "UIPanelCloseButton")
if not ok then
    close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    close:SetSize(24, 22)
    close:SetText("X")
end
close:SetPoint("TOPRIGHT", -6, -6)
close:SetScript("OnClick", function() panel:Hide() end)

-- The inset box around the options, as in Blizzard's dialog.
local inset = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
inset:SetPoint("TOPLEFT", 16, -48)
inset:SetPoint("BOTTOMRIGHT", -16, 50)
if inset.SetBackdrop then
    inset:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    inset:SetBackdropColor(0, 0, 0, 0.4)
    inset:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

local header = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 12, -10)
header:SetText("Frames")

-- Blizzard's checkbox (yellow tick) with a label; column 0 or 1.
local checkboxes = {}
local function Checkbox(column, label, get, set)
    local box = CreateFrame("CheckButton", nil, inset)
    box:SetSize(28, 28)
    box:SetPoint("TOPLEFT", 8 + column * 160, -34)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local text = box:CreateFontString(nil, "OVERLAY", LABEL_FONT)
    text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    text:SetText(label)
    box:SetHitRectInsets(0, -(text:GetStringWidth() + 4), 0, 0) -- the label is clickable too
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    box.Refresh = function() box:SetChecked(get()) end
    checkboxes[#checkboxes + 1] = box
end

Checkbox(0, "Rotation Frame", function() return ns.db.hudEnabled end, ns.SetHudEnabled)
Checkbox(1, "Cooldown Frame", function() return ns.db.cdEnabled end, ns.Cooldowns.SetEnabled)

-- Blizzard's red buttons along the bottom.
local function BottomButton(text, point, x, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(150, 24)
    button:SetPoint(point, x, 18)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
end

BottomButton("Reset Positions", "BOTTOMLEFT", 20, function()
    ns.ResetHudLayout()
    ns.Cooldowns.ResetLayout()
end)
BottomButton("Done", "BOTTOMRIGHT", -20, function() panel:Hide() end)

panel:SetScript("OnShow", function()
    for _, box in ipairs(checkboxes) do
        box.Refresh()
    end
end)
-- Closing the panel (X, Done, Esc) leaves edit mode.
panel:SetScript("OnHide", function()
    if ns.IsHudUnlocked() then
        ns.SetHudUnlocked(false)
    end
end)

-- Shown exactly while unlocked, however that happened.
ns.OnSettingsChanged(function()
    if not ns.db then
        return
    end
    panel:SetShown(ns.IsHudUnlocked())
    if panel:IsShown() then
        for _, box in ipairs(checkboxes) do
            box.Refresh()
        end
    end
end)

-- Opens edit mode (the settings window's Edit Mode button).
function ns.OpenEditMode()
    ns.SetHudUnlocked(true)
end
