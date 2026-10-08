-- Global cooldown "Harvey ball": a faint white pie over the resource circle that shrinks clockwise while
-- the GCD runs. Retail reports the GCD on dummy spell 61304; Forever doesn't have it and uses
-- Classic's GCD spell 29515 instead (found via EllesmereUI's Forever fix, PR #2240).
--
-- In combat the cooldown's start and duration are secret, and Cooldown:SetCooldown rejects secrets
-- from addon code (verified). So:
--   1. Preferred: C_Spell.GetSpellCooldownDuration gives a sealed duration object, which
--      Cooldown:SetCooldownFromDurationObject accepts. Exact timing, drawn by Blizzard.
--   2. Backup: the cooldown's isActive flag is readable in combat (verified). When it turns on,
--      run our own sweep of the Classic GCD length: 1.0s for energy abilities, 1.5s otherwise.
--
-- Outside cat form (no energy) we always use the backup, paced to the swing timer: the pie stands
-- for one whole swing (e.g. 2.5s in bear), so the 1.5s GCD starts at 60% and shrinks at the swing
-- ring's speed. Cast with 1.5s of the swing left and the pie matches the ring exactly, emptying with
-- it. Swing length: UnitAttackSpeed (current form and weapon), else the last measured swing. Falls
-- back to a plain sweep if neither is known, or if the swing is no longer than the GCD. Cat keeps
-- the exact duration object; its 1.0s GCD already roughly matches its swing.
local addonName, ns = ...

local GCD_LENGTH = 1.5 -- Classic GCD outside cat form; not hasted

local REFERENCE_SPELL = ns.GCD_SPELL -- Forever's GCD spell (SpellTiming.lua)
local SHADE = { 1, 1, 1, 0.3 }

