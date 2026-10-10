-- The combo rings: a slot around each of the five combo points, showing the ability the player
-- picks for it in the settings (elements combo.ring1 to combo.ring5, option "spell"): a short
-- cooldown (CooldownRings.lua) or a DoT on the target (DotRings.lua). An ability sits in at most
-- one slot: picking it for one clears it from the other.
--
-- Those files add their abilities with ns.AddComboRingSpell(entry):
--   key            saved in the settings
--   label, color   the dropdown's text ("<Ability> Cooldown" or "<Ability> Duration"), and the
--                  slot's glyph colour in the settings list
--   order          place in the dropdown
--   defaultSlot    optional: the slot it starts in
--   shape          optional: its segments can be "angular" or "circular" (ns.ComboRingShape(key)),
--                  and this is its default; the slot showing it offers the choice (greyed out for
--                  None). The shape belongs to the ability, so it follows it from slot to slot
--   Place(slot)    show the real ring in slot (nil: nowhere); slot = { index, gate, sampleGate };
--                  called again when its shape changes
--   StartSample(slot), StopSample()   preview mode's looping copy, in slot.sampleGate (restarted
--                  when its shape changes)
local addonName, ns = ...

local COUNT = 5
local NONE = "none"
local LEVEL = 5 -- the rings' frame level above their slot's gate: over the dots

-- The old elements, one per ability (until 2026-10-09), and the slot each sat in: their Opacity
-- moves to that slot.
local MIGRATE = { ["combo.ff"] = 1, ["combo.pb"] = 3, ["combo.rake"] = 4, ["combo.rip"] = 5 }

local NONE_GLYPH = { kind = "ring", color = { 0.4, 0.38, 0.34 } }

-- Segment shapes: Angular, pointed on the inside edge with 1-unit gaps (the DoTs' default, telling
-- them apart from the cooldowns); Circular, square-ended with 2-unit gaps (the cooldowns' default).
local SHAPE_NONE = "circular" -- shown, greyed out, for an empty slot
local SHAPES = { { value = "angular", text = "Angular" }, { value = "circular", text = "Circular" } }

local entries = {} -- by key

-- An ability's own settings, stored as a pseudo-element ("dot.rip"; the name is from when only the
-- DoTs had any) so Reset all clears them too.
local function AbilityId(key)
    return "dot." .. key
end

-- A shaped ability's segment shape: "angular" or "circular".
function ns.ComboRingShape(key)
    return ns.ElementOption(AbilityId(key), "shape") or entries[key].shape
end

-- Gives a SegmentedArc.lua ring of ability `key` its shape's look: `art`_angular or `art`_circular,
-- each with its segments and gaps drawn in (make_textures.py).
function ns.ShapeComboRingArc(arc, key, art)
    arc.SetArt(art .. "_" .. ns.ComboRingShape(key))
end
local choices = { { value = NONE, text = "None", order = 0 } } -- the dropdown, filled as abilities are added
local slots = {}
local sampleState -- preview mode's state (nil while not previewing)

-- Rings of abilities that aren't in any slot wait here, hidden (a cooldown's clock keeps running).
local parked = CreateFrame("Frame")
parked:Hide()

-- Moves a ring's frame into `holder` (a slot's gate), centred on combo point `index` and over the
-- dots; with no holder, parks it out of sight.
function ns.PlaceComboRing(frame, holder, index)
    holder = holder or parked
    frame:SetParent(holder)
    frame:ClearAllPoints()
    local x, y = 0, 0
    if index then
        x, y = ns.ComboDotOffset(index)
    end
    frame:SetPoint("CENTER", holder, "CENTER", x, y)
    frame:SetFrameLevel(holder:GetFrameLevel() + LEVEL)
end

-- The ability picked for a slot (its key), or nil for none.
local function Picked(slot)
    local key = ns.ElementOption(slot.id, "spell")
    return entries[key] and key or nil
end

local function Sampling()
    return sampleState == "cat" or sampleState == "bear"
end

