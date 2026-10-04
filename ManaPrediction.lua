-- Mana cost prediction, like Blizzard's player frame: while a spell with a cast time and a mana
-- cost is cast, the resource circle's fill drops by the cost and a darker band shows the mana
-- about to be spent. If the cast is cancelled or interrupted, the fill climbs back up at once and
-- steadily, over a glowing band (Blizzard's "gain" glow: the bar's own texture with
-- UI-StatusBar-Glow added on top, linear over 0.5s); if it lands, the band goes when the mana is
-- spent.
-- Only while the power shown is mana (caster forms): Cat and Bear abilities are instant.
--
-- Mana is secret in combat, so the fill isn't lowered by subtracting: Resource.lua raises the
-- bar's range by the cost (ns.SetResourceOffset). That needs max mana as a plain number, read
-- whenever it's readable and kept. The cost comes from C_Spell.GetSpellPowerCost, readable in
-- combat (FiveSecondRule.lua relies on it too). The bands fill just the gap between mana - cost
-- and mana (see AnchorBands).
local addonName, ns = ...

local MANA = Enum.PowerType.Mana
local SIZE = ns.RESOURCE_SIZE
local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SPEND_COLOR = { 0.45, 0.45, 0.6 } -- tints fill_mana darker, like Blizzard's cost band
local GLOW_FILE = "Interface\\TargetingFrame\\UI-StatusBar-Glow" -- Blizzard's gain glow, drawn additively
local GLOW_ALPHA = 0.75 -- as Blizzard's
local REFUND_TIME = 0.5 -- Blizzard's gain glow runs 0.5s, linear
-- A stop event starts the refund at once (Blizzard doesn't wait either). If our SUCCEEDED arrives
-- this soon after, the stop came first on a cast that landed, so the refund is undone.
local LATE_SUCCESS = 0.15
local SPENT_WAIT = 0.4 -- after SUCCEEDED, longest wait for the mana to drop before clearing anyway

-- The bands only cover the gap between the lowered fill and the mana: the HUD is translucent
-- (hudAlpha), so anything behind the main fill shows through it. Each band is a clip frame
-- stretched from the main fill's top edge up to the top edge of an invisible bar holding the
-- current mana, with full-size circle art inside, so the art lines up with the main fill.
local level = CreateFrame("StatusBar", nil, ns.hud)
level:SetSize(SIZE, SIZE)
level:SetPoint("CENTER")
level:SetOrientation("VERTICAL")
level:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
level:SetStatusBarColor(0, 0, 0, 0)

-- With glow, Blizzard's glow texture is added over the band (it stretches over the gap the same way).
local function CreateBand(color, glow)
    local band = CreateFrame("Frame", nil, ns.hud)
    band:SetFrameLevel(ns.hud:GetFrameLevel() + 1)
    band:SetClipsChildren(true)
    local mask = band:CreateMaskTexture()
    mask:SetTexture(ns.MEDIA .. "circle_feather", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(SIZE, SIZE)
    mask:SetPoint("CENTER", ns.hud)
    local fill = band:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(ns.MEDIA .. "fill_mana")
    fill:SetVertexColor(color[1], color[2], color[3])
    fill:SetSize(SIZE, SIZE)
    fill:SetPoint("CENTER", ns.hud)
    fill:AddMaskTexture(mask)
    if glow then
        local texture = band:CreateTexture(nil, "ARTWORK", nil, 1)
        texture:SetTexture(GLOW_FILE)
        texture:SetBlendMode("ADD")
        texture:SetAlpha(GLOW_ALPHA)
        texture:SetAllPoints(band)
        -- The glow is drawn for a horizontal bar: turn it a quarter so its across-the-bar shading
        -- runs across our vertical one (UL, LL, UR, LR corners)
        texture:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        texture:AddMaskTexture(mask)
    end
    band:Hide()
    return band
end

local spendBand = CreateBand(SPEND_COLOR)
local refundBand = CreateBand({ 1, 1, 1 }, true)

-- Anchors the bands to the two fills' top edges (again each cast, in case Resource.lua's
-- StatusBar handed out a new fill texture). False if the client refused.
local function AnchorBands()
    local top, bottom = level:GetStatusBarTexture(), ns.ResourceFillTexture()
    local ok, err = pcall(function()
        for _, band in ipairs({ spendBand, refundBand }) do
            band:ClearAllPoints()
            band:SetPoint("TOPLEFT", top, "TOPLEFT")
            band:SetPoint("TOPRIGHT", top, "TOPRIGHT")
            band:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
            band:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
        end
    end)
    if not ok then
        ns.Debug("mana prediction: can't anchor the bands:", err)
    end
    return ok
end

local maxMana -- plain number, from the last time it was readable
local state = "idle" -- idle, casting, spent (landed, waiting for the mana to drop), refunding
local castSpellID, cost
local token = 0 -- bumped on every state change, so stale timers do nothing
local refundStart
local lastManaEvent -- GetTime() of the last mana change (GetTime is fixed within a frame)

local function PlainNumber(value)
    if value == nil or ns.IsSecret(value) then
        return nil
    end
    return value
end

local function ReadMaxMana()
    local max = PlainNumber(UnitPowerMax("player", MANA))
    if max and max > 0 then
        maxMana = max
    end
end

local function ManaCost(spellID)
    if not spellID or ns.IsSecret(spellID) then
        return nil
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then
        return nil
    end
    for _, entry in ipairs(costs) do
        if PlainNumber(entry.type) == MANA then
            return PlainNumber(entry.cost)
        end
    end
end

local function ShowingMana()
    local powerType = UnitPowerType("player")
    return not ns.IsSecret(powerType) and powerType == MANA
end

local function UpdateBands()
    level:SetMinMaxValues(0, UnitPowerMax("player", MANA))
    level:SetValue(UnitPower("player", MANA), SMOOTH)
end

local driver = CreateFrame("Frame")

local function Clear(snap)
    token = token + 1
    state = "idle"
    castSpellID, cost = nil, nil
    driver:SetScript("OnUpdate", nil)
    spendBand:Hide()
    refundBand:Hide()
    ns.SetResourceOffset(0, maxMana, snap)
end

-- Cancelled: the fill climbs back up from mana - cost at a steady rate, as Blizzard's glow
-- shrinks, uncovering the glowing band under it.
local function RefundUpdate()
    local t = (GetTime() - refundStart) / REFUND_TIME
    if t >= 1 then
        Clear()
        return
    end
    ns.SetResourceOffset(cost * (1 - t), maxMana)
end

local function Refund()
    token = token + 1
    state = "refunding"
    spendBand:Hide()
    refundBand:Show()
    UpdateBands()
    refundStart = GetTime()
    driver:SetScript("OnUpdate", RefundUpdate)
end

-- Landed: keep the lowered fill until the mana actually drops (it may come just after
-- SUCCEEDED), then put the range back and jump to the new value in the same frame.
local function Spent()
    token = token + 1
    state = "spent"
    local mine = token
    C_Timer.After(SPENT_WAIT, function()
        if token == mine then
            Clear(true)
        end
    end)
end

local function OnStart(spellID)
    Clear()
    if not ShowingMana() then
        return
    end
    ReadMaxMana()
    local spellCost = ManaCost(spellID)
    -- Clearcasting makes the next spell free (true only when we know it's up)
    if not maxMana or not spellCost or spellCost <= 0 or ns.IsClearcasting() == true
        or not AnchorBands() then
        return
    end
    state, castSpellID, cost = "casting", spellID, spellCost
    spendBand:Show()
    UpdateBands()
    ns.SetResourceOffset(cost, maxMana)
end

local function OnSucceeded(spellID)
    local lateSuccess = state == "refunding" and GetTime() - refundStart <= LATE_SUCCESS
    if state ~= "casting" and not lateSuccess then
        return
    end
    -- Only our cast's own SUCCEEDED counts (when both IDs are readable)
    if spellID and not ns.IsSecret(spellID) and spellID ~= castSpellID then
        return
    end
    if lateSuccess then -- back to the lowered fill and dark band
        driver:SetScript("OnUpdate", nil)
        refundBand:Hide()
        spendBand:Show()
        UpdateBands()
        ns.SetResourceOffset(cost, maxMana)
    end
    if lastManaEvent == GetTime() then
        Clear(true) -- the mana already dropped this frame
    else
        Spent()
    end
end

local function StillCasting()
    local ok, active = pcall(function()
        return UnitCastingInfo("player") ~= nil
    end)
    return ok and active
end

-- STOP also comes after a successful cast, maybe before SUCCEEDED (see LATE_SUCCESS).
-- FAILED also fires for a key pressed during the cast ("another action is in progress"), so
-- skip it if it names another spell or our cast is still going (as Blizzard's frame does).
local function OnStop(spellID)
    if state ~= "casting" then
        return
    end
    if spellID and not ns.IsSecret(spellID) and spellID ~= castSpellID then
        return
    end
    if StillCasting() then
        return
    end
    Refund()
end

local function OnPower()
    if state == "spent" then
        Clear(true)
    elseif state ~= "idle" then
        UpdateBands()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_START" then
        local _, _, spellID = ... -- unit, castGUID, spellID
        OnStart(spellID)
        ns.Debug("mana prediction: start", ns.Describe(spellID), "cost", ns.Describe(cost),
            "max", ns.Describe(maxMana))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if state ~= "idle" then
            ns.Debug("mana prediction:", event, "while", state) -- to learn the event order
        end
        OnSucceeded((select(3, ...)))
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if state ~= "idle" then
            ns.Debug("mana prediction:", event, "while", state)
        end
        OnStop((select(3, ...))) -- unit, castGUID, spellID
    elseif event == "UNIT_POWER_FREQUENT" then
        local powerToken = select(2, ...)
        if ns.IsSecret(powerToken) or powerToken == "MANA" then
            lastManaEvent = GetTime()
            OnPower()
        end
    elseif event == "UNIT_MAXPOWER" then
        ReadMaxMana()
        OnPower()
    elseif state ~= "idle" then -- shapeshift or loading screen
        Clear()
    else
        ReadMaxMana()
    end
end)
