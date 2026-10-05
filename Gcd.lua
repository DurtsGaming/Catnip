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

local REFERENCE_SPELL = 29515 -- Forever's GCD spell
ns.GCD_SPELL = REFERENCE_SPELL -- Cooldowns.lua tells real cooldowns from the GCD with it
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

-- Gift of the Earthmother (talent): these spells' GCD is 0.5s shorter. We only see the GCD start,
-- so the cast event tells us which spell it was; the two arrive in either order (unverified), so
-- whichever comes second applies the short length. Nature's Grace (a 10% shorter GCD for 3s after
-- a crit) can't be seen: no Druid buff is readable in combat.
local EARTHMOTHER = { "Gift of the Earthmother" }
local EARTHMOTHER_SPELLS = { ["Rejuvenation"] = true, ["Swiftmend"] = true, ["Wild Growth"] = true }
local EARTHMOTHER_LENGTH = GCD_LENGTH - 0.5
local PAIR_WINDOW = 0.2 -- seconds between the GCD start and its cast event to count as one cast
local hasEarthmother = false
local sweepStart = 0
local shortCastTime = 0 -- GetTime() of the last cast with a short GCD

local function DrawSweep(start, length)
    local swing, source = SwingLength()
    if swing and swing > length then
        -- a swing-length sweep already (swing - GCD) in, so it ends when the GCD does
        ball:SetCooldown(start - (swing - length), swing)
    else
        ball:SetCooldown(start, length)
    end
    sweepStart, sweepEnd = start, start + length
    ns.Debug("GCD sweep:", length, "s, swing", swing, "from", source)
end

local function StartSweep()
    local now = GetTime()
    if not IsPaced() then
        ball:SetCooldown(now, 1)
        sweepStart, sweepEnd = now, now + 1
        return
    end
    local short = now - shortCastTime < PAIR_WINDOW
    DrawSweep(now, short and EARTHMOTHER_LENGTH or GCD_LENGTH)
end

local function OnCast(spellID)
    if not hasEarthmother or not spellID or ns.IsSecret(spellID) then
        return
    end
    if not EARTHMOTHER_SPELLS[C_Spell.GetSpellName(spellID)] then
        return
    end
    local now = GetTime()
    shortCastTime = now
    if IsPaced() and now < sweepEnd and now - sweepStart < PAIR_WINDOW then
        DrawSweep(sweepStart, EARTHMOTHER_LENGTH) -- the GCD started first; shorten it
    end
end

local function CheckTalents()
    hasEarthmother = ns.FindKnownSpell(EARTHMOTHER) ~= nil
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

local function Update()
    if useDurationObject and not IsPaced() and UpdateFromDurationObject() then
        sweepEnd = 0
        return
    end
    UpdateFromFlag()
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("SPELLS_CHANGED")
ns.TryRegisterEvent(events, "PLAYER_TALENT_UPDATE")
ns.TryRegisterEvent(events, "TRAIT_CONFIG_UPDATED")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "SPELL_UPDATE_COOLDOWN" then
        Update()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(spellID)
    else
        CheckTalents()
    end
end)

ns.OnLoad(function()
    CheckTalents()
    ns.Debug("GCD reference spell:", C_Spell.GetSpellName(REFERENCE_SPELL), REFERENCE_SPELL,
        "| method:", useDurationObject and "duration object" or "isActive backup",
        "| Gift of the Earthmother:", hasEarthmother)
end)
