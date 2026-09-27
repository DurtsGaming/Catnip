-- Bridge to Blizzard's Cooldown Manager (CDM). Its frames are updated by Blizzard's own code, which
-- can see combat data we can't. In combat an item's spell ID stays readable and whether it's shown
-- tracks its buff, even though the aura details are secret (verified in Forever).
local addonName, ns = ...

local BUFF_VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local ALL_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

local CDM = {}
ns.CDM = CDM

-- Weak-keyed, so we never write our own fields onto Blizzard's frames.
local hooked = setmetatable({}, { __mode = "k" })
local callbacks = {}
local pending = false

-- Reads a field without erroring if the table itself is secret.
local function Field(tbl, key)
    if tbl == nil or ns.IsSecret(tbl) then
        return tbl
    end
    return tbl[key]
end

local function SpellOf(item)
    local spellID = Field(item.cooldownInfo, "spellID")
    if ns.IsSecret(spellID) then
        return nil
    end
    return spellID
end

-- Blizzard updates its items inside its own event handlers; check once they've finished.
local function NotifySoon()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0, function()
        pending = false
        for _, callback in ipairs(callbacks) do
            callback()
        end
    end)
end

local function HookItem(item)
    if hooked[item] then
        return
    end
    hooked[item] = true
    item:HookScript("OnShow", NotifySoon)
    item:HookScript("OnHide", NotifySoon)
end

-- Is the CDM buff item for spellID showing (i.e. its buff active)? nil if the CDM isn't tracking it.
function CDM.IsActive(spellID)
    local found = false
    for _, viewerName in ipairs(BUFF_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer then
            for _, item in ipairs({ viewer:GetChildren() }) do
                HookItem(item)
                if SpellOf(item) == spellID then
                    -- Pooled frames can hold stale info while hidden, so any shown match wins.
                    if item:IsShown() then
                        return true
                    end
                    found = true
                end
            end
        end
    end
    return found and false or nil
end

-- Runs callback whenever tracked buff state may have changed.
function CDM.OnChange(callback)
    callbacks[#callbacks + 1] = callback
end

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_AURA", "player", "target")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", NotifySoon)

-- /catnip cdm: list what each viewer is tracking and what's readable right now.
local function DescribeItem(item)
    local spellID = Field(item.cooldownInfo, "spellID")
    local name
    if spellID and not ns.IsSecret(spellID) then
        name = C_Spell.GetSpellName(spellID)
    end
    return string.format("%s (spell %s, cdID %s) aura: %s shown: %s",
        ns.Describe(name), ns.Describe(spellID), ns.Describe(item.cooldownID),
        ns.Describe(item.auraInstanceID), ns.Describe(item:IsShown()))
end

ns.commands.cdm = function()
    ns.Print("Cooldown Manager items (in combat: " .. tostring(InCombatLockdown()) .. "):")
    for _, viewerName in ipairs(ALL_VIEWERS) do
        local viewer = _G[viewerName]
        if not viewer then
            ns.Print(viewerName .. ": not found")
        else
            local children = { viewer:GetChildren() }
            ns.Print(string.format("%s: %d items, viewer shown: %s", viewerName, #children, tostring(viewer:IsShown())))
            for _, item in ipairs(children) do
                if item.cooldownID or item.cooldownInfo then
                    ns.Print("  " .. DescribeItem(item))
                end
            end
        end
    end
end
