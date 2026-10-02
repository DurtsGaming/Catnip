-- Cooldown widget: a box, separate from the HUD, holding icons for the non-rotational cooldowns the
-- player picks in the settings (Cooldowns tab), in their priority order. An icon only shows while
-- its ability is on cooldown (greyed out) or its buff is up (the buff's icon in colour, with thin
-- yellow dashes running clockwise around its border); both show the time left. Visible icons pack
-- together in priority order. The box moves and resizes with the HUD's unlock mode: drag it to move
-- it, drag its corners to resize it.
--
-- Combat restrictions (see docs/api-research.md):
--   * Cooldowns: isActive and isOnGCD stay readable in combat, so we know when to show the grey
--     icon. The timing is secret, so it goes to a Cooldown frame as a duration object and Blizzard
--     draws the countdown number.
--   * Buffs and debuffs: secret in combat, so each icon gets two AuraContainers (our buff on us, our
--     debuff on the target, e.g. Growl's taunt), which Blizzard shows over the grey icon while the
--     aura is up. We never learn that it's up, so an icon whose buff is up but whose ability isn't
--     on cooldown only shows out of combat.
--   * Buff IDs: usually the ability's own, but not always (Skysight gives Elemental Blessing). When a
--     tracked ability is cast out of combat, we look for a buff or debuff of ours that started then
--     and remember it (CatnipDB.cdBuffs, by ability name).
--
-- Tracked entries (CatnipDB.cdTracked, in priority order) are spell IDs (numbers) or item entries
-- (strings: "potion", "item:<id>"), which CooldownItems.lua handles.
local addonName, ns = ...

local SLOT = 64 -- icons are built at this size, then scaled to fit the box
local OUTLINE = 1.12 -- dashed border size relative to the icon (the dashes sit just outside it); each icon's cell fits the border
local OUTLINE_COLOR = { 1, 0.82, 0.1 }
local STEP_SECONDS = 0.3 -- one pass through the border's flipbook moves each dash on to the next one's spot
local LEARN_DELAY = 0.3 -- after a cast, when to look for the buff it gave
local LEARN_WINDOW = 0.5 -- how close to the cast the buff must have started, in seconds
local ICON_CROP = 0.08 -- trims the border baked into spell icons
local MIN_SIZE = 24
local DEFAULTS = { cdX = 0, cdY = -330, cdWidth = 220, cdHeight = 48, cdAlign = "TOP", cdEnabled = true }

for key, value in pairs(DEFAULTS) do
    ns.defaults[key] = value
end

local Cooldowns = {}
ns.Cooldowns = Cooldowns

local widget = CreateFrame("Frame", "CatnipCooldowns", UIParent)
widget:SetMovable(true)
widget:SetResizable(true)
widget:SetClampedToScreen(true)
if widget.SetDontSavePosition then
    widget:SetDontSavePosition(true) -- saved in CatnipDB instead
end
if widget.SetResizeBounds then
    widget:SetResizeBounds(MIN_SIZE, MIN_SIZE)
elseif widget.SetMinResize then
    widget:SetMinResize(MIN_SIZE, MIN_SIZE)
end

local Items = ns.CooldownItems
local slots = {} -- by entry; kept when untracked, so their AuraContainers are reused
local unlocked = false

-- Icons -------------------------------------------------------------------------------------------

local function CreateIcon(owner)
    local icon = owner:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(owner)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    return icon
end

-- Blizzard's countdown number, a little bigger than its default, for a timer on frame.
local function CreateTimer(frame)
    local timer = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    timer:ClearAllPoints() -- the template pins itself to its parent's edges; re-pin explicitly
    timer:SetAllPoints(frame)
    timer:SetDrawSwipe(false)
    timer:SetDrawEdge(false)
    timer:SetDrawBling(false)
    timer:SetHideCountdownNumbers(false)
    if timer.SetCountdownFont then
        pcall(timer.SetCountdownFont, timer, "GameFontHighlightHugeOutline")
    end
    return timer
end

-- The buff's look, on the AuraContainer button Blizzard shows while the buff is up. Must be static
-- after this runs (the button becomes off-limits to our code), so the moving dashes are a FlipBook
-- animation: square_dashed holds 16 frames, each with the dashes a little further clockwise.
local function StyleActiveButton(button)
    ns.HideAuraButtonArt(button)

    button:SetIcon(CreateIcon(button)) -- Blizzard fills in the buff's icon

    local spinner = CreateFrame("Frame", nil, button)
    spinner:SetSize(SLOT * OUTLINE, SLOT * OUTLINE)
    spinner:SetPoint("CENTER")
    local outline = spinner:CreateTexture(nil, "OVERLAY")
    outline:SetAllPoints(spinner)
    outline:SetTexture(ns.MEDIA .. "square_dashed")
    outline:SetVertexColor(OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3], 1)
    local spin = outline:CreateAnimationGroup()
    spin:SetLooping("REPEAT")
    local frames = spin:CreateAnimation("FlipBook")
    frames:SetFlipBookRows(4)
    frames:SetFlipBookColumns(4)
    frames:SetFlipBookFrames(16)
    frames:SetFlipBookFrameWidth(0) -- 0: worked out from rows and columns
    frames:SetFlipBookFrameHeight(0)
    frames:SetDuration(STEP_SECONDS)
    -- Started once and left looping: frames on these buttons can't take OnShow/OnHide handlers
    -- ("blocked by secret aspects", seen 2026-10-01). Blood in the Water does the same.
    spin:Play()

    local timer = CreateTimer(button)
    timer:SetFrameLevel(spinner:GetFrameLevel() + 1) -- number above the outline
    button:SetDurationCooldown(timer) -- Blizzard runs it with the buff's real (secret) timing
