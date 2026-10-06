-- Stealth mode's shadow smoke: while stealthed (Stealth.lua) we don't swing, so the swing timer's
-- black glow stays and a periwinkle smoke ring fills it. A still dark base under
-- two rings of irregular clouds (uneven length, thickness and density, soft gaps) that turn at
-- different speeds and opposite ways, so their overlaps keep shifting (the "Cloudy" mockup,
-- 2026-10-04). Colours from the stealthed energy fill. All three are white textures from make_textures.py
-- (smoke_base, and cloud_ring for smoke_a and smoke_b), tinted here.
-- Entering stealth the smoke billows out of the glow: it swells outward from just inside the band
-- and fades in while the clouds whirl fast and slow to their drift. Leaving stealth is instant.
local addonName, ns = ...

local SMOKE_SIZE = 160 -- the textures' canvas in HUD units (SMOKE_UNITS in make_textures.py)
local INTRO = 1.2 -- seconds the billow takes
local START_SCALE = 0.75 -- the smoke starts this size (band ~46 units out instead of 61) and swells to full
local BURST = 15 -- the clouds start turning this many times faster, easing back to their drift

-- texture, colour, alpha, seconds per turn (0 = still), clockwise
local LAYERS = {
    -- PROWL_PERIWINKLE's dark end (make_textures.py, the stealthed energy fill), kept close together so
    -- the layers read flat rather than glowing. Was violet #1a0d2e / #5b3496 / #6f4cb0 (Prowl icon).
    { "smoke_base", { 0x1c, 0x1a, 0x40 }, 0.4, 0 }, -- light, so the glow's black shows between the clouds
    { "smoke_a", { 0x3b, 0x35, 0x92 }, 0.85, 46, true },
    { "smoke_b", { 0x50, 0x4a, 0xad }, 0.3, 31, false },
}

local hud = ns.hud
local layers = {} -- { texture, speed (radians per second, positive counter-clockwise), angle }

for i, layer in ipairs(LAYERS) do
    local file, colour, alpha, period, clockwise = unpack(layer)
    -- Over the swing glow (sublevel -6) and under the resource backdrop (0), in order: base at the bottom.
    local texture = hud:CreateTexture(nil, "BACKGROUND", nil, i - 6)
    texture:SetTexture(ns.MEDIA .. file)
    texture:SetSize(SMOKE_SIZE, SMOKE_SIZE)
    texture:SetPoint("CENTER")
    if texture.SetSnapToPixelGrid then -- no snapping to whole pixels, so the turning clouds don't shimmer
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
    texture:SetVertexColor(colour[1] / 255, colour[2] / 255, colour[3] / 255, alpha)
    texture:Hide()
    local speed = period > 0 and 2 * math.pi / period or 0
    layers[#layers + 1] = { texture = texture, speed = clockwise and -speed or speed, angle = 0 }
end

-- Turns the clouds with SetRotation each frame (rather than a looping Rotation animation) so the
-- intro can vary their speed; runs while stealthed.
local startTime = 0
local driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function(_, elapsed)
    local t = math.min(1, (GetTime() - startTime) / INTRO)
    local ease = 1 - (1 - t) ^ 2 -- ease out
    local size = SMOKE_SIZE * (START_SCALE + (1 - START_SCALE) * ease)
    local boost = 1 + (BURST - 1) * (1 - t) ^ 2
    for _, layer in ipairs(layers) do
        local texture = layer.texture
        if t < 1 then
            texture:SetSize(size, size)
            texture:SetAlpha(ease)
        end
        if layer.speed ~= 0 then
            layer.angle = (layer.angle + layer.speed * boost * elapsed) % (2 * math.pi)
            texture:SetRotation(layer.angle)
        end
    end
end)

-- Settings (Elements.lua): the smoke's opacity, as a share of each layer's own alpha (in its vertex
-- colour; the textures' alpha is the fade-in above). Pickable while stealth mode shows (Prowl).
local function ApplyOpacity(opacity)
    for i, layer in ipairs(layers) do
        local colour, alpha = LAYERS[i][2], LAYERS[i][3]
        layer.texture:SetVertexColor(colour[1] / 255, colour[2] / 255, colour[3] / 255, alpha * opacity)
    end
end

ns.RegisterElement({
    id = "swing.smoke",
    zone = "swing",
    name = "Stealth smoke",
    -- The smoke's visible band: from the gap outside the resource border to where it fades out.
    hit = { kind = "ring", inner = 54, outer = 69, visible = ns.IsStealthMode },
    states = { "prowl" },
    options = {
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        ApplyOpacity(get("opacity") / 100)
    end,
})

ns.OnStealthChanged(function(stealthed)
    if stealthed then
        startTime = GetTime()
        for _, layer in ipairs(layers) do
            layer.texture:SetAlpha(0)
            layer.texture:SetSize(SMOKE_SIZE * START_SCALE, SMOKE_SIZE * START_SCALE)
            layer.texture:Show()
        end
        driver:Show()
    else
        driver:Hide()
        for _, layer in ipairs(layers) do
            layer.texture:Hide()
        end
    end
end)
