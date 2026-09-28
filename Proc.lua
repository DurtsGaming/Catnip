-- Clearcasting (Omen of Clarity) proc: a mirrored pair of pulsing claw marks ("/// \\\")
-- at the top of the resource circle.
--
-- In combat the aura API hides player buffs, so we can't check Clearcasting ourselves.
-- Preferred: an AuraContainer (see AuraContainer.lua). Blizzard shows its button while the aura
-- is up and our claws ride on it; our code never learns whether the proc is up.
-- Fallback without AuraContainer: the Cooldown Manager (user must track Omen of Clarity there).
local addonName, ns = ...

local OMEN_OF_CLARITY = 16864 -- what the Cooldown Manager tracks
local CLEARCASTING = 16870 -- the buff itself
local CLAW_SIZE = 50
local CLAW_X = ns.RESOURCE_SIZE * 0.2 -- each set's offset from the centre line
local CLAW_Y = ns.RESOURCE_SIZE * 0.22
local BOX_WIDTH, BOX_HEIGHT = 2 * CLAW_X + CLAW_SIZE, CLAW_SIZE -- covers both claw sets

-- Is Clearcasting up? nil if we can't tell: in combat the aura API hides it, so only the
-- Cooldown Manager knows (if the player tracks Omen of Clarity there). Our claws don't need
-- this (AuraContainer), but other code deciding things does (FiveSecondRule.lua).
function ns.IsClearcasting()
    local active = ns.CDM.IsActive(OMEN_OF_CLARITY)
    if active ~= nil then
        return active
    end
    if InCombatLockdown() then
        return nil
    end
    return C_UnitAuras.GetPlayerAuraBySpellID(CLEARCASTING) ~= nil
end

-- Our look: both claw sets on one frame centred in parent, pulsing while visible.
local function CreateClawFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(BOX_WIDTH, BOX_HEIGHT)
    frame:SetPoint("CENTER")

    for _, side in ipairs({ -1, 1 }) do
        local claws = frame:CreateTexture(nil, "OVERLAY")
        claws:SetTexture(ns.MEDIA .. "claws")
        claws:SetSize(CLAW_SIZE, CLAW_SIZE)
        claws:SetPoint("CENTER", frame, "CENTER", side * CLAW_X, 0)
        if side == 1 then
            claws:SetTexCoord(1, 0, 0, 1) -- mirrored: "\\\"
        end
    end

    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.5)
    fade:SetDuration(0.6)
    fade:SetSmoothing("IN_OUT")

    frame:SetScript("OnShow", function() pulse:Play() end)
    frame:SetScript("OnHide", function() pulse:Stop() end)
    if frame:IsVisible() then
        pulse:Play()
    end
end

-- Fallback without AuraContainer: the Cooldown Manager.
local function SetupCooldownManagerFallback()
    local anchor = CreateFrame("Frame", nil, ns.hud)
    anchor:SetSize(BOX_WIDTH, BOX_HEIGHT)
    anchor:SetPoint("CENTER", ns.hud, "CENTER", 0, CLAW_Y)
    anchor:SetFrameLevel(ns.hud:GetFrameLevel() + 10)
    anchor:Hide()
    CreateClawFrame(anchor)

    local warnedUntracked = false

    local function Update()
        local active = ns.IsClearcasting()
        if active == nil then
            if not warnedUntracked then
                warnedUntracked = true
                ns.Print("add Omen of Clarity to the Cooldown Manager's tracked buffs so Clearcasting shows in combat.")
            end
            active = false
        end
        if active ~= anchor:IsShown() then
            ns.Debug("Clearcasting:", active, "in combat:", InCombatLockdown())
            anchor:SetShown(active)
        end
    end

    ns.CDM.OnChange(Update)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:SetScript("OnEvent", Update)
end

if ns.HAS_AURA_CONTAINER then
    ns.CreateAuraContainer({
        label = "Clearcasting",
        unit = "player",
        filter = "HELPFUL",
        spellIDs = { CLEARCASTING },
        width = BOX_WIDTH,
        height = BOX_HEIGHT,
        y = CLAW_Y,
        level = 10, -- above the resource fill
        initialize = function(button)
            ns.HideAuraButtonArt(button)
            CreateClawFrame(button)
        end,
    })
else
    SetupCooldownManagerFallback()
end