end

local RequestUpdate -- defined below

-- Some abilities change with your form: Feral Charge is one spellbook entry that becomes Feral
-- Charge (Cat) or (Bear), each with its own spell ID. We list and save the base spell, and check
-- the cooldown and icon of the version the current form uses.
local function BaseSpell(spellID)
    local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID)
    return (type(base) == "number" and base > 0) and base or spellID
end

local function CurrentSpell(spellID)
    local ok, current = pcall(C_Spell.GetOverrideSpell or function() end, spellID)
    return (ok and type(current) == "number" and current > 0) and current or spellID
end

-- The auras that count as "active" for an ability: its own spell ID, plus any aura learned for it.
local function BuffIDs(spellID)
    local ids = { spellID }
    local learned = ns.db.cdBuffs[C_Spell.GetSpellName(spellID) or ""]
    if learned and learned ~= spellID then
        ids[2] = learned
    end
    return ids
end

-- Entries -----------------------------------------------------------------------------------------

local function EntryName(entry)
    if Items.IsItemEntry(entry) then
        return Items.Name(entry)
    end
    return C_Spell.GetSpellName(entry) or ("spell " .. tostring(entry))
end

local function EntryIcon(entry)
    if Items.IsItemEntry(entry) then
        return Items.Icon(entry)
    end
    return C_Spell.GetSpellTexture(CurrentSpell(entry))
end

-- Aura IDs that make the entry "active": for items, the auras of their use effects. Never empty:
-- an AuraContainer with no IDs to match might match everything, so a placeholder stands in.
-- Abilities shown for their cooldown only, never as active: Faerie Fire's debuff (~40s) would keep
-- its icon lit long after the 6s Cat/Bear cooldown that matters.
local COOLDOWN_ONLY_NAMES = { ["Faerie Fire"] = true }

