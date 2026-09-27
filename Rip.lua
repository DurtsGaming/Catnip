-- Rip timer: a thin red layer just outside the swing ring, full when Rip goes up and draining clockwise.
-- An AuraContainer (see AuraContainer.lua) watches our Rip on the target. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with Rip's real remaining time,
-- even in combat, including refreshes and target switches.
local addonName, ns = ...

local RIP_RANKS = { 1079, 9492, 9493, 9752, 9894, 9896 } -- Forever: each rank's aura has its own ID
local COLOR = { 0.9, 0.15, 0.15 }

local function StyleButton(button)
    ns.HideAuraButtonArt(button)

    local ring = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    ring:SetAllPoints(button)
    ring:SetSwipeTexture(ns.MEDIA .. "ring_dot")
    ring:SetSwipeColor(COLOR[1], COLOR[2], COLOR[3], 1)
    ring:SetDrawEdge(false)
    ring:SetDrawBling(false)
    ring:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(ring) -- Blizzard runs it with the aura's real (secret) timing
end

if ns.HAS_AURA_CONTAINER then
    ns.CreateAuraContainer({
        label = "Rip",
        unit = "target",
        filter = "HARMFUL",
        spellIDs = RIP_RANKS,
        width = ns.DOT_RING_SIZE,
        height = ns.DOT_RING_SIZE,
        level = 5,
        initialize = StyleButton,
    })
else
    ns.OnLoad(function()
        ns.Print("this client has no AuraContainer, so the Rip ring is unavailable.")
    end)
end
