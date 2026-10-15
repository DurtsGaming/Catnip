local addonName, ns = ...
local L = ns.L

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

-- Spells we look for, by the ID of any rank (rank 1 here). Forever keeps Classic's IDs; ranks from
-- ForeverAuras' SecretAuraRanks.lua (talentsforever.com data). Never look a spell up by an English
-- name: other clients name it in their own language.
ns.SPELL = {
    BEAR_FORM = 5487,
    CAT_FORM = 768,
    CLAW = 1082,
    DIRE_BEAR_FORM = 9634,
    FAERIE_FIRE = 770,
    FAERIE_FIRE_FERAL = 16857, -- Classic's; in Forever the form version seems to keep the plain name
    GROWL = 6795,
    MAUL = 6807,
    PRIMAL_BITE = 407995,
    PROWL = 5215,
    RAKE = 1822,
    REGROWTH = 8936,
    RIP = 1079,
    SHADOWMELD = 20580,
    SHIFTING_POWER = 1322605, -- from /dump in-game, 2026-10-15 (the rank the player knew)
    SHRED = 5221,
    WRATH = 5176,
}

-- The client's name for a spell, in its own language, from the ID of any rank. nil while unknown.
local spellNames = {}
function ns.SpellName(spell)
    local name = spellNames[spell]
    if not name then
        name = C_Spell.GetSpellName(spell)
        if ns.IsSecret(name) then
            return nil
        end
        spellNames[spell] = name
    end
    return name
end

-- Whether a spell name (e.g. from C_Spell.GetSpellName on a cast's ID) is the name of one of
-- `spells` (ns.SPELL entries): any rank or form version that shares the name. False if secret.
function ns.IsSpellNamed(name, spells)
    if name == nil or ns.IsSecret(name) then
        return false
    end
    for _, spell in ipairs(spells) do
        if ns.SpellName(spell) == name then
            return true
        end
    end
    return false
end

-- The ID of the first of `spells` (IDs of any rank, see ns.SPELL) that's in the spellbook, at the
-- highest rank known, else nil. Looked up by the spell's name, since each rank has its own ID.
function ns.FindKnownSpell(spells)
    for _, spell in ipairs(spells) do
        local name = ns.SpellName(spell)
        local info = name and C_Spell.GetSpellInfo(name)
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
        ns.Print("/catnip: " .. L["open settings"])
        ns.Print("/catnip edit: " .. L["settings and Edit Mode"])
        ns.Print("/catnip debug: " .. L["debug messages on or off"])
        ns.Print("/catnip dev: " .. L["tools for testing and development"])
    end
end

ns.commands.dev = function()
    ns.Print("/catnip perf start [label] | stop: time Catnip's code")
    ns.Print("/catnip cdm, /catnip spells, /catnip item <id>: list what Catnip sees")
    ns.Print("/catnip sp | ff | pb | growl | omen [seconds]: preview the Shifting Power arc, Faerie Fire, Primal Bite, Growl or Omen of Clarity ring")
    ns.Print("/catnip art | icon: record the window or icon under the mouse")
end

ns.commands.debug = function()
    ns.db.debug = not ns.db.debug
    ns.Print(ns.db.debug and L["Debug messages on"] or L["Debug messages off"])
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

-- Per-character settings (CatnipDB.chars[player GUID], as ns.char): what depends on the
-- character's spells and talents. Everything else in CatnipDB is account-wide. Kept inside CatnipDB
-- rather than a SavedVariablesPerCharacter, which needs a game restart to start saving.
-- Keyed by GUID, not name: Forever characters share their first name across the account, so
-- UnitName("player") gave two characters the same entry (2026-10-08). Set up at PLAYER_LOGIN, when
-- the GUID is surely known; code that needs ns.char runs in ns.OnCharacterLoad.
local CHARACTER_KEYS = {
    "cdTracked", -- Cooldowns.lua: the tracked cooldowns, in priority order
    "cdLastPotion", -- CooldownItems.lua
    "lengths", -- SpellTiming.lua: learned cooldown and GCD lengths (talents change them)
}

local characterCallbacks = {}
function ns.OnCharacterLoad(callback)
    characterCallbacks[#characterCallbacks + 1] = callback
end

local function SetUpCharacter()
    local db = ns.db
    db.chars = db.chars or {}
    for key in pairs(db.chars) do
        if not key:find("^Player%-") then
            db.chars[key] = nil -- the shared "Name-Realm" entry from the first try; whose list it holds is unknown
        end
    end
    local firstCharacter = next(db.chars) == nil
    local key = UnitGUID("player")
    db.chars[key] = db.chars[key] or {}
    ns.char = db.chars[key]
    -- To tell entries apart in the saved file (the name alone is shared by the account's characters).
    ns.char.name = string.format("%s %s %s (level %d)", UnitName("player"), UnitRace("player") or "?",
        UnitClass("player") or "?", UnitLevel("player") or 0)
    -- These were account-wide until 2026-10-08: the first character to log in after that keeps them.
    for _, name in ipairs(CHARACTER_KEYS) do
        if db[name] ~= nil then
            if firstCharacter and ns.char[name] == nil then
                ns.char[name] = db[name]
            end
            db[name] = nil
        end
    end
    ns.Debug("Settings for", ns.char.name, key)
    for _, callback in ipairs(characterCallbacks) do
        callback()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" then
        SetUpCharacter()
        return
    end
    if name ~= addonName then
        return
    end
    CatnipDB = CatnipDB or {}
    ns.db = CatnipDB
    ns.db.log = nil -- left over from a removed debug log
    ns.db.layouts = nil -- left over from per-Edit Mode layout settings (removed 2026-10-08)
    ns.db.probeCooldowns = nil -- left by the temporary cooldown probe (2026-10-10)
    for key, value in pairs(ns.defaults) do
        if ns.db[key] == nil then
            ns.db[key] = value
        end
    end
    for _, callback in ipairs(loadCallbacks) do
        callback()
    end
    self:UnregisterEvent("ADDON_LOADED")
end)
