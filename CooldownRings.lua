-- Short cooldowns as segmented rings around the combo points: Faerie Fire and Primal Bite, each in
-- whichever combo ring slot the player picks for it (ComboRings.lua; by default dots 1 and 3). Each
-- ring starts full when the cooldown starts and empties clockwise from 12 o'clock over it, leaving
-- nothing behind; when ready it's simply gone (no flash). (Segments pulsed as they emptied until
-- 2026-10-10.) Hidden with the combo dots outside Cat and Bear Form.
-- Each is a SegmentedArc.lua ring (a radial StatusBar) timed by SegmentedCooldown.lua (the game's
-- own cooldown), coloured from its spell's icon (make_textures.py). Its segments are Circular by
-- default or Angular, the player's pick (ComboRings.lua), both drawn into the art
-- (`art`_circular, `art`_angular), so a different segment count means regenerating those. The
-- timing runs whether or not the ring is in a slot.
local addonName, ns = ...

local RING_SIZE = ns.COMBO_DOT_SIZE + 8 -- same as DotRings.lua; the ring textures have ring_rip's band

local function InFeralForm()
    local powerType = UnitPowerType("player")
    return powerType == Enum.PowerType.Energy or powerType == Enum.PowerType.Rage
end

local RINGS = {
    {
        key = "ff", -- saved in the combo ring settings
        label = "Faerie Fire",
        order = 1, -- in the settings dropdown
        dot = 1, -- its slot by default
        art = "ring_faerie",
        color = { 0.69, 0.31, 0.82 }, -- its glyph in the settings list
        -- In Cat and Bear Form the spell becomes Faerie Fire (Feral) (unverified whether the
        -- spellbook finds it by that name, so the caster one stands in for "known").
        names = { "Faerie Fire (Feral)", "Faerie Fire" },
        castNames = { ["Faerie Fire (Feral)"] = true, ["Faerie Fire"] = true },
        castAllowed = InFeralForm, -- the caster version has no cooldown
        defaultLength = 6,
        command = "ff",
    },
    {
        key = "pb",
        label = "Primal Bite",
        order = 2,
        dot = 3,
        art = "ring_primal_bite",
        color = { 0.91, 0.86, 0.75 },
        names = { "Primal Bite" },
        castNames = { ["Primal Bite"] = true },
        defaultLength = 6, -- for the preview and the sample
        command = "pb",
    },
}

for _, ring in ipairs(RINGS) do
    -- Made out of sight; ns.PlaceComboRing moves each into its slot.
    local function Arc()
        local arc = ns.CreateSegmentedArc({
            parent = UIParent,
            size = RING_SIZE,
            art = ring.art .. "_circular", -- ns.ShapeComboRingArc sets the shape picked
            from = math.pi / 2, -- 12 o'clock
            span = 2 * math.pi,
            clockwise = true,
            drain = true,
            noFlash = true,
        })
        ns.PlaceComboRing(arc.frame, nil)
        return arc
    end

    local arc = Arc()
    ns.CreateSegmentedCooldown({
        label = ring.label,
        names = ring.names,
        castNames = ring.castNames,
        castAllowed = ring.castAllowed,
        defaultLength = ring.defaultLength,
        command = ring.command, -- /catnip <command> [seconds], in Cat or Bear Form (shows only while in a slot)
        arc = arc,
    })

    -- Preview mode's looping copy (ns.ArcSampler).
    local sampleArc = Arc()
    local StartSample, StopSample = ns.ArcSampler(sampleArc, ring.defaultLength)

    ns.AddComboRingSpell({
        key = ring.key,
        label = ring.label .. " Cooldown",
        color = ring.color,
        order = ring.order,
        defaultSlot = ring.dot,
        shape = "circular", -- by default
        Place = function(slot)
            ns.ShapeComboRingArc(arc, ring.key, ring.art)
            ns.PlaceComboRing(arc.frame, slot and slot.gate, slot and slot.index)
        end,
        StartSample = function(slot)
            ns.ShapeComboRingArc(sampleArc, ring.key, ring.art)
            ns.PlaceComboRing(sampleArc.frame, slot.sampleGate, slot.index)
            StartSample()
        end,
        StopSample = StopSample,
    })
end
