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
-- mana blue instead, split diagonally: blue top left, yellow (or periwinkle while stealthed) bottom
-- right, fading into white where they meet; shaded like the other orbs.
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
--
-- Almost there: with fewer than five orbs, while mana is regenerating (outside the five-second rule)
-- and the next orb is at least NEAR of the way paid for, a ghost orb shows on the right of the row,
-- where the next one will appear: fully grey (owner, 2026-10-09; was only for the first orb, grey
-- with a coloured bottom half). Each count has an "almost" row (its orbs and the ghost, laid out
-- as one more) whose curve is 1 from NEAR up to the next shift's worth; while ghosts can show, the
-- plain rows' curves stop at NEAR, so the two never overlap. Inside the rule, or with the setting
-- off, the plain rows' full curves are used and no ghost shows (plain Lua, so this works in combat).
--
-- Mana prediction (ManaPrediction.lua, via ns.onManaPrediction): while a cast would cost orbs,
-- those orbs take the resource circle's dark spend colour. If the cast is cancelled the dim fades
-- out over the circle's 0.5s refill (a bottom-up refill, with or without the glow, was too much at
-- this size, owner's call). Which orbs: orb i (counting from the left) is lost if mana - cost < i shifts'
-- worth, i.e. mana < i * shift + cost. Each orb's overlay frame takes its alpha from a step curve
-- that's 1 below that, so again the secret mana stays engine-side. The curves depend on the cast's
-- cost, so they're made when a cast starts (kept per cost); if that fails in combat, no prediction.
local addonName, ns = ...
local CreateFrame = ns.Profiled("ShiftOrbs") -- timed by /catnip perf (Profiler.lua)

