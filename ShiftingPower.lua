-- Shifting Power cooldown: a four-segment arc under the swing ring that fills left to right over
-- the cooldown, each segment a quarter (4s, 3s or 2s), coloured blue, blue to white, white to
-- yellow, yellow. Each segment has an outline in its own colours; unfilled parts are clear inside it.
-- Each segment pulses briefly as it fills (at 4s, 8s, 12s of a 16s cooldown). At zero the arc
-- flashes and fades out, and a blue light pulses once inside the resource circle.
--
-- The cooldown's timing is secret in combat, so the arc runs on our own clock, like
-- FiveSecondRule.lua: it starts when our Shifting Power cast succeeds (our casts' spell IDs are
-- readable) and runs for the cooldown's length (16s, or 12s/8s with talents), learned from the real
-- numbers out of combat (CatnipDB.spLength). The ready flag (isActive, via ns.CooldownState) ends it
-- early if the cooldown resets, and holds the arc full if our clock runs out first.
--
-- The fill: sp_arc (coloured) masked by half_plane, rotated so its edge sits at the fill front, so
-- only the filled part shows.
local addonName, ns = ...

local SPELL_NAME = "Shifting Power"
local DEFAULT_LENGTH = 16
-- Geometry, in step with make_textures.py (SP_CANVAS, SP_SPAN): the arc textures are drawn on a
-- canvas CANVAS units across, centred on the HUD's centre.
local CANVAS = 164
local SPAN = math.pi / 4.2 -- either side of 6 o'clock
local LEFT_END = 1.5 * math.pi - SPAN -- maths angle (counter-clockwise from 3 o'clock)
local RADIUS = 76 -- the band's centre line (make_textures.py SP_RADIUS)
local SEGMENT_PULSE = 0.55 -- peak brightness of the small pulse as each segment fills
local PULSE_COLOR = { 60 / 255, 150 / 255, 1 } -- the mana bar's blue, brightened
local PULSE_ADD = 1 -- an additive copy on top, for a brighter core
local PULSE_WASH = 0.3 -- a blue tint over the whole circle under the rim light
local PULSE_IN, PULSE_OUT = 0.15, 1.2
local FADE_OUT = 0.45
local HOLD_LIMIT = 10 -- seconds to hold a full arc waiting for the ready flag before giving up
local RESET_GRACE = 0.5 -- ignore "not on cooldown" this soon after a cast (the cooldown may not be set yet)

local hud = ns.hud

-- Arc -----------------------------------------------------------------------------------------------

local arc = CreateFrame("Frame", nil, hud)
arc:SetSize(CANVAS, CANVAS)
arc:SetPoint("CENTER")
arc:SetFrameLevel(hud:GetFrameLevel() + 4)
arc:Hide()

local function ArcTexture(file, layer, sublevel)
    local texture = arc:CreateTexture(nil, layer, nil, sublevel)
    texture:SetTexture(ns.MEDIA .. file)
    texture:SetAllPoints(arc)
    return texture
end

ArcTexture("sp_arc_outline", "BORDER") -- around each segment in its colours, so empty ones still show

local fill = ArcTexture("sp_arc", "ARTWORK") -- the colours, all four segments
local front = arc:CreateMaskTexture()
front:SetTexture(ns.MEDIA .. "half_plane", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
front:SetAllPoints(arc)
fill:AddMaskTexture(front)

local flash = ArcTexture("sp_arc", "OVERLAY") -- brightens the full arc as it fades out
flash:SetBlendMode("ADD")

-- progress 0-1. half_plane shows its left half (maths angles 90-270 degrees); SetRotation turns it
-- counter-clockwise, so turning by front - 270 degrees shows everything up to the fill front.
local function SetProgress(progress)
    front:SetRotation(LEFT_END + 2 * SPAN * progress - 1.5 * math.pi)
end

local function AlphaAnimation(region, from, to, duration, smoothing)
    local group = region:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(from)
    fade:SetToAlpha(to)
    fade:SetDuration(duration)
    fade:SetSmoothing(smoothing)
    return group
end

-- A one-shot effect on an additive texture: shown only while its animation plays. Leaving it to
-- the animation to put the alpha back left the ready flash stuck at 70% over the next cooldown
-- (seen 2026-10-03), so the texture is hidden outright whenever the animation isn't running.
-- Returns play and stop functions.
local function OneShot(texture, group)
    texture:Hide()
    group:SetScript("OnFinished", function()
        texture:Hide()
    end)
    local function Play()
        group:Stop()
        texture:Show()
        group:Play()
    end
    local function Stop()
        group:Stop()
        texture:Hide()
    end
    return Play, Stop
end

-- A quick rise and fall; returns the group.
local function PulseAnimation(region, peak, rise, fall)
    local group = region:CreateAnimationGroup()
    local up = group:CreateAnimation("Alpha")
    up:SetFromAlpha(0)
    up:SetToAlpha(peak)
    up:SetDuration(rise)
    up:SetSmoothing("OUT")
    up:SetOrder(1)
    local down = group:CreateAnimation("Alpha")
    down:SetFromAlpha(peak)
    down:SetToAlpha(0)
    down:SetDuration(fall)
    down:SetSmoothing("IN")
    down:SetOrder(2)
    return group
end

-- Small pulse as each of the first three segments fills (the last one gets the ready flash): an
-- additive copy of sp_arc cropped to that segment. Along the bottom of the circle the segments
-- don't overlap left to right, so a strip between the gaps' centres holds exactly one.
local segmentPulses, segmentStops = {}, {}
do
    local edges = { -CANVAS / 2 }
    for k = 1, 3 do
        edges[k + 1] = RADIUS * math.cos(LEFT_END + k * SPAN / 2) -- centre of the gap after segment k
    end
    for i = 1, 3 do
        local left, right = edges[i], edges[i + 1]
        local texture = arc:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(ns.MEDIA .. "sp_arc")
        texture:SetTexCoord((left + CANVAS / 2) / CANVAS, (right + CANVAS / 2) / CANVAS, 0, 1)
        texture:SetPoint("TOPLEFT", arc, "TOPLEFT", left + CANVAS / 2, 0)
        texture:SetSize(right - left, CANVAS)
        texture:SetBlendMode("ADD")
        segmentPulses[i], segmentStops[i] = OneShot(texture, PulseAnimation(texture, SEGMENT_PULSE, 0.08, 0.35))
    end
end

local fadeOut = AlphaAnimation(arc, 1, 0, FADE_OUT, "IN")
local PlayFlash, StopFlash = OneShot(flash, AlphaAnimation(flash, 0.7, 0, FADE_OUT, "OUT"))

-- Stops every one-shot effect on the arc.
local function StopArcEffects()
    StopFlash()
    for _, stop in ipairs(segmentStops) do
        stop()
    end
end

fadeOut:SetScript("OnFinished", function()
    StopArcEffects() -- the flash may have a frame left; it mustn't be paused mid-fade while hidden
    arc:Hide()
end)

-- Ready pulse ---------------------------------------------------------------------------------------

local pulse = CreateFrame("Frame", nil, hud)
pulse:SetSize(ns.RESOURCE_SIZE, ns.RESOURCE_SIZE)
pulse:SetPoint("CENTER")
pulse:SetFrameLevel(hud:GetFrameLevel() + 3) -- over the resource fill, under its number
pulse:Hide()

local function GlowLayer(file, blendMode, alpha, sublevel)
    local glow = pulse:CreateTexture(nil, "ARTWORK", nil, sublevel)
    glow:SetTexture(ns.MEDIA .. file)
    glow:SetAllPoints(pulse)
    glow:SetVertexColor(PULSE_COLOR[1], PULSE_COLOR[2], PULSE_COLOR[3], alpha)
    glow:SetBlendMode(blendMode)
end
GlowLayer("circle_feather", "BLEND", PULSE_WASH, 0) -- same soft edge as the resource fill
GlowLayer("rim_glow", "BLEND", 1, 1)
GlowLayer("rim_glow", "ADD", PULSE_ADD, 2)

local pulseOnce = PulseAnimation(pulse, 1, PULSE_IN, PULSE_OUT)
pulseOnce:SetScript("OnFinished", function()
    pulse:Hide()
end)

local function Pulse()
    pulseOnce:Stop()
    pulse:Show()
    pulseOnce:Play()
end

local function HidePulse()
    pulseOnce:Stop()
    pulse:Hide()
end

-- State ---------------------------------------------------------------------------------------------

local spellID -- nil while the spell isn't known
local state = "hidden" -- "hidden" (not known), "cooling", "holding" (clock done, still on cooldown), "ready"
local castAt, length, holdSince
local filled = 0 -- segments full so far, for their pulses
local demo = false -- /catnip sp: a pretend cooldown, ignoring the real one

local function Length()
    return ns.db and ns.db.spLength or DEFAULT_LENGTH
end

local function StartCooling(start, duration)
    castAt, length = start, duration
    state = "cooling"
    HidePulse()
    fadeOut:Stop()
    StopArcEffects()
    arc:SetAlpha(1)
    local progress = math.min((GetTime() - castAt) / length, 1)
    filled = math.floor(progress * 4) -- no pulses for segments already full when we start
    SetProgress(progress)
    arc:Show()
end

local function BecomeReady(animate)
    local wasShowing = arc:IsShown() and not fadeOut:IsPlaying()
    state = "ready"
    demo = false
    if wasShowing and animate then
        SetProgress(1)
        PlayFlash()
        fadeOut:Play()
    elseif not fadeOut:IsPlaying() then
        StopArcEffects()
        arc:Hide()
    end
    if animate then -- only when the cooldown actually runs out, not on login or after learning the spell
        Pulse()
    end
end

local function Hide()
    state = "hidden"
    demo = false
    fadeOut:Stop()
    StopArcEffects()
    arc:Hide()
    HidePulse()
end

-- The cooldown's real start and length, when they're readable (out of combat).
local function ReadCooldown()
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then
        return nil
    end
    local start, duration = info.startTime, info.duration
    if start == nil or duration == nil or ns.IsSecret(start) or ns.IsSecret(duration) then
        return nil
    end
    return start, duration
end

local function Learn(duration)
    if ns.db and duration ~= ns.db.spLength then
        ns.db.spLength = duration
        ns.Debug("Shifting Power: cooldown is", duration, "s")
    end
end

local function Timing()
    return state == "cooling" or state == "holding"
end

local function JustCast()
    return Timing() and GetTime() - castAt < RESET_GRACE
end

-- Compares what the game says with our clock: corrects it when the numbers are readable, ends it
-- early if the cooldown was reset, starts it if we missed the cast.
local function Sync()
    if demo then
        return
    end
    if not spellID then
        Hide()
        return
    end
    local start, duration = ReadCooldown()
    if start then
        if duration > 1.5 and start > 0 then -- longer than a GCD: the real cooldown
            Learn(duration)
            if not Timing() or castAt ~= start or length ~= duration then
                StartCooling(start, duration)
            end
        elseif state ~= "ready" and not JustCast() then
            BecomeReady(Timing())
        end
        return
    end
    -- In combat: only the flag. Unsure reads keep what we have.
    if not ns.CooldownState then -- Cooldowns.lua loads after us
        return
    end
    local onCooldown, sure = ns.CooldownState(spellID, state ~= "ready")
    if not sure then
        if state == "hidden" then
            BecomeReady(false)
        end
        return
    end
    if onCooldown and state == "ready" then
        StartCooling(GetTime(), Length())
        ns.Debug("Shifting Power: on cooldown but we missed the cast; timing from now")
    elseif not onCooldown and Timing() then
        if not JustCast() then
            ns.Debug("Shifting Power: ready early (cooldown reset?)")
            BecomeReady(true)
        end
    elseif not onCooldown and state == "hidden" then
        BecomeReady(false)
    end
end

arc:SetScript("OnUpdate", function()
    if not Timing() then
        return
    end
    local progress = (GetTime() - castAt) / length
    if progress < 1 then
        SetProgress(progress)
        local now = math.floor(progress * 4)
        if now > filled then
            filled = now
            segmentPulses[now]()
        end
        return
    end
    SetProgress(1)
    if demo then
        BecomeReady(true)
        return
    end
    if state == "cooling" then
        state, holdSince = "holding", GetTime()
    end
    local onCooldown, sure = true, false
    if spellID and ns.CooldownState then
        onCooldown, sure = ns.CooldownState(spellID, true)
    end
    if (sure and not onCooldown) or GetTime() - holdSince > HOLD_LIMIT then
        BecomeReady(true)
    end
end)

local function IsShiftingPower(id)
    if id == nil or ns.IsSecret(id) then
        return false
    end
    return id == spellID or C_Spell.GetSpellName(id) == SPELL_NAME
end

local function OnCast(id)
    if not IsShiftingPower(id) then
        return
    end
    spellID = spellID or id
    demo = false
    StartCooling(GetTime(), Length())
    ns.Debug("Shifting Power: cast, timing", Length(), "s")
    C_Timer.After(0.1, Sync) -- out of combat the real numbers are readable: learn the length
end

-- Finds the spell in the spellbook by name (its ID may differ by rank or client).
local function Resolve()
    local info = C_Spell.GetSpellInfo(SPELL_NAME)
    local id = info and info.spellID
    if id and ns.IsSecret(id) then
        id = nil
    end
    if id and IsPlayerSpell and not IsPlayerSpell(id) then
        id = nil
    end
    if id ~= spellID then
        ns.Debug("Shifting Power: spell", id or "not known")
    end
    spellID = id
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ns.TryRegisterEvent(events, "PLAYER_TALENT_UPDATE")
ns.TryRegisterEvent(events, "TRAIT_CONFIG_UPDATED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast((select(3, ...))) -- unit, castGUID, spellID
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        Sync()
    else
        if not demo then
            Resolve()
        end
        Sync()
    end
end)

-- /catnip sp [seconds]: run a pretend cooldown to see the arc and pulse (default: the learned length).
ns.commands.sp = function(arg)
    demo = true
    StartCooling(GetTime(), tonumber(arg) or Length())
    ns.Print("Shifting Power preview:", length, "s")
end
