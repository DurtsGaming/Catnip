-- The changelog shown on the settings window's Changelog tab (Options.lua), newest first. It starts
-- at 1.3.0 (owner's call, 2026-11-20).
--
-- Each version has three lists (any may be left out, and then isn't shown):
--   features       new things; shown first, so they read as the version's headline
--   improvements   existing things made better, or working differently
--   fixes          bugs fixed
-- Add to the next version's entry as changes land, and give it its date when it's released (no
-- date: shown as not yet released). See Releasing in docs/architecture.md.
--
-- What goes in (owner's rules, 2026-11-20): the aim is a list players actually read.
-- The test: would a player who skipped this version want to know? If they'd never notice, leave
-- it out.
--   In:  new features (and where to find them); changes players will notice in how things look or
--        behave, new defaults especially; fixes for bugs players could have hit in a released
--        version; anything removed or moved.
--   Out: small polish in the settings window (hover outlines, click areas, spacing); anything
--        players can't see (refactors, docs, tooling, translation plumbing); changes to things that
--        never shipped (a fix or tweak to a feature before its version was released is part of
--        that feature, not a fix).
--   Short: one line per change, written as what the player gets, not how it works; fold small
--        follow-ups into their feature's line ("bigger by default" goes in the feature's line);
--        a handful of lines per version.
local addonName, ns = ...
local L = ns.L

ns.CHANGELOG = {
    {
        version = "1.3.0",
        features = {
            L["DoT End Marker: pick the size of the bar at the top of the Rake and Rip rings (Off, Small, Medium or Large) on the Combo Ring pages. It's bigger by default."],
            L["Changelog: a new settings tab showing what's new in each version."],
        },
        improvements = {
            L["The settings window opens where you last left it."],
            L["Swing timer text is now an option"],
        },
        fixes = {
            L["Fixed an issue where some spell IDs were being learned incorrectly."],
        },
    },
}
