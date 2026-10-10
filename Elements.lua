-- The element registry: each customisable part of the HUD declares itself here with its options,
-- and the settings window builds its Rotation pages from this list (docs/settings-plan.md).
--
-- ns.RegisterElement{
--     id = "resource.number", zone = "resource", name = "Resource number",
--     hidden = true, -- optional: not offered in the settings for now (see Stored below)
--     glyph = { kind = "text", color = { 1, 1, 1 } }, -- its icon there: disc, ring, arc, dots or text
--                                                     -- (or a function returning one, if it can change)
--     options = { { key = "size", type = "slider", label = "Size", min = 8, max = 40, step = 1, default = 20 }, ... },
--     apply = function(get) ... end, -- get(key) is the option's resolved value; called on load and on every change
--     onChange = function() ... end, -- optional: after its own options are set or reset, before
--                                    -- everything is reapplied (e.g. to clear a clashing pick elsewhere)
--     onReset = function() ... end, -- optional: before its options are reset, to reset anything its
--                                   -- page edits that's stored elsewhere (an option with get/set)
-- }
--
-- Option types: "slider" (min, max, step, format), "choice" (values = { { value = v, text = "..." } }),
-- "checkbox", "color" (default = { r, g, b }, 0-1; stored as such a table). An option with `inherit = "<key>"` falls back to the General element's option of that
-- key when it isn't set, and its control gets a "Same as General" choice.
-- An option with `get` and `set` functions keeps its value somewhere else (e.g. on the ability a
-- combo ring slot shows, ComboRings.lua); its control reads and writes through them. `enabled`, a
-- function, greys the control out while it returns false (choices only, for now).
--
-- Stored in CatnipDB.elements[id][key]; nil means the default (or General's value, for inherit).
-- Shared across Edit Mode layouts.
local addonName, ns = ...

-- The settings window's zones (after its own General zone), from the top of the HUD down. Each
-- lists elements in groups, by the elements' `zone` field (resource, combo, swing, under, text); a
-- group's name is a heading over its elements.
ns.ZONES = {
    { id = "above", name = "Above",
        groups = { { zone = "combo" } } },
    { id = "circle", name = "Circle",
        groups = { { zone = "resource", name = "Fill" }, { zone = "swing", name = "Ring" } } },
    { id = "below", name = "Below",
        groups = { { zone = "under", name = "Arcs and orbs" }, { zone = "text", name = "Text" } } },
}

ns.elements = {} -- in registration order
local byId = {}

local function FindOption(element, key)
    for _, option in ipairs(element and element.options or {}) do
        if option.key == key then
            return option
        end
    end
end

function ns.RegisterElement(element)
    assert(not byId[element.id], "element registered twice: " .. element.id)
    ns.elements[#ns.elements + 1] = element
    byId[element.id] = element
    return element
end

function ns.GetElement(id)
    return byId[id]
end

-- A hidden element (`hidden = true`) keeps its code and options but isn't offered: the settings
-- window doesn't list it, preview mode doesn't outline it, and it ignores anything saved for it, so
-- it always uses its defaults. An option can be hidden the same way (its control isn't shown, its
-- saved value is ignored). Delete the flag to offer it again.
local function Stored(id, key)
    local element = byId[id]
    if element and (element.hidden or (FindOption(element, key) or {}).hidden) then
        return nil
    end
    local saved = ns.db and ns.db.elements and ns.db.elements[id]
    if saved then
        return saved[key]
    end
end

-- What the player picked for this option, or nil if it's left at its default (or inherits).
function ns.ElementStored(id, key)
    return Stored(id, key)
end

-- The value in effect: what's stored, else General's value for an inherited option, else the default.
function ns.ElementOption(id, key)
    local value = Stored(id, key)
    if value ~= nil then
        return value
    end
    local option = FindOption(byId[id], key)
    if option and option.inherit then
        return ns.ElementOption("general", option.inherit)
    end
    return option and option.default
end

local function Apply(element)
    if element.apply then
        element.apply(function(key) return ns.ElementOption(element.id, key) end)
    end
end

-- Stores a value (nil resets it) and reapplies. Every element is reapplied, since a change to
-- General can reach any of them through inherit.
function ns.SetElementOption(id, key, value)
    local elements = ns.db.elements
    elements[id] = elements[id] or {}
    elements[id][key] = value
    if next(elements[id]) == nil then
        elements[id] = nil
    end
    if byId[id] and byId[id].onChange then
        byId[id].onChange()
    end
    for _, element in ipairs(ns.elements) do
        Apply(element)
    end
    ns.SettingsChanged()
end

-- Whether two { r, g, b } colours match, to within what an 8-bit picker can tell apart.
function ns.SameColor(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for i = 1, 3 do
        if math.abs(a[i] - b[i]) > 0.5 / 255 then
            return false
        end
    end
    return true
end

-- Puts every option of an element back to its default (or back to inheriting from General).
function ns.ResetElement(id)
    if byId[id] and byId[id].onReset then
        byId[id].onReset()
    end
    ns.db.elements[id] = nil
    if byId[id] and byId[id].onChange then
        byId[id].onChange()
    end
    for _, element in ipairs(ns.elements) do
        Apply(element)
    end
    ns.SettingsChanged()
end

-- Every element's options back to their defaults (the settings window's Reset…).
function ns.ResetAllElements()
    ns.db.elements = {}
    for _, element in ipairs(ns.elements) do
        Apply(element)
    end
    ns.SettingsChanged()
end

ns.OnLoad(function()
    ns.db.elements = ns.db.elements or {}
    for _, element in ipairs(ns.elements) do -- every file has loaded by now, so all are registered
        Apply(element)
    end
end)

-- Fonts --------------------------------------------------------------------------------------------

-- Blizzard's own fonts (no LibSharedMedia for now). "default" is the client's standard font, which
-- is Friz Quadrata in English but differs in some locales.
ns.FONTS = {
    { value = "default", text = "Friz Quadrata", file = STANDARD_TEXT_FONT },
    { value = "arialn", text = "Arial Narrow", file = "Fonts\\ARIALN.TTF" },
    { value = "skurri", text = "Skurri", file = "Fonts\\skurri.ttf" },
    { value = "morpheus", text = "Morpheus", file = "Fonts\\MORPHEUS.TTF" },
}
local fontFiles = {}
for _, font in ipairs(ns.FONTS) do
    fontFiles[font.value] = font.file
end

ns.OUTLINES = {
    { value = "none", text = "None", flags = "" },
    { value = "thin", text = "Thin", flags = "OUTLINE" },
    { value = "thick", text = "Thick", flags = "THICKOUTLINE" },
}
local outlineFlags = {}
for _, outline in ipairs(ns.OUTLINES) do
    outlineFlags[outline.value] = outline.flags
end

-- Sets a FontString's font from option values. If the font file doesn't load, falls back to the
-- standard font (a FontString without a font errors on SetText).
function ns.ApplyFont(fontString, font, size, outline)
    local file = fontFiles[font] or STANDARD_TEXT_FONT
    local flags = outlineFlags[outline] or "OUTLINE"
    local ok = pcall(fontString.SetFont, fontString, file, size, flags)
    if not ok or not fontString:GetFont() then
        ns.Debug("font didn't load:", file)
        fontString:SetFont(STANDARD_TEXT_FONT, size, flags)
    end
end

-- A Font object for a font key at a size, made once and reused. For text we can't call SetFont on:
-- Blizzard's menu (MenuUtil) forbids SetFont on its labels (seen 2026-10-04) but takes SetFontObject.
local fontObjects = {}
local fontObjectCount = 0
function ns.FontObject(font, size)
    local file = fontFiles[font] or STANDARD_TEXT_FONT
    local key = file .. ":" .. size
    if not fontObjects[key] then
        fontObjectCount = fontObjectCount + 1
        local object = CreateFont("CatnipFont" .. fontObjectCount) -- this client requires a (global) name
        if not pcall(object.SetFont, object, file, size, "") or not object:GetFont() then
            object:SetFont(STANDARD_TEXT_FONT, size, "")
        end
        fontObjects[key] = object
    end
    return fontObjects[key]
end

-- The options every text element shares: font and outline (from General unless set), and size.
-- Font and outline are hidden for now (owner, 2026-10-09: bloat), so text uses General's defaults.
function ns.TextOptions(defaultSize)
    return {
        { key = "font", type = "choice", label = "Font", values = ns.FONTS, inherit = "font", fontPreview = true,
            hidden = true },
        { key = "size", type = "slider", label = "Size", min = 6, max = 40, step = 1, format = "%.0f", default = defaultSize },
        { key = "outline", type = "choice", label = "Outline", values = ns.OUTLINES, inherit = "outline", hidden = true },
    }
end

-- General: HUD-wide text defaults (the General zone's Text page, hidden with font and outline for
-- now). The HUD's on/off, scale, opacity and position sit above the zones in the settings window.
ns.RegisterElement({
    id = "general",
    name = "Text",
    hidden = true, -- not offered in the settings for now: font and outline are bloat (owner, 2026-10-09)
    glyph = { kind = "text", color = { 0.95, 0.93, 0.89 } },
    options = {
        { key = "font", type = "choice", label = "Font", values = ns.FONTS, default = "default", fontPreview = true },
        { key = "outline", type = "choice", label = "Outline", values = ns.OUTLINES, default = "thin" },
    },
})