local function EntryAuraIDs(entry)
    if not Items.IsItemEntry(entry) and COOLDOWN_ONLY_NAMES[C_Spell.GetSpellName(entry) or ""] then
        return { 1 } -- spell 1 is never an aura: nothing counts as active
    end
    local spells = Items.IsItemEntry(entry) and Items.UseSpells(entry) or { entry }
    local ids = {}
    for _, spellID in ipairs(spells) do
        for _, id in ipairs(BuffIDs(spellID)) do
            ids[#ids + 1] = id
        end
    end
    if #ids == 0 then
        ids[1] = 1 -- spell 1 is never an aura
    end
    return ids
end

-- Re-points every icon's AuraContainers, after an aura is learned or a potion is added.
local function RefreshAuraFilters()
    for entry, slot in pairs(slots) do
        for _, auras in ipairs(slot.auras) do
            auras.SetSpellIDs(EntryAuraIDs(entry))
        end
    end
end

local function CreateSlot(entry)
    local slot = CreateFrame("Frame", nil, widget)
    slot:SetSize(SLOT, SLOT)
    slot:SetFrameLevel(widget:GetFrameLevel() + 1)
    slot:Hide()

    slot.icon = CreateIcon(slot) -- texture set on every update: it follows the form (CurrentSpell), or the last potion
    slot.icon:SetDesaturated(true)

    slot.timer = CreateTimer(slot)
    slot.timer:SetScript("OnCooldownDone", function()
        slot.onCooldown = false -- so an unsure read can't keep it "on cooldown"
        RequestUpdate()
    end)

    -- "Active" is our buff on us (Barkskin) or our debuff on the target (Growl's taunt, Faerie Fire):
    -- one AuraContainer for each, both drawn the same way.
    slot.auras = {}
    if ns.HAS_AURA_CONTAINER then
        for _, watch in ipairs({ { unit = "player", filter = "HELPFUL" }, { unit = "target", filter = "HARMFUL" } }) do
            slot.auras[#slot.auras + 1] = ns.CreateAuraContainer({
                label = "Cooldown " .. EntryName(entry) .. " (" .. watch.unit .. ")",
                unit = watch.unit,
                filter = watch.filter,
                spellIDs = EntryAuraIDs(entry),
                width = SLOT,
                height = SLOT,
                parent = slot, -- moves, scales and hides with the slot
                relativeTo = slot,
                level = 5,
                initialize = StyleActiveButton,
            })
        end
    end
    slots[entry] = slot
    return slot
end

-- State ---------------------------------------------------------------------------------------------

local function GcdRunning()
    local info = C_Spell.GetSpellCooldown(ns.GCD_SPELL)
    local active = info and info.isActive
    return active == true -- secret or missing counts as not running
end

-- Is the ability on a real cooldown (not just the GCD)? Returns (onCooldown, sure): when sure is
-- false we couldn't tell and kept `previous`, and the timer shouldn't be restarted from this read.
-- isOnGCD isn't trustworthy: EllesmereUI found it nil outside SPELL_UPDATE_COOLDOWN, and here it
-- seems to turn on for every spell whenever any spell starts the GCD (seen 2026-10-01: Enrage's
-- icon vanished on the next cast). So an active cooldown with no GCD running counts as real; while
-- the GCD runs, only isOnGCD == false is believed.
local function CooldownState(spellID, previous)
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then
        return false, true
    end
    local active, onGCD = info.isActive, info.isOnGCD
    if ns.IsSecret(active) then
        return previous, false
    end
    if active == nil then -- older field set: fall back to the numbers, readable out of combat
        local duration = info.duration
        if duration == nil or ns.IsSecret(duration) then
            return previous, false
        end
        return duration > 1.5, true
    end
    if not active then
        return false, true
    end
    if onGCD == false or not GcdRunning() then
        return true, true
    end
    return previous, false
end

-- While the GCD hides what's really on cooldown, look again once it's over (its end fires no event).
local recheckPending = false
local function RecheckAfterGcd()
    if recheckPending then
        return
    end
    recheckPending = true
    C_Timer.After(1.6, function() -- longer than any GCD
        recheckPending = false
        RequestUpdate()
    end)
end

local function StartTimer(timer, spellID)
    if C_Spell.GetSpellCooldownDuration and timer.SetCooldownFromDurationObject then
        local ok = pcall(function()
            local duration = C_Spell.GetSpellCooldownDuration(spellID)
            if duration then
                timer:SetCooldownFromDurationObject(duration)
            end
        end)
        if ok then
            return
        end
    end
    local info = C_Spell.GetSpellCooldown(spellID)
    if info and info.startTime and not ns.IsSecret(info.startTime) then
        timer:SetCooldown(info.startTime, info.duration)
    end
end

-- Out of combat we can see the buff ourselves; in combat only the AuraContainer can.
local function BuffSeenUp(entry)
    for _, buffID in ipairs(EntryAuraIDs(entry)) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, buffID)
        if ok and aura ~= nil and not ns.IsSecret(aura) then
            return true
        end
    end
    return false
