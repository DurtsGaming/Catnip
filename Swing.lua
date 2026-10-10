-- Swing timer: a ring around the resource circle that appears full on each swing and empties
-- clockwise from 12 o'clock until the next auto-attack. Driven by the PLAYER_SWING event
-- (Midnight-era API); tints amber (the "Maul queued color" setting), with a dot in the same colour at 12 o'clock,
-- while Maul is queued. Below it, "elapsed / total" text while a swing counts down, also tinted
-- while Maul is queued unless the Swing/Cast Timer's "Match Maul Color When Queued" is off.
local addonName, ns = ...
local CreateFrame = ns.Profiled("Swing") -- timed by /catnip perf (Profiler.lua)

local SIZE = ns.SWING_RING_SIZE
local GLOW_SCALE = 1.14 -- ring_glow's soft band sits just inside ring_bar's band (1.18 centres it; see tools/make_textures.py)
local COLOR = { 1, 1, 1 } -- the defaults of the "Color" and "Maul queued color" settings (below)
local MAUL_COLOR = { 1, 150 / 255, 30 / 255 } -- amber: warm like rage, apart from the red rage fill and DoT ticks
local TEXT_COLOR = { 1, 1, 1 } -- the swing time, unless matching the Maul colour

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

-- The swipe colour's alpha is the "Bar opacity" setting (the frame's own alpha belongs to Cast.lua).
local ringOpacity = 1
local function SetRingColor(color)
    ring:SetSwipeColor(color[1], color[2], color[3], ringOpacity)
end

SetRingColor(COLOR)

-- Maul marker: a dot (in the Maul colour) on the ring's band at 12 o'clock (where each swing starts), shown while
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

-- Shaded like the shift orbs, with their black rim. In the default amber it's orb_maul, which carries
-- its own gradient (drawn untinted); in a picked "Maul queued color", orb_maul_white tinted to it
-- (the same shading in grey: SetMarkerColor).
local markerDot = marker:CreateTexture(nil, "ARTWORK", nil, 1)
markerDot:SetTexture(ns.MEDIA .. "orb_maul")
markerDot:SetAllPoints()

local function SetMarkerColor(color)
    if ns.SameColor(color, MAUL_COLOR) then
        markerDot:SetTexture(ns.MEDIA .. "orb_maul")
        markerDot:SetVertexColor(1, 1, 1)
    else
        markerDot:SetTexture(ns.MEDIA .. "orb_maul_white")
        markerDot:SetVertexColor(color[1], color[2], color[3])
    end
end

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
timeText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE") -- until the saved font is applied
timeText:SetPoint("TOP")
-- Cast.lua's "Swing/Cast Timer" setting sizes it, and picks it on the HUD while no cast shows.
ns.swingInfo, ns.swingTimeText = info, timeText

local swingStart, swingDuration

-- Preview mode (Preview.lua): while sampling, a made-up swing loops on the ring and text (in the
-- forms that swing: 1.0s in Cat, 2.5s in Bear, roughly their real speeds), and real swings are only
-- noted, not drawn.
local SAMPLE_SWINGS = { cat = 1.0, bear = 2.5 }
ns.SAMPLE_SWING = SAMPLE_SWINGS.bear -- Gcd.lua paces its sample pie to it (every form but Cat)
local sampling = false
local sampleStart -- the looping sample swing's start, while it shows
local sampleLength -- and its length

-- Latest swing length (plain number from PLAYER_SWING), or nil before the first swing. Gcd.lua
-- paces the bear GCD to it.
function ns.GetSwingDuration()
    return swingDuration
end

-- The text shows tenths, so it's only rewritten when the shown tenth (or the swing's length)
-- changes, not every frame (/catnip perf, 2026-10-10: it was the second-costliest thing in combat).
local shownTenth, shownDuration

info:SetScript("OnUpdate", function()
    local start, duration = swingStart, swingDuration
    if sampleStart then
        if GetTime() - sampleStart >= sampleLength then -- loop
            sampleStart = GetTime()
            ring:SetCooldown(sampleStart, sampleLength)
        end
        start, duration = sampleStart, sampleLength
    end
    local elapsed = GetTime() - start
    if elapsed >= duration then
        info:Hide() -- swing ready
        return
    end
    timeText:SetShown(not (ns.IsCasting and ns.IsCasting()))
    local tenth = math.floor(elapsed * 10 + 0.5) -- as %.1f rounds it
    if tenth ~= shownTenth or duration ~= shownDuration then
        shownTenth, shownDuration = tenth, duration
        timeText:SetText(string.format("%.1f / %.1fs", elapsed, duration))
    end
end)

local function OnSwing(duration, weaponSlot)
    if ns.IsSecret(duration) or not duration or duration <= 0 then
        if not sampling then
            ring:Clear()
            info:Hide()
        end
        return
    end
    local now = GetTime()
    swingStart, swingDuration = now, duration
    if not sampling then
        ring:SetCooldown(now, duration)
        info:Show()
    end
