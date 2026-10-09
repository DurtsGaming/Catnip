-- Moving and resizing the HUD. Unlock mode (Catnip Edit Mode): drag to move, click
-- to open its settings (on/off, scale and opacity are set there).
local addonName, ns = ...

local DEFAULTS = { x = 0, y = -285, scale = 1, hudAlpha = 0.95, hudEnabled = true }
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2.5, 0.05
local MIN_ALPHA = 0.1 -- never fully invisible: the Show Rotation Frame checkbox is for that

for key, value in pairs(DEFAULTS) do
    ns.defaults[key] = value
end

local hud = ns.hud
local stealthShare = 1 -- Stealth opacity (below): a share of Overall opacity while stealthed

-- Overall opacity, times Stealth opacity while stealthed (Prowl or Shadowmeld).
local function HudAlpha()
    return ns.db.hudAlpha * (ns.IsStealthMode() and stealthShare or 1)
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
local overlay = ns.CreateUnlockOverlay(hud, "Rotation Frame", function() ns.OpenSettings("hud") end)

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
    name = "Stealth Mode",
    glyph = { kind = "disc", color = { 0.56, 0.55, 0.94 } },
    options = {
        { key = "enabled", type = "checkbox", label = "Enabled", default = true },
        { key = "opacity", type = "slider", label = "Share of Overall opacity", min = 10, max = 100, step = 5,
            format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        ns.SetStealthModeEnabled(get("enabled"))
        stealthShare = get("opacity") / 100
        hud:SetAlpha(HudAlpha())
    end,
})
ns.OnStealthChanged(function() hud:SetAlpha(HudAlpha()) end)
