-- Hiding Blizzard's Action Bar 1 and Stance Bar (settings; Forever's Edit Mode has no option for
-- them). EllesmereUI's technique for MainActionBar: alpha 0, never Hide() or SetParent. Those touch
-- the bar's protected shown state from our code, and Blizzard's next combat bar change then fails
-- (ADDON_ACTION_BLOCKED). Alpha is unprotected, works in combat, and the buttons stay live, so
-- keybinds (action keys, form keys) still work. Invisible buttons would still catch clicks, so their
-- mouse is switched off too: that touches protected buttons, so only out of combat.
local addonName, ns = ...
local CreateFrame = ns.Profiled("ActionBar") -- timed by /catnip perf (Profiler.lua)

local BARS = {
    {
        setting = "hideActionBar1",
        label = "Action Bar 1",
        frame = function() return _G.MainActionBar or _G.MainMenuBar end, -- MainActionBar on Forever (EllesmereUI)
        buttons = "ActionButton",
        count = 12,
        -- Blizzard parents the leave-vehicle button to this bar; it has to stay visible.
        keepVisible = { "MainMenuBarVehicleLeaveButton" },
    },
    {
        setting = "hideStanceBar",
        label = "Stance Bar",
        frame = function() return _G.StanceBar end,
        buttons = "StanceButton",
        count = 10,
    },
}

for _, info in ipairs(BARS) do
    ns.defaults[info.setting] = false
end

local mousePending = false

local function Hidden(info)
    return ns.db and ns.db[info.setting]
end

-- Mouse on the bar, its buttons and (Action Bar 1) its page arrows: off while hidden.
local function SetMouse(info, bar, enabled)
    local frames = { bar }
    for i = 1, info.count do
        frames[#frames + 1] = _G[info.buttons .. i]
    end
    local pager = bar.ActionBarPageNumber
    if pager then
        frames[#frames + 1] = pager
        frames[#frames + 1] = pager.UpButton
        frames[#frames + 1] = pager.DownButton
    end
    for _, frame in ipairs(frames) do
        if frame and frame.EnableMouse then
            frame:EnableMouse(enabled)
        end
    end
end

-- Hides or restores one bar to match its setting.
local function Update(info)
    local bar = info.frame()
    if not bar or not ns.db or not (Hidden(info) or info.hooked) then
        return -- never touched until its setting is first used
    end
    if not info.hooked then
        -- Blizzard re-shows bars on form, page and vehicle changes; keep it see-through.
        hooksecurefunc(bar, "Show", function(self)
            if Hidden(info) then
                self:SetAlpha(0)
            end
        end)
        info.hooked = true -- only once someone uses the setting
    end
    bar:SetAlpha(Hidden(info) and 0 or 1)
    -- Children that must survive the fade opt out of the bar's alpha (unprotected, so fine in
    -- combat). EllesmereUI reparents instead, but then has to own the button's show/hide too.
    for _, name in ipairs(info.keepVisible or {}) do
        local child = _G[name]
        if child and child.SetIgnoreParentAlpha then
            child:SetIgnoreParentAlpha(Hidden(info))
        end
    end
    if InCombatLockdown() then
        mousePending = true -- caught up on PLAYER_REGEN_ENABLED
    else
        SetMouse(info, bar, not Hidden(info))
    end
    ns.Debug(info.label, Hidden(info) and "hidden" or "shown")
end

-- Hides or restores both bars to match the settings.
function ns.UpdateBlizzardBars()
    mousePending = false
    for _, info in ipairs(BARS) do
        Update(info)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or mousePending then
        ns.UpdateBlizzardBars()
    end
end)
