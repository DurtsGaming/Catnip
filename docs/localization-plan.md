# Localization plan

Plan for translating Catnip, starting with Simplified Chinese (zhCN) from a volunteer translator, and for tidying the English wording first. Started 2026-10-15. Update this file as pieces land, then fold the result into architecture.md (a Localization section) and delete it.

## Status

| Step | State |
|------|-------|
| 1. Look up spells by ID, not by English name | Verified in-game (English) 2026-10-15: `ns.SPELL`, `ns.SpellName`, `ns.IsSpellNamed` (Catnip.lua). Shifting Power's ID still unknown (looked up by English name until then). `CooldownItems.lua`'s "Potion" name fallback left as is. zhCN check is in step 6 |
| 2. English wording pass | Done, approved by the owner in-game 2026-10-15 (the table below, plus all element names in Title Case and the chat messages) |
| 3. Locale files and `L` table | Not started |
| 4. Move strings into `L`, file by file | Not started |
| 5. Translator kit: check script, contributor notes | Not started |
| 6. zhCN client checks (fonts, widths) | Not started: needs the translator or a zhCN client |

Order matters. Step 1 fixes bugs that affect every non-English player, translated or not. Step 2 comes before step 4 so the translator works from final English, not text we're about to rewrite.

## 1. Spell lookups by English name (bug fix)

Several features find spells by their English name. On a zhCN client `C_Spell.GetSpellInfo("Shifting Power")` finds nothing, so these features stop working without an error:

| Where | What breaks |
|-------|-------------|
| `CooldownRings.lua` `names` / `castNames` (Faerie Fire, Faerie Fire (Feral), Primal Bite) | FF and PB rings never find their spell |
| `GrowlArc.lua` (Growl), `ShiftingPower.lua` (Shifting Power), via `SegmentedCooldown.lua` | Growl and Shifting Power arcs |
| `ShiftOrbs.lua` `SHIFT_SPELLS`, `SHIFTING_POWER` | Shift orbs can't read form costs |
| `OmenRing.lua` `WATCHED` (Shred, Claw, Wrath) | Omen ICD ring |
| `Swing.lua` `IsCurrentSpell("Maul")` | Maul queued colour |
| `Cooldowns.lua` `COOLDOWN_ONLY_NAMES`, `FORM_COOLDOWN_NAMES` (Faerie Fire) | FF lights up as active for its 40s debuff; FF may not be offered in caster form |
| `Options.lua` `ShiftingPowerIcon` | Rotation tab icon falls back to the cat face (cosmetic) |
| `CooldownItems.lua` `ItemName(itemID):find("Potion")` | Low risk: only a fallback after the item subclass check |

`ns.FindKnownSpell` uses names on purpose: Forever gives each rank its own ID, and looking a name up returns the highest rank the player knows. Keep that, but get the name from the game. Each spec lists one spell ID (any rank), and `C_Spell.GetSpellName(id)` returns the client's own name for it, which then goes through the same lookup. For `castNames`, compare the localized names; for `COOLDOWN_ONLY_NAMES`, compare names from IDs or compare base spell IDs.

To verify in-game: on English, nothing should change (rings, arcs, orbs, Maul colour, Omen ring all still work). Have the translator confirm on zhCN. One thing to check with `/dump`: does `C_Spell.GetSpellInfo(<localized name>)` resolve to the highest known rank the same way it does in English?

## 2. English wording pass

Some text reads as machine-written: long sentences that list every setting, colon-then-fragment hints, and mixed conventions. Proposed house style:

- **Title Case** for named things (elements, frames, tabs, sections), as Blizzard does ("Action Bar 1", "Cooldown Manager"). **Sentence case** for option labels, buttons and hints.
- **US spelling** in the UI (Color, Center), to match the enUS client. Code comments can stay as they are.
- Short hints. Say what the setting does, not every field it touches.
- Chat messages start with a capital letter and say what the player should do.

Candidates (current → proposed). The owner marks which ones to change, or rewrites them:

