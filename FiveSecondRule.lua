-- Five-second rule: mana only regenerates once 5 seconds have passed since mana was last spent.
-- Out of Cat/Bear Form (whenever the power is mana), a dark blue ring over the resource circle's
-- border shows it: full while regenerating (including during a cast, since mana is only spent
-- when it lands), and after a mana spend it empties, then two arcs grow from 6 o'clock up both
-- sides and meet at 12 o'clock after the 5 seconds.
--
-- Only casts that really spend mana count: not ones with no mana cost (skinning), nor ones made
-- free by Clearcasting (judged by whether the cast used the buff up). Our casts' spell IDs, spell costs and UnitPowerType are readable in
-- combat and the timer is our own clock; Clearcasting is the exception (see ns.IsClearcasting).
local addonName, ns = ...

local RULE = 5
local COLOR = { 0.1, 0.25, 0.8 }
local MANA = Enum.PowerType.Mana

local SIZE = ns.RESOURCE_SIZE + 6 -- matches the border in Resource.lua, which the ring covers

-- Each side of the ring is a clip frame showing only its half. Inside it, a half-ring texture
-- (ring_mana_half, the left half) rotates around the ring's centre: starting on the far side,
-- where it's clipped away, it swings in from 6 o'clock until it fills its half at 12 o'clock.
local holder = CreateFrame("Frame", nil, ns.hud)
holder:SetSize(SIZE, SIZE)
holder:SetPoint("CENTER")
holder:SetFrameLevel(ns.hud:GetFrameLevel() + 4) -- over the GCD shading, under the resource number
holder:Hide()

local function CreateSide(point)
    local clip = CreateFrame("Frame", nil, holder)
    clip:SetPoint("TOP" .. point)
    clip:SetPoint("BOTTOM" .. point)
    clip:SetWidth(SIZE / 2)
    clip:SetClipsChildren(true)
    local arc = clip:CreateTexture(nil, "ARTWORK")
    arc:SetTexture(ns.MEDIA .. "ring_mana_half")
    arc:SetSize(SIZE, SIZE)
    arc:SetPoint("CENTER", holder)
    arc:SetVertexColor(COLOR[1], COLOR[2], COLOR[3])
    return arc
end

local rightArc = CreateSide("RIGHT")
local leftArc = CreateSide("LEFT")

-- progress 0-1 -> each arc has swept `angle` (0 to pi) up its side. SetRotation turns
-- counter-clockwise: the left half turned by +angle enters the right side from the bottom, and
-- turned by pi - angle (a right half turned clockwise) enters the left side from the bottom.
local function SetProgress(progress)
    local angle = math.pi * progress
    rightArc:SetRotation(angle)
    leftArc:SetRotation(math.pi - angle)
end

local lastSpend -- GetTime() of the last mana spend
local isMana = false

local function Progress()
    if not lastSpend then
        return 1
    end
    return math.min((GetTime() - lastSpend) / RULE, 1)
end

holder:SetScript("OnUpdate", function()
    SetProgress(Progress())
end)

local function Refresh()
    holder:SetShown(isMana)
    SetProgress(Progress())
end

-- Whether a spell has a mana cost (skinning, for one, has none). If it can't be read, assume so.
local function CostsMana(spellID)
    if ns.IsSecret(spellID) or not (C_Spell and C_Spell.GetSpellPowerCost) then
        return true
    end
    local ok, result = pcall(function()
        for _, cost in ipairs(C_Spell.GetSpellPowerCost(spellID) or {}) do
            if cost.type == MANA and (ns.IsSecret(cost.cost) or cost.cost > 0) then
                return true
            end
        end
        return false
    end)
    return not ok or result
end

local function IsClearcasting()
    return ns.IsClearcasting and ns.IsClearcasting()
end

local function Spent(spellID, at, reason)
    lastSpend = math.max(lastSpend or 0, at)
    local name = not ns.IsSecret(spellID) and C_Spell.GetSpellName(spellID) or spellID
    ns.Debug("5s rule:", name, "spent mana, ring reset (" .. reason .. ")")
end

-- Whether Clearcasting was up when each cast was sent, keyed by spell ID (castGUID may be
-- secret). Only damage and healing spells use it up (not shapeshifts, Wrath or buffs), so rather
-- than listing those, a cast sent with it up is free only if it's gone once the cast lands.
-- If Clearcasting can't be read (in combat, untracked by the Cooldown Manager), assume it's down.
local ccWhenSent = {}

local function OnSent(spellID)
    if spellID and not ns.IsSecret(spellID) then
        ccWhenSent[spellID] = IsClearcasting()
    end
end

local function OnSucceeded(spellID)
    local hadCC = spellID and not ns.IsSecret(spellID) and ccWhenSent[spellID]
    if spellID and not ns.IsSecret(spellID) then
        ccWhenSent[spellID] = nil
    end
    if not CostsMana(spellID) then
        return
    end
    local castAt = GetTime()
    if not hadCC then
        Spent(spellID, castAt, "costs mana")
        return
    end
    C_Timer.After(0.2, function() -- give the buff time to drop
        if IsClearcasting() == false then
            local name = not ns.IsSecret(spellID) and C_Spell.GetSpellName(spellID) or spellID
            ns.Debug("5s rule:", name, "no reset (used Clearcasting)")
        else
            Spent(spellID, castAt, "Clearcasting not used")
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        OnSent((select(4, ...))) -- unit, target, castGUID, spellID
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSucceeded((select(3, ...))) -- unit, castGUID, spellID
    else
        local powerType = UnitPowerType("player")
        isMana = not ns.IsSecret(powerType) and powerType == MANA
    end
    Refresh()
end)
