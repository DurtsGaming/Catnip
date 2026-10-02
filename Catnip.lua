local addonName, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"
ns.RESOURCE_SIZE = 100
ns.SWING_RING_SIZE = 134 -- band starts ~3px outside the resource circle's border

-- In combat, Midnight hands addons "secret" values we can display but not compare or do math on.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Printable form of a value that may be secret.
function ns.Describe(value)
    if ns.IsSecret(value) then
        return "<secret>"
    end
    return tostring(value)
end

function ns.Print(...)
    print("|cff33ff99Catnip|r", ...)
end

function ns.Debug(...)
    if not (ns.db and ns.db.debug) then
        return
    end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = ns.Describe((select(i, ...)))
    end
    ns.Print("|cff999999" .. table.concat(parts, " ") .. "|r")
end

-- Registers an event that may not exist in this client. Returns whether it worked.
function ns.TryRegisterEvent(frame, event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end

local hud = CreateFrame("Frame", "CatnipHUD", UIParent)
hud:SetSize(240, 240) -- positioned and scaled by Layout.lua
hud:SetAlpha(0.85) -- every element inherits this, AuraContainers included
ns.hud = hud

-- Saved settings (CatnipDB). Modules add their defaults to ns.defaults and
-- run setup that needs ns.db via ns.OnLoad.
ns.defaults = { debug = false }
local loadCallbacks = {}
function ns.OnLoad(callback)
    loadCallbacks[#loadCallbacks + 1] = callback
end

-- Call ns.SettingsChanged() after changing a setting, so anything showing it (the settings
-- window) can refresh.
local settingsCallbacks = {}
function ns.OnSettingsChanged(callback)
    settingsCallbacks[#settingsCallbacks + 1] = callback
end
function ns.SettingsChanged()
    for _, callback in ipairs(settingsCallbacks) do
        callback()
    end
end

-- Slash commands: modules add handlers to ns.commands; "/catnip <name> <arg>".
ns.commands = {}
SLASH_CATNIP1 = "/catnip"
SlashCmdList.CATNIP = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg):lower(), 2)
    local handler = ns.commands[cmd]
    if handler then
        handler(arg)
    else
        ns.Print("commands: /catnip (settings), /catnip lock, /catnip unlock, /catnip scale <0.5-2.5>, /catnip reset, /catnip debug, /catnip cdm, /catnip spells")
    end
end

ns.commands.debug = function()
    ns.db.debug = not ns.db.debug
    ns.Print("debug " .. (ns.db.debug and "on" or "off"))
    ns.SettingsChanged()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then
        return
    end
    CatnipDB = CatnipDB or {}
    ns.db = CatnipDB
    ns.db.log = nil -- left over from a removed debug log
    for key, value in pairs(ns.defaults) do
        if ns.db[key] == nil then
            ns.db[key] = value
        end
    end
    for _, callback in ipairs(loadCallbacks) do
        callback()
    end
    ns.Print("loaded. Interface: " .. select(4, GetBuildInfo()))
    self:UnregisterEvent("ADDON_LOADED")
end)
