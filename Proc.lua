-- Clearcasting (Omen of Clarity) proc: a pulsing white cap over the top 10% of the resource circle.
--
-- In combat the aura API hides player buffs, so we can't check Clearcasting ourselves.
-- Preferred: an AuraContainer (see AuraContainer.lua). Blizzard shows its button while the aura
-- is up and our cap rides on it; our code never learns whether the proc is up.
-- Fallback without AuraContainer: the Cooldown Manager (user must track Omen of Clarity there).
local addonName, ns = ...

local OMEN_OF_CLARITY = 16864 -- what the Cooldown Manager tracks
local CLEARCASTING = 16870 -- the buff itself
local SIZE = ns.RESOURCE_SIZE -- circle_cap is drawn on a full-circle canvas, so it lines up with the fill

-- Is Clearcasting up? nil if we can't tell: in combat the aura API hides it, so only the
-- Cooldown Manager knows (if the player tracks Omen of Clarity there). Our cap doesn't need
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

-- Our look: the cap on a frame filling parent, pulsing while visible.
local function CreateCapFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    local cap = frame:CreateTexture(nil, "OVERLAY")
    cap:SetTexture(ns.MEDIA .. "circle_cap")
    cap:SetAllPoints(frame)

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
    anchor:SetSize(SIZE, SIZE)
    anchor:SetPoint("CENTER")
    anchor:SetFrameLevel(ns.hud:GetFrameLevel() + 10)
    anchor:Hide()
    CreateCapFrame(anchor)

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
        width = SIZE,
        height = SIZE,
        level = 10, -- above the resource fill and GCD pie
        initialize = function(button)
            ns.HideAuraButtonArt(button)
            CreateCapFrame(button)
        end,
    })
else
    SetupCooldownManagerFallback()
end
