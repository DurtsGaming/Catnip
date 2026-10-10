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
local CreateFrame = ns.Profiled("Gcd") -- timed by /catnip perf (Profiler.lua)

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
-- no spell to the spellbook), so instead each spell's GCD is learned (ns.LearnLength "gcd",
-- SpellTiming.lua). The SPELL_UPDATE_COOLDOWN that starts the GCD names the spell being cast (its
-- first argument; verified 2026-10-10, 0.1-0.17s before the cast events), so the sweep starts at
-- that spell's length straight away, casts with a cast time included. Out of combat the GCD's
-- duration is readable (verified: 0.99 for Rejuvenation), so it's used and learned then. In combat
-- the GCD is timed instead: isActive stays readable, so it's checked every frame until it turns off
-- (measured 1.50s and 0.99s to the frame, 2026-10-10). Back-to-back GCDs never read inactive between
-- them, so only a GCD that started from idle is timed, and anything longer than MAX_GCD is dropped.
-- Nature's Grace (a 10% shorter GCD for 3s after a crit) can't be seen in combat: no Druid buff is
-- readable then. (Until 2026-10-10 the spell came from the cast event, paired with the GCD start
-- within 0.4s, and lengths were only learned out of combat.)
local MAX_GCD = 1.6 -- seconds; no GCD is longer, so a longer measurement spans two
local MIN_GCD = 0.5
local sweepStart = 0
local sweepLength = 0
local wasActive = false -- the GCD as last read, to tell a fresh GCD from one already running

-- The GCD's real start and duration, or nil when secret (in combat) or not running.
local function ReadableGcd()
    local start, duration = ns.ReadCooldown(REFERENCE_SPELL)
    if start and duration > 0 then
        return start, duration
    end
end

local function SpellName(spellID)
    if not spellID or ns.IsSecret(spellID) then
        return nil
    end
    local name = C_Spell.GetSpellName(spellID)
    if name and not ns.IsSecret(name) then
        return name
    end
end

-- Times a GCD in combat: from its start to the frame isActive turns off. Runs only meanwhile.
local timer = CreateFrame("Frame")
timer:Hide()
local timedFrom, timedName
timer:SetScript("OnUpdate", function()
    local info = C_Spell.GetSpellCooldown(REFERENCE_SPELL)
    local active = info and info.isActive
    if ns.IsSecret(active) then
        timer:Hide()
        return
    end
    if active then
        return
    end
    timer:Hide()
    wasActive = false
    local length = GetTime() - timedFrom
    if length >= MIN_GCD and length <= MAX_GCD then
        ns.LearnLength("gcd", timedName, length)
    end
end)

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

-- spellID: the spell the starting event named; fresh: the GCD was idle before it.
local function StartSweep(spellID, fresh)
    local now = GetTime()
    if not IsPaced() then
        ball:SetCooldown(now, 1)
        sweepStart, sweepEnd = now, now + 1
        return
    end
    local name = SpellName(spellID)
    local start, duration = ReadableGcd()
    if start then
        if name and fresh then
            ns.LearnLength("gcd", name, duration)
        end
        DrawSweep(start, duration)
        return
    end
    DrawSweep(now, name and ns.LearnedLength("gcd", name) or GCD_LENGTH)
    if name and fresh then
        timedFrom, timedName = now, name
        timer:Show()
    end
end

local function UpdateFromFlag(active, spellID, fresh)
    -- Time-based, so a GCD that ends without a cooldown event can't block the next one
    local sweeping = GetTime() < sweepEnd
    if active and not sweeping then
        StartSweep(spellID, fresh)
    elseif not active and sweeping then
        ball:Clear()
        sweepEnd = 0
    end
end

local sampling = false -- preview mode's looping sweep is showing (below); real GCDs wait

local function Update(spellID)
    -- isActive, not isOnGCD: it's what the duration-object path reads, and it's readable in combat.
    -- Read in every form, so a GCD running across a shapeshift isn't taken for a fresh one.
    local info = C_Spell.GetSpellCooldown(REFERENCE_SPELL)
    local active = info and info.isActive
    if ns.IsSecret(active) then
        ns.Debug("GCD: isActive is secret")
        active = false
    end
    active = active and true or false
    local fresh = active and not wasActive
    wasActive = active
    if sampling then
        return
    end
    if useDurationObject and not IsPaced() and UpdateFromDurationObject() then
        sweepEnd = 0
        return
    end
    UpdateFromFlag(active, spellID, fresh)
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:SetScript("OnEvent", function(_, _, spellID)
    Update(spellID) -- the spell whose cooldown changed: at the GCD's start, the one being cast
end)

-- Settings and preview mode (Elements.lua, Preview.lua). Opacity scales the shade's own alpha (the
-- swipe colour). No hit shape: the pie covers the whole circle, so it's picked from the list.
-- The sample sweeps every SAMPLE_EVERY seconds, drawn as the real one is: in Cat Form a plain 1.0s
-- sweep; otherwise 1.5s paced to the swing, i.e. a swing-length pie starting part-way (60% for the
-- preview's 2.5s sample swing, Swing.lua), so it shrinks at the sample swing ring's speed.
local SAMPLE_EVERY = 2.5
local sampleLength, sampleSwing -- sampleSwing: the swing it's paced to, or nil for a plain sweep
local sampleDriver = CreateFrame("Frame")
sampleDriver:Hide()
local sampleStart = 0
sampleDriver:SetScript("OnUpdate", function()
    if GetTime() - sampleStart >= SAMPLE_EVERY then
        sampleStart = GetTime()
        if sampleSwing and sampleSwing > sampleLength then
            ball:SetCooldown(sampleStart - (sampleSwing - sampleLength), sampleSwing)
        else
            ball:SetCooldown(sampleStart, sampleLength)
        end
    end
end)

ns.RegisterElement({
    id = "resource.gcd",
    zone = "resource",
    name = "GCD pie",
    hidden = true, -- not offered in the settings for now (Elements.lua)
    glyph = { kind = "disc", color = { 0.43, 0.40, 0.36 } },
    options = {
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        ball:SetSwipeColor(SHADE[1], SHADE[2], SHADE[3], SHADE[4] * get("opacity") / 100)
    end,
    sample = function(state)
        sampling = state ~= nil
        if sampling then
            local paced = state ~= "cat" -- as IsPaced: every form but Cat
            sampleLength = paced and GCD_LENGTH or 1
            sampleSwing = paced and ns.SAMPLE_SWING or nil
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
