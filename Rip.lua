-- Rip timer: a red ring around the 5th combo point, full when Rip goes up and draining clockwise.
-- An AuraContainer (see AuraContainer.lua) watches our Rip on the target. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with Rip's real remaining time,
-- even in combat, including refreshes and target switches.
local addonName, ns = ...

local RIP_RANKS = { 1079, 9492, 9493, 9752, 9894, 9896 } -- Forever: each rank's aura has its own ID
local RING_SIZE = ns.COMBO_DOT_SIZE + 7 -- ~3.5px band (ring_rip is 10px thick in 128), touching the dot's edge
local COLOR = { 0.9, 0.15, 0.15 }

local function StyleButton(button)
    ns.HideAuraButtonArt(button)

    local ring = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    ring:SetAllPoints(button)
    ring:SetSwipeTexture(ns.MEDIA .. "ring_rip")
    ring:SetSwipeColor(COLOR[1], COLOR[2], COLOR[3], 1)
    ring:SetDrawEdge(false)
    ring:SetDrawBling(false)
    ring:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(ring) -- Blizzard runs it with the aura's real (secret) timing
end

if ns.HAS_AURA_CONTAINER then
    local x, y = ns.ComboDotOffset(5)
    ns.CreateAuraContainer({
        label = "Rip",
        unit = "target",
        filter = "HARMFUL",
        spellIDs = RIP_RANKS,
        width = RING_SIZE,
        height = RING_SIZE,
        x = x,
        y = y,
        level = 5,
        parent = ns.comboGroup, -- hides with the combo dots outside Cat Form
        initialize = StyleButton,
    })
else
    ns.OnLoad(function()
        ns.Print("this client has no AuraContainer, so the Rip ring is unavailable.")
    end)
end
