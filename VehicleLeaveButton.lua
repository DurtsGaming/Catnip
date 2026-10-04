-- Workaround for a Blizzard bug: on a flight path the leave-vehicle button ("request early landing")
-- never shows. Blizzard's button only re-checks itself on vehicle and bonus-bar events, and none
-- fire for a taxi on Forever (seen 2026-10-03: UnitOnTaxi and CanExitVehicle true, button hidden;
-- calling its Update() by hand showed it). So while on a taxi, we call Update() for it.
-- Only for routes with a connection to get off at: on a direct flight the button stays hidden.
local addonName, ns = ...

local ticker
local multiHop = false -- the flight we're taking (or about to) stops at a connection

local function Refresh()
    local button = _G.MainMenuBarVehicleLeaveButton
    -- Update() shows/hides an Edit Mode frame, which is protected in combat.
    if button and button.Update and not InCombatLockdown() then
        button:Update()
    end
end

-- Refreshes now, then once a second until the flight ends (UnitOnTaxi can lag the triggering
-- event, and nothing tells the button when we land either).
local function Watch()
    if not multiHop then
        return
    end
    Refresh()
    if ticker then
        return
    end
    local seenTaxi = false
    local checks = 0
    ticker = C_Timer.NewTicker(1, function()
        checks = checks + 1
        local onTaxi = UnitOnTaxi("player")
        seenTaxi = seenTaxi or onTaxi
        Refresh()
        -- Stop after landing, or after a few seconds if the flight never started.
        if (seenTaxi and not onTaxi) or (not seenTaxi and checks >= 5) then
            ticker:Cancel()
            ticker = nil
            multiHop = false
        end
    end)
end

-- A destination was picked on the flight map; GetNumRoutes counts the hops to it.
hooksecurefunc("TakeTaxiNode", function(slot)
    multiHop = (GetNumRoutes(slot) or 0) > 1
    Watch()
end)

local events = CreateFrame("Frame")
ns.TryRegisterEvent(events, "PLAYER_CONTROL_LOST") -- the flight started (EllesmereUI uses these on Forever)
ns.TryRegisterEvent(events, "PLAYER_CONTROL_GAINED")
events:SetScript("OnEvent", Watch)