local ball = CreateFrame("Cooldown", nil, ns.hud, "CooldownFrameTemplate")
ball:ClearAllPoints() -- the template fills its parent (the whole HUD); size it to the circle instead
ball:SetSize(ns.RESOURCE_SIZE, ns.RESOURCE_SIZE)
ball:SetPoint("CENTER")
ball:SetFrameLevel(ns.hud:GetFrameLevel() + 3) -- over the resource fill, under its number
ball:SetSwipeTexture(ns.MEDIA .. "circle_feather") -- same soft edge as the resource fill
ball:SetSwipeColor(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
ball:SetDrawEdge(false)
ball:SetDrawBling(false)
ball:SetHideCountdownNumbers(true)

local useDurationObject = C_Spell.GetSpellCooldownDuration ~= nil and ball.SetCooldownFromDurationObject ~= nil

local function UpdateFromDurationObject()
    local ok, err = pcall(function()
        -- isActive stays readable in combat; gating on it avoids redrawing a finished GCD (as EllesmereUI does).
        local info = C_Spell.GetSpellCooldown(REFERENCE_SPELL)
        local active = info and info.isActive
        local duration = active and not ns.IsSecret(active) and C_Spell.GetSpellCooldownDuration(REFERENCE_SPELL)
        if duration then
            ball:SetCooldownFromDurationObject(duration)
        else
            ball:Clear()
        end
    end)
    if not ok then
        useDurationObject = false
        ns.Debug("GCD: duration object rejected, switching to isActive backup:", err)
    end
    return ok
end

local sweepEnd = 0 -- GetTime() our own sweep runs out; 0 when none

local function IsPaced()
    return UnitPowerType("player") ~= Enum.PowerType.Energy
end

-- Seconds per main-hand swing in the current form, and where that came from; nil if unknown.
local function SwingLength()
    local speed = UnitAttackSpeed("player")
    if speed and not ns.IsSecret(speed) and speed > 0 then
        return speed, "attack speed"
    end
    local swing = ns.GetSwingDuration and ns.GetSwingDuration()
    if swing then
        return swing, "last swing"
    end
end

-- Some spells have a shorter GCD, e.g. Rejuvenation, Swiftmend and Wild Growth (1.0s) with the Gift
-- of the Earthmother talent. Detecting the talent by name failed (2026-10-08: a passive talent adds
-- no spell to the spellbook), so instead each spell's GCD is learned: out of combat the GCD's
-- duration is readable (verified: 0.99 for Rejuvenation), so an instant cast records it
-- (ns.LearnLength "gcd", SpellTiming.lua). Out of combat the sweep uses the real duration.
-- In combat we only see the GCD start, so the cast event says which spell it was; the two arrive in
-- either order (the GCD first, seen 2026-10-08), and whichever comes second applies the learned
-- length. Nature's Grace (a 10% shorter GCD for 3s after a crit) can't be seen in combat: no Druid
-- buff is readable then.

-- Seconds between the GCD start and its cast event to count as one cast. The cast event came 0.12s
-- after the GCD start (2026-10-08), so leave room for lag; no GCD is shorter than 1s.
local PAIR_WINDOW = 0.4
local sweepStart = 0
local sweepLength = 0
local castTime = 0 -- GetTime() of the last cast event
local castLength -- its learned GCD length, if any

-- The GCD's real start and duration, or nil when secret (in combat) or not running.
local function ReadableGcd()
    local start, duration = ns.ReadCooldown(REFERENCE_SPELL)
    if start and duration > 0 then
        return start, duration
    end
end

local function DrawSweep(start, length)
    local swing, source = SwingLength()
    if swing and swing > length then
        -- a swing-length sweep already (swing - GCD) in, so it ends when the GCD does
        ball:SetCooldown(start - (swing - length), swing)
    else
        ball:SetCooldown(start, length)
    end
    sweepStart, sweepEnd, sweepLength = start, start + length, length
    ns.Debug("GCD sweep:", length, "s, swing", swing, "from", source)
end

local function StartSweep()
    local now = GetTime()
    if not IsPaced() then
        ball:SetCooldown(now, 1)
        sweepStart, sweepEnd = now, now + 1
        return
    end
    local start, duration = ReadableGcd()
    if start then
        DrawSweep(start, duration)
    else
        local paired = now - castTime < PAIR_WINDOW and castLength
        DrawSweep(now, paired or GCD_LENGTH)
    end
end

local function OnCast(spellID)
    if not spellID or ns.IsSecret(spellID) then
        return
    end
    local name = C_Spell.GetSpellName(spellID)
    if not name or ns.IsSecret(name) then
        return
    end
    local now = GetTime()
    -- Learn: a GCD that started just now is this cast's (an instant). A cast with a cast time
    -- started its GCD when the cast began, so it's skipped.
    local start, duration = ReadableGcd()
    if start and now - start < PAIR_WINDOW then
        ns.LearnLength("gcd", name, duration)
    end
    castTime, castLength = now, ns.LearnedLength("gcd", name)
    if castLength and castLength ~= sweepLength and not start and IsPaced()
        and now < sweepEnd and now - sweepStart < PAIR_WINDOW then
        DrawSweep(sweepStart, castLength) -- the GCD started first; fix its length
    end
end

local function UpdateFromFlag()
    -- isActive, not isOnGCD: it's what the duration-object path reads, and it's readable in combat
    local info = C_Spell.GetSpellCooldown(REFERENCE_SPELL)
    local active = info and info.isActive
    if ns.IsSecret(active) then
        ns.Debug("GCD: isActive is secret")
        active = false
    end
    -- Time-based, so a GCD that ends without a cooldown event can't block the next one
    local sweeping = GetTime() < sweepEnd
    if active and not sweeping then
        StartSweep()
    elseif not active and sweeping then
        ball:Clear()
        sweepEnd = 0
    end
end

local sampling = false -- preview mode's looping sweep is showing (below); real GCDs wait

local function Update()
    if sampling then
        return
    end
    if useDurationObject and not IsPaced() and UpdateFromDurationObject() then
        sweepEnd = 0
        return
    end
    UpdateFromFlag()
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "SPELL_UPDATE_COOLDOWN" then
        Update()
    else
        OnCast(spellID)
    end
end)

-- Settings and preview mode (Elements.lua, Preview.lua). Opacity scales the shade's own alpha (the
-- swipe colour). No hit shape: the pie covers the whole circle, so it's picked from the list.
-- The sample sweeps every SAMPLE_EVERY seconds: 1.0s in Cat Form (and Prowl), 1.5s otherwise.
local SAMPLE_EVERY = 2.5
local sampleLength
local sampleDriver = CreateFrame("Frame")
sampleDriver:Hide()
local sampleStart = 0
sampleDriver:SetScript("OnUpdate", function()
    if GetTime() - sampleStart >= SAMPLE_EVERY then
        sampleStart = GetTime()
        ball:SetCooldown(sampleStart, sampleLength)
    end
end)

ns.RegisterElement({
    id = "resource.gcd",
    zone = "resource",
    name = "GCD pie",
    options = {
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        ball:SetSwipeColor(SHADE[1], SHADE[2], SHADE[3], SHADE[4] * get("opacity") / 100)
    end,
    sample = function(state)
        sampling = state ~= nil
        if sampling then
            sampleLength = (state == "cat" or state == "prowl") and 1 or GCD_LENGTH
            sampleStart = 0 -- sweep at once
            sampleDriver:Show()
        else
            sampleDriver:Hide()
            ball:Clear()
            sweepEnd = 0
            Update() -- a real GCD, if one is running
        end
    end,
})

ns.OnLoad(function()
    ns.Debug("GCD reference spell:", C_Spell.GetSpellName(REFERENCE_SPELL), REFERENCE_SPELL,
        "| method:", useDurationObject and "duration object" or "isActive backup")
end)
