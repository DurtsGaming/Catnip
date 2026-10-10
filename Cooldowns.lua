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
-- Tracked entries (CatnipDB.chars[character].cdTracked, in priority order) are spell IDs (numbers) or item entries
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
local MIN_ICON_SIZE, MAX_ICON_SIZE = 16, 128
local DEFAULTS = { cdX = 0, cdY = -500, cdWidth = 240, cdHeight = 138, cdAlign = "TOP", cdAlpha = 1, cdActiveAlpha = 1,
    cdIconSize = 40, cdOverflow = "hide", cdEnabled = true }

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
local previewing = false -- Blizzard's Edit Mode is open (Cooldowns.SetPreview)

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

-- Thin yellow dashes running clockwise round `frame`, just outside it: a FlipBook animation
-- (square_dashed holds 16 frames, each with the dashes a little further clockwise), started once and
-- left looping. Returns the frame holding them.
local function AddDashes(frame)
    local spinner = CreateFrame("Frame", nil, frame)
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
    -- Started once and left looping: frames on AuraContainer buttons can't take OnShow/OnHide
    -- handlers ("blocked by secret aspects", seen 2026-10-01). Blood in the Water does the same.
    spin:Play()
    return spinner
end

-- Free of the box's alpha (Inactive opacity, on the widget): active icons have Active opacity of
-- their own, and the outlines are always full strength. Below 100% an active icon is see-through,
-- so a grey cooldown icon under it shows; we can't hide that one instead: in combat we never learn
-- that the buff is up.
local function IgnoreBoxOpacity(frame)
    if frame.SetIgnoreParentAlpha then
        frame:SetIgnoreParentAlpha(true)
    end
end

-- The buff's look, on the AuraContainer button Blizzard shows while the buff is up. Must be static
-- after this runs (the button becomes off-limits to our code), hence AddDashes' looping animation.
local function StyleActiveButton(button)
    ns.HideAuraButtonArt(button) -- its opacity comes from the slot's activeGate
    button:SetIcon(CreateIcon(button)) -- Blizzard fills in the buff's icon
    local spinner = AddDashes(button)

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
    -- They sit in activeGate, a frame of ours free of the box's alpha and carrying Active opacity:
    -- the buttons themselves can't be changed once styled (Rake and Rip's gates do the same).
    slot.activeGate = CreateFrame("Frame", nil, slot)
    slot.activeGate:SetAllPoints()
    IgnoreBoxOpacity(slot.activeGate)
    slot.activeGate:SetAlpha(ns.db and ns.db.cdActiveAlpha or 1)
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
                parent = slot.activeGate, -- moves, scales and hides with the slot
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
-- Whether a spell is on cooldown: ns.CooldownState (SpellTiming.lua).

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
-- Auras can be secret out of combat too (battlegrounds), and then reading them errors instead.
local function LearnBuff(spellID, castTime)
    if InCombatLockdown() or not C_UnitAuras.GetAuraDataByIndex then
        return
    end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local best, bestGap
    for _, watch in ipairs({ { "player", "HELPFUL" }, { "target", "HARMFUL" } }) do
        for index = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, watch[1], index, watch[2])
            if not ok or not aura or ns.IsSecret(aura) then
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