-- Puts every ability's ring, and its preview sample, in the slot the settings say (if two slots
-- name the same one, the first wins).
local function Arrange()
    local where = {}
    for _, slot in ipairs(slots) do
        local key = Picked(slot)
        if key and not where[key] then
            where[key] = slot
        end
    end
    for key, entry in pairs(entries) do
        local slot = where[key]
        local shape = entry.shape and ns.ComboRingShape(key) or nil
        if entry.slot ~= slot or entry.shape ~= shape then
            entry.slot, entry.shape = slot, shape
            entry.Place(slot)
        end
        local sampleSlot = Sampling() and slot or nil
        if entry.sampleSlot ~= sampleSlot or entry.sampleShape ~= shape then
            entry.StopSample()
            entry.sampleSlot, entry.sampleShape = sampleSlot, shape
            if sampleSlot then
                entry.StartSample(sampleSlot)
            end
        end
    end
end

function ns.AddComboRingSpell(entry)
    entries[entry.key] = entry
    entry.glyph = { kind = "ring", color = entry.color }
    local at = #choices + 1
    while choices[at - 1].order > entry.order do
        at = at - 1
    end
    table.insert(choices, at, { value = entry.key, text = entry.label, order = entry.order })
    if entry.defaultSlot then
        slots[entry.defaultSlot].spellOption.default = entry.key
    end
end

-- Stores `key` as a slot's pick (nil when that's its default).
local function Store(slot, key)
    local saved = ns.db.elements[slot.id] or {}
    if key == slot.spellOption.default then
        key = nil
    end
    saved.spell = key
    ns.db.elements[slot.id] = next(saved) and saved or nil
end

for index = 1, COUNT do
    local slot = { index = index, id = "combo.ring" .. index }
    -- Gates (ns.ComboRingGate) carry the Opacity setting: the real rings go in comboLive (hidden with
    -- the combo dots outside Cat and Bear Form), preview mode's samples in comboSample.
    slot.gate = ns.ComboRingGate(ns.comboLive)
    slot.sampleGate = ns.ComboRingGate(ns.comboSample)
    slot.spellOption = { key = "spell", type = "choice", label = "Shows", values = choices, default = NONE }
    slots[index] = slot
    -- The shown ability's shape, if it has one (else greyed out).
    local function Shaped()
        local key = Picked(slot)
        return key and entries[key].shape and key or nil
    end
    local shapeOption = { key = "segments", type = "choice", label = "Segments", values = SHAPES,
        enabled = function() return Shaped() ~= nil end,
        get = function()
            local key = Shaped()
            return key and ns.ComboRingShape(key) or SHAPE_NONE
        end,
        set = function(value)
            local key = Shaped()
            if key then
                ns.SetElementOption(AbilityId(key), "shape", value ~= entries[key].shape and value or nil)
            end
        end,
    }

    ns.RegisterElement({
        id = slot.id,
        zone = "combo",
        name = "Combo ring " .. index,
        glyph = function()
            local entry = entries[Picked(slot)]
            return entry and entry.glyph or NONE_GLYPH
        end,
        order = index,
        -- Pickable whenever the combo points show in preview mode, even while the slot's sample is
        -- between loops or the slot is empty.
        hit = ns.ComboRingHit(index, Sampling),
        options = {
            slot.spellOption,
            shapeOption,
            { key = "opacity", type = "slider", label = "Opacity", min = 0, max = 100, step = 5, format = "%.0f%%", default = 100 },
        },
        onReset = function()
            -- Reset to defaults puts the shown ability's shape back too: it's on this page.
            local key = Shaped()
            if key then
                ns.db.elements[AbilityId(key)] = nil
            end
        end,
        onChange = function()
            -- An ability picked here leaves the slot it was in.
            local key = Picked(slot)
            if not key then
                return
            end
            for _, other in ipairs(slots) do
                if other ~= slot and Picked(other) == key then
                    Store(other, NONE)
                end
            end
        end,
        apply = function(get)
            slot.gate:SetAlpha(get("opacity") / 100)
            slot.sampleGate:SetAlpha(get("opacity") / 100)
            Arrange()
        end,
        sample = function(state)
            sampleState = state
            Arrange()
        end,
    })
end

ns.OnLoad(function()
    local saved = ns.db.elements
    for old, index in pairs(MIGRATE) do
        if saved[old] then
            local id = "combo.ring" .. index
            saved[id] = saved[id] or {}
            if saved[id].opacity == nil then
                saved[id].opacity = saved[old].opacity
            end
            if next(saved[id]) == nil then
                saved[id] = nil
            end
            saved[old] = nil
        end
    end
    for _, slot in ipairs(slots) do -- Elements.lua applied them before this ran
        ns.GetElement(slot.id).apply(function(key) return ns.ElementOption(slot.id, key) end)
    end
end)
