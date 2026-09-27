-- Moving and resizing the HUD. /catnip toggles unlock mode: drag to move, mouse wheel to resize.
local addonName, ns = ...

local DEFAULTS = { x = 0, y = -180, scale = 1 }
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2.5, 0.05

local hud = ns.hud
local db

hud:SetMovable(true)
hud:SetClampedToScreen(true)
if hud.SetDontSavePosition then
    hud:SetDontSavePosition(true) -- we save it ourselves, not in WoW's layout cache
end

-- Position is stored as the HUD centre's offset from the screen centre, in UIParent units,
-- so changing the scale keeps the HUD centred where it is.
local function ApplyLayout()
    hud:SetScale(db.scale)
    hud:ClearAllPoints()
    hud:SetPoint("CENTER", UIParent, "CENTER", db.x / db.scale, db.y / db.scale)
end

local function SavePosition()
    local scale = hud:GetScale()
    local cx, cy = hud:GetCenter()
    local ux, uy = UIParent:GetCenter()
    db.x = cx * scale - ux
    db.y = cy * scale - uy
    ApplyLayout()
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
    label:SetText(string.format("Catnip %d%%: drag to move, scroll to resize", db.scale * 100 + 0.5))
end

overlay:SetScript("OnDragStart", function()
    hud:StartMoving()
end)
overlay:SetScript("OnDragStop", function()
    hud:StopMovingOrSizing()
    SavePosition()
end)
overlay:SetScript("OnMouseWheel", function(_, delta)
    db.scale = math.min(MAX_SCALE, math.max(MIN_SCALE, db.scale + delta * SCALE_STEP))
    ApplyLayout()
    UpdateLabel()
end)

local function SetUnlocked(unlocked)
    overlay:SetShown(unlocked)
    UpdateLabel()
    print("|cff33ff99Catnip|r " .. (unlocked and "unlocked. Type /catnip again to lock." or "locked."))
end

SLASH_CATNIP1 = "/catnip"
SlashCmdList.CATNIP = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg):lower(), 2)
    if cmd == "" then
        SetUnlocked(not overlay:IsShown())
    elseif cmd == "reset" then
        db.x, db.y, db.scale = DEFAULTS.x, DEFAULTS.y, DEFAULTS.scale
        ApplyLayout()
        UpdateLabel()
    elseif cmd == "scale" and tonumber(arg) then
        db.scale = math.min(MAX_SCALE, math.max(MIN_SCALE, tonumber(arg)))
        ApplyLayout()
        UpdateLabel()
    else
        print("|cff33ff99Catnip|r commands: /catnip (lock/unlock), /catnip scale <0.5-2.5>, /catnip reset")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then
        return
    end
    CatnipDB = CatnipDB or {}
    db = CatnipDB
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then
            db[key] = value
        end
    end
    ApplyLayout()
    self:UnregisterEvent("ADDON_LOADED")
end)