-- Preview -----------------------------------------------------------------------------------------
-- While the settings window is open on the Cooldown tab (out of combat), or either Edit Mode is
-- open, the box shows samples instead of the real icons (owner, 2026-10-09): every tracked icon in
-- priority order (one placeholder when none are), most on cooldown and every fourth from the second
-- active (never a cooldown-only one), each with a looping timer. They're our own frames, so the
-- active look, drawn on an AuraContainer for real, can show too. The real icons hide meanwhile,
-- their AuraContainers with them. In the settings window the box gets the HUD preview's idle
-- outline (Edit Mode's blue frame, faint), and hovering an Abilities row gives its icon the hover
-- one (the same frame at full strength, brightened), matching Preview.lua (owner, 2026-10-09).

local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local IDLE_ALPHA = 0.4 -- Preview.lua's, for outlines not hovered
local GLOW_ALPHA = 0.4 -- Preview.lua's: the additive copy brightening a hovered outline
local samples = {} -- sample icons, by position
local sampleCount = 0 -- how many show (0 while not sampling)
local settingsWanted = false -- the settings window is open on the Cooldown tab
local highlighted -- the entry whose Abilities row is hovered

local function Sampling()
    return previewing or unlocked or (settingsWanted and not InCombatLockdown())
end

-- Edit Mode's blue frame (UnlockOverlay.lua) round `frame`, as Preview.lua outlines the HUD's
-- texts; `hover` adds its additive copy, brightening it.
local function EditModeOutline(frame, hover)
    local look = CreateFrame("Frame", nil, frame)
    look:SetAllPoints()
    ns.ApplyEditModeLook(look)
    if hover then
        local glow = CreateFrame("Frame", nil, frame)
        glow:SetAllPoints()
        ns.ApplyEditModeLook(glow)
        for _, region in ipairs({ glow:GetRegions() }) do
            if region.SetBlendMode then
                region:SetBlendMode("ADD")
            end
        end
        glow:SetAlpha(GLOW_ALPHA)
    end
end

-- The box's outline in the settings preview, full strength whatever the box's Opacity.
local boxOutline = CreateFrame("Frame", nil, widget)
boxOutline:SetAllPoints()
IgnoreBoxOpacity(boxOutline)
EditModeOutline(boxOutline)
boxOutline:SetAlpha(IDLE_ALPHA)
boxOutline:Hide()

-- Runs `timer` round and round over `duration` seconds, `elapsed` of it already gone.
local function Loop(timer, duration, elapsed)
    timer.loop = duration
    timer:SetCooldown(GetTime() - elapsed, duration)
end

local function StopLoop(timer)
    timer.loop = nil
    timer:Clear()
end

local function LoopingTimer(frame)
    local timer = CreateTimer(frame)
    timer:SetScript("OnCooldownDone", function(self)
        if self.loop then
            self:SetCooldown(GetTime(), self.loop)
        end
    end)
    return timer
end

local function CreateSample()
    local sample = CreateFrame("Frame", nil, widget)
    sample:SetSize(SLOT, SLOT)
    sample:SetFrameLevel(widget:GetFrameLevel() + 1)
    sample:Hide()
    -- On cooldown: the grey icon and its time left, as a real icon.
    sample.icon = CreateIcon(sample)
    sample.icon:SetDesaturated(true)
    sample.timer = LoopingTimer(sample)
    -- Active: StyleActiveButton's look over it, the icon in colour.
    sample.active = CreateFrame("Frame", nil, sample)
    sample.active:SetAllPoints()
    sample.active:SetFrameLevel(sample:GetFrameLevel() + 5)
    IgnoreBoxOpacity(sample.active) -- Active opacity instead (ApplyLayout)
    sample.active:SetAlpha(ns.db and ns.db.cdActiveAlpha or 1)
    sample.activeIcon = CreateIcon(sample.active)
    local spinner = AddDashes(sample.active)
    sample.activeTimer = LoopingTimer(sample.active)
    sample.activeTimer:SetFrameLevel(spinner:GetFrameLevel() + 1)
    -- The hovered Abilities row's icon: the hover outline round it, outside the dashes.
    sample.highlight = CreateFrame("Frame", nil, sample)
    sample.highlight:SetSize(SLOT * 1.2, SLOT * 1.2)
    sample.highlight:SetPoint("CENTER")
    sample.highlight:SetFrameLevel(sample:GetFrameLevel() + 10)
    IgnoreBoxOpacity(sample.highlight)
    EditModeOutline(sample.highlight, true)
    return sample
end

local function CooldownOnly(entry)
    return not Items.IsItemEntry(entry) and COOLDOWN_ONLY_NAMES[C_Spell.GetSpellName(entry) or ""] or false
end

local function UpdateSamples()
    local tracked = ns.char.cdTracked
    sampleCount = math.max(#tracked, 1)
    for i = 1, sampleCount do
        local sample = samples[i] or CreateSample()
        samples[i] = sample
        local entry = tracked[i]
        local icon = entry and EntryIcon(entry) or PLACEHOLDER_ICON
        sample.icon:SetTexture(icon)
        sample.activeIcon:SetTexture(icon)
        local active = entry ~= nil and i % 4 == 2 and not CooldownOnly(entry)
        -- Timers restart only when the icon changes, not on every update.
        if not sample.running or sample.entry ~= entry or sample.isActive ~= active then
            if active then
                StopLoop(sample.timer)
                Loop(sample.activeTimer, 12, (i * 1.7) % 12)
            else
                local duration = 15 + (i * 11) % 40 -- staggered, so the numbers differ
                Loop(sample.timer, duration, duration * ((i * 0.29) % 1))
                StopLoop(sample.activeTimer)
            end
        end
        sample.running, sample.entry, sample.isActive = true, entry, active
        sample.active:SetShown(active)
        sample.highlight:SetShown(entry ~= nil and entry == highlighted)
        sample:Show()
    end
    for i = sampleCount + 1, #samples do
        local sample = samples[i]
        sample.running = false
        StopLoop(sample.timer)
        StopLoop(sample.activeTimer)
        sample:Hide()
    end
end

local function StopSamples()
    sampleCount = 0
    for _, sample in ipairs(samples) do
        sample.running = false
        StopLoop(sample.timer)
        StopLoop(sample.activeTimer)
        sample:Hide()
    end
end

-- Layout ----------------------------------------------------------------------------------------------

-- Spot (0 = left or top) for the `rank`th icon (0 = highest priority) of `count` in a line, nearest
-- the anchor first: from the start, from the end, or from the middle outward. In the middle, ties
-- (an equal distance either side, or the two middle spots of an even count) go to `tieToStart`'s side.
local function SpotFromAnchor(rank, count, side, tieToStart)
    if side == "START" then
        return rank
    elseif side == "END" then
        return count - 1 - rank
    end
    local middle = (count - 1) / 2
    local spots = {}
    for spot = 0, count - 1 do
        spots[spot + 1] = spot
    end
    table.sort(spots, function(a, b)
        local distanceA, distanceB = math.abs(a - middle), math.abs(b - middle)
        if distanceA ~= distanceB then
            return distanceA < distanceB
        end
        return a ~= b and (a < b) == tieToStart -- never true for a spot against itself
    end)
    return spots[rank + 1]
end

-- Packs the shown icons into the box at the alignment point (CatnipDB.cdAlign: one of the nine
-- anchor points), higher priority nearer the anchor: rows fill outward from the anchor's edge
-- (from the middle row for the middle anchors, then below, then above), and each row fills outward
-- from the anchor's side (from its middle for the centre anchors, then left, then right). E.g. top
-- centre: middle of the top row, then the rest of it, then the middle of the second row. Icons are
-- the Icon size setting (CatnipDB.cdIconSize), not sized to the box (owner, 2026-10-09): a row takes
-- as many as fit across the box's width, and rows past its far edge are hidden or spill outside it
-- (Overflow). Shows the icons it places and hides overflow, so Update only marks which it wants
-- (showWanted); the samples always want to show.
local function Arrange()
    if not (ns.char and ns.char.cdTracked) then
        return -- before PLAYER_LOGIN (ApplyLayout at load resizes the box)
    end
    local tracked = ns.char.cdTracked
    local width, height = widget:GetWidth(), widget:GetHeight()
    local shown = {}
    if sampleCount > 0 then -- previewing: the samples, in place of the real icons
        for i = 1, sampleCount do
            shown[i] = samples[i]
        end
    else
        for _, entry in ipairs(tracked) do
            local slot = slots[entry]
            if slot and slot.showWanted then
                shown[#shown + 1] = slot
            end
        end
    end
    local size = ns.db.cdIconSize or DEFAULTS.cdIconSize
    local cell = size * OUTLINE -- room for the dashed border round an active icon
    local columns = math.max(1, math.floor(width / cell + 0.001))
    -- Overflow (CatnipDB.cdOverflow): "hide" drops the icons past the rows that fit, lowest priority
    -- first; "spill" lets their rows run past the box's far edge.
    if (ns.db.cdOverflow or DEFAULTS.cdOverflow) == "hide" then
        local fit = columns * math.max(1, math.floor(height / cell + 0.001))
        for i = #shown, fit + 1, -1 do
            shown[i]:Hide()
            shown[i] = nil
        end
    end
    for _, slot in ipairs(shown) do
        slot:Show()
    end
    local scale = size / SLOT
    local align = ns.db.cdAlign or DEFAULTS.cdAlign
    local horizontal = align:find("LEFT") and "LEFT" or align:find("RIGHT") and "RIGHT" or "CENTER"
    local vertical = align:find("TOP") and "TOP" or align:find("BOTTOM") and "BOTTOM" or "MIDDLE"
    local rows = math.ceil(#shown / columns)
    local rowSide = vertical == "TOP" and "START" or vertical == "BOTTOM" and "END" or "MIDDLE"
    local columnSide = horizontal == "LEFT" and "START" or horizontal == "RIGHT" and "END" or "MIDDLE"
    for i, slot in ipairs(shown) do
        -- Rows take icons in priority order: which row this icon is in and its rank there, then
        -- where those ranks sit relative to the anchor.
        local rowRank, columnRank = math.floor((i - 1) / columns), (i - 1) % columns
        local inRow = math.min(columns, #shown - rowRank * columns)
        local row = SpotFromAnchor(rowRank, rows, rowSide, false) -- middle anchors: below first
        local column = SpotFromAnchor(columnRank, inRow, columnSide, true) -- centre anchors: left first
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
    if not (ns.char and ns.char.cdTracked) then
        return -- before PLAYER_LOGIN
    end
    local sampling = Sampling()
    for _, slot in pairs(slots) do
        slot.wanted = false
    end
    for _, entry in ipairs(ns.char.cdTracked) do
        local slot = slots[entry] or CreateSlot(entry)
        slot.wanted = true
        slot.icon:SetTexture(EntryIcon(entry))
        local isItem = Items.IsItemEntry(entry)
        local current = not isItem and CurrentSpell(entry)
        local onCooldown, sure, start, duration
        if isItem then
            onCooldown, sure, start, duration = Items.CooldownState(entry, slot.onCooldown)
        else
            onCooldown, sure = ns.CooldownState(current, slot.onCooldown)
            if not sure then
                RecheckAfterGcd()
            end
        end
        onCooldown = onCooldown and true or false
        if onCooldown ~= (slot.onCooldown or false) then
            local info = current and C_Spell.GetSpellCooldown(current)
            ns.Debug("Cooldowns:", EntryName(entry), onCooldown and "on cooldown" or "ready",
                "| sure:", sure, "isActive:", info and info.isActive, "isOnGCD:", info and info.isOnGCD,
                "GCD running:", ns.GcdRunning(), "in combat:", InCombatLockdown())
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
        slot.showWanted = not sampling and (onCooldown or BuffSeenUp(entry))
        if not slot.showWanted then
            slot:Hide()
        end
    end
    for _, slot in pairs(slots) do
        if not slot.wanted then
            slot.showWanted = false
            slot:Hide()
        end
    end
    if sampling then
        UpdateSamples()
    else
        StopSamples()
    end
    boxOutline:SetShown(sampling and settingsWanted and not (previewing or unlocked))
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
    widget:SetAlpha(db.cdAlpha) -- Inactive opacity: the icons inherit it; active ones and the unlock overlay don't
    for _, slot in pairs(slots) do
        slot.activeGate:SetAlpha(db.cdActiveAlpha)
    end
    for _, sample in ipairs(samples) do
        sample.active:SetAlpha(db.cdActiveAlpha)
    end
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

-- Inactive opacity (the box's alpha: grey cooldown icons), ns.MIN_ALPHA to 1.
function Cooldowns.SetAlpha(alpha)
    ns.db.cdAlpha = math.min(1, math.max(ns.MIN_ALPHA, alpha))
    ApplyLayout()
    ns.SettingsChanged()
end

-- Icon size: an icon's side, without its dashed border.
function Cooldowns.SetIconSize(size)
    ns.db.cdIconSize = math.min(MAX_ICON_SIZE, math.max(MIN_ICON_SIZE, size))
    Arrange()
    ns.SettingsChanged()
end
Cooldowns.MIN_ICON_SIZE, Cooldowns.MAX_ICON_SIZE = MIN_ICON_SIZE, MAX_ICON_SIZE

-- Overflow: "hide" (icons that don't fit in the box don't show) or "spill" (they show past its edge).
function Cooldowns.SetOverflow(mode)
    ns.db.cdOverflow = mode
    Update()
    ns.SettingsChanged()
end

-- Active opacity (icons whose buff or debuff is up), ns.MIN_ALPHA to 1.
function Cooldowns.SetActiveAlpha(alpha)
    ns.db.cdActiveAlpha = math.min(1, math.max(ns.MIN_ALPHA, alpha))
    ApplyLayout()
    ns.SettingsChanged()
end

-- Turns the whole Cooldown Frame on or off (the settings window's checkbox).
function Cooldowns.SetEnabled(enabled)
    ns.db.cdEnabled = enabled
    ApplyLayout()
    ns.SettingsChanged()
end

-- The whole frame back to its defaults: size, position, opacity, alignment and on/off (the
-- settings window's Reset...). The tracked abilities stay.
function Cooldowns.ResetLayout()
    for key, value in pairs(DEFAULTS) do
        ns.db[key] = value
    end
    ApplyLayout()
    Arrange()
    ns.SettingsChanged()
end

function Cooldowns.ResetPosition()
    local db = ns.db
    db.cdX, db.cdY = DEFAULTS.cdX, DEFAULTS.cdY
    ApplyLayout()
    ns.SettingsChanged()
end

-- Shown while the HUD is unlocked: catches the mouse only then. Clicking it opens the Cooldown tab.
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

-- Follows the HUD's unlock mode; while unlocked the box shows its preview, so it can be fitted.
ns.OnSettingsChanged(function()
    if not ns.db or ns.IsHudUnlocked() == unlocked then
        return
    end
    unlocked = ns.IsHudUnlocked()
    overlay:SetShown(unlocked)
    Update()
end)

-- The preview (see Preview above) while Blizzard's Edit Mode is open (BlizzardEditMode.lua), like
-- unlock mode.
function Cooldowns.SetPreview(on)
    if previewing == on then
        return
    end
    previewing = on
    if ns.db then
        Update()
    end
end

-- The preview while the settings window is open on the Cooldown tab (Options.lua).
function Cooldowns.SetSettingsPreview(on)
    on = on and true or false
    if settingsWanted == on then
        return
    end
    settingsWanted = on
    if ns.db then
        Update()
    end
end

-- Outlines the sample icon for `entry` (nil for none): the Abilities row under the mouse.
function Cooldowns.SetPreviewHighlight(entry)
    if highlighted == entry then
        return
    end
    highlighted = entry
    if sampleCount > 0 then
        UpdateSamples()
    end
end

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
    local tracked = ns.char.cdTracked
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
    for _, entry in ipairs(ns.char.cdTracked) do
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
    for _, tracked in ipairs(ns.char.cdTracked) do
        if tracked == entry then
            return true
        end
    end
    return false
end

-- Newly tracked entries go last (lowest priority). Untracked items drop off the list entirely.
function Cooldowns.SetTracked(entry, track)
    local tracked = ns.char.cdTracked
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
        ns.char.cdTracked[#ns.char.cdTracked + 1] = entry
    end
    RefreshAuraFilters() -- a new special-case potion adds its buff to Potions
    Update()
    ns.SettingsChanged()
end

-- Moves the tracked ability at position `from` to position `to` (1 = highest priority).
function Cooldowns.Move(from, to)
    local tracked = ns.char.cdTracked
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
    for _, entry in ipairs(ns.char.cdTracked) do
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
    if not (ns.char and ns.char.cdTracked) then
        return -- before PLAYER_LOGIN (SPELLS_CHANGED can come first)
    end
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
    ns.db.cdBuffs = ns.db.cdBuffs or {} -- ability name -> buff spell ID, when they differ
    ns.db.cdFormCooldowns = ns.db.cdFormCooldowns or {} -- base spell ID -> true: has a cooldown in some form
    ApplyLayout()
end)

ns.OnCharacterLoad(function()
    ns.char.cdTracked = ns.char.cdTracked or {}
    ns.Debug("Cooldowns: tracking", #ns.char.cdTracked, "| countdownForCooldowns CVar:", GetCVar("countdownForCooldowns"))
    RequestUpdate()
end)
