-- Clearcasting (Omen of Clarity) proc: a crescent of light inside the top of the resource circle.
--
-- In combat the aura API hides player buffs, so we can't check Clearcasting ourselves.
-- Preferred: an AuraContainer (see AuraContainer.lua). Blizzard shows its button while the aura
-- is up and our crescent rides on it; our code never learns whether the proc is up.
-- Fallback without AuraContainer: the Cooldown Manager (user must track Omen of Clarity there).
local addonName, ns = ...

local OMEN_OF_CLARITY = 16864 -- what the Cooldown Manager tracks
local CLEARCASTING = 16870 -- the buff itself
local SIZE = ns.RESOURCE_SIZE -- crescent textures are drawn on a full-circle canvas, so they line up with the fill
local SHADOW_ALPHA = 0.4 -- dark backing under the crescent
local EDGE_ALPHA = 0.6 -- dark line under the bright arc

-- Is Clearcasting up? nil if we can't tell: in combat the aura API hides it, so only the
-- Cooldown Manager knows (if the player tracks Omen of Clarity there). Our crescent doesn't need
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

-- An additive texture filling frame, with an alpha pulse. Returns the pulse to play.
local function AddGlowLayer(frame, textureName, lowAlpha, duration)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(ns.MEDIA .. textureName)
    texture:SetAllPoints(frame)
    texture:SetBlendMode("ADD") -- brightens what's under it, so it reads as light rather than paint

    local pulse = texture:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(lowAlpha)
    fade:SetDuration(duration)
    fade:SetSmoothing("IN_OUT")
    return pulse
end

-- Our look: a crescent of light inside the top rim, on a frame filling parent. The glow under
-- it breathes; the arc itself barely dims, so the proc stays readable at the glow's low point.
-- A steady dark backing sits under both: additive light can't brighten a full energy fill (yellow
-- is already near max), so this dims the fill there and gives the light contrast.
local function CreateCrescentFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    local shadow = frame:CreateTexture(nil, "ARTWORK") -- below the OVERLAY glow layers
    shadow:SetTexture(ns.MEDIA .. "crescent_shadow")
    shadow:SetAllPoints(frame)
    shadow:SetVertexColor(0, 0, 0, SHADOW_ALPHA)

    local edge = frame:CreateTexture(nil, "ARTWORK", nil, 1) -- a dark line just under the arc, for a crisp edge
    edge:SetTexture(ns.MEDIA .. "crescent_edge")
    edge:SetAllPoints(frame)
    edge:SetVertexColor(0, 0, 0, EDGE_ALPHA)

    local pulses = {
        AddGlowLayer(frame, "crescent_bloom", 0.68, 0.9),
        AddGlowLayer(frame, "crescent_line", 0.95, 1.8),
    }
    local function Play()
        for _, pulse in ipairs(pulses) do pulse:Play() end
    end
    frame:SetScript("OnShow", Play)
    frame:SetScript("OnHide", function()
        for _, pulse in ipairs(pulses) do pulse:Stop() end
    end)
    if frame:IsVisible() then
        Play()
    end
end

-- Fallback without AuraContainer: the Cooldown Manager.
local function SetupCooldownManagerFallback()
    local anchor = CreateFrame("Frame", nil, ns.hud)
    anchor:SetSize(SIZE, SIZE)
    anchor:SetPoint("CENTER")
    anchor:SetFrameLevel(ns.hud:GetFrameLevel() + 10)
    anchor:Hide()
    CreateCrescentFrame(anchor)

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
            CreateCrescentFrame(button)
        end,
    })
else
    SetupCooldownManagerFallback()
end
