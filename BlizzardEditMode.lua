-- Catnip's frames in Blizzard's Edit Mode, through LibEditMode (libs/LibEditMode, by p3lim). While
-- Blizzard's Edit Mode is open, the Rotation Frame (the HUD) and the Cooldown Frame get Blizzard's
-- selection box and can be dragged; clicking one opens a Blizzard-style popup with two buttons:
-- Catnip Settings, and the library's own Reset Position. Edit Mode only moves the frames: turning
-- them on or off, scale, opacity and size are in Catnip's settings window. Positions are saved in
-- CatnipDB, one for each frame, whichever Edit Mode layout is active. If the library or Blizzard's
-- Edit Mode is missing, Catnip's own Edit Mode (EditMode.lua) stays in charge.
local addonName, ns = ...

local lib = ns.LibEditMode
if not (lib and lib.AddFrame and EditModeManagerFrame) then
    return
end

local hud = ns.hud
local cooldowns = CatnipCooldowns -- Cooldowns.lua's box

-- A frame's centre as an offset from the screen centre, in UIParent units: how Catnip stores
-- positions.
local function CentreOffset(frame)
    local scale = frame:GetScale()
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    return math.floor(cx * scale - ux + 0.5), math.floor(cy * scale - uy + 0.5)
end

-- Adds buttons to a frame's popup; AddFrameSettingsButtons is the newer name.
local function AddButtons(frame, buttons)
    if lib.AddFrameSettingsButtons then
        lib:AddFrameSettingsButtons(frame, buttons)
    else
        for _, button in ipairs(buttons) do
            lib:AddFrameSettingsButton(frame, button)
        end
    end
end

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

-- The library's Reset Position anchors the HUD at these offsets, which are in the HUD's own
-- (scaled) units, so they follow the scale setting; it also compares them with the HUD's anchor
-- to grey the button out when the HUD is already there.
local hudDefault = { point = "CENTER", x = ns.defaults.x, y = ns.defaults.y }
local function UpdateHudDefault()
    if ns.db then
        hudDefault.x, hudDefault.y = ns.defaults.x / ns.db.scale, ns.defaults.y / ns.db.scale
    end
end
ns.OnLoad(UpdateHudDefault)
ns.OnSettingsChanged(UpdateHudDefault)

lib:AddFrame(hud, function(frame)
    ns.SetHudPosition(CentreOffset(frame))
end, hudDefault, "Catnip: Rotation Frame")
FollowOnClick(hud, "hud")
SnapOnDrop(hud, function(dx, dy)
    ns.SetHudPosition(ns.db.x + dx, ns.db.y + dy)
end)
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
AddButtons(cooldowns, { { text = "Catnip Settings", click = function() ns.OpenSettings("cooldowns") end } })

-- Entering and leaving -----------------------------------------------------------------------------

lib:RegisterCallback("enter", function()
    if ns.IsHudUnlocked() then
        ns.SetHudUnlocked(false) -- Blizzard's Edit Mode takes over from Catnip's own
    end
    ns.Cooldowns.SetPreview(true)
end)
lib:RegisterCallback("exit", function()
    ns.StopSnapPreview()
    ns.Cooldowns.SetPreview(false)
end)

-- Opening Edit Mode (/catnip edit, the Move in Edit Mode buttons in Catnip's settings) now opens Blizzard's.
function ns.OpenEditMode()
    if InCombatLockdown() then
        ns.Print("Edit Mode can't open in combat.")
        return
    end
    ShowUIPanel(EditModeManagerFrame)
end
