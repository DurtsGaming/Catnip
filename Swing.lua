-- Swing timer: a ring around the resource circle that appears full on each swing and empties
-- clockwise from 12 o'clock until the next auto-attack. Driven by the PLAYER_SWING event
-- (Midnight-era API); tints pink while Maul is queued.
local addonName, ns = ...

local SIZE = ns.SWING_RING_SIZE
local GLOW_SCALE = 1.18 -- lines ring_glow's soft band up with ring_bar's band (see tools/make_textures.py)
local COLOR = { 1, 1, 1 }
local MAUL_COLOR = { 1, 0.3, 0.5 }

local hud = ns.hud

-- #4 glow ring: the timer's black, feathered background (darkest along the band, fading out)
local glow = hud:CreateTexture(nil, "BACKGROUND", nil, -1)
glow:SetTexture(ns.MEDIA .. "ring_glow")
glow:SetSize(SIZE * GLOW_SCALE, SIZE * GLOW_SCALE)
glow:SetPoint("CENTER")
glow:SetVertexColor(0, 0, 0, 0.75)

-- #7 bar ring, drawn by a Cooldown frame's swipe, which starts full and empties clockwise from
-- 12 o'clock. SetCooldown rejects secrets from addon code, but PLAYER_SWING's duration is a plain
-- number (verified in-game).
local ring = CreateFrame("Cooldown", nil, hud)
ring:SetSize(SIZE, SIZE)
ring:SetPoint("CENTER")
ring:SetSwipeTexture(ns.MEDIA .. "ring_bar")
ring:SetDrawEdge(false)
ring:SetDrawBling(false)
ring:SetHideCountdownNumbers(true)
ns.swingRing = ring -- Cast.lua hides it (via alpha, so it keeps timing) while casting

local function SetRingColor(color)
    ring:SetSwipeColor(color[1], color[2], color[3], 1)
end

SetRingColor(COLOR)

local function OnSwing(duration, weaponSlot)
    if ns.IsSecret(duration) or not duration or duration <= 0 then
        ring:Clear()
        return
    end
    ring:SetCooldown(GetTime(), duration)
end

local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
local maulQueued = false

local function UpdateMaul()
    local queued = IsCurrentSpell("Maul")
    if ns.IsSecret(queued) then
        queued = false -- can't read it; show as not queued
    end
    queued = queued and true or false
    if queued ~= maulQueued then
        maulQueued = queued
        ns.Debug("Maul queued:", queued)
        SetRingColor(queued and MAUL_COLOR or COLOR)
    end
end

local events = CreateFrame("Frame")
local hasSwingEvent = ns.TryRegisterEvent(events, "PLAYER_SWING")
ns.TryRegisterEvent(events, "ACTIONBAR_UPDATE_STATE")
ns.TryRegisterEvent(events, "CURRENT_SPELL_CAST_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_SWING" then
        OnSwing(...)
    else
        UpdateMaul()
    end
end)

ns.OnLoad(function()
    if not hasSwingEvent then
        ns.Print("PLAYER_SWING isn't available in this client, so the swing timer is inactive.")
    end
    ns.Debug("swing event:", hasSwingEvent, "C_SwingTimer:", C_SwingTimer and "present" or "missing")
end)
