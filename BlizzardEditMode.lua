-- Catnip's frames in Blizzard's Edit Mode, through LibEditMode (libs/LibEditMode, by p3lim). While
-- Blizzard's Edit Mode is open, the Rotation Frame (the HUD) and the Cooldown Frame get Blizzard's
-- selection box and can be dragged; clicking one opens a Blizzard-style settings popup with its
-- sliders and a button to Catnip's settings. A small Catnip section under Blizzard's Edit Mode
-- panel turns each frame on or off. Positions stay in CatnipDB as before; EditModeLayouts.lua keeps
-- a copy per Edit Mode layout. If the library or Blizzard's Edit Mode is missing, Catnip's own Edit Mode
-- (EditMode.lua) stays in charge.
local addonName, ns = ...

local lib = ns.LibEditMode
if not (lib and lib.AddFrame and EditModeManagerFrame) then
    return
end

local hud = ns.hud
local cooldowns = CatnipCooldowns -- Cooldowns.lua's box
local LABEL_FONT = _G.GameFontHighlightMedium and "GameFontHighlightMedium" or "GameFontHighlight"

-- A frame's centre as an offset from the screen centre, in UIParent units: how Catnip stores
-- positions.
local function CentreOffset(frame)
    local scale = frame:GetScale()
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    return math.floor(cx * scale - ux + 0.5), math.floor(cy * scale - uy + 0.5)
end

local function Percent(value)
    return string.format("%d%%", value)
end

-- Adds settings to a frame's popup; AddFrameSettingsButtons is the newer name for the buttons.
local function AddButtons(frame, buttons)
    if lib.AddFrameSettingsButtons then
        lib:AddFrameSettingsButtons(frame, buttons)
    else
        for _, button in ipairs(buttons) do
            lib:AddFrameSettingsButton(frame, button)
        end
    end
end

local Slider = lib.SettingType.Slider

-- Snaps a frame when it's dropped, showing red lines where it will snap while it's dragged
-- (EditModeSnap.lua). The drop runs after LibEditMode's own, which has already saved the dropped
-- position; move(dx, dy) saves the snapped one.
local function SnapOnDrop(frame, move)
    local selection = lib.frameSelections and lib.frameSelections[frame]
    if not (selection and ns.EditModeSnapOffset) then
        return
    end
    selection:HookScript("OnDragStart", function()
        if not InCombatLockdown() then
            ns.StartSnapPreview(frame, lib.frameSelections)
        end
    end)
    selection:HookScript("OnDragStop", function()
        ns.StopSnapPreview()
        if InCombatLockdown() then
            return
        end
        local dx, dy = ns.EditModeSnapOffset(frame, lib.frameSelections)
        if dx ~= 0 or dy ~= 0 then
            move(dx, dy)
        end
    end)
end

-- Clicking (selecting) a frame turns an open Catnip settings window to that frame's settings.
local function FollowOnClick(frame, where)
    local selection = lib.frameSelections and lib.frameSelections[frame]
    if selection then
        selection:HookScript("OnMouseDown", function()
            if ns.FollowSettings then
                ns.FollowSettings(where)
            end
        end)
    end
end

-- Rotation Frame ---------------------------------------------------------------------------------

lib:AddFrame(hud, function(frame)
    ns.SetHudPosition(CentreOffset(frame))
end, { point = "CENTER", x = ns.defaults.x, y = ns.defaults.y }, "Catnip: Rotation Frame")
FollowOnClick(hud, "hud")
SnapOnDrop(hud, function(dx, dy)
    ns.SetHudPosition(ns.db.x + dx, ns.db.y + dy)
end)

lib:AddFrameSettings(hud, {
    {
        kind = Slider, name = "Scale", default = ns.defaults.scale * 100,
        minValue = ns.MIN_SCALE * 100, maxValue = ns.MAX_SCALE * 100, valueStep = ns.SCALE_STEP * 100,
        formatter = Percent,
        get = function() return ns.db.scale * 100 end,
        set = function(_, value) ns.SetHudScale(value / 100) end,
    },
    {
        kind = Slider, name = "Opacity", default = ns.defaults.hudAlpha * 100,
        minValue = ns.MIN_ALPHA * 100, maxValue = 100, valueStep = 5,
        formatter = Percent,
        get = function() return ns.db.hudAlpha * 100 end,
        set = function(_, value) ns.SetHudAlpha(value / 100) end,
    },
})
AddButtons(hud, { { text = "Catnip Settings", click = function() ns.OpenSettings("hud") end } })

