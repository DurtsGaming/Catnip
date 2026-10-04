-- Stealth mode's shadow smoke: while stealthed (Stealth.lua) we don't swing, so the swing timer's
-- black glow fades out and a violet smoke ring fades in where it was. A still dark base under
-- two broken, blurred rings that turn at different speeds and directions, so their overlaps keep
-- shifting (picked from ten mockups, 2026-10-04). Colours from the Prowl icon. All three are white
-- textures from make_textures.py (smoke_*), tinted here.
local addonName, ns = ...

local SMOKE_SIZE = 160 -- the textures' canvas in HUD units (SMOKE_UNITS in make_textures.py)
local FADE_IN, FADE_OUT = 0.9, 0.6 -- smoke in / glow out when stealth starts; the reverse on the way out

-- texture, colour, alpha, seconds per turn (0 = still), clockwise
local LAYERS = {
    { "smoke_base", { 0x1a, 0x0d, 0x2e }, 0.7, 0 },
    { "smoke_a", { 0x5b, 0x34, 0x96 }, 0.85, 46, true },
    { "smoke_b", { 0x9b, 0x6f, 0xdc }, 0.5, 31, false },
}

local hud = ns.hud
local textures, spins = {}, {}

for i, layer in ipairs(LAYERS) do
    local file, colour, alpha, period, clockwise = unpack(layer)
    -- Under the swing glow's sublevel (-1) and the resource backdrop, in order: base at the bottom.
    local texture = hud:CreateTexture(nil, "BACKGROUND", nil, i - 6)
    texture:SetTexture(ns.MEDIA .. file)
    texture:SetSize(SMOKE_SIZE, SMOKE_SIZE)
    texture:SetPoint("CENTER")
    texture:SetVertexColor(colour[1] / 255, colour[2] / 255, colour[3] / 255, alpha)
    texture:SetAlpha(0)
    texture:Hide()
    textures[#textures + 1] = texture
    if period > 0 then
        local spin = texture:CreateAnimationGroup()
        local rotation = spin:CreateAnimation("Rotation")
        rotation:SetDegrees(clockwise and -360 or 360) -- positive turns counter-clockwise
        rotation:SetDuration(period)
        spin:SetLooping("REPEAT")
        spins[#spins + 1] = spin
    end
end

-- Eases the smoke's alpha (and the swing glow's, the other way) toward a target.
local level, from, to, startTime, duration = 0, 0, 0, 0, 1
local driver = CreateFrame("Frame")
driver:Hide()

local function Apply(value)
    level = value
    for _, texture in ipairs(textures) do
        texture:SetAlpha(value)
    end
    if ns.swingGlow then
        ns.swingGlow:SetAlpha(1 - value)
    end
end

driver:SetScript("OnUpdate", function(self)
    local t = math.min(1, (GetTime() - startTime) / duration)
    Apply(from + (to - from) * (1 - (1 - t) ^ 2)) -- ease out
    if t >= 1 then
        self:Hide()
        if to == 0 then
            for _, texture in ipairs(textures) do
                texture:Hide()
            end
            for _, spin in ipairs(spins) do
                spin:Stop()
            end
        end
    end
end)

ns.OnStealthChanged(function(stealthed)
    if stealthed then
        for _, texture in ipairs(textures) do
            texture:Show()
        end
        for _, spin in ipairs(spins) do
            if not spin:IsPlaying() then
                spin:Play()
            end
        end
    end
    from, to, startTime = level, stealthed and 1 or 0, GetTime()
    duration = stealthed and FADE_IN or FADE_OUT
    driver:Show()
end)
