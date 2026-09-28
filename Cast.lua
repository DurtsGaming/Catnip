-- Cast bar: while the player casts or channels, a ring takes the swing timer's exact place (same
-- size, texture and glow) and the swing ring goes invisible. The swing ring keeps running
-- underneath, so it reappears in sync when the cast ends. Casts fill clockwise from 12 o'clock;
-- channels start full and drain. Below the ring: "elapsed / total" (remaining for channels) and
-- the spell name.
--
-- Cast timings may be secret in combat, so the ring is driven by duration objects
-- (UnitCastingDuration / UnitChannelDuration -> Cooldown:SetCooldownFromDurationObject), the same
-- technique as Gcd.lua, and the time text passes the object's (possibly secret) numbers straight
-- to string.format. Both seen in the Forever-adapted ThreatPlates castbar.
local addonName, ns = ...

local SIZE = ns.SWING_RING_SIZE
local TEXT_OFFSET = SIZE * 1.18 / 2 + 2 -- just below the swing glow's outer edge (Swing.lua GLOW_SCALE)
local CAST_COLOR = { 1, 0.7, 0 } -- Blizzard cast bar gold
local CHANNEL_COLOR = { 0.3, 0.8, 1 }

local ring = CreateFrame("Cooldown", nil, ns.hud)
ring:SetSize(SIZE, SIZE)
ring:SetPoint("CENTER")
ring:SetSwipeTexture(ns.MEDIA .. "ring_bar")
ring:SetDrawEdge(false)
ring:SetDrawBling(false)
ring:SetHideCountdownNumbers(true)
ring:Hide()

-- Text under the ring: "0.0 / 2.5s", then the spell name.
local info = CreateFrame("Frame", nil, ns.hud)
info:SetSize(1, 1)
info:SetPoint("TOP", ns.hud, "CENTER", 0, -TEXT_OFFSET)
info:Hide()

local timeText = info:CreateFontString(nil, "OVERLAY")
timeText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
timeText:SetPoint("TOP")

local nameText = info:CreateFontString(nil, "OVERLAY")
nameText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
nameText:SetPoint("TOP", timeText, "BOTTOM", 0, -2)

-- The running cast: a duration object, or plain start/end seconds on a client without one.
local channel, durationObject, startTime, endTime
local fullFormat = true -- false once the object turns out to lack elapsed/total getters

local function FormatFromObject()
    if fullFormat then
        local ok = pcall(function()
            -- No "a and b or c" here: that tests b's truthiness, which errors on a secret.
            local shown
            if channel then
                shown = durationObject:GetRemainingDuration()
            else
                shown = durationObject:GetElapsedDuration()
            end
            timeText:SetText(string.format("%.1f / %.1fs", shown, durationObject:GetTotalDuration()))
        end)
        if ok then
            return
        end
        fullFormat = false
        ns.Debug("cast: duration object lacks elapsed/total, showing remaining time only")
    end
    timeText:SetText(string.format("%.1fs", durationObject:GetRemainingDuration()))
end

info:SetScript("OnUpdate", function()
    if durationObject then
        FormatFromObject()
    elseif startTime then
        local now = GetTime()
        local shown = channel and endTime - now or now - startTime
        timeText:SetText(string.format("%.1f / %.1fs", math.max(shown, 0), endTime - startTime))
    end
end)

-- True if the info function reports an active cast. Guarded in case its result is ever secret
-- (then we show nothing rather than erroring).
local function IsActive(infoFn)
    local ok, active = pcall(function()
        return infoFn("player") ~= nil
    end)
    return ok and active
end

-- Starts the ring and text for the current cast. Returns whether it worked.
local function Start(durationFn, infoFn)
    local name, _, _, startMS, endMS = infoFn("player")
    nameText:SetText(name) -- FontStrings accept secrets
    durationObject, startTime, endTime = nil, nil, nil

    if durationFn and ring.SetCooldownFromDurationObject then
        local ok, err = pcall(function()
            local object = durationFn("player")
            ring:SetCooldownFromDurationObject(object)
            durationObject = object
        end)
        if ok then
            return true
        end
        ns.Debug("cast: duration object rejected:", err)
    end
    if not startMS or ns.IsSecret(startMS) or ns.IsSecret(endMS) then
        return false
    end
    startTime, endTime = startMS / 1000, endMS / 1000
    ring:SetCooldown(startTime, endTime - startTime)
    return true
end

-- Our own state: the ring can't be asked, since a Cooldown hides itself when its timer runs out.
local isCasting = false

local function SetCasting(casting)
    isCasting = casting
    ring:SetShown(casting)
    info:SetShown(casting)
    if ns.swingRing then
        ns.swingRing:SetAlpha(casting and 0 or 1)
    end
    if not casting then
        ring:Clear()
        durationObject, startTime, endTime = nil, nil, nil
    end
end

local function Update()
    local shown = false
    if IsActive(UnitCastingInfo) then
        channel = false
        ring:SetReverse(true) -- fill, like a cast bar
        ring:SetSwipeColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3], 1)
        shown = Start(UnitCastingDuration, UnitCastingInfo)
    elseif IsActive(UnitChannelInfo) then
        channel = true
        ring:SetReverse(false) -- drain, like a channel bar
        ring:SetSwipeColor(CHANNEL_COLOR[1], CHANNEL_COLOR[2], CHANNEL_COLOR[3], 1)
        shown = Start(UnitChannelDuration, UnitChannelInfo)
    end
    SetCasting(shown)
end

local events = CreateFrame("Frame")
for _, event in ipairs({
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
}) do
    pcall(events.RegisterUnitEvent, events, event, "player")
end
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
    local wasCasting = isCasting
    Update()
    if isCasting ~= wasCasting then -- skip the many events that change nothing (e.g. failed casts)
        ns.Debug("cast bar", isCasting and "shown" or "hidden", "on", event)
    end
end)

ns.OnLoad(function()
    ns.Debug("cast bar method:", UnitCastingDuration and "duration object" or "UnitCastingInfo times")
end)
