-- Shifting Power mana counter: in Cat Form, a centred row of small blue-to-yellow orbs under the
-- Shifting Power arc, one for each cast your mana pays for: floor(mana / cost). Hidden if Shifting
-- Power isn't known; COMBAT_ONLY (off for now) also hides it out of combat. Hidden while casting
-- or channelling (ns.IsCasting), since Cast.lua's text (time and spell name) sits in the same spot.
-- It also gates ShiftingPower.lua's ready pulse (ns.shiftingPowerPulseGate) on a one-cast curve,
-- in every form, so the pulse only shows if your mana pays for a cast.
--
-- Mana is secret in combat, so we can't divide it. Instead there's a pre-built, centred row for
-- each count (one orb, two orbs, ...), and each row's alpha comes from UnitPowerPercent with a step
-- curve that is 1 only between that count's thresholds (n and n+1 casts' worth of mana, as a
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
local SPACING = ORB_SIZE * 1.25
local Y = -95 -- centre, below the Shifting Power arc (its outer edge is ~78.5 below the HUD's centre)
local MANA = Enum.PowerType.Mana
local CAN_COUNT = UnitPowerPercent ~= nil and C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil
    and Enum.LuaCurveType ~= nil

local hud = ns.hud

local holder = CreateFrame("Frame", nil, hud)
holder:SetSize(MAX_ORBS * SPACING, ORB_SIZE)
holder:SetPoint("CENTER", hud, "CENTER", 0, Y)
holder:SetFrameLevel(hud:GetFrameLevel() + 2)
holder:Hide()
ns.OnStealthChanged(function(stealthed)
    holder:SetAlpha(stealthed and 0.3 or 1) -- dimmed in stealth mode (Stealth.lua); the rows set their own alpha
end)

-- rows[n]: n orbs, centred.
local rows = {}
for n = 1, MAX_ORBS do
    local row = CreateFrame("Frame", nil, holder)
    row:SetAllPoints()
    row:SetAlpha(0)
    for i = 1, n do
        local x = (i - (n + 1) / 2) * SPACING
        local orb = row:CreateTexture(nil, "ARTWORK")
        orb:SetTexture(ns.MEDIA .. "sp_orb")
        orb:SetSize(ORB_SIZE, ORB_SIZE)
        orb:SetPoint("CENTER", row, "CENTER", x, 0)
        local border = row:CreateTexture(nil, "OVERLAY") -- same black rim as the combo points
        border:SetTexture(ns.MEDIA .. "ring_small")
        border:SetVertexColor(0, 0, 0)
        border:SetSize(ORB_SIZE, ORB_SIZE)
        border:SetPoint("CENTER", orb)
    end
    rows[n] = row
end

local cost, maxMana -- mana per cast and max mana, as last read out of combat; cost nil = unknown
local curves = {} -- curves[n]: 1 while mana is between n and n+1 casts' worth, as a fraction of max
local affordCurve -- 1 from one cast's worth of mana up: gates ShiftingPower.lua's ready pulse
local inCombat = false -- from PLAYER_REGEN_DISABLED / _ENABLED

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

-- Out of combat: reads the cost and max mana and rebuilds the curves. In combat they keep the
-- values from the last time.
local function Rebuild()
    local spellID = ns.ShiftingPowerSpell and ns.ShiftingPowerSpell()
    if not spellID then
        cost = nil
        return
    end
    if InCombatLockdown() then
        return
    end
    local newCost, max = ReadCost(spellID), PlainNumber(UnitPowerMax("player", MANA))
    if not newCost or newCost <= 0 or not max or max <= 0 then
        ns.Debug("SP mana counter: cost", newCost, "max mana", max, "- hidden")
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
    ns.Debug("SP mana counter: cost", cost, "of", max, "mana")
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
    local show = CAN_COUNT and (inCombat or not COMBAT_ONLY) and cost ~= nil and UnitPowerType("player") == Enum.PowerType.Energy
        and not ns.IsCasting() -- Cast.lua's text sits where the orbs are
    holder:SetShown(show and true or false)
    if not show then
        return
    end
    for n, row in ipairs(rows) do
        row:SetAlpha(UnitPowerPercent("player", MANA, false, curves[n]))
    end
end

local function RebuildAndUpdate()
    Rebuild()
    Update()
end

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
ns.OnCastChanged(Update)
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
    ns.Debug("SP mana counter: curves available:", CAN_COUNT)
end)
