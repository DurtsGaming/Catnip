-- Simplified Chinese (zhCN) translation for Catnip.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty
-- quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in
-- English. Keep %s (a name or text) and %d (a number) in the translation; if the sentence needs
-- two of them in the other order, number them: %2$d ... %1$s. Spell names (Rake, Prowl...) come
-- from the game already translated, so they aren't listed here.
--
-- This file is rewritten by tools/locales.py, which keeps your translations and adds new text as
-- it appears. Only edit the L[...] lines; other changes here are lost.
if GetLocale() ~= "zhCN" then
    return
end
local addonName, ns = ...
local L = ns.L

-- Catnip.lua
-- L["open settings"] = ""
-- L["settings and Edit Mode"] = ""
-- L["debug messages on or off"] = ""
-- L["tools for testing and development"] = ""
-- L["Debug messages on"] = ""
-- L["Debug messages off"] = ""

-- Elements.lua
-- L["Above"] = ""
-- L["Circle"] = ""
-- L["Fill"] = ""
-- L["Ring"] = ""
-- L["Below"] = ""
-- L["Arcs and Orbs"] = ""
-- L["Text"] = ""
-- L["None"] = ""
-- L["Thin"] = ""
-- L["Thick"] = ""
-- L["Font"] = ""
-- L["Size"] = ""
-- L["Outline"] = ""

-- UnlockOverlay.lua
-- L["Click to edit"] = ""

-- Layout.lua
-- L["Rotation Frame"] = ""
-- L["Stealth Mode"] = ""
-- L["Enabled"] = ""
-- L["Opacity while stealthed"] = ""

-- Resource.lua
-- L["Resource Circle"] = ""
-- L["Fill opacity"] = ""
-- L["Background opacity"] = ""
-- L["Border opacity"] = ""
-- L["Mana as"] = ""
-- L["Percent"] = ""
-- L["Value"] = ""
-- L["Resource Value"] = ""

-- ComboPoints.lua
-- L["Combo Points"] = ""
-- L["Opacity"] = ""

-- ComboRings.lua
-- L["Angular"] = ""
-- L["Circular"] = ""
-- L["Shows"] = ""
-- L["Segments"] = ""
-- L["Combo Ring %d"] = ""

-- Swing.lua
-- L["Swing Time"] = ""
-- L["Swing Timer"] = ""
-- L["Bar opacity"] = ""
-- L["Color"] = ""
-- L["Maul queued color"] = ""
-- L["Maul Orb"] = ""
-- L["The swing timer isn't supported in this version of the game."] = ""

-- StealthSmoke.lua
-- L["Stealth Smoke"] = ""

-- Cast.lua
-- L["Cast Time"] = ""
-- L["Swing/Cast Timer"] = ""
-- L["Timer size"] = ""
-- L["Spell name size"] = ""
-- L["Match Maul color when queued"] = ""
-- L["Cast Timer"] = ""

-- ManaPrediction.lua
-- L["Mana Prediction"] = ""
-- L["Show mana cost prediction"] = ""

-- FiveSecondRule.lua
-- L["Five-Second Ring"] = ""

-- Gcd.lua
-- L["GCD Pie"] = ""

-- Proc.lua
-- L["To see Clearcasting in combat, add Omen of Clarity to the Cooldown Manager's tracked buffs."] = ""

-- DotRings.lua
-- L["Rake Duration"] = ""
-- L["Rip Duration"] = ""
-- L["%s will move to combo point %d after combat."] = ""
-- L["DoT rings aren't supported in this version of the game."] = ""

-- Enrage.lua
-- L["The Enrage tint isn't supported in this version of the game."] = ""
-- L["Enrage Tint"] = ""

-- ShiftingPower.lua
-- L["Shifting Power Arc"] = ""

-- GrowlArc.lua
-- L["Growl Arc"] = ""
-- L["Cooldown Arc"] = ""
-- L["Shifting Power ready pulse"] = ""

-- ShiftOrbs.lua
-- L["Shift Orbs"] = ""
-- L["Show almost-ready orb"] = ""

-- CooldownRings.lua
-- L["Faerie Fire Cooldown"] = ""
-- L["Primal Bite Cooldown"] = ""

-- OmenRing.lua
-- L["Omen of Clarity Internal Cooldown"] = ""

-- CooldownItems.lua
-- L["Potions (%s)"] = ""
-- L["Potions"] = ""
-- L["%s has no Use: effect, so there's no cooldown to track."] = ""
-- L["Tracking Potions: %s's buff will light up the Potions icon."] = ""

-- Cooldowns.lua
-- L["Cooldown Frame"] = ""

-- EditMode.lua
-- L["Catnip Edit Mode"] = ""
-- L["Drag a frame to move it. Click it for its settings."] = ""
-- L["Reset Positions"] = ""
-- L["Done"] = ""

-- BlizzardEditMode.lua
-- L["Catnip Settings"] = ""
-- L["Edit Mode can't open in combat."] = ""

-- Preview.lua
-- L["Caster"] = ""
-- L["Bear"] = ""
-- L["Cat"] = ""

-- Options.lua
-- L["The color picker isn't available in this version of the game."] = ""
-- L["General (%s)"] = ""
-- L["Disabled"] = ""
-- L["Move in Edit Mode"] = ""
-- L["Reset..."] = ""
-- L["Reset %s"] = ""
-- L["Reset"] = ""
-- L["Cancel"] = ""
-- L["General"] = ""
-- L["Blizzard UI"] = ""
-- L["Hide Blizzard's cast bar"] = ""
-- L["Blizzard's cast bar will change after combat."] = ""
-- L["Hide Action Bar 1"] = ""
-- L["Hide Stance Bar"] = ""
-- L["Keybinds still work while the bars are hidden."] = ""
-- L["Troubleshooting"] = ""
-- L["Debug messages in chat"] = ""
-- L["Rotation"] = ""
-- L["Resets every element, plus the frame's scale, opacity and position."] = ""
-- L["Scale"] = ""
-- L["Overall opacity"] = ""
-- L["Horizontal position"] = ""
-- L["Vertical position"] = ""
-- L["Preview"] = ""
-- L["Stealth"] = ""
-- L["Reset to defaults"] = ""
-- L["Default font and outline. Elements can choose their own."] = ""
-- L["Cooldown"] = ""
-- L["Resets the frame's size, position, icons and opacity. Your tracked abilities are kept."] = ""
-- L["Height"] = ""
-- L["Width"] = ""
-- L["Abilities"] = ""
-- L["Check the abilities to show, then drag them to set their order. Higher ones sit closer to the anchor (see Alignment). Unchecked items are removed from the list."] = ""
-- L["No abilities with a cooldown found."] = ""
-- L["Drop an item here to track it"] = ""
-- L["Items with a Use: effect, like trinkets, get their own icon. All potions share one Potions icon, which lights up while a potion's buff is active."] = ""
-- L["Icons"] = ""
-- L["Icon size"] = ""
-- L["Overflow"] = ""
-- L["Hide"] = ""
-- L["Spill"] = ""
-- L["When icons don't fit: hide the lowest-priority ones, or let them spill past the edge."] = ""
-- L["Active opacity"] = ""
-- L["Inactive opacity"] = ""
-- L["Alignment"] = ""
-- L["Where icons gather inside the frame."] = ""
-- L["To show countdown numbers, turn on Options > Action Bars > Show Numbers for Cooldowns."] = ""

-- AddOnsPage.lua
-- L["Open Catnip Settings"] = ""
-- L["or type /catnip"] = ""
