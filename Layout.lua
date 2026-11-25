-- Moving and resizing the HUD. Unlock mode (Catnip Edit Mode): drag to move, click
-- to open its settings (on/off, scale and opacity are set there).
local addonName, ns = ...
local L = ns.L
local CreateFrame = ns.Profiled("Layout") -- timed by /catnip perf (Profiler.lua)

local DEFAULTS = { x = 0, y = -285, scale = 1, hudAlpha = 0.95, hudEnabled = true }
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2.5, 0.05
local MIN_ALPHA = 0.1 -- never fully invisible: the Show Rotation Frame checkbox is for that

for key, value in pairs(DEFAULTS) do
    ns.defaults[key] = value
end

local hud = ns.hud
local stealthShare = 1 -- Stealth opacity (below): a share of Overall opacity while stealthed
local showInForm = { caster = true, bear = true, cat = true } -- the Forms page (below)

-- The player's form from their power type, as Preview.lua reads it: Rage is Bear Form, Energy (or a
-- secret power type) Cat Form, anything else (mana: caster, Moonkin, Travel...) Caster.
local function CurrentForm()
    local powerType = UnitPowerType("player")
    if ns.IsSecret(powerType) or powerType == Enum.PowerType.Energy then
        return "cat"
    elseif powerType == Enum.PowerType.Rage then
        return "bear"
    end
    return "caster"
end

