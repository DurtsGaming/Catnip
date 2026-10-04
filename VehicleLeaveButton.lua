-- Workaround for a Blizzard bug: on a flight path the leave-vehicle button ("request early landing")
-- never shows. Blizzard's button only re-checks itself on vehicle and bonus-bar events, and none
-- fire for a taxi on Forever (seen 2026-10-03: UnitOnTaxi and CanExitVehicle true, button hidden;
-- calling its Update() by hand showed it). So while on a taxi, we call Update() for it.
local addonName, ns = ...

local ticker

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
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("TAXIMAP_CLOSED") -- a destination was picked (or the map just closed)
events:RegisterEvent("PLAYER_ENTERING_WORLD") -- e.g. a /reload mid-flight
ns.TryRegisterEvent(events, "PLAYER_CONTROL_LOST") -- unverified on Forever
ns.TryRegisterEvent(events, "PLAYER_CONTROL_GAINED")
events:SetScript("OnEvent", Watch)
