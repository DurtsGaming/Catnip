-- Catnip Edit Mode: a panel styled like Blizzard's "HUD Edit Mode" dialog, shown while the widgets
-- are unlocked (the settings window's Move in Edit Mode buttons, or /catnip edit). Only the fallback for
-- when Blizzard's Edit Mode can't be used (BlizzardEditMode.lua). Like there, it only moves the
-- frames: turning them on or off is in the settings window. Closing the panel locks them again.
-- Built from Blizzard's stock textures and templates (dialog border, red panel buttons) to match
-- its look.
local addonName, ns = ...

local WIDTH, HEIGHT = 360, 132

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

local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hint:SetPoint("TOPLEFT", 24, -50)
hint:SetPoint("TOPRIGHT", -24, -50)
hint:SetText("Drag a frame to move it. Click it for its settings.")

-- Blizzard's red buttons along the bottom.
local function BottomButton(text, point, x, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(150, 24)
    button:SetPoint(point, x, 18)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
end

BottomButton("Reset Positions", "BOTTOMLEFT", 20, function()
    ns.ResetHudPosition()
    ns.Cooldowns.ResetPosition()
end)
BottomButton("Done", "BOTTOMRIGHT", -20, function() panel:Hide() end)

-- Closing the panel (X, Done, Esc) leaves edit mode.
panel:SetScript("OnHide", function()
    if ns.IsHudUnlocked() then
        ns.SetHudUnlocked(false)
    end
end)

-- Shown exactly while unlocked, however that happened.
ns.OnSettingsChanged(function()
    if ns.db then
        panel:SetShown(ns.IsHudUnlocked())
    end
end)

-- Opens edit mode (the settings window's Move in Edit Mode buttons).
function ns.OpenEditMode()
    ns.SetHudUnlocked(true)
end