-- Whether the HUD shows in the current form. In preview mode (the settings window's Rotation tab)
-- the form is the previewed one, so switching a form off shows there too. Always while it's being
-- moved: Catnip's Edit Mode, or Blizzard's.
local function ShownInForm()
    if (ns.IsHudUnlocked and ns.IsHudUnlocked())
        or (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        return true
    end
    local previewing = ns.Preview and ns.Preview.IsActive()
    return showInForm[previewing and ns.Preview.GetState() or CurrentForm()]
end

-- Overall opacity, times Stealth opacity while stealthed (Prowl or Shadowmeld); 0 in a form the HUD
-- is switched off for. Alpha rather than Hide: the HUD holds AuraContainers, and alpha is safe to
-- change in combat, where most form changes happen.
local function HudAlpha()
    if not ShownInForm() then
        return 0
    end
    return ns.db.hudAlpha * (ns.IsStealthMode() and stealthShare or 1)
end

-- Re-reads the form (and preview / Edit Mode) and fades the HUD to match.
function ns.RefreshHudAlpha()
    if ns.db then
        hud:SetAlpha(HudAlpha())
        if ns.Preview and ns.Preview.SetFormHidden then
            ns.Preview.SetFormHidden(not ShownInForm()) -- its outlines ignore the HUD's alpha
        end
    end
end

hud:SetMovable(true)
hud:SetClampedToScreen(true)
if hud.SetDontSavePosition then
    hud:SetDontSavePosition(true) -- we save it ourselves, not in WoW's layout cache
end

-- Position is stored as the HUD centre's offset from the screen centre, in UIParent units,
-- so changing the scale keeps the HUD centred where it is.
-- The HUD frame's height, which both Edit Modes outline: at least its 240 square (the circle, ring,
-- arcs and combo point rings fit, up to ~119 above the centre), taller when the text under the orbs
-- reaches further down (Cast.lua sets how far). It grows evenly both ways: everything is anchored to
-- the centre, so nothing moves. Not in combat (the HUD holds AuraContainers): applied after.
local BASE_SIZE = 240
local TEXT_MARGIN = 4 -- room below the lowest text
local textBottom = 0

local function ApplySize()
    if InCombatLockdown() then
        return
    end
    hud:SetHeight(math.max(BASE_SIZE, 2 * math.ceil(textBottom + TEXT_MARGIN)))
end

-- How far below the HUD's centre its lowest text reaches, in HUD units.
function ns.SetHudTextBottom(bottom)
    textBottom = bottom
    ApplySize()
end

local sizeEvents = CreateFrame("Frame")
sizeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
sizeEvents:SetScript("OnEvent", ApplySize)

local function ApplyLayout()
    local db = ns.db
    ApplySize()
    hud:SetShown(db.hudEnabled)
    hud:SetScale(db.scale)
    hud:SetAlpha(HudAlpha()) -- every element inherits this, AuraContainers included
    hud:ClearAllPoints()
    hud:SetPoint("CENTER", UIParent, "CENTER", db.x / db.scale, db.y / db.scale)
end

local function SavePosition()
    local scale = hud:GetScale()
    local cx, cy = hud:GetCenter()
    local ux, uy = UIParent:GetCenter()
    ns.db.x = cx * scale - ux
    ns.db.y = cy * scale - uy
    ApplyLayout()
    ns.SettingsChanged()
end

-- Offset of the HUD centre from the screen centre, in UIParent units.
function ns.SetHudPosition(x, y)
    ns.db.x, ns.db.y = x, y
    ApplyLayout()
    ns.SettingsChanged()
end

-- Unlock overlay: catches the mouse only while unlocked, so the HUD never blocks clicks otherwise.
-- Clicking it opens the settings where its position and scale are.
local overlay = ns.CreateUnlockOverlay(hud, L["Rotation Frame"], function() ns.OpenSettings("hud") end)

ns.MIN_SCALE, ns.MAX_SCALE, ns.SCALE_STEP = MIN_SCALE, MAX_SCALE, SCALE_STEP

local function SetScale(scale)
    ns.db.scale = math.min(MAX_SCALE, math.max(MIN_SCALE, scale))
    ApplyLayout()
    ns.SettingsChanged()
end
ns.SetHudScale = SetScale

ns.MIN_ALPHA = MIN_ALPHA

-- Opacity of the whole HUD, MIN_ALPHA to 1. The unlock overlay ignores it.
function ns.SetHudAlpha(alpha)
    ns.db.hudAlpha = math.min(1, math.max(MIN_ALPHA, alpha))
    ApplyLayout()
    ns.SettingsChanged()
end

-- Turns the whole Rotation Frame (the HUD) on or off (the settings window's checkbox).
function ns.SetHudEnabled(enabled)
    ns.db.hudEnabled = enabled
    ApplyLayout()
    ns.SettingsChanged()
end

-- Scale, opacity and on/off back to their defaults (the settings window's Reset…). Position stays:
-- Edit Mode's Reset Position does that.
function ns.ResetHudLook()
    ns.db.scale, ns.db.hudAlpha, ns.db.hudEnabled = DEFAULTS.scale, DEFAULTS.hudAlpha, DEFAULTS.hudEnabled
    ApplyLayout()
    ns.SettingsChanged()
end

function ns.IsHudUnlocked()
    return overlay:IsShown()
end

function ns.SetHudUnlocked(unlocked)
    overlay:SetShown(unlocked)
    ns.SettingsChanged()
end

function ns.ResetHudPosition()
    ns.SetHudPosition(DEFAULTS.x, DEFAULTS.y)
end

overlay:SetScript("OnDragStart", function()
    hud:StartMoving()
end)
overlay:SetScript("OnDragStop", function()
    hud:StopMovingOrSizing()
    SavePosition()
end)

ns.OnLoad(ApplyLayout)

-- Stealth Mode, under General in the settings window: Enabled turns stealth's whole look on or off
-- (Stealth.lua: periwinkle fill, smoke, dimmer orbs and this opacity); while stealthed (Prowl or
-- Shadowmeld) the HUD's opacity is the share of Overall opacity, one value for both.
ns.RegisterElement({
    id = "stealth",
    name = L["Stealth Mode"],
    glyph = { kind = "disc", color = { 0.56, 0.55, 0.94 } },
    options = {
        { key = "enabled", type = "checkbox", label = L["Enabled"], default = true },
        { key = "opacity", type = "slider", label = L["Opacity while stealthed"], min = 10, max = 100, step = 5,
            format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        ns.SetStealthModeEnabled(get("enabled"))
        stealthShare = get("opacity") / 100
        hud:SetAlpha(HudAlpha())
    end,
})
ns.OnStealthChanged(function() hud:SetAlpha(HudAlpha()) end)

-- Forms, under General in the settings window: which forms the Rotation Frame shows in (all by
-- default). Switched off in a form, the HUD fades out while in it (HudAlpha).
ns.RegisterElement({
    id = "forms",
    name = L["Forms"],
    glyph = { kind = "disc", color = { 0.85, 0.65, 0.3 } },
    options = {
        { key = "caster", type = "checkbox", label = L["Caster"], default = true },
        { key = "bear", type = "checkbox", label = L["Bear"], default = true },
        { key = "cat", type = "checkbox", label = L["Cat"], default = true },
    },
    apply = function(get)
        showInForm.caster, showInForm.bear, showInForm.cat = get("caster"), get("bear"), get("cat")
        ns.RefreshHudAlpha()
    end,
})

local formEvents = CreateFrame("Frame")
formEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
formEvents:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") -- into and out of Bear and Cat Form
formEvents:SetScript("OnEvent", ns.RefreshHudAlpha)
ns.OnSettingsChanged(ns.RefreshHudAlpha) -- Catnip's Edit Mode opening or closing
if EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnShow", ns.RefreshHudAlpha)
    EditModeManagerFrame:HookScript("OnHide", ns.RefreshHudAlpha)
end
