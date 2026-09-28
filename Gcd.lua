-- Global cooldown "Harvey ball": a faint white pie over the resource circle that shrinks clockwise while
-- the GCD runs. Retail reports the GCD on dummy spell 61304; Forever doesn't have it and uses
-- Classic's GCD spell 29515 instead (found via EllesmereUI's Forever fix, PR #2240).
--
-- In combat the cooldown's start and duration are secret, and Cooldown:SetCooldown rejects secrets
-- from addon code (verified). So:
--   1. Preferred: C_Spell.GetSpellCooldownDuration gives a sealed duration object, which
--      Cooldown:SetCooldownFromDurationObject accepts. Exact timing, drawn by Blizzard.
--   2. Backup: the cooldown's isOnGCD flag is readable in combat (verified). When it turns on,
--      run our own sweep of the Classic GCD length: 1.0s for energy abilities, 1.5s otherwise.
local addonName, ns = ...

local REFERENCE_SPELL = 29515 -- Forever's GCD spell
local SHADE = { 1, 1, 1, 0.2 }

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
        ns.Debug("GCD: duration object rejected, switching to isOnGCD backup:", err)
    end
    return ok
end

local sweeping = false

local function UpdateFromFlag()
    local info = C_Spell.GetSpellCooldown(REFERENCE_SPELL)
    local onGCD = info and info.isOnGCD
    if ns.IsSecret(onGCD) then
        onGCD = false
    end
    if onGCD and not sweeping then
        local length = UnitPowerType("player") == Enum.PowerType.Energy and 1 or 1.5
        ball:SetCooldown(GetTime(), length)
    elseif not onGCD and sweeping then
        ball:Clear()
    end
    sweeping = onGCD and true or false
end

local function Update()
    if useDurationObject and UpdateFromDurationObject() then
        return
    end
    UpdateFromFlag()
end

local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:SetScript("OnEvent", Update)

ns.OnLoad(function()
    ns.Debug("GCD reference spell:", C_Spell.GetSpellName(REFERENCE_SPELL), REFERENCE_SPELL,
        "| method:", useDurationObject and "duration object" or "isOnGCD backup")
end)
