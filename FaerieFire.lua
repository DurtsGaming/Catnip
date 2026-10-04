-- Faerie Fire cooldown: a segmented ring around combo point 1, in the spell icon's violet to pink,
-- that starts full and empties clockwise from 12 o'clock over Faerie Fire (Feral)'s cooldown (6s in
-- Cat and Bear Form; the caster version has none), leaving nothing behind. As each segment empties
-- the next one pulses, except the last one left; when ready it's simply gone (no flash).
-- Hidden with the combo dots outside Cat and Bear Form.
-- A SegmentedArc.lua ring timed by SegmentedCooldown.lua; change SEGMENTS freely.
local addonName, ns = ...

local SEGMENTS = 6
local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- same as DotRings.lua; ring_faerie has ring_rip's band
local BAND_RADIUS = RING_SIZE * 55 / 128 -- the band's centre line (63 out, 16 thick, in 128)
local GAP = 2 / BAND_RADIUS -- 2 units between segments, in radians

local function InFeralForm()
    local powerType = UnitPowerType("player")
    return powerType == Enum.PowerType.Energy or powerType == Enum.PowerType.Rage
end

local x, y = ns.ComboDotOffset(1)
local arc = ns.CreateSegmentedArc({
    parent = ns.comboGroup,
    size = RING_SIZE,
    x = x,
    y = y,
    level = 5, -- with the DoT rings, over the dots
    art = "ring_faerie",
    from = math.pi / 2, -- 12 o'clock
    span = 2 * math.pi,
    clockwise = true,
    segments = SEGMENTS,
    gap = GAP,
    drain = true,
    noFlash = true,
})

ns.CreateSegmentedCooldown({
    label = "Faerie Fire",
    -- In Cat and Bear Form the spell becomes Faerie Fire (Feral) (unverified whether the spellbook
    -- finds it by that name, so the caster one stands in for "known").
    names = { "Faerie Fire (Feral)", "Faerie Fire" },
    castNames = { ["Faerie Fire (Feral)"] = true, ["Faerie Fire"] = true },
    castAllowed = InFeralForm, -- the caster version has no cooldown
    defaultLength = 6,
    lengthKey = "ffLength",
    arc = arc,
    command = "ff", -- /catnip ff [seconds], in Cat or Bear Form
})
