-- Moving and resizing the HUD. Unlock mode (settings window or /catnip unlock): drag to move,
-- mouse wheel to resize.
local addonName, ns = ...

local DEFAULTS = { x = 0, y = -180, scale = 1 }
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2.5, 0.05

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
    hud:SetScale(db.scale)
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
local overlay = CreateFrame("Frame", nil, hud)
overlay:SetAllPoints()
overlay:SetFrameLevel(hud:GetFrameLevel() + 20)
overlay:EnableMouse(true)
overlay:EnableMouseWheel(true)
overlay:RegisterForDrag("LeftButton")
overlay:Hide()

local tint = overlay:CreateTexture(nil, "BACKGROUND")
tint:SetAllPoints()
tint:SetColorTexture(0.2, 0.6, 1, 0.25)

local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("BOTTOM", overlay, "TOP", 0, 4)

local function UpdateLabel()
    label:SetText(string.format("Catnip %d%%: drag to move, scroll to resize", ns.db.scale * 100 + 0.5))
end

ns.MIN_SCALE, ns.MAX_SCALE, ns.SCALE_STEP = MIN_SCALE, MAX_SCALE, SCALE_STEP

local function SetScale(scale)
    ns.db.scale = math.min(MAX_SCALE, math.max(MIN_SCALE, scale))
    ApplyLayout()
    UpdateLabel()
    ns.SettingsChanged()
end
ns.SetHudScale = SetScale

function ns.IsHudUnlocked()
    return overlay:IsShown()
end

function ns.SetHudUnlocked(unlocked)
    overlay:SetShown(unlocked)
    UpdateLabel()
    ns.SettingsChanged()
end

function ns.ResetHudLayout()
    ns.db.x, ns.db.y = DEFAULTS.x, DEFAULTS.y
    SetScale(DEFAULTS.scale)
end

overlay:SetScript("OnDragStart", function()
    hud:StartMoving()
end)
overlay:SetScript("OnDragStop", function()
    hud:StopMovingOrSizing()
    SavePosition()
end)
overlay:SetScript("OnMouseWheel", function(_, delta)
    SetScale(ns.db.scale + delta * SCALE_STEP)
end)

ns.commands.unlock = function()
    ns.SetHudUnlocked(true)
    ns.Print("unlocked. Type /catnip lock when done.")
end

ns.commands.lock = function()
    ns.SetHudUnlocked(false)
    ns.Print("locked.")
end

ns.commands.reset = ns.ResetHudLayout

ns.commands.scale = function(arg)
    local scale = tonumber(arg)
    if scale then
        SetScale(scale)
    else
        ns.Print("usage: /catnip scale <0.5-2.5>")
    end
end

ns.OnLoad(ApplyLayout)
