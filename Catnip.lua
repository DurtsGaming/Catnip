local addonName, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"
ns.RESOURCE_SIZE = 100
ns.SWING_RING_SIZE = 134 -- band starts ~3px outside the resource circle's border
-- Top of the cast and swing time text, below the HUD's centre: under the shift orbs
-- (ShiftOrbs.lua: centres 89 below, 22.8 across, so their bottom is ~100.4).
ns.TIME_TEXT_OFFSET = 104

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

-- The ID of the first of `names` that's in the spellbook, else nil. By name, since IDs differ by
-- rank and client.
function ns.FindKnownSpell(names)
    for _, name in ipairs(names) do
        local info = C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if id and not ns.IsSecret(id) and not (IsPlayerSpell and not IsPlayerSpell(id)) then
            return id
        end
    end
    return nil
end

local hud = CreateFrame("Frame", "CatnipHUD", UIParent)
hud:SetSize(240, 240) -- positioned, scaled and faded by Layout.lua
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
        ns.Print("commands: /catnip (settings), /catnip edit (settings + Edit Mode), /catnip debug, /catnip cdm, /catnip spells, /catnip item <id>, /catnip sp [seconds] (Shifting Power preview), /catnip ff|pb [seconds] (Faerie Fire, Primal Bite ring previews, in Cat or Bear Form), /catnip growl [seconds] (Growl arc preview), /catnip art (mouse over a window), /catnip icon (mouse over an icon)")
    end
end

ns.commands.debug = function()
    ns.db.debug = not ns.db.debug
    ns.Print("debug " .. (ns.db.debug and "on" or "off"))
    ns.SettingsChanged()
end

-- /catnip art: with the mouse over a Blizzard window, records every texture in it (debug name,
-- layer, atlas or file, size, tex coords, colour) into CatnipDB.artDump[<window name>], so Claude
-- can read Blizzard's art names from the SavedVariables file to reuse them. /reload afterwards
-- writes the file.
local function DescribeTexture(texture)
    local width, height = texture:GetSize()
    local r, g, b, a = texture:GetVertexColor()
    local left, top, _, _, _, _, right, bottom = texture:GetTexCoord()
    return string.format("%s | %s | atlas %s | file %s | %.0fx%.0f | coords %.3f,%.3f-%.3f,%.3f | colour %.2f,%.2f,%.2f,%.2f%s",
        texture:GetDebugName(), (texture:GetDrawLayer()), tostring(texture:GetAtlas()), tostring(texture:GetTexture()),
        width, height, left, top, right, bottom, r, g, b, a, texture:IsShown() and "" or " | hidden")
end

-- /catnip icon: with the mouse over an icon (a macro icon, an action button...), prints its file ID
-- and keeps the last few in CatnipDB.iconPicks, to reuse the icon in Catnip.
ns.commands.icon = function()
    local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    if not focus or focus == WorldFrame or focus == UIParent then
        ns.Print("put the mouse over an icon, then press Enter on /catnip icon")
        return
    end
    local found
    local function Look(frame, depth)
        for _, region in ipairs({ frame:GetRegions() }) do
            local file = region:IsObjectType("Texture") and region:IsShown() and region:GetTexture()
            if type(file) == "number" and (not found or region == frame.Icon or region == frame.icon) then
                found = { file = file, name = region:GetDebugName() }
            end
        end
        if not found and depth < 2 then
            for _, child in ipairs({ frame:GetChildren() }) do
                Look(child, depth + 1)
            end
        end
    end
    Look(focus, 0)
    if not found then
        ns.Print("no icon found under the mouse (" .. focus:GetDebugName() .. ")")
        return
    end
    ns.db.iconPicks = ns.db.iconPicks or {}
    table.insert(ns.db.iconPicks, 1, found.file .. " " .. found.name)
    ns.db.iconPicks[11] = nil
    ns.Print(string.format("icon |T%d:20|t file ID %d (%s)", found.file, found.file, found.name))
end

ns.commands.art = function()
    local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    if not focus or focus == WorldFrame or focus == UIParent then
        ns.Print("put the mouse over a window, then press Enter on /catnip art")
        return
    end
    while focus:GetParent() and focus:GetParent() ~= UIParent do -- up to the whole window
        focus = focus:GetParent()
    end
    local lines = {}
    local function Walk(frame, depth)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsObjectType("Texture") then
                local ok, line = pcall(DescribeTexture, region)
                lines[#lines + 1] = ok and line or ("error: " .. tostring(line))
            end
        end
        if depth < 10 then
            for _, child in ipairs({ frame:GetChildren() }) do
                Walk(child, depth + 1)
            end
        end
    end
    Walk(focus, 0)
    local name = focus:GetDebugName()
    ns.db.artDump = ns.db.artDump or {}
    ns.db.artDump[name] = lines
    ns.Print(string.format("recorded %d textures from %s. /reload to save them to disk.", #lines, name))
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
