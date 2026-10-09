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
        id = "combo.ff", -- the settings element (Elements.lua)
        label = "Faerie Fire",
        dot = 1,
        art = "ring_faerie",
        color = { 0.69, 0.31, 0.82 }, -- its icon in the settings list
        segments = 6, -- 6s
        -- In Cat and Bear Form the spell becomes Faerie Fire (Feral) (unverified whether the
        -- spellbook finds it by that name, so the caster one stands in for "known").
        names = { "Faerie Fire (Feral)", "Faerie Fire" },
        castNames = { ["Faerie Fire (Feral)"] = true, ["Faerie Fire"] = true },
        castAllowed = InFeralForm, -- the caster version has no cooldown
        defaultLength = 6,
        command = "ff",
    },
    {
        id = "combo.pb",
        label = "Primal Bite",
        dot = 3,
        art = "ring_primal_bite",
        color = { 0.91, 0.86, 0.75 },
        segments = 6,
        names = { "Primal Bite" },
        castNames = { ["Primal Bite"] = true },
        defaultLength = 6, -- a guess; learned from the first cast
        command = "pb",
    },
}

for _, ring in ipairs(RINGS) do
    local x, y = ns.ComboDotOffset(ring.dot)
    local function ArcOptions(parent)
        return {
            parent = parent,
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
        }
    end

    -- Gates (ns.ComboRingGate, at the group's level) carry the Opacity setting: the real arc's in
    -- comboLive (hides with the combo dots outside Cat and Bear Form), preview mode's looping copy
    -- (ns.ArcSampler) in comboSample.
    local gate = ns.ComboRingGate(ns.comboLive)
    local sampleGate = ns.ComboRingGate(ns.comboSample)

    ns.CreateSegmentedCooldown({
        label = ring.label,
        names = ring.names,
        castNames = ring.castNames,
        castAllowed = ring.castAllowed,
        defaultLength = ring.defaultLength,
        command = ring.command, -- /catnip <command> [seconds], in Cat or Bear Form
        arc = ns.CreateSegmentedArc(ArcOptions(gate)),
    })

    local sampleArc = ns.CreateSegmentedArc(ArcOptions(sampleGate))
    local StartSample, StopSample = ns.ArcSampler(sampleArc, ring.defaultLength)
    ns.RegisterElement({
        id = ring.id,
        zone = "combo",
        name = ring.label .. " ring",
        desc = "Around combo point " .. ring.dot,
        glyph = { kind = "ring", color = ring.color },
        order = ring.dot,
        hit = ns.ComboRingHit(ring.dot, function() return sampleArc.frame:IsVisible() end),
        states = { "cat", "bear" },
        options = {
            { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
        },
        apply = function(get)
            gate:SetAlpha(get("opacity") / 100)
            sampleGate:SetAlpha(get("opacity") / 100)
        end,
        sample = function(state)
            if state == "cat" or state == "bear" then
                StartSample()
            else
                StopSample()
            end
        end,
    })
end
