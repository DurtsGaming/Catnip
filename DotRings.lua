-- DoT timers: a segmented red ring around a combo point for each of our DoTs on the target (Rake
-- on dot 4 in 3 segments, one per 3s tick; Rip on dot 5 in 6, one per 2s tick), full when the DoT
-- goes up and draining clockwise from 12 o'clock.
-- Each ring is an AuraContainer (see AuraContainer.lua) watching that DoT. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with the DoT's real remaining time,
-- even in combat, including refreshes and target switches.
-- The timing is secret, so SegmentedArc.lua (which needs it as a number) can't draw these: the
-- segments are cut into the swipe texture instead (make_textures.py ring_rake, ring_rip_segments;
-- change the count there and regenerate). No per-segment pulses, for the same reason.
local addonName, ns = ...

local DOTS = { -- Forever: each rank's aura has its own ID
    { label = "Rake", dot = 4, texture = "ring_rake", spellIDs = { 1822, 1823, 1824, 9904 } },
    { label = "Rip", dot = 5, texture = "ring_rip_segments", spellIDs = { 1079, 9492, 9493, 9752, 9894, 9896 } },
}
local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- ~5.75px band (16px thick in 128), covering the dot's border ring; make_textures.py COMBO_RING_UNITS

local function StyleButton(button, texture)
    ns.HideAuraButtonArt(button)

    local ring = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    ring:SetAllPoints(button)
    ring:SetSwipeTexture(ns.MEDIA .. texture) -- coloured, so untinted
    ring:SetSwipeColor(1, 1, 1, 1)
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
            parent = ns.comboGroup, -- hides with the combo dots outside Cat and Bear Form
            initialize = function(button)
                StyleButton(button, dot.texture)
            end,
        })
    end
else
    ns.OnLoad(function()
        ns.Print("this client has no AuraContainer, so the DoT rings are unavailable.")
    end)
end
