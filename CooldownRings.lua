-- Short cooldowns as segmented rings around the combo points: Faerie Fire (dot 1) and Primal Bite
-- (dot 3); dot 2 is free (Growl moved to GrowlArc.lua). Each ring starts full when we cast the spell and empties clockwise from
-- 12 o'clock over its cooldown, leaving nothing behind. As each segment empties the next one
-- pulses, except the last one left; when ready it's simply gone (no flash). Hidden with the combo
-- dots outside Cat and Bear Form. Each is a SegmentedArc.lua ring timed by SegmentedCooldown.lua,
-- coloured from its spell's icon (make_textures.py); change `segments` freely.
local addonName, ns = ...

local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- same as DotRings.lua; the ring textures have ring_rip's band
local BAND_RADIUS = RING_SIZE * 55 / 128 -- the band's centre line (63 out, 16 thick, in 128)
local GAP = 2 / BAND_RADIUS -- 2 units between segments, in radians

local function InFeralForm()
    local powerType = UnitPowerType("player")
    return powerType == Enum.PowerType.Energy or powerType == Enum.PowerType.Rage
end

local RINGS = {
    {
        label = "Faerie Fire",
        dot = 1,
        art = "ring_faerie",
        segments = 6, -- 6s
        -- In Cat and Bear Form the spell becomes Faerie Fire (Feral) (unverified whether the
        -- spellbook finds it by that name, so the caster one stands in for "known").
        names = { "Faerie Fire (Feral)", "Faerie Fire" },
        castNames = { ["Faerie Fire (Feral)"] = true, ["Faerie Fire"] = true },
        castAllowed = InFeralForm, -- the caster version has no cooldown
        defaultLength = 6,
        lengthKey = "ffLength",
        command = "ff",
    },
    {
        label = "Primal Bite",
        dot = 3,
        art = "ring_primal_bite",
        segments = 6,
        names = { "Primal Bite" },
        castNames = { ["Primal Bite"] = true },
        defaultLength = 6, -- a guess; learned from the first cast
        lengthKey = "pbLength",
        command = "pb",
    },
}

for _, ring in ipairs(RINGS) do
    local x, y = ns.ComboDotOffset(ring.dot)
    ns.CreateSegmentedCooldown({
        label = ring.label,
        names = ring.names,
        castNames = ring.castNames,
        castAllowed = ring.castAllowed,
        defaultLength = ring.defaultLength,
        lengthKey = ring.lengthKey,
        command = ring.command, -- /catnip <command> [seconds], in Cat or Bear Form
        learnFromReady = true, -- nothing resets these early, so the ready flag gives the length in combat too
        arc = ns.CreateSegmentedArc({
            parent = ns.comboGroup, -- hides with the combo dots outside Cat and Bear Form
            size = RING_SIZE,
            x = x,
            y = y,
            level = 5, -- with the DoT rings, over the dots
            art = ring.art,
            from = math.pi / 2, -- 12 o'clock
            span = 2 * math.pi,
            clockwise = true,
            segments = ring.segments,
            gap = GAP,
            drain = true,
            noFlash = true,
        }),
    })
end
