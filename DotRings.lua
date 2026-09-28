-- DoT timers: a red ring around a combo point for each of our DoTs on the target (Rake on dot 4,
-- Rip on dot 5), full when the DoT goes up and draining clockwise.
-- Each ring is an AuraContainer (see AuraContainer.lua) watching that DoT. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with the DoT's real remaining time,
-- even in combat, including refreshes and target switches.
local addonName, ns = ...

local DOTS = { -- Forever: each rank's aura has its own ID
    { label = "Rake", dot = 4, spellIDs = { 1822, 1823, 1824, 9904 } },
    { label = "Rip", dot = 5, spellIDs = { 1079, 9492, 9493, 9752, 9894, 9896 } },
}
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
    for _, dot in ipairs(DOTS) do
        local x, y = ns.ComboDotOffset(dot.dot)
        ns.CreateAuraContainer({
            label = dot.label,
            unit = "target",
            filter = "HARMFUL",
            spellIDs = dot.spellIDs,
            width = RING_SIZE,
            height = RING_SIZE,
            x = x,
            y = y,
            level = 5,
            parent = ns.comboGroup, -- hides with the combo dots outside Cat Form
            initialize = StyleButton,
        })
    end
else
    ns.OnLoad(function()
        ns.Print("this client has no AuraContainer, so the DoT rings are unavailable.")
    end)
end
