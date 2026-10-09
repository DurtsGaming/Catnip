-- Moving and resizing the HUD. Unlock mode (Catnip Edit Mode): drag to move, click
-- to open its settings (on/off, scale and opacity are set there).
local addonName, ns = ...

local DEFAULTS = { x = 0, y = -180, scale = 1, hudAlpha = 0.85, hudEnabled = true }
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2.5, 0.05
local MIN_ALPHA = 0.1 -- never fully invisible: the Show Rotation Frame checkbox is for that

for key, value in pairs(DEFAULTS) do
    ns.defaults[key] = value
end

local hud = ns.hud

hud:SetMovable(true)
hud:SetClampedToScreen(true)
if hud.SetDontSavePosition then
    hud:SetDontSavePosition(true) -- we save it ourselves, not in WoW's layout cache
end

-- Position is stored as the HUD centre's offset from the screen centre, in UIParent units,
-- so changing the scale keeps the HUD centred where it is.
local function ApplyLayout()
    local db = ns.db
    hud:SetShown(db.hudEnabled)
    hud:SetScale(db.scale)
    hud:SetAlpha(db.hudAlpha) -- every element inherits this, AuraContainers included
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