end

-- Registered for its preview sample (the swing loop); its setting is Cast.lua's "Swing/Cast Timer".
ns.RegisterElement({
    id = "text.swing",
    zone = "text",
    name = "Swing time",
    hidden = true, -- offered as one setting with the cast text: "Swing/Cast Timer" (Cast.lua)
    -- No swing while stealthed (the preview's Stealth toggle), or in Caster, which shows a cast in
    -- the ring's place; nil puts back the real swing, if one is still running.
    sample = function(state)
        sampling = state ~= nil
        if (state == "cat" or state == "bear") and not ns.IsStealthMode() then
            sampleStart, sampleLength = GetTime(), SAMPLE_SWINGS[state]
            ring:SetCooldown(sampleStart, sampleLength)
            info:Show()
            return
        end
        sampleStart = nil
        if not sampling and swingStart and GetTime() - swingStart < swingDuration then
            ring:SetCooldown(swingStart, swingDuration)
            info:Show()
        else
            ring:Clear()
            info:Hide()
        end
    end,
})

local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
local maulQueued = false
local maulSampled = false -- preview mode's Bear sample shows Maul queued, whatever the game says

local shownQueued = false -- what ShowMaul last drew (real or sampled), for a colour change to redraw

-- The colours are read from the settings each time, so apply (below) can redraw with new ones.
local function ShowMaul(queued)
    shownQueued = queued
    local maulColor = ns.ElementOption("swing.ring", "maulColor")
    SetRingColor(queued and maulColor or ns.ElementOption("swing.ring", "color"))
    SetMarkerColor(maulColor)
    marker:SetShown(queued)
    local textColor = (queued and ns.ElementOption("text.under", "matchMaul")) and maulColor or TEXT_COLOR
    timeText:SetTextColor(textColor[1], textColor[2], textColor[3])
end

local function UpdateMaul()
    local queued = IsCurrentSpell("Maul")
    if ns.IsSecret(queued) then
        queued = false -- can't read it; show as not queued
    end
    queued = queued and true or false
    if queued ~= maulQueued then
        maulQueued = queued
        ns.Debug("Maul queued:", queued)
        if not maulSampled then
            ShowMaul(queued)
        end
    end
end

-- Settings (Elements.lua). The ring and its black glow behind; the glow's own alpha belongs to
-- StealthSmoke.lua's fade, so the setting goes in its vertex colour. Hidden in stealth (the smoke
-- takes the spot) and under a cast (the cast bar is picked there).
local function Percent(key, label, default)
    return { key = key, type = "slider", label = label, min = 0, max = 100, step = 5, format = "%.0f%%", default = default }
end
local RING_OUTER = SIZE * 127 / 256 -- ring_bar's band: 20 of 256 pixels thick, out to 127
local RING_INNER = SIZE * 107 / 256
ns.SWING_BAND = { inner = RING_INNER, outer = RING_OUTER } -- Cast.lua's ring sits in the same band

ns.RegisterElement({
    id = "swing.ring",
    zone = "swing",
    name = "Swing Timer",
    order = 1, -- in the Ring group: Swing Timer, Cast Timer, Stealth smoke (owner, 2026-10-09)
    glyph = { kind = "ring", color = { 0.91, 0.89, 0.82 } },
    hit = { kind = "ring", inner = RING_INNER, outer = RING_OUTER,
        visible = function() return not ns.IsStealthMode() and not (ns.CastBarShown and ns.CastBarShown()) end },
    options = {
        Percent("barOpacity", "Bar opacity", 100),
        Percent("glowOpacity", "Background opacity", 75),
        { key = "color", type = "color", label = "Color", default = COLOR },
        { key = "maulColor", type = "color", label = "Maul queued color", default = MAUL_COLOR },
    },
    -- Every element reapplies on any change, so this also picks up "Match Maul Color When Queued" (Cast.lua).
    apply = function(get)
        ringOpacity = get("barOpacity") / 100
        glow:SetVertexColor(0, 0, 0, get("glowOpacity") / 100)
        ShowMaul(shownQueued)
    end,
    -- Bear shows Maul queued, so its amber look and orb can be seen; nil puts back the real state.
    sample = function(state)
        maulSampled = state ~= nil
        if maulSampled then
            ShowMaul(state == "bear")
        else
            ShowMaul(maulQueued)
        end
    end,
})

ns.RegisterElement({
    id = "swing.maul",
    zone = "swing",
    name = "Maul orb",
    hidden = true, -- not offered in the settings for now (Elements.lua)
    glyph = { kind = "disc", color = { 0.91, 0.64, 0.23 } },
    hit = { kind = "circle", x = 0, y = MARKER_Y, radius = MARKER_SIZE / 2 + 3,
        visible = function() return marker:IsShown() end },
    options = { Percent("opacity", "Opacity", 100) },
    apply = function(get)
        marker:SetAlpha(get("opacity") / 100)
    end,
})

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
