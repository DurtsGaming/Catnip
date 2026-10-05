-- DoT timers: a segmented red ring around a combo point for each of our DoTs on the target (Rake
-- on dot 4 in 3 segments, one per 3s tick; Rip on dot 5 in 6, one per 2s tick), full when the DoT
-- goes up and draining clockwise from 12 o'clock.
-- Each ring is an AuraContainer (see AuraContainer.lua) watching that DoT. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with the DoT's real remaining time,
-- even in combat, including refreshes and target switches.
-- The timing is secret, so SegmentedArc.lua (which needs it as a number) can't draw these: the
-- segments are cut into the swipe texture instead (make_textures.py ring_rake, ring_rip_segments;
-- change the count there and regenerate). No per-segment pulses, for the same reason.
-- A shaded red orb sits on each ring at 12 o'clock. It's on the button, so Blizzard shows and
-- hides it with the DoT itself: a plain on/off for "is it still up", which the draining swipe makes
-- hard to read near the end.
local addonName, ns = ...

local DOTS = { -- Forever: each rank's aura has its own ID
    { label = "Rake", dot = 4, texture = "ring_rake", spellIDs = { 1822, 1823, 1824, 9904 } },
    { label = "Rip", dot = 5, texture = "ring_rip_segments", spellIDs = { 1079, 9492, 9493, 9752, 9894, 9896 } },
}
local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- ~5.75px band (16px thick in 128), covering the dot's border ring; make_textures.py COMBO_RING_UNITS
local BAND_OUTER = RING_SIZE * 63 / 128 -- the band's outer edge (63 out, 16 thick, in 128)
local ORB_SIZE = 7 -- smaller than Swing.lua's Maul marker (12), to suit the thinner band
local ORB_Y = BAND_OUTER + ORB_SIZE * 0.2 -- the orb's centre: perched on the ring, its lower part over the band

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

    -- The "still up" orb, sitting on top of the ring at 12 o'clock, where the last segment ends. On its own frame
    -- so it draws over the swipe. Shaded like Swing.lua's Maul marker: orb_dot carries the rings'
    -- red gradient (drawn untinted), with a black rim and soft black backing.
    local orb = CreateFrame("Frame", nil, button)
    orb:SetSize(ORB_SIZE, ORB_SIZE)
    orb:SetPoint("CENTER", button, "CENTER", 0, ORB_Y)
    orb:SetFrameLevel(ring:GetFrameLevel() + 1)

    local shadow = orb:CreateTexture(nil, "ARTWORK", nil, 0)
    shadow:SetTexture(ns.MEDIA .. "circle_soft")
    shadow:SetSize(ORB_SIZE * 1.6, ORB_SIZE * 1.6)
    shadow:SetPoint("CENTER")
    shadow:SetVertexColor(0, 0, 0, 0.8)

    local fill = orb:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetTexture(ns.MEDIA .. "orb_dot")
    fill:SetAllPoints()

    local rim = orb:CreateTexture(nil, "OVERLAY")
    rim:SetTexture(ns.MEDIA .. "ring_small")
    rim:SetVertexColor(0, 0, 0)
    rim:SetAllPoints()
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
