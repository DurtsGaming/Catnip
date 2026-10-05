-- Swing timer: a ring around the resource circle that appears full on each swing and empties
-- clockwise from 12 o'clock until the next auto-attack. Driven by the PLAYER_SWING event
-- (Midnight-era API); tints amber, with an amber dot at 12 o'clock, while Maul is queued. Below it, "elapsed / total" text while a
-- swing counts down.
local addonName, ns = ...

local SIZE = ns.SWING_RING_SIZE
local GLOW_SCALE = 1.14 -- ring_glow's soft band sits just inside ring_bar's band (1.18 centres it; see tools/make_textures.py)
local COLOR = { 1, 1, 1 }
local MAUL_COLOR = { 1, 150 / 255, 30 / 255 } -- amber: warm like rage, apart from the red rage fill and DoT ticks

local hud = ns.hud

-- #4 glow ring: the timer's black, feathered background (darkest along the band, fading out)
local glow = hud:CreateTexture(nil, "BACKGROUND", nil, -6) -- under StealthSmoke.lua's smoke (-5 to -3)
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

-- Maul marker: an amber dot on the ring's band at 12 o'clock (where each swing starts), shown while
-- Maul is queued, so it shows even when not swinging and the ring is empty. On its own frame so it
-- draws over the ring's swipe; a soft black backing keeps it readable over the white ring.
local MARKER_SIZE = 12
local MARKER_Y = SIZE * (127 - 10) / 256 -- middle of ring_bar's band (20px thick, out to 127 of 256)

local marker = CreateFrame("Frame", nil, hud)
marker:SetSize(MARKER_SIZE, MARKER_SIZE)
marker:SetPoint("CENTER", hud, "CENTER", 0, MARKER_Y)
marker:SetFrameLevel(ring:GetFrameLevel() + 1)
marker:Hide()

local markerShadow = marker:CreateTexture(nil, "ARTWORK", nil, 0)
markerShadow:SetTexture(ns.MEDIA .. "circle_soft")
markerShadow:SetSize(MARKER_SIZE * 1.6, MARKER_SIZE * 1.6)
markerShadow:SetPoint("CENTER")
markerShadow:SetVertexColor(0, 0, 0, 0.8)

-- Shaded like the shift orbs: orb_maul carries its own amber gradient (drawn untinted), with their black rim
local markerDot = marker:CreateTexture(nil, "ARTWORK", nil, 1)
markerDot:SetTexture(ns.MEDIA .. "orb_maul")
markerDot:SetAllPoints()

local markerRim = marker:CreateTexture(nil, "OVERLAY")
markerRim:SetTexture(ns.MEDIA .. "ring_small")
markerRim:SetVertexColor(0, 0, 0)
markerRim:SetAllPoints()

-- Swing text: "0.0 / 2.5s" (elapsed / swing length) where the cast text goes, under the shift
-- orbs; same font as the cast time. Hidden once the swing is ready, and while casting (the cast
-- text takes the spot). The frame is only shown while a swing is counting down.
local info = CreateFrame("Frame", nil, hud)
info:SetSize(1, 1)
info:SetPoint("TOP", hud, "CENTER", 0, -ns.TIME_TEXT_OFFSET)
info:Hide()

local timeText = info:CreateFontString(nil, "OVERLAY")
timeText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
timeText:SetPoint("TOP")

local swingStart, swingDuration

-- Latest swing length (plain number from PLAYER_SWING), or nil before the first swing. Gcd.lua
-- paces the bear GCD to it.
function ns.GetSwingDuration()
    return swingDuration
end

info:SetScript("OnUpdate", function()
    local elapsed = GetTime() - swingStart
    if elapsed >= swingDuration then
        info:Hide() -- swing ready
        return
    end
    timeText:SetShown(not (ns.IsCasting and ns.IsCasting()))
    timeText:SetText(string.format("%.1f / %.1fs", elapsed, swingDuration))
end)

local function OnSwing(duration, weaponSlot)
    if ns.IsSecret(duration) or not duration or duration <= 0 then
        ring:Clear()
        info:Hide()
        return
    end
    local now = GetTime()
    ring:SetCooldown(now, duration)
    swingStart, swingDuration = now, duration
    info:Show()
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
        local color = queued and MAUL_COLOR or COLOR
        SetRingColor(color)
        marker:SetShown(queued)
        timeText:SetTextColor(color[1], color[2], color[3])
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
