-- Stealth mode ("Moonlit"): while stealthed (Prowl, or Shadowmeld), the HUD cools down: a periwinkle
-- energy fill and combo points, a paler number and periwinkle, dimmer shift orbs.
-- This file only tracks the state; each piece restyles itself from ns.OnStealthChanged.
--
-- IsStealthed and UPDATE_STEALTH are retail API, unverified on Forever. UNIT_AURA is a backup in
-- case UPDATE_STEALTH doesn't exist or fire. Prowl breaks on entering combat, so this runs mostly
-- out of combat; if IsStealthed is ever secret, the current state is kept.
local addonName, ns = ...
local CreateFrame = ns.Profiled("Stealth") -- timed by /catnip perf (Profiler.lua)

local stealthed = false
local override -- preview mode's state (Preview.lua: true while previewing Prowl, else false), or nil
local callbacks = {}
local enabled = true -- the Stealth Mode setting's Enabled (Layout.lua): off, stealth leaves the HUD as is

function ns.IsStealthMode()
    if not enabled then
        return false
    end
    if override ~= nil then
        return override
    end
    return stealthed
end

-- fn(stealthed) runs whenever stealth mode turns on or off.
function ns.OnStealthChanged(fn)
    callbacks[#callbacks + 1] = fn
end

-- Tells the callbacks if stealth mode differs from `before`.
local function Notify(before)
    local now = ns.IsStealthMode()
    if now ~= before then
        for _, fn in ipairs(callbacks) do
            fn(now)
        end
    end
end

-- Stealth Mode on or off (the setting): off, stealth mode never shows, so nothing restyles.
function ns.SetStealthModeEnabled(on)
    on = on and true or false
    if on == enabled then
        return
    end
    local before = ns.IsStealthMode()
    enabled = on
    Notify(before)
end

-- Preview mode shows stealth mode on or off whatever the game says (true/false), then hands back to
-- the game (nil). Everything that restyles for stealth follows, as if it had really changed.
function ns.SetStealthPreview(value)
    local before = ns.IsStealthMode()
    override = value
    Notify(before)
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
    local before = ns.IsStealthMode()
    stealthed = now
    ns.Debug("stealth mode:", now)
    Notify(before) -- nothing changes on screen while preview mode overrides it
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_AURA", "player")
local hasStealthEvent = ns.TryRegisterEvent(events, "UPDATE_STEALTH")
events:SetScript("OnEvent", Update)

ns.OnLoad(function()
    ns.Debug("stealth: IsStealthed", IsStealthed ~= nil, "| UPDATE_STEALTH", hasStealthEvent)
end)
