-- Rip timer: a thin red layer just outside the swing ring, full when Rip goes up and draining clockwise.
-- Whether Rip is on the target comes from the Cooldown Manager (the user tracks Rip there); how long
-- is left comes from our own timer, started when we cast Rip, since the aura's duration is secret.
local addonName, ns = ...

local RIP = 1079 -- the ID the Cooldown Manager tracks Rip under
local RIP_DURATION = 12 -- seconds; Classic's value, to be confirmed against Blizzard's Rip bar
local COLOR = { 0.9, 0.15, 0.15 }

local ripName = C_Spell.GetSpellName(RIP)

-- #5 thin ring, drawn by a Cooldown swipe, which drains clockwise by default.
local ring = CreateFrame("Cooldown", nil, ns.hud)
ring:SetSize(ns.DOT_RING_SIZE, ns.DOT_RING_SIZE)
ring:SetPoint("CENTER")
ring:SetSwipeTexture(ns.MEDIA .. "ring_dot")
ring:SetSwipeColor(COLOR[1], COLOR[2], COLOR[3], 1)
ring:SetDrawEdge(false)
ring:SetDrawBling(false)
ring:SetHideCountdownNumbers(true)
ring:Hide()

-- When our Rip expires, per target. Keyed by GUID when the game lets us read it, else one shared slot.
local expirations = {}

local function TargetKey()
    local guid = UnitGUID("target")
    if guid == nil or ns.IsSecret(guid) then
        return "target"
    end
    return guid
end

local shownExpiration

local function Update()
    local expires = expirations[TargetKey()]
    local onTarget = ns.CDM.IsActive(RIP) -- nil if the Cooldown Manager isn't tracking Rip
    local active = expires ~= nil and expires > GetTime() and onTarget ~= false

    if not active then
        if ring:IsShown() then
            ns.Debug("Rip ring hidden. on target:", onTarget)
        end
        ring:Hide()
        shownExpiration = nil
        return
    end

    if shownExpiration ~= expires then
        shownExpiration = expires
        ring:SetCooldown(expires - RIP_DURATION, RIP_DURATION)
    end
    ring:Show()
end

ring:SetScript("OnCooldownDone", Update)

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" and not ns.IsSecret(spellID)
        and C_Spell.GetSpellName(spellID) == ripName then
        local key = TargetKey()
        expirations[key] = GetTime() + RIP_DURATION
        ns.Debug("Rip cast, spell:", spellID, "target key:", key)
    end
    Update()
end)

ns.CDM.OnChange(Update)
