-- The element registry: each customisable part of the HUD declares itself here with its options,
-- and the settings window builds its Rotation pages from this list (docs/settings-plan.md).
--
-- ns.RegisterElement{
--     id = "resource.number", zone = "resource", name = "Resource number",
--     options = { { key = "size", type = "slider", label = "Size", min = 8, max = 40, step = 1, default = 20 }, ... },
--     apply = function(get) ... end, -- get(key) is the option's resolved value; called on load and on every change
-- }
--
-- Option types: "slider" (min, max, step, format), "choice" (values = { { value = v, text = "..." } }),
-- "checkbox". An option with `inherit = "<key>"` falls back to the General element's option of that
-- key when it isn't set, and its control gets a "Same as General" choice.
--
-- Stored in CatnipDB.elements[id][key]; nil means the default (or General's value, for inherit).
-- Shared across Edit Mode layouts.
local addonName, ns = ...

-- Zones in the order the settings tree lists them, from the centre of the HUD out.
ns.ZONES = {
    { id = "resource", name = "Resource circle" },
    { id = "combo", name = "Combo arc" },
    { id = "swing", name = "Swing ring" },
    { id = "under", name = "Under the ring" },
    { id = "text", name = "Text" },
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

local function Stored(id, key)
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
    for _, element in ipairs(ns.elements) do
        Apply(element)
    end
    ns.SettingsChanged()
end

-- Puts every option of an element back to its default (or back to inheriting from General).
function ns.ResetElement(id)
    ns.db.elements[id] = nil
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

-- The options every text element shares: font and outline (from General unless set), and size.
function ns.TextOptions(defaultSize)
    return {
        { key = "font", type = "choice", label = "Font", values = ns.FONTS, inherit = "font", fontPreview = true },
        { key = "size", type = "slider", label = "Size", min = 6, max = 40, step = 1, format = "%.0f", default = defaultSize },
        { key = "outline", type = "choice", label = "Outline", values = ns.OUTLINES, inherit = "outline" },
    }
end

-- General: HUD-wide defaults. Its own page also has the HUD's scale, opacity and position
-- (Options.lua), which stay per Edit Mode layout.
ns.RegisterElement({
    id = "general",
    name = "General",
    options = {
        { key = "font", type = "choice", label = "Font", values = ns.FONTS, default = "default", fontPreview = true },
        { key = "outline", type = "choice", label = "Outline", values = ns.OUTLINES, default = "thin" },
    },
})