-- Cooldown Frame ---------------------------------------------------------------------------------

lib:AddFrame(cooldowns, function(frame)
    local x, y = CentreOffset(frame)
    ns.Cooldowns.SetLayout(x, y, ns.db.cdWidth, ns.db.cdHeight)
end, { point = "CENTER", x = ns.defaults.cdX, y = ns.defaults.cdY }, "Catnip: Cooldown Frame")
FollowOnClick(cooldowns, "cooldowns")
SnapOnDrop(cooldowns, function(dx, dy)
    ns.Cooldowns.SetLayout(ns.db.cdX + dx, ns.db.cdY + dy, ns.db.cdWidth, ns.db.cdHeight)
end)

lib:AddFrameSettings(cooldowns, {
    {
        kind = Slider, name = "Width", default = ns.defaults.cdWidth,
        minValue = ns.Cooldowns.MIN_SIZE, maxValue = 800, valueStep = 1,
        get = function() return ns.db.cdWidth end,
        set = function(_, value)
            ns.Cooldowns.SetLayout(ns.db.cdX, ns.db.cdY, value, ns.db.cdHeight)
        end,
    },
    {
        kind = Slider, name = "Height", default = ns.defaults.cdHeight,
        minValue = ns.Cooldowns.MIN_SIZE, maxValue = 400, valueStep = 1,
        get = function() return ns.db.cdHeight end,
        set = function(_, value)
            ns.Cooldowns.SetLayout(ns.db.cdX, ns.db.cdY, ns.db.cdWidth, value)
        end,
    },
    {
        kind = Slider, name = "Opacity", default = ns.defaults.cdAlpha * 100,
        minValue = ns.MIN_ALPHA * 100, maxValue = 100, valueStep = 5,
        formatter = Percent,
        get = function() return ns.db.cdAlpha * 100 end,
        set = function(_, value) ns.Cooldowns.SetAlpha(value / 100) end,
    },
})
AddButtons(cooldowns, { { text = "Catnip Settings", click = function() ns.OpenSettings("cooldowns") end } })

-- Catnip section under Blizzard's Edit Mode panel -------------------------------------------------

-- Our own frame (on UIParent, only anchored to Blizzard's panel), so nothing of ours runs inside
-- Blizzard's Edit Mode code. Styled like Catnip Edit Mode's panel (EditMode.lua).
local section = CreateFrame("Frame", "CatnipEditModeSection", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
section:SetFrameStrata(EditModeManagerFrame:GetFrameStrata())
section:SetPoint("TOPLEFT", EditModeManagerFrame, "BOTTOMLEFT", 0, 2)
section:SetPoint("TOPRIGHT", EditModeManagerFrame, "BOTTOMRIGHT", 0, 2)
section:SetHeight(84)
section:Hide()
if section.SetBackdrop then
    section:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 20, -18)
header:SetText("Catnip")

-- Blizzard's checkbox (yellow tick) with a label; column 0 or 1.
local checkboxes = {}
local function Checkbox(column, label, get, set)
    local box = CreateFrame("CheckButton", nil, section)
    box:SetSize(28, 28)
    box:SetPoint("TOPLEFT", 16 + column * 150, -40)
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

local function Refresh()
    for _, box in ipairs(checkboxes) do
        box.Refresh()
    end
end

lib:RegisterCallback("enter", function()
    if ns.IsHudUnlocked() then
        ns.SetHudUnlocked(false) -- Blizzard's Edit Mode takes over from Catnip's own
    end
    Refresh()
    section:Show()
    ns.Cooldowns.SetPreview(true)
end)
lib:RegisterCallback("exit", function()
    ns.StopSnapPreview()
    section:Hide()
    ns.Cooldowns.SetPreview(false)
end)
ns.OnSettingsChanged(function()
    if section:IsShown() then
        Refresh()
    end
end)

-- Opening Edit Mode (/catnip edit, the Edit Mode button in Catnip's settings) now opens Blizzard's.
function ns.OpenEditMode()
    if InCombatLockdown() then
        ns.Print("Edit Mode can't open in combat.")
        return
    end
    ShowUIPanel(EditModeManagerFrame)
end
