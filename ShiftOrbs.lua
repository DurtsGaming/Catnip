-- Shift orbs: a row of small orbs curved under the swing ring, one for each shapeshift your
-- mana pays for: floor(mana / cost), up to 5. In every form, once a form is learned (Bear Form at
-- 10, Cat Form at 20); before that there's no cost to divide by and nothing shows. Shifting Power
-- costs the same as a shift, so the orbs count its casts too. COMBAT_ONLY (off for now) also hides
-- them out of combat. They curve around 6 o'clock just outside the thin Shifting Power arc, mirroring
-- the combo points across the bottom. Cast.lua's text sits below them, so they stay up during casts
-- (when the count matters: can I shift back after this heal?).
--
-- The orbs match the resource circle (Resource.lua): mana's gradient out of Cat and Bear Form, full
-- rage in Bear Form, full energy in Cat Form, and stealth mode's periwinkle while stealthed (Prowl
-- or Shadowmeld, in any form; dimmed then too). With Shifting Power known, Cat Form's orbs are half
-- mana blue instead: blue to yellow, or blue to periwinkle while stealthed.
--
-- It also gates ShiftingPower.lua's ready pulse (ns.shiftingPowerPulseGate) on a one-shift curve,
-- in every form, so the pulse only shows if your mana pays for a cast.
--
-- Mana is secret in combat, so we can't divide it. Instead there's a pre-built, centred row for
-- each count (one orb, two orbs, ...), and each row's alpha comes from UnitPowerPercent with a step
-- curve that is 1 only between that count's thresholds (n and n+1 shifts' worth of mana, as a
-- fraction of max mana). The engine evaluates the curve, so the secret never reaches our code, and
-- SetAlpha takes the result as it is (Blood in the Water colours its combo text the same way;
-- EllesmereUI feeds curve results to SetAlpha). The cost and max mana are plain numbers out of
-- combat; the curves are rebuilt then.
--
-- The design's 0.1s fade when the count changes isn't done: in combat we can't tell the count
-- changed, so the rows just swap. (Out of combat it could be; not worth it while undecided.)
local addonName, ns = ...

local COMBAT_ONLY = false -- off for now: the orbs show in and out of combat
local MAX_ORBS = 5
local ORB_SIZE = 0.6 * ns.COMBO_DOT_SIZE -- 60% of a combo point
local SPACING = ORB_SIZE * 1.25 -- centre to centre, along the chord
local RADIUS = 89 -- inner edge ~77.6, ~3.4 outside the Shifting Power arc (make_textures.py SP_RADIUS)
local STEP = 2 * math.asin(SPACING / 2 / RADIUS) -- angle between neighbouring orbs (~18.4 degrees)
local STEALTH_ALPHA = 0.6 -- 30% was too much
local MANA = Enum.PowerType.Mana
local SHIFT_SPELLS = { "Cat Form", "Dire Bear Form", "Bear Form" } -- all cost the same
local SHIFTING_POWER = { "Shifting Power" }
local CAN_COUNT = UnitPowerPercent ~= nil and C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil
    and Enum.LuaCurveType ~= nil

-- Orb art (make_textures.py), coloured and drawn untinted. Anything not listed gets mana's.
local POWER_ART = {
    [Enum.PowerType.Energy] = "orb_energy",
    [Enum.PowerType.Rage] = "orb_rage",
}
local MANA_ART = "orb_mana"
local STEALTH_ART = "orb_prowl"
local SP_CAT_ART = "sp_orb" -- Cat Form with Shifting Power known: blue to yellow
local SP_CAT_STEALTH_ART = "sp_orb_prowl" -- the same, stealthed: blue to periwinkle

local hud = ns.hud

local holder = CreateFrame("Frame", nil, hud)
holder:SetSize(1, 1)
holder:SetPoint("CENTER", hud, "CENTER")
holder:SetFrameLevel(hud:GetFrameLevel() + 2)
holder:Hide()

