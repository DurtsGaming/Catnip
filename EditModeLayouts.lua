-- Catnip's frames follow Blizzard's Edit Mode layouts: each layout keeps its own position, size and
-- opacity for the Rotation Frame and the Cooldown Frame (CatnipDB.layouts[layout name]). The rest of
-- Catnip keeps reading and writing the live values in CatnipDB as before; this file copies them into
-- the active layout whenever they change, and loads a layout's values when Blizzard switches layout
-- (in Edit Mode, or on a spec change). Changes save at once: Blizzard's Save button isn't involved.
-- Needs LibEditMode (BlizzardEditMode.lua); without it there's one set of values, as before.
local addonName, ns = ...

local lib = ns.LibEditMode
if not (lib and lib.RegisterCallback and EditModeManagerFrame) then
    return
end

-- The settings each layout keeps (the frames' on/off checkboxes stay shared).
local FIELDS = { "x", "y", "scale", "hudAlpha", "cdX", "cdY", "cdWidth", "cdHeight", "cdAlpha" }

local active -- the active layout's name, once Blizzard has loaded the layouts
local loading -- true while a layout's values are applied, so they aren't copied back half-done

local function Layouts()
    ns.db.layouts = ns.db.layouts or {}
    return ns.db.layouts
end

local function Snapshot()
    local values = {}
    for _, key in ipairs(FIELDS) do
        values[key] = ns.db[key]
    end
    return values
end

local function Save()
    if active and not loading and ns.db then
        Layouts()[active] = Snapshot()
    end
end

-- Applies the active layout's values; a layout seen for the first time starts from the current ones.
local function Load()
    local values = Layouts()[active]
    if not values then
        Save()
        return
    end
    loading = true
    local db = ns.db
    for _, key in ipairs(FIELDS) do
        if values[key] ~= nil then
            db[key] = values[key]
        end
    end
    ns.SetHudPosition(db.x, db.y) -- applies the HUD's scale and opacity too
    ns.Cooldowns.SetLayout(db.cdX, db.cdY, db.cdWidth, db.cdHeight) -- and the box's opacity
    loading = false
    Save()
end

ns.OnSettingsChanged(Save)

lib:RegisterCallback("layout", function(name)
    if not (name and ns.db) then
        return
    end
    active = name
    Load()
end)

-- A new layout copies the one it was made from (when it's a copy) or the current values.
lib:RegisterCallback("create", function(name, _, sourceName)
    local layouts = Layouts()
    local source = sourceName and layouts[sourceName]
    layouts[name] = source and CopyTable(source) or Snapshot()
end)

lib:RegisterCallback("rename", function(oldName, newName)
    local layouts = Layouts()
    layouts[newName], layouts[oldName] = layouts[oldName], nil
    if active == oldName then
        active = newName
    end
end)

lib:RegisterCallback("delete", function(name)
    Layouts()[name] = nil
end)
