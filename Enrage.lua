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

local function UpdateForm()
    group:SetShown(UnitPowerType("player") == Enum.PowerType.Rage)
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
