-- Nature's Grace (in-game test, 2026-10-19, with the Eclipse moon; /catnip moon): while the 3s buff
-- is up, the swing/cast ring's shadow glows mint. The black shadow is Swing.lua's ring_glow; this is
-- the same texture, tinted mint and drawn additively on an AuraContainer button (AuraContainer.lua),
-- so Blizzard shows it while the buff is up, even in combat. Additive so the gold cast ring, which
-- shares this frame level, still shows through if it ends up under the glow.
-- Created by EclipseMoon.lua, in its group: shown with the moon, out of Cat and Bear Form.
local addonName, ns = ...

local SPELL_IDS = { 16886, 16880 } -- Classic's buff and talent IDs (ForeverAuras' data; unverified on Forever)
local SIZE = ns.SWING_RING_SIZE * 1.14 -- as Swing.lua's glow (GLOW_SCALE)
local MINT = { 0.37, 0.91, 0.71, 0.9 }

function ns.CreateNaturesGrace(group)
    if not ns.HAS_AURA_CONTAINER then
        return
    end
    ns.CreateAuraContainer({
        label = "Nature's Grace",
        unit = "player",
        filter = "HELPFUL",
        spellIDs = SPELL_IDS,
        width = SIZE,
        height = SIZE,
        level = 0, -- with the HUD: under the moon and dots, as low as the shadow allows
        parent = group,
        initialize = function(button)
            ns.HideAuraButtonArt(button)
            local glow = button:CreateTexture(nil, "BACKGROUND")
            glow:SetTexture(ns.MEDIA .. "ring_glow")
            glow:SetAllPoints()
            glow:SetVertexColor(unpack(MINT))
            glow:SetBlendMode("ADD")
        end,
    })
end