local COMBAT_ONLY = false -- off for now: the orbs show in and out of combat
local MAX_ORBS = 5
local ORB_SIZE = 0.6 * ns.COMBO_DOT_SIZE -- 60% of a combo point
local SPACING = ORB_SIZE * 1.25 -- centre to centre, along the chord
local RADIUS = 89 -- inner edge ~77.6, ~3.4 outside the Shifting Power arc (make_textures.py SP_RADIUS)
local STEP = 2 * math.asin(SPACING / 2 / RADIUS) -- angle between neighbouring orbs (~18.4 degrees)
local STEALTH_ALPHA = 0.6 -- 30% was too much
local NEAR = 0.8 -- a ghost orb shows once the next orb is this far paid for (owner's eyeball)
local GHOST_GREY = 0.55 -- the ghost's desaturated art is darkened to this
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

-- rows[n]: n orbs, centred on 6 o'clock. almostRows[n] (n = 0 to 4): n orbs and the ghost of the
-- next on their right, laid out as n + 1. orbs and ghosts: every orb texture, for swapping the art.
-- predictions: every full orb's mana prediction overlay ({ frame, index, dim }), in every row.
local rows, almostRows, orbs, ghosts, predictions = {}, {}, {}, {}, {}
local currentArt = MANA_ART

local function CreateBorder(parent, orb) -- same black rim as the combo points
    local border = parent:CreateTexture(nil, "OVERLAY")
    border:SetTexture(ns.MEDIA .. "ring_small")
    border:SetVertexColor(0, 0, 0)
    border:SetSize(ORB_SIZE, ORB_SIZE)
    border:SetPoint("CENTER", orb)
end

-- Over orb `index` of a row: mana's orb tinted like ManaPrediction's dark band. The frame's alpha
-- says whether the orb is lost (secret); the dim's own alpha fades it on a refund. A child frame
-- draws over the row's rim, so it has its own.
local function CreatePrediction(row, orb, index)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetSize(ORB_SIZE, ORB_SIZE)
    frame:SetPoint("CENTER", orb)
    frame:SetAlpha(0)
    local dim = frame:CreateTexture(nil, "ARTWORK")
    dim:SetTexture(ns.MEDIA .. MANA_ART)
    dim:SetVertexColor(unpack(ns.MANA_SPEND_COLOR))
    dim:SetAllPoints()
    CreateBorder(frame, orb)
    predictions[#predictions + 1] = { frame = frame, index = index, dim = dim }
end

local function CreateOrb(row, x, y, index)
    local orb = row:CreateTexture(nil, "ARTWORK")
    orb:SetTexture(ns.MEDIA .. currentArt)
    orb:SetSize(ORB_SIZE, ORB_SIZE)
    orb:SetPoint("CENTER", row, "CENTER", x, y)
    CreateBorder(row, orb)
    if index then
        CreatePrediction(row, orb, index)
    end
    return orb
end

local function CreateRow()
    local row = CreateFrame("Frame", nil, holder)
    row:SetAllPoints()
    row:SetAlpha(0)
    return row
end

-- Orb i of a row of n, from the HUD's centre.
local function OrbOffset(i, n)
    local angle = -math.pi / 2 + (i - (n + 1) / 2) * STEP
    return RADIUS * math.cos(angle), RADIUS * math.sin(angle)
end

for n = 1, MAX_ORBS do
    local row = CreateRow()
    for i = 1, n do
        local x, y = OrbOffset(i, n)
        orbs[#orbs + 1] = CreateOrb(row, x, y, i)
    end
    rows[n] = row
end

for n = 0, MAX_ORBS - 1 do
    local row = CreateRow()
    for i = 1, n do
        local x, y = OrbOffset(i, n + 1)
        orbs[#orbs + 1] = CreateOrb(row, x, y, i)
    end
    local x, y = OrbOffset(n + 1, n + 1) -- the rightmost spot
    local ghost = CreateOrb(row, x, y) -- grey: desaturated and darkened
    ghost:SetDesaturated(true)
    ghost:SetVertexColor(GHOST_GREY, GHOST_GREY, GHOST_GREY)
    ghosts[#ghosts + 1] = ghost
    almostRows[n] = row
end

local cost, maxMana -- mana per shift and max mana, as last read out of combat; cost nil = unknown
-- Curves, as fractions of max mana: fullCurves[n] 1 from n to n+1 shifts' worth (no top for five),
-- shortCurves[n] the same but stopping at n + NEAR (so the almost row can take over), and
-- almostCurves[n] 1 from n + NEAR to n + 1.
local fullCurves, shortCurves, almostCurves = {}, {}, {}
local affordCurve -- 1 from one shift's worth of mana up: gates ShiftingPower.lua's ready pulse
local hasShiftingPower = false
local inCombat = false -- from PLAYER_REGEN_DISABLED / _ENABLED
local lostCurves = {} -- lostCurves[castCost][i]: 1 while orb i would be lost to that cast; reset in Rebuild
local predictCost -- the cast's mana cost while ManaPrediction.lua shows a band, else nil

-- Settings (the element below) and preview mode's sample state (Preview.lua), nil when live.
local opacity, showGhost = 1, true
local sampleState
local SAMPLE_POWER = { cat = Enum.PowerType.Energy,
    bear = Enum.PowerType.Rage, caster = MANA }
-- The sample: five orbs in every form, the rightmost grey (four and the fifth almost ready) while
-- the Almost-ready orb setting is on (owner, 2026-10-09).

-- The art for the current form and stealth state; nil (keep the current art) if the form is secret.
local function OrbArt()
    local powerType = sampleState and SAMPLE_POWER[sampleState] or UnitPowerType("player")
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
    for _, ghost in ipairs(ghosts) do
        ghost:SetTexture(ns.MEDIA .. art)
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
    lostCurves = {}
    local fraction = cost / max
    -- 1 from `from` shifts' worth of mana up to `to` (nil: no upper end).
    local function Band(from, to)
        local curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 0)
        curve:AddPoint(from * fraction, 1)
        if to then
            curve:AddPoint(to * fraction, 0)
        end
        return curve
    end
    for n = 1, MAX_ORBS do
        fullCurves[n] = Band(n, n < MAX_ORBS and n + 1 or nil)
        shortCurves[n] = n < MAX_ORBS and Band(n, n + NEAR) or fullCurves[n]
    end
    for n = 0, MAX_ORBS - 1 do
        almostCurves[n] = Band(n + NEAR, n + 1)
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

-- lostCurves for a cast costing castCost, made on first use; nil if they can't be made
local function LostCurves(castCost)
    if not lostCurves[castCost] then
        local ok, list = pcall(function()
            local list = {}
            for i = 1, MAX_ORBS do
                local curve = C_CurveUtil.CreateCurve()
                curve:SetType(Enum.LuaCurveType.Step)
                curve:AddPoint(0, 1)
                curve:AddPoint((i * cost + castCost) / maxMana, 0)
                list[i] = curve
            end
            return list
        end)
        if not ok then
            ns.Debug("shift orbs: can't make prediction curves:", list)
            return nil
        end
        lostCurves[castCost] = list
    end
    return lostCurves[castCost]
end

local function UpdatePrediction()
    if sampleState then
        return -- the sample has no prediction (ShowSample clears it)
    end
    local curves = predictCost and cost ~= nil and LostCurves(predictCost) or nil
    for _, p in ipairs(predictions) do
        if curves then
            p.frame:SetAlpha(UnitPowerPercent("player", MANA, false, curves[p.index]))
        else
            p.frame:SetAlpha(0)
        end
    end
end

-- Preview mode: a fixed count per form, shown whatever the mana; no prediction; the ready pulse
-- free to show (ShiftingPower.lua's sample plays it).
local function ShowSample()
    if ns.shiftingPowerPulseGate then
        ns.shiftingPowerPulseGate:SetAlpha(1)
    end
    holder:Show()
    UpdateArt()
    for n, row in ipairs(rows) do
        row:SetAlpha((not showGhost and n == MAX_ORBS) and 1 or 0)
    end
    for n = 0, MAX_ORBS - 1 do
        almostRows[n]:SetAlpha((showGhost and n == MAX_ORBS - 1) and 1 or 0)
    end
    for _, p in ipairs(predictions) do
        p.frame:SetAlpha(0)
    end
end

local function Update()
    if sampleState then
        ShowSample()
        return
    end
    UpdatePulseGate()
    local show = CAN_COUNT and (inCombat or not COMBAT_ONLY) and cost ~= nil
    holder:SetShown(show and true or false)
    if not show then
        return
    end
    UpdateArt()
    -- Ghosts only while regenerating, and if turned on; then the plain rows stop at NEAR and the
    -- almost rows take over. (Curve results may be secret, so no `and`/`or` on them: that would
    -- test them.)
    local almost = showGhost and not ns.InFiveSecondRule()
    local plainCurves = almost and shortCurves or fullCurves
    for n, row in ipairs(rows) do
        row:SetAlpha(UnitPowerPercent("player", MANA, false, plainCurves[n]))
    end
    for n = 0, MAX_ORBS - 1 do
        if almost then
            almostRows[n]:SetAlpha(UnitPowerPercent("player", MANA, false, almostCurves[n]))
        else
            almostRows[n]:SetAlpha(0)
        end
    end
    UpdatePrediction()
end

local function RebuildAndUpdate()
    Rebuild()
    Update()
end

-- From ManaPrediction.lua: the cast's mana cost while a band shows (nil otherwise) and the dim's
-- strength: 1 while casting, falling to 0 over a refund (called every frame then)
function ns.onManaPrediction(castCost, strength)
    if castCost ~= predictCost then
        predictCost = castCost
        UpdatePrediction()
    end
    if predictCost then
        for _, p in ipairs(predictions) do
            p.dim:SetAlpha(strength)
        end
    end
end

-- The holder's alpha: stealth mode's dimming times the Opacity setting (the rows set their own).
local function ApplyHolderAlpha()
    holder:SetAlpha((ns.IsStealthMode() and STEALTH_ALPHA or 1) * opacity)
end

ns.OnStealthChanged(function()
    ApplyHolderAlpha()
    Update()
end)

-- Settings (Elements.lua). The hit is the orbs themselves, picked as one: all five spots (the
-- sample's five, and the real count is secret in combat).
local function OrbCentres()
    local count = MAX_ORBS
    local centres = {}
    for i = 1, count do
        centres[i] = { OrbOffset(i, count) }
    end
    return centres
end

ns.RegisterElement({
    id = "under.orbs",
    zone = "under",
    name = "Shift orbs",
    glyph = { kind = "dots", color = { 0.31, 0.56, 0.91 } },
    hit = { kind = "circles", radius = ORB_SIZE / 2, centres = OrbCentres, -- outlines just meet
        visible = function() return holder:IsVisible() end },
    options = {
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
        -- Previewed in every form: the fifth orb grey.
        { key = "ghost", type = "checkbox", label = "Almost-ready orb", default = false },
    },
    apply = function(get)
        opacity = get("opacity") / 100
        showGhost = get("ghost")
        ApplyHolderAlpha()
        if UnitExists("player") then
            Update()
        end
    end,
    sample = function(state)
        sampleState = state
        Update()
    end,
})

ns.OnFiveSecondRuleChanged(Update)

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
