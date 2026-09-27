-- Swing timer: a ring around the resource circle that fills counter-clockwise from 12 o'clock
-- until the next auto-attack. Driven by the PLAYER_SWING event (Midnight-era API); tints pink
-- while Maul is queued.
local addonName, ns = ...

local SIZE = ns.SWING_RING_SIZE
local GLOW_SCALE = 1.18 -- lines ring_glow's soft band up with ring_bar's band (see tools/make_textures.py)
local ROTATION_SIGN = 1 -- -1 if SetRotation turns out to rotate clockwise
local COLOR = { 1, 1, 1 }
local MAUL_COLOR = { 1, 0.3, 0.5 }

local hud = ns.hud

-- #4 glow ring behind, as a dark halo
local glow = hud:CreateTexture(nil, "BACKGROUND", nil, -1)
glow:SetTexture(ns.MEDIA .. "ring_glow")
glow:SetSize(SIZE * GLOW_SCALE, SIZE * GLOW_SCALE)
glow:SetPoint("CENTER")
glow:SetVertexColor(0, 0, 0, 0.8)

-- dark full ring, so the empty part of the timer is still visible
local track = hud:CreateTexture(nil, "BORDER")
track:SetTexture(ns.MEDIA .. "ring_bar")
track:SetSize(SIZE, SIZE)
track:SetPoint("CENTER")
track:SetVertexColor(0.15, 0.15, 0.15, 0.7)

-- #7 bar ring. A Cooldown swipe can only go clockwise, so the arc is built from two half-rings,
-- each rotated inside a frame that clips to one half of the circle. This needs a readable swing
-- duration, which PLAYER_SWING gives us (not secret; verified in-game).
local ring = CreateFrame("Frame", nil, hud)
ring:SetSize(SIZE, SIZE)
ring:SetPoint("CENTER")

local function CreateHalf(side)
    local clip = CreateFrame("Frame", nil, ring)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOP" .. side)
    clip:SetPoint("BOTTOM" .. side)
    clip:SetWidth(SIZE / 2)

    local half = clip:CreateTexture(nil, "ARTWORK")
    half:SetTexture(ns.MEDIA .. "ring_bar_half")
    half:SetSize(SIZE, SIZE)
    half:SetPoint("CENTER", ring)
    half:Hide()
    return half
end

-- Counter-clockwise from 12 o'clock, the fill covers the left half first, then the right.
local leftHalf = CreateHalf("LEFT")
local rightHalf = CreateHalf("RIGHT")

-- Crisp black lines on both edges of the band, above the fill, so the ring keeps a defined shape.
local outlineFrame = CreateFrame("Frame", nil, ring)
outlineFrame:SetAllPoints()
outlineFrame:SetFrameLevel(ring:GetFrameLevel() + 5)
local outline = outlineFrame:CreateTexture(nil, "OVERLAY")
outline:SetTexture(ns.MEDIA .. "ring_bar_outline")
outline:SetAllPoints()
outline:SetVertexColor(0, 0, 0)

local function SetRingColor(color)
    leftHalf:SetVertexColor(color[1], color[2], color[3])
    rightHalf:SetVertexColor(color[1], color[2], color[3])
end

-- progress 0..1. The half-ring texture starts covering the right half; rotating it
-- counter-clockwise sweeps it into view of the left clip frame. The right one starts
-- half a turn further on, so it enters its clip frame from 6 o'clock.
local function SetProgress(progress)
    local twoPi = 2 * math.pi
    leftHalf:SetRotation(ROTATION_SIGN * math.min(progress, 0.5) * twoPi)
    rightHalf:SetRotation(ROTATION_SIGN * (math.pi + math.max(progress - 0.5, 0) * twoPi))
    rightHalf:SetShown(progress > 0.5)
end

local swingStart, swingDuration

-- Only shown mid-swing, so it costs nothing when idle.
local ticker = CreateFrame("Frame", nil, hud)
ticker:Hide()

local function StopSwing()
    ticker:Hide()
    leftHalf:Hide()
    rightHalf:Hide()
end

ticker:SetScript("OnUpdate", function()
    local swingElapsed = GetTime() - swingStart
    if swingElapsed >= swingDuration then
        StopSwing()
        return
    end
    SetProgress(swingElapsed / swingDuration)
end)

local function OnSwing(duration, weaponSlot)
    ns.Debug("PLAYER_SWING duration:", duration, "slot:", weaponSlot)
    if ns.IsSecret(duration) or not duration or duration <= 0 then
        StopSwing() -- can't compute progress from a secret duration
        return
    end
    swingStart, swingDuration = GetTime(), duration
    SetProgress(0)
    leftHalf:Show()
    ticker:Show()
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
