-- Stealth mode ("Moonlit"): while stealthed (Prowl, or Shadowmeld), the HUD cools down: a periwinkle
-- energy fill and combo points, a paler number and periwinkle, dimmer shift orbs.
-- This file only tracks the state; each piece restyles itself from ns.OnStealthChanged.
--
-- IsStealthed and UPDATE_STEALTH are retail API, unverified on Forever. UNIT_AURA is a backup in
-- case UPDATE_STEALTH doesn't exist or fire. Prowl breaks on entering combat, so this runs mostly
-- out of combat; if IsStealthed is ever secret, the current state is kept.
local addonName, ns = ...

local stealthed = false
local callbacks = {}

function ns.IsStealthMode()
    return stealthed
end

-- fn(stealthed) runs whenever stealth mode turns on or off.
function ns.OnStealthChanged(fn)
    callbacks[#callbacks + 1] = fn
end

local function Update()
    if not IsStealthed then
        return
    end
    local now = IsStealthed()
    if ns.IsSecret(now) then
        return
    end
    now = now and true or false
    if now == stealthed then
        return
    end
    stealthed = now
    ns.Debug("stealth mode:", now)
    for _, fn in ipairs(callbacks) do
        fn(now)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_AURA", "player")
local hasStealthEvent = ns.TryRegisterEvent(events, "UPDATE_STEALTH")
events:SetScript("OnEvent", Update)

ns.OnLoad(function()
    ns.Debug("stealth: IsStealthed", IsStealthed ~= nil, "| UPDATE_STEALTH", hasStealthEvent)
end)
