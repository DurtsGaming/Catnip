-- Stealth (Prowl; Shadowmeld counts too): the HUD fades and night motes circle it.
-- Stealth breaks when combat starts, so this runs out of combat, where IsStealthed() is readable.
-- The motes ignore the HUD's alpha, so they stay bright while the rest fades.
local addonName, ns = ...

ns.defaults.stealthAlpha = 0.5 -- HUD alpha while stealthed, as a fraction of normal

local FADE_TIME = 0.4 -- seconds to fade in or out
local TWINKLE_LOW = 0.15
local TEAL = { 0.62, 0.97, 0.94 }
local VIOLET = { 0.79, 0.64, 1 }

-- radius from the HUD centre, starting angle (degrees), seconds per orbit (negative: counter-clockwise),
-- size, colour, seconds per twinkle. The resource circle's edge is at 50, the swing ring's at ~70,
-- the combo dots at 93.
local MOTES = {
    { 78, 20, 18, 24, TEAL, 1.3 },
    { 86, 140, 26, 20, VIOLET, 1.8 },
    { 94, 250, -22, 26, VIOLET, 1.1 },
    { 102, 310, 30, 18, TEAL, 2.2 },
    { 108, 70, -34, 22, VIOLET, 1.6 },
    { 82, 200, 21, 18, TEAL, 1.9 },
    { 114, 170, 28, 24, TEAL, 1.4 },
    { 98, 100, -19, 20, VIOLET, 2.0 },
    { 90, 330, 24, 22, VIOLET, 1.2 },
}

local hud = ns.hud

local motes = CreateFrame("Frame", nil, hud)
motes:SetAllPoints()
motes:SetFrameLevel(hud:GetFrameLevel() + 9) -- over the HUD, under the Clearcasting crescent
if motes.SetIgnoreParentAlpha then
    motes:SetIgnoreParentAlpha(true)
end
motes:SetAlpha(0)
motes:Hide()

-- Moved by hand in OnUpdate (only while shown, so only while stealthed). Rotation animations
-- pivoting on the HUD centre (SetOrigin far outside the texture) made the motes vanish in Forever.
local list = {}

local function CreateMote(radius, angle, period, size, colour, twinkle)
    local mote = motes:CreateTexture(nil, "OVERLAY")
    mote:SetTexture(ns.MEDIA .. "mote")
    mote:SetSize(size, size)
    mote:SetVertexColor(colour[1], colour[2], colour[3])
    mote:SetBlendMode("ADD")
    list[#list + 1] = {
        texture = mote,
        radius = radius,
        angle = math.rad(angle),
        speed = -2 * math.pi / period, -- radians per second; positive period turns clockwise
        twinkle = 2 * math.pi / (2 * twinkle), -- one bright-dim-bright cycle per 2 * twinkle seconds
    }
end

for _, m in ipairs(MOTES) do
    CreateMote(unpack(m))
end

motes:SetScript("OnUpdate", function()
    local now = GetTime()
    for _, m in ipairs(list) do
        local angle = m.angle + m.speed * now
        m.texture:SetPoint("CENTER", motes, "CENTER", m.radius * math.cos(angle), m.radius * math.sin(angle))
        local wave = 0.5 + 0.5 * math.cos(m.twinkle * now)
        m.texture:SetAlpha(TWINKLE_LOW + (1 - TWINKLE_LOW) * wave)
    end
end)

-- How stealthed the HUD looks, 0 to 1, eased toward the target over FADE_TIME.
local amount, target = 0, 0
local preview = false -- /catnip stealth: show the look without stealthing

local function Apply()
    local fade = ns.db.stealthAlpha
    hud:SetAlpha(ns.HUD_ALPHA * (1 - amount * (1 - fade)))
    motes:SetAlpha(amount)
end

local driver = CreateFrame("Frame", nil, UIParent) -- parented, so it's visible and gets OnUpdate
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
    local step = elapsed / FADE_TIME
    amount = amount < target and math.min(target, amount + step) or math.max(target, amount - step)
    Apply()
    if amount == target then
        self:Hide()
        if amount == 0 then
            motes:Hide()
        end
        ns.Debug("stealth look done: hud alpha", hud:GetAlpha(), "motes shown", motes:IsVisible(),
            "motes alpha", motes:GetAlpha())
    end
end)

local function Update()
    local stealthed = IsStealthed and IsStealthed()
    if ns.IsSecret(stealthed) then
        return -- shouldn't happen (stealth ends in combat); keep the current look
    end
    local wanted = (stealthed or preview) and 1 or 0
    if wanted == target then
        return
    end
    ns.Debug("stealthed:", stealthed, "preview:", preview)
    target = wanted
    ns.SetResourceStealthed(target == 1)
    if target == 1 then
        motes:Show()
    end
    driver:Show()
end

function ns.SetStealthFade(fade)
    ns.db.stealthAlpha = math.min(1, math.max(0, fade))
    Apply()
    ns.SettingsChanged()
end

ns.commands.stealth = function()
    preview = not preview
    ns.Print("stealth preview " .. (preview and "on" or "off"))
    Update()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_AURA", "player") -- backup in case UPDATE_STEALTH doesn't fire
local hasStealthEvent = ns.TryRegisterEvent(events, "UPDATE_STEALTH")
events:SetScript("OnEvent", Update)

ns.OnLoad(function()
    ns.Debug("stealth: IsStealthed", IsStealthed ~= nil, "UPDATE_STEALTH", hasStealthEvent,
        "SetIgnoreParentAlpha", motes.SetIgnoreParentAlpha ~= nil)
end)
