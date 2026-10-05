-- DoT timers: a segmented red ring around a combo point for each of our DoTs on the target (Rake
-- on dot 4 in 3 segments, one per 3s tick; Rip on dot 5 in 6, one per 2s tick), full when the DoT
-- goes up and draining clockwise from 12 o'clock.
-- Each ring is an AuraContainer (see AuraContainer.lua) watching that DoT. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with the DoT's real remaining time,
-- even in combat, including refreshes and target switches.
-- The timing is secret, so SegmentedArc.lua (which needs it as a number) can't draw these: the
-- segments are cut into the swipe texture instead (make_textures.py ring_rake, ring_rip_segments;
-- change the count there and regenerate). No per-segment pulses, for the same reason.
-- A red tick stands across each ring at 12 o'clock. It's on the button, so Blizzard shows and
-- hides it with the DoT itself: a plain on/off for "is it still up", which the draining swipe makes
-- hard to read near the end.
local addonName, ns = ...

local DOTS = { -- Forever: each rank's aura has its own ID
    { label = "Rake", dot = 4, texture = "ring_rake", spellIDs = { 1822, 1823, 1824, 9904 } },
    { label = "Rip", dot = 5, texture = "ring_rip_segments", spellIDs = { 1079, 9492, 9493, 9752, 9894, 9896 } },
}
local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- ~5.75px band (16px thick in 128), covering the dot's border ring; make_textures.py COMBO_RING_UNITS
local BAND_INNER = RING_SIZE * 47 / 128 -- the band's inner edge (63 out, 16 thick, in 128)
local TICK_TOP = RING_SIZE * 63 / 128 + 3 -- the band's outer edge, plus how far the tick stands above it
local TICK_WIDTH = 2.5
local TICK_OUTLINE = 0.75

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

    -- The "still up" tick: a red bar shaded like the rings (tick_dot, drawn untinted) in a thin black
    -- outline, standing across the band at 12 o'clock (where the last segment ends) from its inner
    -- edge to a little above it. On its own frame so it draws over the swipe.
    local tick = CreateFrame("Frame", nil, button)
    tick:SetSize(TICK_WIDTH + 2 * TICK_OUTLINE, TICK_TOP - BAND_INNER + 2 * TICK_OUTLINE)
    tick:SetPoint("BOTTOM", button, "CENTER", 0, BAND_INNER - TICK_OUTLINE)
    tick:SetFrameLevel(ring:GetFrameLevel() + 1)

    local outline = tick:CreateTexture(nil, "ARTWORK", nil, 0)
    outline:SetColorTexture(0, 0, 0, 1)
    outline:SetAllPoints()

    local fill = tick:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetTexture(ns.MEDIA .. "tick_dot")
    fill:SetPoint("TOPLEFT", TICK_OUTLINE, -TICK_OUTLINE)
    fill:SetPoint("BOTTOMRIGHT", -TICK_OUTLINE, TICK_OUTLINE)
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
