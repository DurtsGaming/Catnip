-- Eclipse moon (Balance, in-game test, 2026-10-19): a moon above the resource circle that waxes
-- with Eclipse's stacks, one quarter per stack (crescent, half, gibbous, full), silver-blue like the
-- buff icon. Off by default, per character: /catnip moon. Shown out of Cat and Bear Form (wherever
-- the power is mana), so it never sits on the combo points.
-- The stack count is secret in combat, so our code never reads it. Each phase is its own
-- AuraContainer (AuraContainer.lua) watching Eclipse, one button each:
--   1 stack: the crescent is on the button itself, which Blizzard shows while Eclipse is up at all.
--   2-4: the phase is on a StatusBar registered with button:SetApplicationBar(bar,
--   { minApplications = n }); Blizzard's own code then shows the bar only at n stacks or more
--   (Blizzard_CustomAuraButton.lua, ApplyApplicationBar; see docs/api-research.md, "Aura stacks").
-- Each phase sits a frame level above the one before, so the highest reached covers the rest.
-- Mockup: the "Catnip Balance HUD" canvas, board C2 (docs/design.md). The rest of that board lives
-- in BalanceDots.lua (Moonfire and Insect Swarm) and NaturesGrace.lua, created here in this group.
local addonName, ns = ...
local CreateFrame = ns.Profiled("EclipseMoon") -- timed by /catnip perf (Profiler.lua)

local ECLIPSE = { 408255 } -- Forever's Eclipse buff (verified 2026-10-19)
local MAX_STACKS = 4
local SIZE = 40 -- a little bigger than a combo point (38)
local Y = 104 -- the moon's centre above the HUD's centre (the combo points' arc is 93 out)
local LEVEL = 5 -- above the HUD, as the other AuraContainers; phase n at LEVEL + n

local CAN_COUNT = C_AuraContainerUtil and C_AuraContainerUtil.ProcessCustomAuraButtonApplicationBarOptions and true or false

local group = CreateFrame("Frame", nil, ns.hud)
group:SetAllPoints()
group:Hide()

local base = group:CreateTexture(nil, "ARTWORK")
base:SetTexture(ns.MEDIA .. "moon_dark")
base:SetSize(SIZE, SIZE)
base:SetPoint("CENTER", ns.hud, "CENTER", 0, Y)

-- Adds phase `stacks` to an Eclipse button (runs once per pooled button, out of combat).
local function AddPhase(button, stacks)
    ns.HideAuraButtonArt(button)
    local holder = button
    if stacks > 1 then
        if not CAN_COUNT then
            return
        end
        local bar = CreateFrame("StatusBar", nil, button) -- no fill texture: only whether it shows matters
        bar:SetAllPoints()
        local ok, err = pcall(button.SetApplicationBar, button, bar, { minApplications = stacks, maxApplications = MAX_STACKS })
        if not ok then
            ns.Debug("eclipse moon: stack", stacks, "bar refused:", err)
            bar:Hide()
            return
        end
        holder = bar
    end
    local phase = holder:CreateTexture(nil, "ARTWORK")
    phase:SetTexture(ns.MEDIA .. "moon_phase" .. stacks)
    phase:SetAllPoints()
end

local created
local function Create()
    if created then
        return
    end
    created = true
    -- The rest of the Balance test, in the same group: shown and hidden with the moon.
    ns.CreateBalanceDots(group) -- BalanceDots.lua
    ns.CreateNaturesGrace(group) -- NaturesGrace.lua
    if not ns.HAS_AURA_CONTAINER then
        ns.Debug("eclipse moon: no AuraContainer in this client")
        return
    end
    ns.Debug("eclipse moon: stack bars available:", CAN_COUNT)
    for stacks = 1, MAX_STACKS do
        ns.CreateAuraContainer({
            label = "Eclipse moon " .. stacks,
            unit = "player",
            filter = "HELPFUL",
            spellIDs = ECLIPSE,
            width = SIZE,
            height = SIZE,
            y = Y,
            level = LEVEL + stacks,
            parent = group,
            initialize = function(button)
                AddPhase(button, stacks)
            end,
        })
    end
end

local function Enabled()
    return ns.char and ns.char.eclipseMoon
end

local function Update()
    local powerType = UnitPowerType("player")
    if ns.IsSecret(powerType) then
        return -- keep the last state
    end
    group:SetShown(Enabled() and powerType == Enum.PowerType.Mana or false)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", Update)

ns.OnCharacterLoad(function()
    if Enabled() then
        Create()
    end
    Update()
end)

ns.commands.moon = function()
    ns.char.eclipseMoon = not ns.char.eclipseMoon or nil
    if Enabled() then
        Create()
    end
    Update()
    ns.Print("Eclipse moon (test): " .. (Enabled() and "on" or "off"))
end
