-- Cast bar: while the player casts or channels, a ring takes the swing timer's exact place (same
-- size, texture and glow) and the swing ring goes invisible. The swing ring keeps running
-- underneath, so it reappears in sync when the cast ends. Casts fill counter-clockwise from
-- 12 o'clock; channels start full and drain clockwise (the same shape, run backwards). Below the
-- ring: "elapsed / total" (remaining for channels) and the spell name.
--
-- Cast timings may be secret in combat, so the ring is driven by duration objects
-- (UnitCastingDuration / UnitChannelDuration -> Cooldown:SetCooldownFromDurationObject), the same
-- technique as Gcd.lua, and the time text passes the object's (possibly secret) numbers straight
-- to string.format. Both seen in the Forever-adapted ThreatPlates castbar.
--
-- A Cooldown swipe only runs clockwise, so a cast's counter-clockwise fill is drawn with two
-- rotated half-ring arcs instead (FiveSecondRule.lua's technique). That needs the cast's progress
-- as a number; if it's secret, the cast falls back to the swipe, filling clockwise.
local addonName, ns = ...

local SIZE = ns.SWING_RING_SIZE
-- Below the shift orbs (ShiftOrbs.lua: centres 93 below the HUD's centre, 22.8 across, so their
-- bottom is ~104.4). Was just below the swing glow (~81) before the orbs moved there.
local TEXT_OFFSET = 108
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

-- The counter-clockwise fill: each side is a clip frame showing only its half, holding a left
-- half-ring that rotates into view. Shown instead of the swipe while the progress is readable.
local arcs = CreateFrame("Frame", nil, ns.hud)
arcs:SetSize(SIZE, SIZE)
arcs:SetPoint("CENTER")
arcs:SetFrameLevel(ring:GetFrameLevel())
arcs:Hide()

local function CreateSide(point)
    local clip = CreateFrame("Frame", nil, arcs)
    clip:SetPoint("TOP" .. point)
    clip:SetPoint("BOTTOM" .. point)
    clip:SetWidth(SIZE / 2)
    clip:SetClipsChildren(true)
    local arc = clip:CreateTexture(nil, "ARTWORK")
    arc:SetTexture(ns.MEDIA .. "ring_bar_half")
    arc:SetSize(SIZE, SIZE)
    arc:SetPoint("CENTER", arcs)
    arc:SetVertexColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
    return arc
end

local leftArc = CreateSide("LEFT")
local rightArc = CreateSide("RIGHT")

-- progress 0-1 -> the fill's angle runs 0 to 2pi counter-clockwise from 12 o'clock: first down
-- the left side, then up the right. SetRotation turns counter-clockwise. The left half turned by
-- pi sits on the right (clipped away) and turning further enters the left side from 12 o'clock;
-- unturned it sits on the left (clipped away) and turning enters the right side from 6 o'clock.
local function SetArcs(progress)
    local angle = 2 * math.pi * math.max(0, math.min(progress, 1))
    leftArc:SetRotation(math.pi + math.min(angle, math.pi))
    rightArc:SetRotation(math.max(angle - math.pi, 0))
end

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
local useArcs = false -- whether this cast is drawn by the arcs (else the swipe)

-- The cast's progress 0-1, or nil if it can't be worked out (secret timings).
local function Progress()
    local ok, progress = pcall(function()
        if durationObject then
            return durationObject:GetElapsedDuration() / durationObject:GetTotalDuration()
        end
        return (GetTime() - startTime) / (endTime - startTime)
    end)
    if ok and type(progress) == "number" and not ns.IsSecret(progress) then
        return progress
    end
end

-- Draws the arcs, or hands the cast over to the swipe if the progress can't be read.
local function UpdateArcs()
    local progress = Progress()
    if progress then
        SetArcs(progress)
        return
    end
    ns.Debug("cast: progress unreadable, filling clockwise with the swipe")
    useArcs = false
    arcs:Hide()
    ring:Show()
end

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
    if useArcs then
        UpdateArcs()
    end
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
    useArcs = casting and not channel and Progress() ~= nil
    if useArcs then
        UpdateArcs()
    end
    ring:SetShown(casting and not useArcs)
    arcs:SetShown(useArcs)
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
        ring:SetReverse(true) -- fill, like a cast bar (only seen if the arcs can't be used)
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

-- Other modules' callbacks for when a cast starts or ends (ns.OnCastChanged).
local listeners = {}

-- Whether our cast ring and text are showing.
function ns.IsCasting()
    return isCasting
end

function ns.OnCastChanged(callback)
    listeners[#listeners + 1] = callback
end

local function Refresh(reason)
    local wasCasting = isCasting
    Update()
    if isCasting ~= wasCasting then -- skip the many events that change nothing (e.g. failed casts)
        ns.Debug("cast bar", isCasting and "shown" or "hidden", "on", reason)
        for _, callback in ipairs(listeners) do
            callback(isCasting)
        end
    end
end

-- The cast can still be reported as running when its stop event fires (seen 2026-10-03: the text
-- froze at "3.0 / 3.0s Skinning"), and no later event tells us, so look again shortly after.
local STOP_EVENTS = {
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
}
local function RecheckSoon()
    C_Timer.After(0.2, function()
        Refresh("re-check after stop")
    end)
    C_Timer.After(1, function()
        Refresh("late re-check after stop")
    end)
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
    Refresh(event)
    if STOP_EVENTS[event] and isCasting then
        RecheckSoon()
    end
end)

ns.OnLoad(function()
    ns.Debug("cast bar method:", UnitCastingDuration and "duration object" or "UnitCastingInfo times")
end)

-- Blizzard's player cast bar: ours replaces it, so (by default) park it under a hidden frame
-- (EllesmereUI's technique; it leaves Blizzard's events and code untouched). Edit Mode re-parents
-- the bar during layout changes, so park it again afterwards, but never in combat or while Edit
-- Mode is open: SetParent there runs Blizzard's layout code under our taint.
ns.defaults.hideBlizzardCastBar = true

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local originalParent

-- Parks or releases the bar to match the setting. Changes wait until after combat.
function ns.UpdateBlizzardCastBar()
    local bar = PlayerCastingBarFrame
    if not bar or not ns.db or InCombatLockdown()
        or (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        return
    end
    local parked = bar:GetParent() == hiddenParent
    if ns.db.hideBlizzardCastBar and not parked then
        originalParent = bar:GetParent()
        bar:SetParent(hiddenParent)
        ns.Debug("Blizzard cast bar hidden")
    elseif not ns.db.hideBlizzardCastBar and parked then
        -- Never hand it back to a hidden parent (e.g. an Edit Mode layout frame), or it stays invisible.
        local parent = originalParent
        if not (parent and parent:IsVisible()) then
            parent = UIParent
        end
        bar:SetParent(parent)
        ns.Debug("Blizzard cast bar shown")
    end
end

local function UpdateBlizzardBarSoon()
    C_Timer.After(0, ns.UpdateBlizzardCastBar)
end

local parker = CreateFrame("Frame")
parker:RegisterEvent("PLAYER_LOGIN")
parker:RegisterEvent("PLAYER_REGEN_ENABLED") -- catch up on a re-parent that happened in combat
parker:SetScript("OnEvent", UpdateBlizzardBarSoon)
if PlayerCastingBarFrame then
    hooksecurefunc(PlayerCastingBarFrame, "SetParent", UpdateBlizzardBarSoon)
end
if EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnHide", UpdateBlizzardBarSoon)
end
