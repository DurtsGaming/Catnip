-- Omen of Clarity's internal cooldown: it can't proc again for 10s after a proc, so a segmented
-- ring (like CooldownRings.lua's) starts full when Clearcasting procs and empties over those 10s.
-- In whichever combo ring slot the player picks for it (ComboRings.lua; dot 2 by default).
--
-- Clearcasting can't be read in combat, but its effect can: while it's up, an ability it makes
-- free reports a cost of 0 (C_Spell.GetSpellPowerCost, readable in combat; verified 2026-10-09 with
-- Shred: 60 to 0 on the proc's UNIT_AURA, back to 60 when used). So the clock starts when that
-- cost turns 0. A proc while Clearcasting is already up (a refresh) leaves the cost at 0 and isn't
-- seen.
local addonName, ns = ...
local CreateFrame = ns.Profiled("OmenRing") -- timed by /catnip perf (Profiler.lua)

local ICD = 10 -- seconds
local SEGMENTS = 5 -- 2s each; ring_omen_angular has them drawn in (make_textures.py)
local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- as CooldownRings.lua
-- Abilities Clearcasting makes free, first known wins. Shred is verified; the others are guesses
-- for characters without it (Wrath: every druid has it, if its mana cost reads 0 the same way).
local WATCHED = { "Shred", "Claw", "Wrath" }

local function Arc()
    local arc = ns.CreateSegmentedArc({
        parent = UIParent,
        size = RING_SIZE,
        art = "ring_omen",
        from = math.pi / 2, -- 12 o'clock
        span = 2 * math.pi,
        clockwise = true,
        segments = SEGMENTS, -- cut by ns.ShapeComboRingArc (Circular by default, or Angular)
        drain = true,
        noFlash = true,
    })
    ns.PlaceComboRing(arc.frame, nil)
    return arc
end

local arc = Arc()
local startedAt, length

-- The clock runs on its own frame, so it keeps time while the ring's slot is hidden.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    local progress = (GetTime() - startedAt) / length
    if progress >= 1 then
        driver:Hide()
        arc.Finish()
    else
        arc.SetProgress(progress)
    end
end)

local function Start(seconds)
    startedAt, length = GetTime(), seconds
    arc.Start(0)
    driver:Show()
end

-- Is Clearcasting up, judged by the watched ability's cost? nil if it can't be told.
local watched
local function Free()
    if not watched then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, watched)
    if not ok or ns.IsSecret(costs) or type(costs) ~= "table" or not costs[1] then
        return nil
    end
    local cost = costs[1].cost
    if ns.IsSecret(cost) then
        return nil
    end
    return cost == 0
end

local wasFree = false
local function Check(canStart)
    local free = Free()
    if free == nil then
        return
    end
    if free and not wasFree and canStart then
        ns.Debug("Omen of Clarity: proc, ICD", ICD, "s")
        Start(ICD)
    end
    wasFree = free
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" then
        Check(true)
    else
        watched = ns.FindKnownSpell(WATCHED)
        Check(false) -- already up at login: when it procced is unknown
    end
end)

ns.OnLoad(function()
    ns.db.probeLog = nil -- left by the temporary probe that found the cost trick (2026-10-09)
end)

ns.commands.omen = function(arg) -- /catnip omen [seconds]: a preview run
    Start(tonumber(arg) or ICD)
    ns.Print("Omen of Clarity ICD preview:", length, "s")
end

-- Preview mode's looping copy (ns.ArcSampler).
local sampleArc = Arc()
local StartSample, StopSample = ns.ArcSampler(sampleArc, ICD)

ns.AddComboRingSpell({
    key = "omen",
    label = "Omen of Clarity Internal Cooldown",
    color = { 0.4, 0.8, 0.6 }, -- its glyph in the settings list
    order = 3, -- after the spell cooldowns, before the DoTs
    defaultSlot = 2,
    shape = "circular", -- by default
    Place = function(slot)
        ns.ShapeComboRingArc(arc, "omen", "ring_omen")
        ns.PlaceComboRing(arc.frame, slot and slot.gate, slot and slot.index)
    end,
    StartSample = function(slot)
        ns.ShapeComboRingArc(sampleArc, "omen", "ring_omen")
        ns.PlaceComboRing(sampleArc.frame, slot.sampleGate, slot.index)
        StartSample()
    end,
    StopSample = StopSample,
})
