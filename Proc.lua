-- Clearcasting (Omen of Clarity) proc: a mirrored pair of pulsing claw marks ("/// \\\")
-- at the top of the resource circle.
-- In combat the aura API hides player buffs, so we read it from the Cooldown Manager instead:
-- the user must add Omen of Clarity to its tracked buffs or bars.
local addonName, ns = ...

local OMEN_OF_CLARITY = 16864 -- what the Cooldown Manager tracks
local CLEARCASTING = 16870 -- the buff itself; the direct lookup only works out of combat
local CLAW_SIZE = 50
local CLAW_X = ns.RESOURCE_SIZE * 0.2 -- each set's offset from the centre line
local CLAW_Y = ns.RESOURCE_SIZE * 0.22

-- Own frame above the resource circle, so the claws draw on top of the fill.
local frame = CreateFrame("Frame", nil, ns.hud)
frame:SetAllPoints()
frame:SetFrameLevel(ns.hud:GetFrameLevel() + 10)
frame:Hide()

local function CreateClaws(x, mirrored)
    local claws = frame:CreateTexture(nil, "OVERLAY")
    claws:SetTexture(ns.MEDIA .. "claws")
    claws:SetSize(CLAW_SIZE, CLAW_SIZE)
    claws:SetPoint("CENTER", frame, "CENTER", x, CLAW_Y)
    if mirrored then
        claws:SetTexCoord(1, 0, 0, 1) -- flip horizontally
    end
end

CreateClaws(-CLAW_X, false) -- "///"
CreateClaws(CLAW_X, true) -- "\\\"

local pulse = frame:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.5)
fade:SetDuration(0.6)
fade:SetSmoothing("IN_OUT")

local warnedUntracked = false

local function IsClearcasting()
    local tracked = ns.CDM.IsActive(OMEN_OF_CLARITY)
    if tracked ~= nil then
        return tracked
    end
    if InCombatLockdown() and not warnedUntracked then
        warnedUntracked = true
        ns.Print("add Omen of Clarity to the Cooldown Manager's tracked buffs so Clearcasting shows in combat.")
    end
    return C_UnitAuras.GetPlayerAuraBySpellID(CLEARCASTING) ~= nil
end

local function Update()
    local active = IsClearcasting()
    if active ~= frame:IsShown() then
        ns.Debug("Clearcasting:", active, "in combat:", InCombatLockdown())
        frame:SetShown(active)
        if active then
            pulse:Play()
        else
            pulse:Stop()
        end
    end
end

ns.CDM.OnChange(Update)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:SetScript("OnEvent", Update)