-- rows[n]: n orbs, centred on 6 o'clock. orbs: every orb texture across the rows, for swapping the art.
local rows, orbs = {}, {}
local currentArt = MANA_ART
for n = 1, MAX_ORBS do
    local row = CreateFrame("Frame", nil, holder)
    row:SetAllPoints()
    row:SetAlpha(0)
    for i = 1, n do
        local angle = -math.pi / 2 + (i - (n + 1) / 2) * STEP
        local x, y = RADIUS * math.cos(angle), RADIUS * math.sin(angle)
        local orb = row:CreateTexture(nil, "ARTWORK")
        orb:SetTexture(ns.MEDIA .. currentArt)
        orb:SetSize(ORB_SIZE, ORB_SIZE)
        orb:SetPoint("CENTER", row, "CENTER", x, y)
        orbs[#orbs + 1] = orb
        local border = row:CreateTexture(nil, "OVERLAY") -- same black rim as the combo points
        border:SetTexture(ns.MEDIA .. "ring_small")
        border:SetVertexColor(0, 0, 0)
        border:SetSize(ORB_SIZE, ORB_SIZE)
        border:SetPoint("CENTER", orb)
    end
    rows[n] = row
end

local cost, maxMana -- mana per shift and max mana, as last read out of combat; cost nil = unknown
local curves = {} -- curves[n]: 1 while mana is between n and n+1 shifts' worth, as a fraction of max
local affordCurve -- 1 from one shift's worth of mana up: gates ShiftingPower.lua's ready pulse
local hasShiftingPower = false
local inCombat = false -- from PLAYER_REGEN_DISABLED / _ENABLED

-- The art for the current form and stealth state; nil (keep the current art) if the form is secret.
local function OrbArt()
    local powerType = UnitPowerType("player")
    if ns.IsSecret(powerType) then
        return nil
    end
    local stealthed = ns.IsStealthMode()
    if powerType == Enum.PowerType.Energy and hasShiftingPower then
        return stealthed and SP_CAT_STEALTH_ART or SP_CAT_ART
    end
    if stealthed then
        return STEALTH_ART
    end
    return POWER_ART[powerType] or MANA_ART
end

local function UpdateArt()
    local art = OrbArt()
    if not art or art == currentArt then
        return
    end
    currentArt = art
    for _, orb in ipairs(orbs) do
        orb:SetTexture(ns.MEDIA .. art)
    end
end

local function PlainNumber(value)
    if value == nil or ns.IsSecret(value) then
        return nil
    end
    return value
end

local function ReadCost(spellID)
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then
        return nil
    end
    for _, entry in ipairs(costs) do
        if PlainNumber(entry.type) == MANA then
            return PlainNumber(entry.cost)
        end
    end
    return nil
end

-- Looks up the spells; out of combat also reads the cost and max mana and rebuilds the curves. In
-- combat they keep the values from the last time.
local function Rebuild()
    hasShiftingPower = ns.FindKnownSpell(SHIFTING_POWER) ~= nil
    local spellID = ns.FindKnownSpell(SHIFT_SPELLS)
    if not spellID then
        cost = nil -- no form learned yet
        return
    end
    if InCombatLockdown() then
        return
    end
    local newCost, max = ReadCost(spellID), PlainNumber(UnitPowerMax("player", MANA))
    if not newCost or newCost <= 0 or not max or max <= 0 then
        ns.Debug("shift orbs: cost", newCost, "max mana", max, "- hidden")
        cost = nil
        return
    end
    if newCost == cost and max == maxMana then
        return
    end
    cost, maxMana = newCost, max
    local fraction = cost / max
    for n = 1, MAX_ORBS do
        local curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 0)
        curve:AddPoint(n * fraction, 1)
        if n < MAX_ORBS then
            curve:AddPoint((n + 1) * fraction, 0)
        end
        curves[n] = curve
    end
    affordCurve = C_CurveUtil.CreateCurve()
    affordCurve:SetType(Enum.LuaCurveType.Step)
    affordCurve:AddPoint(0, 0)
    affordCurve:AddPoint(fraction, 1)
    ns.Debug("shift orbs: cost", cost, "of", max, "mana (spell", spellID .. ")")
end

-- The ready pulse shows only if mana pays for a cast, in every form. Cost unknown: always shows.
local function UpdatePulseGate()
    local gate = ns.shiftingPowerPulseGate
    if not gate then
        return
    end
    if CAN_COUNT and cost ~= nil and affordCurve then
        gate:SetAlpha(UnitPowerPercent("player", MANA, false, affordCurve))
    else
        gate:SetAlpha(1)
    end
end

local function Update()
    UpdatePulseGate()
    local show = CAN_COUNT and (inCombat or not COMBAT_ONLY) and cost ~= nil
    holder:SetShown(show and true or false)
    if not show then
        return
    end
    UpdateArt()
    for n, row in ipairs(rows) do
        row:SetAlpha(UnitPowerPercent("player", MANA, false, curves[n]))
    end
end

local function RebuildAndUpdate()
    Rebuild()
    Update()
end

ns.OnStealthChanged(function(stealthed)
    holder:SetAlpha(stealthed and STEALTH_ALPHA or 1) -- the rows set their own alpha
    Update()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
ns.TryRegisterEvent(events, "PLAYER_TALENT_UPDATE")
ns.TryRegisterEvent(events, "TRAIT_CONFIG_UPDATED")
events:SetScript("OnEvent", function(_, event, _, powerToken)
    if event == "UNIT_POWER_FREQUENT" then
        if powerToken == "MANA" then
            Update()
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        Update()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        Update()
    else
        if event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        elseif event == "PLAYER_ENTERING_WORLD" then
            inCombat = InCombatLockdown() -- e.g. a /reload in combat
        end
        RebuildAndUpdate()
    end
end)

ns.OnLoad(function()
    ns.Debug("shift orbs: curves available:", CAN_COUNT)
end)
