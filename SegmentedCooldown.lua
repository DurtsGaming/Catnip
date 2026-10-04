-- ns.CreateSegmentedCooldown(spec): runs a SegmentedArc.lua arc over a spell's cooldown. Used by
-- ShiftingPower.lua and CooldownRings.lua.
--
-- Cooldown timing is secret in combat, so the arc runs on our own clock, like FiveSecondRule.lua:
-- it starts when our cast of the spell succeeds (our casts' spell IDs are readable) and runs for the
-- cooldown's length, learned from the real numbers out of combat (CatnipDB[spec.lengthKey]). The
-- ready flag (isActive, via ns.CooldownState) ends it early if the cooldown resets, and holds the
-- arc full if our clock runs out first.
--
-- spec:
--   label          for debug output
--   names          spellbook names to look for, first known wins; nothing shows while none is known
--   castNames      set of spell names whose successful casts start the clock
--   castAllowed    optional function(): false to ignore a cast (e.g. a form without the cooldown)
--   defaultLength  seconds, until the real length is learned
--   lengthKey      CatnipDB key the learned length is kept under
--   learnFromReady also learn the length in combat, from when the ready flag turns on (only for
--                  spells nothing resets early, or a reset would teach a short length)
--   arc            from ns.CreateSegmentedArc
--   onStart, onReady(animate), onHide   optional callbacks
--   command        "/catnip <command> [seconds]" runs a preview
local addonName, ns = ...

local HOLD_LIMIT = 10 -- seconds to hold a full arc waiting for the ready flag before giving up
local RESET_GRACE = 0.5 -- ignore "not on cooldown" this soon after a cast (the cooldown may not be set yet)
local POLL = 0.1 -- seconds between ready-flag checks while the clock runs (its end may fire no event)

local function Call(callback, ...)
    if callback then
        callback(...)
    end
end

function ns.CreateSegmentedCooldown(spec)
    local arc = spec.arc
    local knownID -- the spellbook's spell, nil while none is known
    local castID -- the spell we last cast: in a form it may be a different spell from knownID
    local state = "hidden" -- "hidden" (not known), "cooling", "holding" (clock done, still on cooldown), "ready"
    local castAt, length, holdSince
    local demo = false -- the preview command: a pretend cooldown, ignoring the real one

    -- The arc's frame may be hidden with its parent (Faerie Fire's, outside Cat and Bear Form), so
    -- the clock runs on its own frame.
    local driver = CreateFrame("Frame")
    driver:Hide()

    local function TimingID()
        return castID or knownID
    end

    local function Length()
        return ns.db and ns.db[spec.lengthKey] or spec.defaultLength
    end

    local function StartCooling(start, duration)
        castAt, length = start, duration
        state = "cooling"
        Call(spec.onStart)
        arc.Start((GetTime() - castAt) / length)
        driver:Show()
    end

    local function BecomeReady(animate)
        local wasShowing = arc.frame:IsVisible() and not arc.IsFading()
        state = "ready"
        demo = false
        driver:Hide()
        if wasShowing and animate then
            arc.Finish()
        elseif not arc.IsFading() then
            arc.Hide()
        end
        Call(spec.onReady, animate) -- animate: only when the cooldown actually runs out, not on login or after learning the spell
    end

    local function Hide()
        state = "hidden"
        demo = false
        driver:Hide()
        arc.Hide()
        Call(spec.onHide)
    end

    -- The cooldown's real start and length, when they're readable (out of combat).
    local function ReadCooldown()
        local info = C_Spell.GetSpellCooldown(TimingID())
        if not info then
            return nil
        end
        local start, duration = info.startTime, info.duration
        if start == nil or duration == nil or ns.IsSecret(start) or ns.IsSecret(duration) then
            return nil
        end
        return start, duration
    end

    local function Learn(duration)
        if ns.db and duration ~= ns.db[spec.lengthKey] then
            ns.db[spec.lengthKey] = duration
            ns.Debug(spec.label .. ": cooldown is", duration, "s")
        end
    end

    local function Timing()
        return state == "cooling" or state == "holding"
    end

    local function JustCast()
        return Timing() and GetTime() - castAt < RESET_GRACE
    end

    -- Compares what the game says with our clock: corrects it when the numbers are readable, ends it
    -- early if the cooldown was reset, starts it if we missed the cast.
    local function Sync()
        if demo then
            return
        end
        if not knownID then
            Hide()
            return
        end
        local start, duration = ReadCooldown()
        if start then
            if duration > 1.5 and start > 0 then -- longer than a GCD: the real cooldown
                Learn(duration)
                if not Timing() or castAt ~= start or length ~= duration then
                    StartCooling(start, duration)
                end
            elseif state ~= "ready" and not JustCast() then
                BecomeReady(Timing())
            end
            return
        end
        -- In combat: only the flag. Unsure reads keep what we have.
        if not ns.CooldownState then -- Cooldowns.lua loads after us
            return
        end
        local onCooldown, sure = ns.CooldownState(TimingID(), state ~= "ready")
        if not sure then
            if state == "hidden" then
                BecomeReady(false)
            end
            return
        end
        if onCooldown and state == "ready" then
            StartCooling(GetTime(), Length())
            ns.Debug(spec.label .. ": on cooldown but we missed the cast; timing from now")
        elseif not onCooldown and Timing() then
            if not JustCast() then
                ns.Debug(spec.label .. ": ready early (cooldown reset?)")
                BecomeReady(true)
            end
        elseif not onCooldown and state == "hidden" then
            BecomeReady(false)
        end
    end

    -- The ready flag: onCooldown, sure (see ns.CooldownState); unsure without it.
    local function ReadyFlag()
        if not (TimingID() and ns.CooldownState) then
            return nil, false
        end
        return ns.CooldownState(TimingID(), nil)
    end

    -- Ready now, by the flag: with learnFromReady, the time since the cast is the cooldown's length
    -- (to the half second; it was read within POLL of the end).
    local function ReadyByFlag()
        if spec.learnFromReady then
            local elapsed = GetTime() - castAt
            if elapsed > 1.5 then
                Learn(math.floor(elapsed * 2 + 0.5) / 2)
            end
        end
        BecomeReady(true)
    end

    local sincePoll = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        if not Timing() then
            driver:Hide()
            return
        end
        local progress = (GetTime() - castAt) / length
        arc.SetProgress(progress)
        if demo then
            if progress >= 1 then
                BecomeReady(true)
            end
            return
        end
        if progress < 1 then
            -- Ready before our clock ran out (too long a length, or a reset)?
            sincePoll = sincePoll + elapsed
            if sincePoll < POLL or JustCast() then
                return
            end
            sincePoll = 0
            local onCooldown, sure = ReadyFlag()
            if sure and not onCooldown then
                ns.Debug(spec.label .. ": ready at", string.format("%.1f", GetTime() - castAt), "s, before our clock")
                ReadyByFlag()
            end
            return
        end
        if state == "cooling" then
            state, holdSince = "holding", GetTime()
        end
        -- Our clock is done: ready unless the game is sure it's still on cooldown. During the GCD it
        -- can't tell, and waiting for a gap in the GCD made the flash come late (you could press the
        -- spell before it showed).
        local onCooldown, sure = ReadyFlag()
        if sure and not onCooldown then
            ReadyByFlag() -- a little after our clock: the real length may be longer
        elseif not sure or GetTime() - holdSince > HOLD_LIMIT then
            BecomeReady(true)
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
        demo = false
        StartCooling(GetTime(), Length())
        ns.Debug(spec.label .. ": cast, timing", Length(), "s")
        C_Timer.After(0.1, Sync) -- out of combat the real numbers are readable: learn the length
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
    ns.TryRegisterEvent(events, "PLAYER_TALENT_UPDATE")
    ns.TryRegisterEvent(events, "TRAIT_CONFIG_UPDATED")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCast((select(3, ...))) -- unit, castGUID, spellID
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            Sync()
        else
            if not demo then
                Resolve()
            end
            Sync()
        end
    end)

    if spec.command then
        ns.commands[spec.command] = function(arg)
            demo = true
            StartCooling(GetTime(), tonumber(arg) or Length())
            ns.Print(spec.label .. " preview:", length, "s")
        end
    end

    -- The spellbook's spell while it's known, else nil.
    return {
        SpellID = function()
            return knownID
        end,
    }
end