end

-- Learning buffs ----------------------------------------------------------------------------------

local IGNORED_BUFFS = { [16870] = true } -- Clearcasting: procs on its own, could start at any cast

-- After a tracked ability is cast (out of combat), find our buff on us or debuff on the target that
-- started with it. Nothing to learn if one of them has the ability's own spell ID: that already matches.
local function LearnBuff(spellID, castTime)
    if InCombatLockdown() or not C_UnitAuras.GetAuraDataByIndex then
        return
    end
    local best, bestGap
    for _, watch in ipairs({ { "player", "HELPFUL" }, { "target", "HARMFUL" } }) do
        for index = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(watch[1], index, watch[2])
            if not aura or ns.IsSecret(aura) then
                break
            end
            local auraID, duration, expires = aura.spellId, aura.duration, aura.expirationTime
            if aura.sourceUnit == "player" and auraID == spellID then
                return
            end
            if aura.sourceUnit == "player" and auraID and not IGNORED_BUFFS[auraID]
                and duration and duration > 0 and expires then
                local gap = math.abs(expires - duration - castTime)
                if gap <= LEARN_WINDOW and (not bestGap or gap < bestGap) then
                    best, bestGap = auraID, gap
                end
            end
        end
    end
    if not best then
        ns.Debug("Cooldowns: no new buff or debuff found after", C_Spell.GetSpellName(spellID))
        return
    end
    local name = C_Spell.GetSpellName(spellID) or ""
    if ns.db.cdBuffs[name] ~= best then
        ns.db.cdBuffs[name] = best
        ns.Debug("Cooldowns:", name, "gives aura", C_Spell.GetSpellName(best), best)
        RefreshAuraFilters()
        RequestUpdate()
    end
end

-- Layout ----------------------------------------------------------------------------------------------

-- The largest square cell that fits `count` icons in the box, and how many columns that takes.
local function CellSize(count, width, height)
    local best, bestColumns = 0, 1
    for columns = 1, count do
        local rows = math.ceil(count / columns)
        local cell = math.min(width / columns, height / rows)
        if cell > best then
            best, bestColumns = cell, columns
        end
    end
    return best, bestColumns
end

