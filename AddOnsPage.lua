-- Catnip's entry in Blizzard's settings (Options → AddOns). Every setting lives in Catnip's own
-- window, so the page only points there: the druid icon, name and version, a button that closes
-- Blizzard's settings and opens ours, and the /catnip command. Same idea as Leatrix Plus's page.
local addonName, ns = ...

if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
end

local DRUID_ICON = 625999 -- Interface\Icons\ClassIcon_Druid, as the settings window's portrait

local page = CreateFrame("Frame")

local icon = page:CreateTexture(nil, "ARTWORK")
icon:SetSize(96, 96)
icon:SetPoint("TOP", 0, -64)
icon:SetTexture(DRUID_ICON)

local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
title:SetPoint("TOP", icon, "BOTTOM", 0, -20)
title:SetText("Catnip")
local titleFont, _, titleFlags = title:GetFont()
title:SetFont(titleFont, 48, titleFlags)

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
version:SetPoint("TOP", title, "BOTTOM", 0, -8)
version:SetText(GetMetadata and GetMetadata(addonName, "Version") or "")

local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
open:SetSize(200, 32)
open:SetPoint("TOP", version, "BOTTOM", 0, -40)
open:SetText("Open Catnip Settings")
open:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    ns.ShowSettings()
end)

local command = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
command:SetPoint("TOP", open, "BOTTOM", 0, -16)
command:SetText("or type /catnip")

local category = Settings.RegisterCanvasLayoutCategory(page, "Catnip")
Settings.RegisterAddOnCategory(category)
