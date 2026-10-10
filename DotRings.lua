-- DoT timers: a segmented red ring around a combo point for each of our DoTs on the target (Rake in
-- 3 segments, one per 3s tick; Rip in 6, one per 2s tick), full when the DoT goes up and draining
-- clockwise from 12 o'clock. Each sits in whichever combo ring slot the player picks for it
-- (ComboRings.lua; by default dots 4 and 5).
-- Each ring is an AuraContainer (see AuraContainer.lua) watching that DoT. We give its button a
-- Cooldown frame whose swipe is our ring, and Blizzard drives it with the DoT's real remaining time,
-- even in combat, including refreshes and target switches. AuraContainers can't be moved in combat,
-- so each DoT gets one per slot it has been in, made the first time it's picked there (after combat,
-- if picked in combat); only the current slot's shows.
-- The timing is secret, so SegmentedArc.lua (which needs it as a number) can't draw these: the
-- segments are cut into the swipe texture instead (make_textures.py ring_rake, ring_rip_segments;
-- change the count there and regenerate). No per-segment pulses, for the same reason.
-- A red tick stands across each ring at 12 o'clock. It's on the button, so Blizzard shows and
-- hides it with the DoT itself: a plain on/off for "is it still up", which the draining swipe makes
-- hard to read near the end.
local addonName, ns = ...

-- Forever: each rank's aura has its own ID. key: saved in the combo ring settings; order: in their
-- dropdown; dot: its slot by default; length: the sample's, in preview mode.
local DOTS = {
    { key = "rake", label = "Rake", order = 4, dot = 4, texture = "ring_rake", length = 9,
        color = { 0.82, 0.23, 0.14 }, -- its glyph in the settings list
        spellIDs = { 1822, 1823, 1824, 9904 } },
    { key = "rip", label = "Rip", order = 5, dot = 5, texture = "ring_rip_segments", length = 12,
        color = { 0.69, 0.12, 0.12 },
        spellIDs = { 1079, 9492, 9493, 9752, 9894, 9896 } },
}
local LEVEL = 5 -- above the HUD, as the AuraContainers
local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- ~5.75px band (16px thick in 128), covering the dot's border ring; make_textures.py COMBO_RING_UNITS
local BAND_INNER = RING_SIZE * 47 / 128 -- the band's inner edge (63 out, 16 thick, in 128)
local TICK_TOP = RING_SIZE * 63 / 128 + 3 -- the band's outer edge, plus how far the tick stands above it
local TICK_WIDTH = 2.5
local TICK_OUTLINE = 0.75

-- The ring and tick on `owner` (an aura button, or preview mode's stand-in); returns the ring's
-- Cooldown.
local function BuildRing(owner, texture)
    local ring = CreateFrame("Cooldown", nil, owner, "CooldownFrameTemplate")
    ring:ClearAllPoints() -- the template pins it to its parent; set it ourselves
    ring:SetAllPoints(owner)
    ring:SetSwipeTexture(ns.MEDIA .. texture) -- coloured, so untinted
    ring:SetSwipeColor(1, 1, 1, 1)
    ring:SetDrawEdge(false)
    ring:SetDrawBling(false)
    ring:SetHideCountdownNumbers(true)

    -- The "still up" tick: a red bar shaded like the rings (tick_dot, drawn untinted) in a thin black
    -- outline, standing across the band at 12 o'clock (where the last segment ends) from its inner
    -- edge to a little above it. On its own frame so it draws over the swipe.
    local tick = CreateFrame("Frame", nil, owner)
    tick:SetSize(TICK_WIDTH + 2 * TICK_OUTLINE, TICK_TOP - BAND_INNER + 2 * TICK_OUTLINE)
    tick:SetPoint("BOTTOM", owner, "CENTER", 0, BAND_INNER - TICK_OUTLINE)
    tick:SetFrameLevel(ring:GetFrameLevel() + 1)

    local outline = tick:CreateTexture(nil, "ARTWORK", nil, 0)
    outline:SetColorTexture(0, 0, 0, 1)
    outline:SetAllPoints()

    local fill = tick:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetTexture(ns.MEDIA .. "tick_dot")
    fill:SetPoint("TOPLEFT", TICK_OUTLINE, -TICK_OUTLINE)
    fill:SetPoint("BOTTOMRIGHT", -TICK_OUTLINE, TICK_OUTLINE)
    return ring
end

local function StyleButton(button, texture)
    ns.HideAuraButtonArt(button)
    local ring = BuildRing(button, texture)
    button:SetDurationCooldown(ring) -- Blizzard runs it with the aura's real (secret) timing
end

-- Preview mode's stand-in: the same ring and tick, draining over the DoT's length in a loop (plain
-- numbers, so SetCooldown takes them); ns.PlaceComboRing moves it into a slot's sample gate.
-- Returns the frame, and Start/Stop.
local function StandIn(dot)
    local frame = CreateFrame("Frame")
    frame:SetSize(RING_SIZE, RING_SIZE)
    ns.PlaceComboRing(frame, nil)
    frame:Hide()
    local ring = BuildRing(frame, dot.texture)
    local started
    local driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        if GetTime() - started >= dot.length then
            started = GetTime()
            ring:SetCooldown(started, dot.length)
        end
    end)
    local function Start()
        started = GetTime()
        ring:SetCooldown(started, dot.length)
        frame:Show()
        driver:Show()
    end
    local function Stop()
        driver:Hide()
        frame:Hide()
        ring:Clear()
    end
    return frame, Start, Stop
end

for _, dot in ipairs(DOTS) do
    -- The slot's AuraContainer, in a holder in the slot's gate (which carries the slot's Opacity:
    -- the buttons can't be touched after setup, so this applies live, even to the real ring, and
    -- hides with the combo dots outside Cat and Bear Form). Showing and hiding the holder picks
    -- which slot's ring is live.
    local holders = {} -- by slot index
    local current
    local function Holder(slot)
        local holder = holders[slot.index]
        if holder then
            return holder
        end
        holder = ns.ComboRingGate(slot.gate)
        holders[slot.index] = holder
        if ns.HAS_AURA_CONTAINER then
            local x, y = ns.ComboDotOffset(slot.index)
            ns.CreateAuraContainer({
                label = dot.label .. " " .. slot.index,
                unit = "target",
                filter = "HARMFUL",
                spellIDs = dot.spellIDs,
                width = RING_SIZE,
                height = RING_SIZE,
                x = x,
                y = y,
                level = LEVEL,
                parent = holder,
                initialize = function(button)
                    StyleButton(button, dot.texture)
                end,
            })
            if IsLoggedIn() and InCombatLockdown() then
                ns.Print(dot.label .. " shows around combo point " .. slot.index .. " after combat.")
            end
        end
        return holder
    end

    local standIn, StartSample, StopSample = StandIn(dot)
    ns.AddComboRingSpell({
        key = dot.key,
        label = dot.label .. " Duration",
        color = dot.color,
        order = dot.order,
        defaultSlot = dot.dot,
        Place = function(slot)
            if current then
                current:Hide()
            end
            current = slot and Holder(slot)
            if current then
                current:Show()
            end
        end,
        StartSample = function(slot)
            ns.PlaceComboRing(standIn, slot.sampleGate, slot.index)
            StartSample()
        end,
        StopSample = StopSample,
    })
end

if not ns.HAS_AURA_CONTAINER then
    ns.OnLoad(function()
        ns.Print("this client has no AuraContainer, so the DoT rings are unavailable.")
    end)
end
