-- Enrage: while the buff is up in Bear Form, the empty part of the resource circle turns a dim red.
-- A red disc sits behind the rage fill (between the dark backdrop and the bar), so only the
-- unfilled part shows it. It's an AuraContainer (see AuraContainer.lua): Blizzard shows the disc
-- while Enrage is up, even in combat when the buff is secret to us.
local addonName, ns = ...

local ENRAGE = 5229 -- the buff's aura ID (verified in Forever)
local SIZE = ns.RESOURCE_SIZE
local COLOR = { 0.9, 0.1, 0.1, 0.35 }

-- Hidden outside Bear Form (rage), taking the container with it.
local group = CreateFrame("Frame", nil, ns.hud)
group:SetAllPoints()

local sampling = false -- preview mode: the stand-in shows instead (below)

local function UpdateForm()
    group:SetShown(not sampling and UnitPowerType("player") == Enum.PowerType.Rage)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:SetScript("OnEvent", UpdateForm)

if ns.HAS_AURA_CONTAINER then
    ns.CreateAuraContainer({
        label = "Enrage",
        unit = "player",
        filter = "HELPFUL",
        spellIDs = { ENRAGE },
        width = SIZE,
        height = SIZE,
        level = 1, -- below the resource bar (+2), above the backdrop
        parent = group,
        initialize = function(button)
            ns.HideAuraButtonArt(button)
            local tint = button:CreateTexture(nil, "ARTWORK")
            tint:SetTexture(ns.MEDIA .. "circle_feather")
            tint:SetAllPoints(button)
            tint:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], COLOR[4])
        end,
    })
else
    ns.OnLoad(function()
        ns.Print("this client has no AuraContainer, so the Enrage tint is unavailable.")
    end)
end

-- Preview mode's stand-in: the same red disc, in Bear Form, at the container's level.
local standIn = CreateFrame("Frame", nil, ns.hud)
standIn:SetSize(SIZE, SIZE)
standIn:SetPoint("CENTER")
standIn:SetFrameLevel(ns.hud:GetFrameLevel() + 1)
standIn:Hide()
local standInTint = standIn:CreateTexture(nil, "ARTWORK")
standInTint:SetTexture(ns.MEDIA .. "circle_feather")
standInTint:SetAllPoints()
standInTint:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], COLOR[4])

-- Settings (Elements.lua): Opacity is the group's alpha (it holds the container, whose buttons
-- can't be touched after setup) and the stand-in's. No hit shape: it lies behind the circle's
-- fill, so it's picked from the list.
ns.RegisterElement({
    id = "resource.enrage",
    zone = "resource",
    name = "Enrage tint",
    states = { "bear" },
    options = {
        { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
    },
    apply = function(get)
        group:SetAlpha(get("opacity") / 100)
        standIn:SetAlpha(get("opacity") / 100)
    end,
    sample = function(state)
        sampling = state ~= nil
        standIn:SetShown(state == "bear")
        UpdateForm()
    end,
})
