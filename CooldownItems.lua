-- Items for the cooldown widget (Cooldowns.lua): anything with a "Use:" effect dropped onto the
-- Cooldowns tab's drop box. Tracked entries are strings next to the spell IDs:
--   "item:<itemID>"  one item (Hearthstone, a trinket), its own icon
--   "potion"         every potion: they share one cooldown, so one icon
-- A potion dropped on the box adds the "potion" entry and, as a special case, makes its buff
-- (Mighty Rage Potion's strength) count as the potion icon being active.
--
-- Item cooldowns look like plain numbers even in combat: EllesmereUI's Cooldown Manager passes
-- them straight to Cooldown:SetCooldown on Forever. Unverified by us, so a secret still falls back.
-- The shared potion cooldown reports on the potion that was used (and on others you own);
-- EllesmereUI found that once the last of a kind is drunk it only reports on that item's ID, so we
-- remember the last potion used (CatnipDB.cdLastPotion).
local addonName, ns = ...

local Items = {}
ns.CooldownItems = Items

local POTION_ENTRY = "potion"
local POTION_ICON = "Interface\\Icons\\INV_Potion_54"
local ITEM_GCD = 1.5 -- items share a short lockout on use; anything this short isn't a cooldown

local GetInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown

local potionsInBags = {} -- itemID -> its use spell ID, for potions in the bags right now

local function ItemName(itemID)
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
        or (GetItemInfo and GetItemInfo(itemID))
    return name or ("item " .. itemID)
end

local function ItemIcon(itemID)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    return icon or (GetInfoInstant and select(5, GetInfoInstant(itemID)))
end

local function UseSpell(itemID)
    local _, spellID = GetItemSpell(itemID)
    return spellID
end

-- Consumable / Potion. Classic-era item data may file potions under plain Consumable, so the name
-- is a fallback (English only).
local function IsPotion(itemID)
    if not GetInfoInstant then
        return false
    end
    local _, _, _, _, _, classID, subClassID = GetInfoInstant(itemID)
    local consumable = Enum.ItemClass and Enum.ItemClass.Consumable or 0
    local potion = Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Potion or 1
    if classID ~= consumable then
        return false
    end
    return subClassID == potion or ItemName(itemID):find("Potion") ~= nil
end

-- The tracked item ID in an "item:<id>" entry, or nil.
local function EntryItem(entry)
    return type(entry) == "string" and tonumber(entry:match("^item:(%d+)$")) or nil
end

function Items.IsItemEntry(entry)
    return entry == POTION_ENTRY or EntryItem(entry) ~= nil
end

-- Reads an item's cooldown. Returns start, duration, enable, or "secret" if the game hid it.
local function ReadCooldown(itemID)
    if not GetItemCooldown then
        return nil
    end
    local start, duration, enable = GetItemCooldown(itemID)
    if ns.IsSecret(start) or ns.IsSecret(duration) or ns.IsSecret(enable) then
        return "secret"
    end
    return start, duration, enable
end

-- (onCooldown, sure, start, duration) from one read; enable 0 means the cooldown starts when
-- combat ends, so it's on cooldown with no timer yet.
local function StateOf(start, duration, enable)
    if start == "secret" then
        return nil, false
    end
    if enable == 0 or enable == false then
        return (start or 0) > 0, true
    end
    if start and duration and start > 0 and duration > ITEM_GCD then
        return true, true, start, duration
    end
    return false, true
end

local function PotionState(previous)
    local candidates, seen = {}, {}
    local function Consider(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            candidates[#candidates + 1] = itemID
        end
    end
    Consider(ns.db.cdLastPotion)
    for itemID in pairs(potionsInBags) do
        Consider(itemID)
    end
    for _, itemID in ipairs(ns.db.cdPotionItems) do
        Consider(itemID)
    end
    local unsure = false
    for _, itemID in ipairs(candidates) do
        local onCooldown, sure, start, duration = StateOf(ReadCooldown(itemID))
        if not sure then
            unsure = true
        elseif onCooldown then
            ns.db.cdLastPotion = itemID
            return true, true, start, duration
        end
    end
    if unsure then
        return previous, false
    end
    return false, true
end

-- Is the entry on cooldown? Returns (onCooldown, sure, start, duration) like CooldownState in
-- Cooldowns.lua; start and duration are plain numbers for SetCooldown, or nil for no timer.
function Items.CooldownState(entry, previous)
    if entry == POTION_ENTRY then
        return PotionState(previous)
    end
    local onCooldown, sure, start, duration = StateOf(ReadCooldown(EntryItem(entry)))
    if not sure then
        return previous, false
    end
    return onCooldown, true, start, duration
end

function Items.Name(entry)
    if entry == POTION_ENTRY then
        local names = {}
        for _, itemID in ipairs(ns.db.cdPotionItems) do
            names[#names + 1] = ItemName(itemID)
        end
        return #names > 0 and ("Potions (" .. table.concat(names, ", ") .. ")") or "Potions"
    end
    return ItemName(EntryItem(entry))
end

function Items.Icon(entry)
    if entry == POTION_ENTRY then
        local itemID = ns.db.cdLastPotion or next(potionsInBags) or ns.db.cdPotionItems[1]
        return itemID and ItemIcon(itemID) or POTION_ICON
    end
    return ItemIcon(EntryItem(entry))
end

-- Spell IDs of the entry's use effects: the auras they give count as "active".
function Items.UseSpells(entry)
    local spells = {}
    local itemIDs = entry == POTION_ENTRY and ns.db.cdPotionItems or { EntryItem(entry) }
    for _, itemID in ipairs(itemIDs) do
        spells[#spells + 1] = UseSpell(itemID)
    end
    return spells
end

-- An item dropped on the Cooldowns tab. Returns the entry to track, or nil and why not.
function Items.Add(itemID)
    if not UseSpell(itemID) then
        return nil, ItemName(itemID) .. " has no Use: effect, so it has no cooldown to track."
    end
    if IsPotion(itemID) then
        local potions = ns.db.cdPotionItems
        for _, known in ipairs(potions) do
            if known == itemID then
                return POTION_ENTRY
            end
        end
        potions[#potions + 1] = itemID
        ns.Print("tracking Potions; " .. ItemName(itemID) .. "'s buff will show as active.")
        return POTION_ENTRY
    end
    return "item:" .. itemID
end

-- Called when an entry is untracked: unticking Potions forgets the special-case potions too.
function Items.Forget(entry)
    if entry == POTION_ENTRY then
        wipe(ns.db.cdPotionItems)
    end
end

-- Our cast of spellID: if it's a potion's use spell, remember that potion as the cooldown source.
function Items.OnCast(spellID)
    for itemID, useSpell in pairs(potionsInBags) do
        if useSpell == spellID then
            ns.db.cdLastPotion = itemID
            return
        end
    end
end

-- Finds the potions in the bags (on login and whenever the bags change).
function Items.ScanBags()
    wipe(potionsInBags)
    if not (C_Container and C_Container.GetContainerNumSlots) then
        return
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and not potionsInBags[itemID] and IsPotion(itemID) then
                potionsInBags[itemID] = UseSpell(itemID) or 0
            end
        end
    end
end

-- /catnip item <itemID or link>: why an item is or isn't treated as a potion.
ns.commands.item = function(arg)
    local itemID = tonumber(arg) or tonumber(arg and arg:match("item:(%d+)"))
    if not itemID then
        ns.Print("usage: /catnip item <item ID> (or shift-click an item into the chat line)")
        return
    end
    local _, _, _, _, _, classID, subClassID = GetInfoInstant(itemID)
    local start, duration, enable = ReadCooldown(itemID)
    ns.Print(string.format("%s: class %s, subclass %s, use spell %s, potion %s, cooldown %s/%s/%s",
        ItemName(itemID), tostring(classID), tostring(subClassID), tostring(UseSpell(itemID)),
        tostring(IsPotion(itemID)), tostring(start), tostring(duration), tostring(enable)))
end

ns.OnLoad(function()
    ns.db.cdPotionItems = ns.db.cdPotionItems or {} -- potions whose buff counts as Potions being active
end)