-- Packs the shown icons into the box in priority order, left to right, then top to bottom, gathered
-- at the alignment point (CatnipDB.cdAlign: one of the nine anchor points, e.g. "TOP" = across the
-- top, each row centred). Sized so every tracked ability fits at once, so icons don't change size
-- as they come and go.
local function Arrange()
    local tracked = ns.db.cdTracked
    local width, height = widget:GetWidth(), widget:GetHeight()
    local cell, columns = CellSize(math.max(#tracked, 1), width, height)
    local scale = math.max(cell / OUTLINE, 1) / SLOT
    local shown = {}
    for _, entry in ipairs(tracked) do
        local slot = slots[entry]
        if slot and slot:IsShown() then
            shown[#shown + 1] = slot
        end
    end
    local align = ns.db.cdAlign or DEFAULTS.cdAlign
    local horizontal = align:find("LEFT") and "LEFT" or align:find("RIGHT") and "RIGHT" or "CENTER"
    local vertical = align:find("TOP") and "TOP" or align:find("BOTTOM") and "BOTTOM" or "MIDDLE"
    local rows = math.ceil(#shown / columns)
    for i, slot in ipairs(shown) do
        local row, column = math.floor((i - 1) / columns), (i - 1) % columns
        local inRow = math.min(columns, #shown - row * columns)
        local x, y
        if horizontal == "LEFT" then
            x = (column + 0.5) * cell
        elseif horizontal == "RIGHT" then
            x = width - (inRow - column - 0.5) * cell
        else
            x = width / 2 + (column - (inRow - 1) / 2) * cell
        end
        if vertical == "TOP" then
            y = (row + 0.5) * cell
        elseif vertical == "BOTTOM" then
            y = height - (rows - row - 0.5) * cell
        else
            y = height / 2 + (row - (rows - 1) / 2) * cell
        end
        slot:SetScale(scale)
        slot:ClearAllPoints()
        -- Offsets are in the slot's own (scaled) units.
        slot:SetPoint("CENTER", widget, "TOPLEFT", x / scale, -y / scale)
    end
end

local function Update()
    for _, slot in pairs(slots) do
        slot.wanted = false
    end
    for _, entry in ipairs(ns.db.cdTracked) do
        local slot = slots[entry] or CreateSlot(entry)
        slot.wanted = true
        slot.icon:SetTexture(EntryIcon(entry))
        local isItem = Items.IsItemEntry(entry)
        local current = not isItem and CurrentSpell(entry)
        local onCooldown, sure, start, duration
        if isItem then
            onCooldown, sure, start, duration = Items.CooldownState(entry, slot.onCooldown)
        else
            onCooldown, sure = CooldownState(current, slot.onCooldown)
            if not sure then
                RecheckAfterGcd()
            end
        end
        onCooldown = onCooldown and true or false
        if onCooldown ~= (slot.onCooldown or false) then
            local info = current and C_Spell.GetSpellCooldown(current)
            ns.Debug("Cooldowns:", EntryName(entry), onCooldown and "on cooldown" or "ready",
                "| sure:", sure, "isActive:", info and info.isActive, "isOnGCD:", info and info.isOnGCD,
                "GCD running:", GcdRunning(), "in combat:", InCombatLockdown())
        end
        if onCooldown and sure then
            if not isItem then
                StartTimer(slot.timer, current)
            elseif start then
                slot.timer:SetCooldown(start, duration)
            else
                slot.timer:Clear() -- waiting for combat to end before it starts
            end
        elseif not onCooldown and slot.onCooldown then
            slot.timer:Clear()
        end
        slot.onCooldown = onCooldown
        slot:SetShown(unlocked or onCooldown or BuffSeenUp(entry))
    end
    for _, slot in pairs(slots) do
        if not slot.wanted then
            slot:Hide()
        end
    end
    Arrange()
end

-- Coalesces bursts of events (and cooldowns finishing) into one update on the next frame.
local pending = false
function RequestUpdate()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0, function()
        pending = false
        Update()
    end)
end

-- Moving and resizing -----------------------------------------------------------------------------

-- Position is the box centre's offset from the screen centre, like the HUD's.
local function ApplyLayout()
    local db = ns.db
    widget:SetShown(db.cdEnabled)
    widget:SetSize(db.cdWidth, db.cdHeight)
    widget:ClearAllPoints()
    widget:SetPoint("CENTER", UIParent, "CENTER", db.cdX, db.cdY)
end

local function SaveLayout()
    local cx, cy = widget:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local db = ns.db
    db.cdX, db.cdY = math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
    db.cdWidth, db.cdHeight = math.floor(widget:GetWidth() + 0.5), math.floor(widget:GetHeight() + 0.5)
    ApplyLayout()
    ns.SettingsChanged()
end

-- Box centre's offset from the screen centre, and its size (from the settings sliders).
function Cooldowns.SetLayout(x, y, width, height)
    local db = ns.db
    db.cdX, db.cdY = x, y
    db.cdWidth, db.cdHeight = math.max(MIN_SIZE, width), math.max(MIN_SIZE, height)
    ApplyLayout()
    ns.SettingsChanged()
end
Cooldowns.MIN_SIZE = MIN_SIZE

-- Where the shown icons gather: "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT",
-- "BOTTOM" or "BOTTOMRIGHT".
function Cooldowns.SetAlignment(point)
    ns.db.cdAlign = point
    Arrange()
    ns.SettingsChanged()
end

-- Turns the whole Cooldown Frame on or off (Edit Mode's checkbox).
function Cooldowns.SetEnabled(enabled)
    ns.db.cdEnabled = enabled
    ApplyLayout()
    ns.SettingsChanged()
end

function Cooldowns.ResetLayout()
    local db = ns.db
    db.cdX, db.cdY, db.cdWidth, db.cdHeight = DEFAULTS.cdX, DEFAULTS.cdY, DEFAULTS.cdWidth, DEFAULTS.cdHeight
    ApplyLayout()
    ns.SettingsChanged()
end

-- Shown while the HUD is unlocked: catches the mouse only then. Clicking it opens Cooldowns → Layout.
local overlay = ns.CreateUnlockOverlay(widget, "Cooldown Frame", function() ns.OpenSettings("cooldowns") end)

overlay:SetScript("OnDragStart", function()
    widget:StartMoving()
end)
overlay:SetScript("OnDragStop", function()
    widget:StopMovingOrSizing()
    SaveLayout()
end)

-- Invisible grips over the overlay's corner art, which marks where to grab.
for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local grip = CreateFrame("Frame", nil, overlay)
    grip:SetSize(16, 16)
    grip:SetPoint(corner)
    grip:SetFrameLevel(overlay:GetFrameLevel() + 1)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function()
        widget:StartSizing(corner)
    end)
    grip:SetScript("OnMouseUp", function()
        widget:StopMovingOrSizing()
        SaveLayout()
    end)
end

widget:SetScript("OnSizeChanged", function()
    if ns.db then
        Arrange()
    end
end)

-- Follows the HUD's unlock mode; while unlocked every tracked icon shows, so the box can be fitted.
ns.OnSettingsChanged(function()
    if not ns.db or ns.IsHudUnlocked() == unlocked then
        return
    end
    unlocked = ns.IsHudUnlocked()
    overlay:SetShown(unlocked)
    Update()
end)

-- Choosing abilities (used by the settings window) ------------------------------------------------

-- Calls visit(line, itemType, spellID) for every spellbook entry, on every skill line.
local function WalkSpellbook(visit)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum.SpellBookItemType) then
        return false
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        if line and line.itemIndexOffset and line.numSpellBookItems then
            for index = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(index, bank)
                visit(line, itemType, spellID or actionID)
            end
        end
    end
    return true
end

-- Why a spellbook entry isn't offered, or nil if it is.
-- Spells whose cooldown only exists in some forms, offered even when we haven't seen it yet:
-- Faerie Fire becomes Faerie Fire (Feral), which has a cooldown, in Cat and Bear Form.
local FORM_COOLDOWN_NAMES = { ["Faerie Fire"] = true }

-- Does the spell have a cooldown of its own (not just the GCD), in any form? Checks the spellbook
-- entry, its base spell and the current form's version; a form version seen with a cooldown is
-- remembered (CatnipDB.cdFormCooldowns), so the spell stays listed in forms where it has none.
local function HasCooldown(spellID)
    local base = BaseSpell(spellID)
    if ns.db.cdFormCooldowns[base] or FORM_COOLDOWN_NAMES[C_Spell.GetSpellName(base) or ""] then
        return true
    end
    if not GetSpellBaseCooldown then
        return true -- can't tell, so offer it
    end
    for _, id in ipairs({ spellID, base, CurrentSpell(spellID) }) do
        local cooldown = GetSpellBaseCooldown(id)
        if cooldown == nil or cooldown > 0 then
            if id ~= base then
                ns.db.cdFormCooldowns[base] = true
            end
            return true
        end
    end
    return false
end

local function SkipReason(line, itemType, spellID)
    if line.shouldHide then
        return "hidden line"
    elseif line.offSpecID and line.offSpecID ~= 0 then
        return "off-spec line"
    elseif itemType ~= Enum.SpellBookItemType.Spell or not spellID then
        return "not a spell"
    elseif C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID) then
        return "passive"
    end
    if not HasCooldown(spellID) then
        return "no cooldown"
    end
end

-- Spells in the spellbook that have a cooldown of their own (not just the GCD), as base spells.
-- One per name: the spellbook can list several ranks of a spell, and the later one is the higher rank.
local function KnownCooldownSpells()
    local spells, indexByName = {}, {}
    local function Add(spellID)
        spellID = BaseSpell(spellID)
        local name = C_Spell.GetSpellName(spellID) or tostring(spellID)
        local index = indexByName[name] or #spells + 1
        indexByName[name] = index
        spells[index] = spellID
    end
    WalkSpellbook(function(line, itemType, spellID)
        if not SkipReason(line, itemType, spellID) then
            Add(spellID)
        end
    end)
    return spells
end

-- /catnip spells: what the spellbook walk sees, to find out why an ability isn't offered.
ns.commands.spells = function()
    local walked = WalkSpellbook(function(line, itemType, spellID)
        local name = spellID and C_Spell.GetSpellName(spellID) or "?"
        local reason = SkipReason(line, itemType, spellID)
        ns.Print(string.format("  [%s] %s (%s): %s", tostring(line.name), name, tostring(spellID),
            reason or "offered"))
    end)
    if not walked then
        ns.Print("no C_SpellBook API in this client")
    end
end

-- Tracked spells are saved by ID, and each rank on Forever has its own. When the list offers a
-- different rank of a tracked spell (a newly learned one), switch to it. Also turns form versions
-- saved before we tracked base spells (Feral Charge (Cat)) into their base, dropping duplicates.
local function FollowRanks(known)
    local tracked = ns.db.cdTracked
    for i = #tracked, 1, -1 do
        local base = type(tracked[i]) == "number" and BaseSpell(tracked[i]) or tracked[i]
        if base ~= tracked[i] then
            ns.Debug("Cooldowns: tracking base spell", C_Spell.GetSpellName(base), "instead of", tracked[i])
            table.remove(tracked, i)
            if not Cooldowns.IsTracked(base) then
                table.insert(tracked, i, base)
            end
            RequestUpdate()
        end
    end
    local byName = {}
    for _, spellID in ipairs(known) do
        byName[C_Spell.GetSpellName(spellID) or ""] = spellID
    end
    for i, spellID in ipairs(tracked) do
        local newRank = type(spellID) == "number" and byName[C_Spell.GetSpellName(spellID) or ""]
        if newRank and newRank ~= spellID and not Cooldowns.IsTracked(newRank) then
            ns.Debug("Cooldowns: following new rank of", C_Spell.GetSpellName(spellID), spellID, "->", newRank)
            tracked[i] = newRank
            RequestUpdate()
        end
    end
end

-- What to list: tracked entries first in priority order (items included), then the untracked
-- abilities alphabetically. Each is { entry, name, icon, tracked }.
function Cooldowns.Candidates()
    local known = KnownCooldownSpells()
    FollowRanks(known) -- so a tracked old rank and its new rank don't both show
    local list, listed = {}, {}
    local function Add(entry, tracked)
        listed[entry] = true
        list[#list + 1] = { entry = entry, name = EntryName(entry), icon = EntryIcon(entry), tracked = tracked }
    end
    for _, entry in ipairs(ns.db.cdTracked) do
        Add(entry, true)
    end
    local untracked = {}
    for _, spellID in ipairs(known) do
        if not listed[spellID] then
            untracked[#untracked + 1] = spellID
            listed[spellID] = true
        end
    end
    table.sort(untracked, function(a, b)
        return (C_Spell.GetSpellName(a) or "") < (C_Spell.GetSpellName(b) or "")
    end)
    for _, spellID in ipairs(untracked) do
        Add(spellID, false)
    end
    return list
end

function Cooldowns.IsTracked(entry)
    for _, tracked in ipairs(ns.db.cdTracked) do
        if tracked == entry then
            return true
        end
    end
    return false
end

-- Newly tracked entries go last (lowest priority). Untracked items drop off the list entirely.
function Cooldowns.SetTracked(entry, track)
    local tracked = ns.db.cdTracked
    for i = #tracked, 1, -1 do
        if tracked[i] == entry then
            table.remove(tracked, i)
        end
    end
    if track then
        tracked[#tracked + 1] = entry
    else
        Items.Forget(entry)
    end
    RefreshAuraFilters()
    Update()
    ns.SettingsChanged()
end

-- An item dropped on the Cooldowns tab's drop box.
function Cooldowns.AddItem(itemID)
    local entry, problem = Items.Add(itemID)
    if not entry then
        ns.Print(problem)
        return
    end
    if not Cooldowns.IsTracked(entry) then
        ns.db.cdTracked[#ns.db.cdTracked + 1] = entry
    end
    RefreshAuraFilters() -- a new special-case potion adds its buff to Potions
    Update()
    ns.SettingsChanged()
end

-- Moves the tracked ability at position `from` to position `to` (1 = highest priority).
function Cooldowns.Move(from, to)
    local tracked = ns.db.cdTracked
    if from == to or not tracked[from] then
        return
    end
    to = math.max(1, math.min(#tracked, to))
    table.insert(tracked, to, table.remove(tracked, from))
    Update()
    ns.SettingsChanged()
end

-- Wiring ------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ns.TryRegisterEvent(events, "UPDATE_SHAPESHIFT_FORM") -- form versions of a spell (CurrentSpell)
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("BAG_UPDATE_DELAYED")

-- Is spellID the use effect of a tracked item (or special-case potion)?
local function IsTrackedItemSpell(spellID)
    for _, entry in ipairs(ns.db.cdTracked) do
        if Items.IsItemEntry(entry) then
            for _, useSpell in ipairs(Items.UseSpells(entry)) do
                if useSpell == spellID then
                    return true
                end
            end
        end
    end
    return false
end

events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not spellID or ns.IsSecret(spellID) then
            return
        end
        Items.OnCast(spellID)
        local base = BaseSpell(spellID)
        local learnAs = (Cooldowns.IsTracked(base) and base) or (IsTrackedItemSpell(spellID) and spellID)
        if learnAs and not InCombatLockdown() then
            local castTime = GetTime()
            C_Timer.After(LEARN_DELAY, function() LearnBuff(learnAs, castTime) end)
        end
        return
    end
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" then
        Items.ScanBags()
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        Update() -- right away: isOnGCD is most trustworthy inside this event
        return
    end
    if event == "SPELLS_CHANGED" then
        FollowRanks(KnownCooldownSpells())
        ns.SettingsChanged() -- the settings list may need new spells
    end
    RequestUpdate()
end)

ns.OnLoad(function()
    ns.db.cdTracked = ns.db.cdTracked or {}
    ns.db.cdBuffs = ns.db.cdBuffs or {} -- ability name -> buff spell ID, when they differ
    ns.db.cdFormCooldowns = ns.db.cdFormCooldowns or {} -- base spell ID -> true: has a cooldown in some form
    ApplyLayout()
    ns.Debug("Cooldowns: tracking", #ns.db.cdTracked, "| countdownForCooldowns CVar:", GetCVar("countdownForCooldowns"))
end)
