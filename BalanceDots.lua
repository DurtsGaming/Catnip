-- Balance DoT dots (in-game test, 2026-10-19, with the Eclipse moon; /catnip moon): Moonfire left of
-- the moon, Insect Swarm right. Each is a small disc in the spell's colours with a segmented ring,
-- one segment per damage tick (Moonfire 3s, Insect Swarm 2s), that drains clockwise from 12 o'clock
-- like DotRings.lua's: a Cooldown swipe Blizzard runs with the DoT's real (secret) timing.
-- Nature's Splendor lengthens them (Moonfire 12 -> 15s, Insect Swarm 12 -> 14s), which changes the
-- tick count, and the talent can't be detected. So each DoT has two AuraContainers in one spot: the
-- talented ring (5 / 7 segments), shown whenever the DoT is up, and over it the base ring (4 / 6)
-- with maxDuration BASE_MAX, which Blizzard shows only for a DoT of base length. Each button has an
-- opaque dark track under its ring, so the base one hides the talented one beneath it.
-- While a DoT is down, a dimmed disc shows instead (on the Balance group, outside the buttons).
-- Created by EclipseMoon.lua, in its group: shown with the moon, out of Cat and Bear Form.
local addonName, ns = ...
local CreateFrame = ns.Profiled("BalanceDots") -- timed by /catnip perf (Profiler.lua)

local RING = 36 -- ring_* textures: a 4.5-unit band, its inner edge ~13 out
local DISC = 22 -- with its 1-unit rim, ~2 inside the ring's inner edge
local X, Y = 47, 82 -- each dot's centre from the HUD's centre, down and out from the moon (EclipseMoon.lua)
local BASE_MAX = 13 -- seconds: both base lengths are 12, both talented ones longer
local TRACK = { 0.04, 0.06, 0.13, 1 } -- the empty track: the moon's dark blue
local DIM = 0.3 -- the disc while the DoT is down
local LEVELS = { talented = 10, base = 14 } -- above the HUD; 4 apart so the base track covers the talented ring

local DOTS = {
    { label = "Moonfire", x = -X, disc = "disc_moonfire", talented = "ring_moonfire5", base = "ring_moonfire4",
        spellIDs = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 } },
    { label = "Insect Swarm", x = X, disc = "disc_swarm", talented = "ring_swarm7", base = "ring_swarm6",
        spellIDs = { 5570, 24974, 24975, 24976, 24977 } },
}

-- The disc with a thin black rim, centred on `parent`.
local function AddDisc(parent, dot, alpha)
    local rim = parent:CreateTexture(nil, "ARTWORK", nil, 0)
    rim:SetTexture(ns.MEDIA .. "circle_hard")
    rim:SetVertexColor(0, 0, 0, 1)
    rim:SetSize(DISC + 2, DISC + 2)
    rim:SetPoint("CENTER")
    local disc = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    disc:SetTexture(ns.MEDIA .. dot.disc) -- coloured, so untinted
    disc:SetSize(DISC, DISC)
    disc:SetPoint("CENTER")
    disc:SetAlpha(alpha)
end

local function StyleButton(button, dot, texture)
    ns.HideAuraButtonArt(button)
    local track = button:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(ns.MEDIA .. "ring_rip") -- the same band as the coloured rings
    track:SetVertexColor(unpack(TRACK))
    track:SetAllPoints()
    AddDisc(button, dot, 1)

    local ring = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    ring:ClearAllPoints() -- the template pins it to its parent; set it ourselves
    ring:SetAllPoints(button)
    ring:SetSwipeTexture(ns.MEDIA .. texture) -- coloured, so untinted
    ring:SetSwipeColor(1, 1, 1, 1)
    ring:SetDrawEdge(false)
    ring:SetDrawBling(false)
    ring:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(ring) -- Blizzard runs it with the aura's real (secret) timing
end

function ns.CreateBalanceDots(group)
    for _, dot in ipairs(DOTS) do
        local holder = CreateFrame("Frame", nil, group)
        holder:SetSize(RING, RING)
        holder:SetPoint("CENTER", ns.hud, "CENTER", dot.x, Y)
        AddDisc(holder, dot, DIM)
        if ns.HAS_AURA_CONTAINER then
            for kind, level in pairs(LEVELS) do
                ns.CreateAuraContainer({
                    label = dot.label .. " " .. kind,
                    unit = "target",
                    filter = "HARMFUL",
                    spellIDs = dot.spellIDs,
                    maxDuration = kind == "base" and BASE_MAX or nil,
                    width = RING,
                    height = RING,
                    x = dot.x,
                    y = Y,
                    level = level,
                    parent = group,
                    initialize = function(button)
                        StyleButton(button, dot, dot[kind])
                    end,
                })
            end
        end
    end
end