| Where | Current | Proposed |
|-------|---------|----------|
| Options.lua:1270, Rotation reset | Every element's settings, Scale, Overall opacity, position and the Rotation Frame switch go back to their defaults. | Resets every element, plus the frame's scale, opacity and position. |
| Options.lua:1671, Cooldown reset | Height, Width, position, Icon size, Overflow, both opacities, Alignment and the Cooldown Frame switch go back to their defaults. Tracked abilities stay. | Resets the frame's size, position, icons and opacity. Your tracked abilities are kept. |
| Options.lua:1140, reset confirm button | Everything back to defaults | Reset |
| Options.lua:1713, Abilities | Tick the abilities to show. Drag ticked ones up or down to set their priority: higher ones sit closer to the anchor point (Alignment, below). Unticked items drop off the list. | Check the abilities to show, then drag them to set their order. Higher ones sit closer to the anchor (see Alignment). |
| Options.lua:1953, items | Items with a Use: effect (Hearthstone, trinkets) get their own icon. Every potion shares one Potions icon; a dropped potion's buff (e.g. Mighty Rage Potion) shows as Potions being active. | Items with a Use: effect, like trinkets, get their own icon. All potions share one Potions icon, which lights up while a potion's buff is active. |
| Options.lua:1970, Overflow | Icons that don't fit in the box: hidden, lowest priority first, or shown past its edge. | When icons don't fit: hide the lowest-priority ones, or let them spill past the edge. |
| Options.lua:1984, Alignment | Where the shown icons gather in the box: a corner, the middle of a side, or the centre. | Where icons gather inside the frame. |
| Options.lua:1592, General text | Fonts and outline for all text, unless an element picks its own. | Default font and outline. Elements can choose their own. |
| Options.lua:1237 | Hidden bars' keybinds still work. | Keybinds still work while the bars are hidden. |
| Layout.lua:151 | Share of Overall opacity | Opacity while stealthed (check the meaning first) |
| Cast.lua:87 | Match Maul Color When Queued | Match Maul color when queued |
| UnlockOverlay.lua:106 vs Preview.lua | Click To Edit / Click to edit | Click to edit (both) |
| Element names | Mixed: "Swing/Cast Timer", "Resource Value", "Cooldown Arc" vs "Combo points", "Shift orbs", "Five-second ring", "Growl arc" | All Title Case |
| Proc.lua:108 | add Omen of Clarity to the Cooldown Manager's tracked buffs so Clearcasting shows in combat. | To see Clearcasting in combat, add Omen of Clarity to the Cooldown Manager's tracked buffs. |
| DotRings.lua:176, Enrage.lua:47 | this client has no AuraContainer, so the DoT rings are unavailable. | DoT rings aren't supported in this version of the game. |
| Catnip.lua:90, `/catnip` help | One long line listing every command, dev ones included | A few lines for player commands; dev tools (`art`, `icon`, `cdm`, `spells`, `item`, `perf`) under `/catnip dev` |

## 3. Locale files

The usual addon setup, with no library:

- `Locales/enUS.lua`: `ns.L = setmetatable({}, { __index = function(_, key) return key end })`. A missing key shows its English text, so nothing breaks before a translation is complete.
- `Locales/zhCN.lua`: starts `if GetLocale() ~= "zhCN" then return end`, then sets `L["..."] = "..."`.
- Both load first in `Catnip.toc`, right after the libraries.

**Keys are the English text** (`L["Reset to defaults"]`). This keeps the code readable, and English needs no entries at all. The downside: changing English wording orphans its translation, so the string falls back to English until it's re-translated. The check script (step 5) catches that, and doing the wording pass first keeps it rare.

Strings built by joining pieces become format strings so the translator can reorder words: `"Reset " .. spec.name` → `L["Reset %s"]:format(spec.name)`. Same for "Combo ring %d", "General (%s)", "Potions (%s)", "%s shows around combo point %d after combat.", and similar.

## 4. What gets translated

**Translate:** settings window text (tabs, sections, labels, hints, buttons, choice values, reset dialogs), element names, Edit Mode panel and overlays, AddOns page, preview form names, and chat messages a player would see in normal play.

**Get from the game instead of translating:** spell, form and item names. Use `C_Spell.GetSpellName(id)` for labels like Rake, Rip, Faerie Fire, Growl, Clearcasting, Prowl, Shadowmeld, Cat Form, Bear Form. Their translations come with the client.

**Leave in English:** `ns.Debug` output, dev commands and their output (`/catnip art`, `icon`, `cdm`, `spells`, `item`, `perf`), slash command names, saved keys and IDs.

**Watch for display text used as an ID.** Tab names are passed to `topTabs.Add("General")` and also key `SIDE_TAB_ICONS`; element `name`s may be matched too. Split these into an ID and a display label before translating, or a translated tab name breaks its icon. Search for every place a label is compared.

Do it file by file, about 25 files, Options.lua (~220 strings) the largest. Check each file in-game in English after converting it; the text should look the same as before.

## 5. Translator kit

- `tools/check_locales.py`: scans the `.lua` files for `L["..."]`, compares with `Locales/zhCN.lua`, and lists missing keys (needs translating) and unused keys (English changed or text removed). Run it before each release.
- In `Locales/zhCN.lua`, group entries by where they appear (General tab, Rotation tab, Cooldown tab, chat), with a comment where length matters (side tabs, buttons, the Preview row).
- A short section in README.md, or a CONTRIBUTING.md, on how to submit translations.

**How the translator submits:** GitHub pull requests to `Locales/zhCN.lua` are simplest with one translator. CurseForge also has a translation system that the BigWigs packager (already in our release workflow) can inject at build time with `@localization(...)@`. That's worth it only if more translators join, so start with the repo file.

## 6. zhCN client checks

Needs someone on a zhCN client, probably the translator:

- **Fonts.** `Elements.lua` offers Friz Quadrata (the client's standard font, which becomes a CJK font on zhCN), Arial Narrow, Skurri and Morpheus by file path. The last three may not have Chinese glyphs or may not exist on zhCN clients, so spell names in the cast timer could show as boxes. Possible fixes: offer only the standard font on CJK clients, or use the zhCN client's own font files. The label "Friz Quadrata" is also wrong there; something like "Game default" fits every locale.
- **Widths.** Chinese is usually shorter than English, but check the fixed-width spots: side tabs, the Preview row's form and stealth buttons, the reset dialog, the Cooldown drop box.
- **Everything still works:** rings, arcs, orbs, Maul colour, Omen ring (step 1).

## Open questions

- zhCN (Simplified) only, or zhTW (Traditional) too? Same setup either way.
- Does the translator play Forever on a zhCN client (useful for step 6), or only translate?
- Which wording candidates to change (step 2), and any others the owner noticed.
