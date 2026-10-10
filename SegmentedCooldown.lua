-- ns.CreateSegmentedCooldown(spec): runs a SegmentedArc.lua arc over a spell's cooldown. Used by
-- ShiftingPower.lua, GrowlArc.lua and CooldownRings.lua.
--
-- Since 2026-10-10 the game drives it (verified in combat with a probe, docs/api-research.md):
-- isActive and isOnGCD stay readable in combat, and "isActive and isOnGCD ~= true" means the spell
-- is on its own cooldown (isOnGCD is true while only the GCD covers it, false for an on-GCD spell on
-- its own cooldown, nil for an off-GCD spell). When that turns on, the arc gets
-- C_Spell.GetSpellCooldownDuration(id, true), the cooldown without the GCD, as a duration object:
-- Blizzard times it exactly, secret or not. When it turns off (ready, reset, or only the GCD left)
-- the arc finishes. Nothing ends a cooldown with an event, so the flags are checked every POLL
-- seconds while one runs. Until then the arc ran on our own clock from the cast, over a length
-- learned per spell (SpellTiming.lua), corrected by the flags.
--
-- spec:
--   label          the spell's name, for debug output
--   names          spellbook names to look for, first known wins; nothing shows while none is known
--   castNames      set of spell names whose casts are this spell (a form's version may have its own
--                  ID, whose cooldown is then the one read)
--   castAllowed    optional function(): false to ignore a cast (e.g. a form without the cooldown)
--   defaultLength  seconds, for the preview command
--   arc            from ns.CreateSegmentedArc
--   onStart, onReady(animate), onHide   optional callbacks
--   command        "/catnip <command> [seconds]" runs a preview
local addonName, ns = ...
local CreateFrame = ns.Profiled("SegmentedCooldown") -- timed by /catnip perf (Profiler.lua)

local POLL = 0.1 -- seconds between flag checks while a cooldown runs

local function Call(callback, ...)
    if callback then
        callback(...)
    end
end

function ns.CreateSegmentedCooldown(spec)
    local arc = spec.arc
    local knownID -- the spellbook's spell, nil while none is known
    local castID -- the spell we last cast: in a form it may be a different spell from knownID
    local state = "hidden" -- "hidden" (not known), "cooling", "ready"
    local demoEnd -- the preview command's end time, while it runs (the real cooldown is ignored)

    local function TimingID()
        return castID or knownID
    end

    -- The poll, on its own frame so it runs while the arc's parent is hidden.
    local driver = CreateFrame("Frame")
    driver:Hide()

    local function StartCooling(duration)
        state = "cooling"
        Call(spec.onStart)
        arc.Start(duration)
        driver:Show()
    end

    local function BecomeReady(animate)
        local wasShowing = arc.frame:IsVisible() and not arc.IsFading()
        state = "ready"
        demoEnd = nil
        driver:Hide()
        if wasShowing and animate then
            arc.Finish()
        elseif not arc.IsFading() then
            arc.Hide()
        end
        Call(spec.onReady, animate) -- animate: only when a cooldown actually ends, not on login or after learning the spell
    end

    local function Hide()
        state = "hidden"
        demoEnd = nil
        driver:Hide()
        arc.Hide()
        Call(spec.onHide)
    end

    -- The cooldown without the GCD, as a duration object; nil if the client refuses.
    local function CooldownDuration(id)
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, id, true)
        return ok and duration or nil
    end

    -- Reads the flags and moves between ready and cooling. `changedID`: the spell a
    -- SPELL_UPDATE_COOLDOWN named, to refresh a running arc's timing when it's ours.
    local function Sync(changedID)
        if demoEnd then
            return
        end
        local id = TimingID()
        if not id then
            if state ~= "hidden" then
                Hide()
            end
            return
        end
        local info = C_Spell.GetSpellCooldown(id)
        local active, onGCD = info and info.isActive, info and info.isOnGCD
        if ns.IsSecret(active) or ns.IsSecret(onGCD) then
            return -- unknown: keep what we have
        end
        if active == true and onGCD ~= true then
            if state ~= "cooling" then
                local duration = CooldownDuration(id)
                if duration then
                    StartCooling(duration)
                    ns.Debug(spec.label .. ": cooldown started")
                end
            elseif changedID == id then
                local duration = CooldownDuration(id)
                if duration then
                    arc.SetDuration(duration) -- e.g. shortened by a talent or effect
                end
            end
        elseif state == "cooling" then
            ns.Debug(spec.label .. ": ready")
            BecomeReady(true)
        elseif state == "hidden" then
            BecomeReady(false)
        end
    end

    local sincePoll = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        if demoEnd then
            if GetTime() >= demoEnd then
                BecomeReady(true)
            end
            return
        end
        sincePoll = sincePoll + elapsed
        if sincePoll >= POLL then
            sincePoll = 0
            Sync()
        end
    end)

    local function OnCast(id)
        if id == nil or ns.IsSecret(id) then
            return
        end
        if not spec.castNames[C_Spell.GetSpellName(id) or ""] then
            return
        end
        if spec.castAllowed and not spec.castAllowed() then
            return
        end
        knownID = knownID or id
        castID = id
        Sync(id)
    end

    -- Finds the spell in the spellbook by name (its ID may differ by rank or client).
    local function Resolve()
        local id = ns.FindKnownSpell(spec.names)
        if id ~= knownID then
            ns.Debug(spec.label .. ": spell", id or "not known")
        end
        knownID = id
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCast((select(3, ...))) -- unit, castGUID, spellID
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            local changedID = ... -- the spell whose cooldown changed (verified 2026-10-10)
            Sync(not ns.IsSecret(changedID) and changedID or nil)
        else
            Resolve()
            Sync()
        end
    end)

    if spec.command then
        ns.commands[spec.command] = function(arg)
            local seconds = tonumber(arg) or spec.defaultLength
            demoEnd = GetTime() + seconds
            StartCooling(ns.Duration(GetTime(), seconds))
            ns.Print(spec.label .. " preview:", seconds, "s")
        end
    end

    -- The spellbook's spell while it's known, else nil.
    return {
        SpellID = function()
            return knownID
        end,
    }
end
