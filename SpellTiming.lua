-- What we know about spell timing: whether a spell is on cooldown, the GCD, and the GCD lengths
-- learned from earlier casts. Loads early so every module can use it (the GCD pie, the cooldown arcs
-- and rings, the cooldown box).
--
-- In combat a cooldown's start and duration are secret; only the isActive/isOnGCD flags are
-- readable. The cooldown box, arcs and rings hand Blizzard duration objects, which count down
-- exactly. Only the GCD pie, paced to the swing outside Cat Form, needs a length as a number, so it
-- learns each spell's GCD (Gcd.lua).
local addonName, ns = ...

-- Forever reports the GCD on Classic's GCD spell; retail's 61304 doesn't exist here (EllesmereUI's
-- Forever fix, PR #2240).
ns.GCD_SPELL = 29515

-- A spell's cooldown start and duration, when they're readable (out of combat); nil when secret.
-- Duration is 0 when it's not on cooldown.
function ns.ReadCooldown(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    local start, duration = info and info.startTime, info and info.duration
    if start == nil or duration == nil or ns.IsSecret(start) or ns.IsSecret(duration) then
        return nil
    end
    return start, duration
end

-- Is the GCD running? Readable in combat; secret or missing counts as not running.
function ns.GcdRunning()
    local info = C_Spell.GetSpellCooldown(ns.GCD_SPELL)
    local active = info and info.isActive
    return active == true
end

-- Is the ability on a real cooldown (not just the GCD)? Returns (onCooldown, sure): when sure is
-- false we couldn't tell and kept `previous`, and a timer shouldn't be restarted from this read.
-- Verified in and out of combat (2026-10-10, docs/api-research.md): isOnGCD is true while only the
-- GCD covers the spell, false for an on-GCD spell on its own cooldown, nil for an off-GCD spell, so
-- "isActive and isOnGCD ~= true" is a real cooldown, at once. (Until then, after a 2026-10-01
-- suspicion that isOnGCD turned true for Enrage on another spell's GCD, which the probe didn't
-- see, a GCD made the answer unsure and the cooldown box re-checked 1.6s later.)
function ns.CooldownState(spellID, previous)
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then
        return false, true
    end
    local active, onGCD = info.isActive, info.isOnGCD
    if ns.IsSecret(active) or ns.IsSecret(onGCD) then
        return previous, false
    end
    if active == nil then -- older field set: fall back to the numbers, readable out of combat
        local duration = info.duration
        if duration == nil or ns.IsSecret(duration) then
            return previous, false
        end
        return duration > 1.5, true
    end
    return active and onGCD ~= true, true
end

-- Learned lengths ---------------------------------------------------------------------------------
-- Per character, since talents change them: CatnipDB.chars[character].lengths[kind][spell name], in seconds, rounded to the half second (so a 10% shorter GCD
-- from Nature's Grace doesn't stick). Kinds: "gcd" (the GCD a spell starts, e.g. 1.0s for
-- Rejuvenation with Gift of the Earthmother; Gcd.lua) and "cooldown" (a spell's own cooldown,
-- unused since 2026-10-10: the cooldown arcs are timed by the game now; kept, not cleared). By
-- name, since IDs differ by rank.

-- The learned length, or nil if none yet.
function ns.LearnedLength(kind, name)
    local lengths = ns.char and ns.char.lengths
    return lengths and lengths[kind][name]
end

-- Saves a measured length; returns it rounded.
function ns.LearnLength(kind, name, seconds)
    local length = math.floor(seconds * 2 + 0.5) / 2
    local lengths = ns.char and ns.char.lengths
    if lengths and lengths[kind][name] ~= length then
        lengths[kind][name] = length
        ns.Debug("Learned", kind, "length:", name, length, "s")
    end
    return length
end

-- Where lengths were kept before (one key per arc, until 2026-10-08), moved here once.
local OLD_KEYS = {
    spLength = "Shifting Power",
    growlLength = "Growl",
    ffLength = "Faerie Fire",
    pbLength = "Primal Bite",
}

ns.OnCharacterLoad(function()
    local db = ns.db
    local lengths = ns.char.lengths or {}
    ns.char.lengths = lengths
    lengths.cooldown = lengths.cooldown or {}
    lengths.gcd = lengths.gcd or {}
    for key, name in pairs(OLD_KEYS) do
        if db[key] then
            lengths.cooldown[name] = lengths.cooldown[name] or db[key]
            db[key] = nil
        end
    end
    if db.gcdLengths then
        for name, length in pairs(db.gcdLengths) do
            lengths.gcd[name] = lengths.gcd[name] or length
        end
        db.gcdLengths = nil
    end
end)
