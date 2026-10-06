-- The big middle circle: energy / rage / mana, filling from the bottom, with the raw value in the middle.
local addonName, ns = ...

local SIZE = ns.RESOURCE_SIZE
-- Fill textures carry their own colour (the Forever energy bar's gradient; see make_textures.py), so
-- they're drawn untinted. Anything else (or a secret power type) gets a flat grey.
local POWER_TEXTURES = {
    [Enum.PowerType.Energy] = ns.MEDIA .. "fill_energy",
    [Enum.PowerType.Rage] = ns.MEDIA .. "fill_rage",
    [Enum.PowerType.Mana] = ns.MEDIA .. "fill_mana",
}
local STEALTH_ENERGY_TEXTURE = ns.MEDIA .. "fill_energy_prowl" -- periwinkle, in stealth mode (Stealth.lua)
local FLAT_TEXTURE ="Interface\\Buttons\\WHITE8X8"
local DEFAULT_COLOR = { 0.7, 0.7, 0.7 }
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local hud = ns.hud

-- #2 soft circle as a dark backdrop
local backdrop = hud:CreateTexture(nil, "BACKGROUND")
backdrop:SetTexture(ns.MEDIA .. "circle_soft")
backdrop:SetSize(SIZE * 1.3, SIZE * 1.3)
backdrop:SetPoint("CENTER")
backdrop:SetVertexColor(0, 0, 0, 0.4) -- light enough for the GCD shading to show over the empty part

-- #1 circle: a square vertical bar, masked to a soft-edged circle so it fills from the bottom
local bar = CreateFrame("StatusBar", nil, hud)
bar:SetSize(SIZE, SIZE)
bar:SetPoint("CENTER")
bar:SetFrameLevel(hud:GetFrameLevel() + 2) -- leaves +1 for the Enrage tint behind it (Enrage.lua)
bar:SetOrientation("VERTICAL")
local mask = bar:CreateMaskTexture()
mask:SetTexture(ns.MEDIA .. "circle_feather", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
mask:SetAllPoints(bar)

-- Swaps the fill texture, only when it changes. If the StatusBar hands back a new texture object,
-- the mask goes on that one too.
local currentFile, maskedTexture
local fillAlpha = 1 -- the fill's own alpha, lowered in stealth mode
local fillOpacity = 1 -- the Resource circle's "Fill opacity" setting; multiplies fillAlpha
local function SetFill(file, r, g, b)
    if file ~= currentFile then
        bar:SetStatusBarTexture(file)
        currentFile = file
        local texture = bar:GetStatusBarTexture()
        if texture ~= maskedTexture then
            texture:AddMaskTexture(mask)
            maskedTexture = texture
        end
        texture:SetAlpha(fillAlpha * fillOpacity)
    end
    bar:SetStatusBarColor(r, g, b)
end
SetFill(FLAT_TEXTURE, unpack(DEFAULT_COLOR))

-- #3 ring as the border: the same size and band as the five-second-rule ring (FiveSecondRule.lua),
-- so the black shows exactly where the blue drains away
local border = bar:CreateTexture(nil, "OVERLAY")
border:SetTexture(ns.MEDIA .. "ring_thin")
border:SetSize(SIZE + 6, SIZE + 6)
border:SetPoint("CENTER")
border:SetVertexColor(0, 0, 0)

-- The number sits on its own higher layer, so the GCD shading (Gcd.lua) never dims it.
local textLayer = CreateFrame("Frame", nil, bar)
textLayer:SetAllPoints()
textLayer:SetFrameLevel(bar:GetFrameLevel() + 5)
local text = textLayer:CreateFontString(nil, "OVERLAY")
text:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE") -- until the saved font is applied (the element below)
text:SetPoint("CENTER")

local function StyleText()
    if ns.IsStealthMode() then
        text:SetTextColor(0.9, 0.93, 0.98, 0.85)
    else
        text:SetTextColor(1, 1, 1, 1)
    end
end
StyleText()

-- Stealth mode crossfade: when the energy fill changes colour (Stealth.lua), a copy of the old
-- colour sits over the new fill and fades out. Like ManaPrediction.lua's bands, it's a clip frame
-- from the bar's bottom up to the fill's top edge, holding full-size circle art, so it covers just
-- the filled part and follows the fill while it fades. It sits over the border for that moment.
-- The fill itself (not the border or number) also dims to STEALTH_FILL_ALPHA over the same time.
local FADE_TIME = 0.35
local STEALTH_FILL_ALPHA = 0.7
local ghost = CreateFrame("Frame", nil, hud)
ghost:SetFrameLevel(bar:GetFrameLevel() + 1)
ghost:SetClipsChildren(true)
ghost:Hide()
local ghostMask = ghost:CreateMaskTexture()
ghostMask:SetTexture(ns.MEDIA .. "circle_feather", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
ghostMask:SetSize(SIZE, SIZE)
ghostMask:SetPoint("CENTER", hud)
local ghostFill = ghost:CreateTexture(nil, "ARTWORK")
ghostFill:SetSize(SIZE, SIZE)
ghostFill:SetPoint("CENTER", hud)
ghostFill:AddMaskTexture(ghostMask)
local fade = ghost:CreateAnimationGroup()
local fadeAlpha = fade:CreateAnimation("Alpha")
fadeAlpha:SetFromAlpha(1)
fadeAlpha:SetToAlpha(0)
fadeAlpha:SetDuration(FADE_TIME)
fadeAlpha:SetSmoothing("OUT")
fade:SetScript("OnFinished", function()
    ghost:Hide()
end)

local function FadeFrom(file)
    local top = bar:GetStatusBarTexture()
    local ok, err = pcall(function()
        ghost:ClearAllPoints()
        ghost:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
        ghost:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        ghost:SetPoint("TOP", top, "TOP")
    end)
    if not ok then
        ns.Debug("stealth fade: can't anchor:", err)
        return
    end
    ghostFill:SetTexture(file)
    fadeAlpha:SetFromAlpha(fillAlpha * fillOpacity) -- starts as bright as the fill it covers
    fade:Stop()
    ghost:Show()
    fade:Play()
end

local alphaFrom, alphaTo, alphaStart = 1, 1, 0
local alphaDriver = CreateFrame("Frame")
alphaDriver:Hide()
alphaDriver:SetScript("OnUpdate", function(self)
    local t = math.min(1, (GetTime() - alphaStart) / FADE_TIME)
    local eased = 1 - (1 - t) ^ 2 -- ease out, like the crossfade
    fillAlpha = alphaFrom + (alphaTo - alphaFrom) * eased
    bar:GetStatusBarTexture():SetAlpha(fillAlpha * fillOpacity)
    if t >= 1 then
        self:Hide()
    end
end)

local function FadeFillAlpha(to)
    alphaFrom, alphaTo, alphaStart = fillAlpha, to, GetTime()
    alphaDriver:Show()
end

-- Mana shows as a percentage. Mana is secret in combat, so we can't divide it ourselves:
-- UnitPowerPercent works it out engine-side, and the ScaleTo100 curve makes it 0-100.
-- string.format accepts secrets, so it can add the "%".
local SCALE_TO_100 = CurveConstants and CurveConstants.ScaleTo100
local CAN_SHOW_PERCENT = UnitPowerPercent ~= nil and SCALE_TO_100 ~= nil
local manaFormat = "percent" -- the Resource number's "Mana as" option: "percent" or "value"

local function PowerText(powerType, power)
    if powerType == Enum.PowerType.Mana and CAN_SHOW_PERCENT and manaFormat == "percent" then
        return string.format("%d%%", UnitPowerPercent("player", powerType, false, SCALE_TO_100))
    end
    return power
end

-- Mana cost prediction (ManaPrediction.lua) lowers the fill by a spell's cost while it's cast.
-- Mana is secret in combat, so it can't subtract: it raises the bar's range by the cost instead
-- (offset to max + offset), which draws mana - cost. maxMana is a plain number it read earlier.
local offset, offsetMax = 0, nil
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

local function SetRange(powerType)
    if offset > 0 and offsetMax and powerType == Enum.PowerType.Mana then
        bar:SetMinMaxValues(offset, offsetMax + offset)
    else
        bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
    end
end

-- The fill texture, whose top edge ManaPrediction.lua anchors its bands to.
function ns.ResourceFillTexture()
    return bar:GetStatusBarTexture()
end

-- snap: also jump the fill to the current value, skipping the smoothing (for when the range
-- returns to normal in the same moment the mana is spent, so the fill doesn't dip and recover).
local sample -- preview mode's sample { powerType, value, max } (below), shown instead of the real power
ns.SAMPLE_MANA = 0.8 -- Caster's sample mana, as a fraction of max (ManaPrediction.lua places its band by it)

-- Whether the circle shows preview mode's sample, not the real power (ManaPrediction.lua hides
-- its bands then).
function ns.IsResourceSampled()
    return sample ~= nil
end

function ns.SetResourceOffset(newOffset, maxMana, snap)
    offset, offsetMax = newOffset, maxMana
    if sample then
        return -- kept for when the preview ends
    end
    local powerType = UnitPowerType("player")
    SetRange(powerType)
    if snap then
        bar:SetValue(UnitPower("player", powerType), IMMEDIATE)
    end
end

-- The sample's number: mana in the Resource number's format, else the value.
local function SampleText()
    if sample.powerType == Enum.PowerType.Mana and manaFormat == "percent" then
        return string.format("%d%%", math.floor(sample.value / sample.max * 100 + 0.5))
    end
    return tostring(math.floor(sample.value))
end

local function Update()
    local powerType = sample and sample.powerType or UnitPowerType("player")
    local knownType = not ns.IsSecret(powerType)
    local file = knownType and POWER_TEXTURES[powerType]
    if file and powerType == Enum.PowerType.Energy and ns.IsStealthMode() then
        file = STEALTH_ENERGY_TEXTURE
    end
    if file then
        SetFill(file, 1, 1, 1)
    else
        SetFill(FLAT_TEXTURE, unpack(DEFAULT_COLOR))
    end

    if sample then
        bar:SetMinMaxValues(0, sample.max)
        -- Caster's sample shows a cast's cost taken off the fill, if the prediction is on
        -- (ManaPrediction.lua draws its band over the gap); the number keeps the full value.
        local spend = sample.powerType == Enum.PowerType.Mana and ns.SampleManaSpend and ns.SampleManaSpend() or 0
        bar:SetValue(sample.value - spend * sample.max, SMOOTH)
        text:SetText(SampleText())
        if ns.onResourceUpdate then -- hides the mana prediction bands (ns.IsResourceSampled)
            ns.onResourceUpdate()
        end
        return
    end

    -- Current and max power may be secret in combat; StatusBar and FontString accept secrets as-is.
    local power = UnitPower("player", powerType)
    SetRange(powerType)
    bar:SetValue(power, SMOOTH)
    text:SetText(knownType and PowerText(powerType, power) or power)
    if ns.onResourceUpdate then -- ManaPrediction.lua
        ns.onResourceUpdate()
    end
end

ns.RefreshResource = Update -- for ManaPrediction.lua's settings, which change the Caster sample

ns.OnLoad(function()
    ns.Debug("mana as percent:", CAN_SHOW_PERCENT, "| UnitPowerPercent:", UnitPowerPercent ~= nil,
        "| CurveConstants.ScaleTo100:", SCALE_TO_100 ~= nil)
end)

-- Settings (Elements.lua). The circle: opacity of the fill, the dark background and the black
-- border, in percent. The hit circle (preview mode, Preview.lua) takes in the border.
local function PercentSlider(key, label, default)
    return { key = key, type = "slider", label = label, min = 0, max = 100, step = 5, format = "%.0f%%", default = default }
end
ns.RegisterElement({
    id = "resource.circle",
    zone = "resource",
    name = "Resource circle",
    hit = { kind = "circle", radius = SIZE / 2 + 3 },
    options = {
        PercentSlider("fillOpacity", "Fill opacity", 100),
        PercentSlider("backgroundOpacity", "Background opacity", 40),
        PercentSlider("borderOpacity", "Border opacity", 100),
    },
    apply = function(get)
        fillOpacity = get("fillOpacity") / 100
        bar:GetStatusBarTexture():SetAlpha(fillAlpha * fillOpacity)
        backdrop:SetVertexColor(0, 0, 0, get("backgroundOpacity") / 100)
        border:SetVertexColor(0, 0, 0, get("borderOpacity") / 100)
    end,
    -- Preview mode: a fixed fill per state (Prowl's periwinkle comes from the stealth preview), or
    -- back to the real power (nil). Max mana is the real one when readable, so "Value" looks right.
    sample = function(state)
        local mana = Enum.PowerType.Mana
        if state == "caster" then
            local max = UnitPowerMax("player", mana)
            if ns.IsSecret(max) or not max or max <= 0 then
                max = 5000
            end
            sample = { powerType = mana, value = math.floor(max * ns.SAMPLE_MANA), max = max }
        elseif state == "bear" then
            sample = { powerType = Enum.PowerType.Rage, value = 45, max = 100 }
        elseif state then -- cat, prowl
            sample = { powerType = Enum.PowerType.Energy, value = 70, max = 100 }
        else
            sample = nil
            SetRange(UnitPowerType("player")) -- puts back the mana prediction's offset, if any
        end
        Update()
    end,
})

-- The number's font, size and outline, and how mana shows. A raw mana
-- value is secret in combat too, but SetText takes it as-is.
local numberOptions = ns.TextOptions(20)
-- states: changing it switches the preview to a state that shows mana (Preview.lua).
numberOptions[#numberOptions + 1] = { key = "manaFormat", type = "choice", label = "Mana as", default = "percent",
    values = { { value = "percent", text = "Percent" }, { value = "value", text = "Value" } },
    states = { "caster" } }
ns.RegisterElement({
    id = "resource.number",
    zone = "resource",
    name = "Resource number",
    hit = { kind = "text", region = text, anchor = textLayer, point = "CENTER", chars = 4 },
    options = numberOptions,
    apply = function(get)
        ns.ApplyFont(text, get("font"), get("size"), get("outline"))
        manaFormat = get("manaFormat")
        if UnitExists("player") then
            Update()
        end
    end,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", Update)

local ENERGY_FILES = { [POWER_TEXTURES[Enum.PowerType.Energy]] = true, [STEALTH_ENERGY_TEXTURE] = true }

ns.OnStealthChanged(function(stealthed)
    StyleText()
    local before = currentFile
    Update()
    if before ~= currentFile and ENERGY_FILES[before] then
        FadeFrom(before)
    end
    FadeFillAlpha(stealthed and STEALTH_FILL_ALPHA or 1)
end)
