# Catnip design

Text summary of [design.pdf](design.pdf) ("Feral Forever: Resource Manager / Rotation Addon") and [layout-sketch.svg](layout-sketch.svg). The originals are the source of truth for visuals; this file is the working spec.

## Concept

A compact, circular Feral Druid HUD, ported from a WeakAuras setup. Inspiration: [Rabble's energy WA](https://wago.io/Ak7NxBdCc) plus the same author's Rage and Mana WAs ([wago.io/p/Rabble](https://wago.io/p/Rabble)).

Layout, from the centre out: the resource circle (with the GCD pie over it), the swing timer ring, then five combo point dots along an arc above, with the Rake ring around dot 4 and the Rip ring around dot 5. Clearcasting lights a crescent of light inside the top of the resource circle. The whole HUD draws at 0.85 alpha.

- **Combo points follow the arc** of the big circle's top edge (a paw-print shape), not a flat row. See the sketch.
- Ignore the thin inner ring in the reference WA — it's the old Classic 2s energy ticker.

## Textures

We need to make these (with transparency):

| # | Texture | Used for | Static/Dynamic | Style |
|---|---------|----------|----------------|-------|
| 1 | Circle – hard edge | Resource fill (soft ~3px edge); combo points | Dynamic | WoW Forever energy bar gradient, stood on end, darker at both sides |
| 2 | Circle – soft/glow | Background of big circle | Static | Gradient |
| 3 | Ring – very thin | Borders of combo points and big circle | Static | Flat, thin and sharp |
| 4 | Ring – glow | Background behind swing timer ring | Static | Gradient |
| 5 | Ring – thin | Small DoT timers | Dynamic | Flat |
| 6 | Ring – thin partial | Segmented DoT timers (later) | Dynamic | Flat |
| 7 | Ring – bar | Swing timer (cast bar later) | Dynamic | Gradient |
| – | Proc texture | Clearcasting | Dynamic | Crescent: bright arc inside the top rim plus a downward glow, additive |

## MVP

1. **Resource circle (#1 on #2, bordered by #3).** Energy in Cat, Rage in Bear. Fills from the bottom; raw value as text in the middle.
2. **Combo points (#1 bordered by #3).** Five small circles; fill/fade in by count. Hide the borders when not in Cat Form.
3. **DoT rings (#5).** Rip is a red ring (~5.75px band, overlapping the dot's border ring) around the 5th combo point and Rake the same around the 4th (one AuraContainer each), hidden with the dots outside Cat Form. Full when applied, drains clockwise to empty. (A thin red layer outside the swing ring was tried and dropped.)
4. **Swing timer (#7 on #4).** Ring around the big circle that appears full on each swing and empties clockwise from 12 o'clock (earlier versions filled, then emptied counter-clockwise), over the soft glow (#4, pulled slightly inside the bar's band) with a small gap from the resource circle. (A crisp black outline was tried and dropped in favour of the feathered look.) Turns red/pink when Maul is queued. The `0.2 / 1.0` text was tried and dropped: the ring alone is the swing timer.
5. **Enrage tint.** In Bear Form, while the Enrage buff is up, the empty part of the resource circle turns a dim red (a red disc behind the rage fill).
6. **Clearcasting proc texture.** A crescent of light: a thin bright arc just inside the top rim (barely dims) over a glow with soft rays spilling down into the fill (breathes), both drawn additively so they read as light, over a steady soft black backing (40%) and a thin dark line just under the arc (60%) so they still have contrast on a full energy fill (additive white alone barely changes bright yellow). Picked from five mockups (crescent, moonbeams, rim light, halo, sheen). (Mirrored claw marks were used first, then an opaque white cap over the top 10%, which looked like a sticker.) (A translucent "phantom" +10 energy preview was tried and removed.)

## Later

- ~~Mana (as %) in caster/other forms~~ done: shown as a % whenever the power is mana (via `UnitPowerPercent`). Lacerate stacks still to do.
- ~~Five-second rule~~ built: in every form (mana keeps its own clock in Cat and Bear too), a deep indigo ring over the resource circle's border, shaded like a tube so it reads as a bar and stands apart from the azure mana fill. A mana spend fills it; over the 5 seconds it opens at 12 o'clock and the two ends retreat down both sides to meet at 6 o'clock, leaving it empty. Empty while regenerating (and during a cast: mana is only spent when it lands). (Tried first: a bottom-up "water level" fill, then the reverse of the current look: empty after a spend, with arcs growing from 6 o'clock to meet at 12.) Only casts that really spend mana reset it (shapeshifting does; energy and rage abilities don't): not ones with no mana cost (skinning) or made free by Clearcasting. A cast counts as free only if Clearcasting was up when it was sent and gone just after it landed, because Clearcasting only applies to damage and healing spells: shapeshifting with it up still spends mana. In combat, Clearcasting is only known if Omen of Clarity is tracked in the Cooldown Manager; otherwise a free cast still resets the ring. Doesn't know when mana is full (secret in combat), so it runs then too.
- Segmented DoT rings (#6): Rip in 6 segments (12s, 2s ticks), Rake in 3 (9s, 3s ticks).
- ~~Cast bar on the #7 ring~~ built: a gold ring replaces the swing ring while casting (fills counter-clockwise from 12 o'clock, via rotated half-ring arcs; falls back to a clockwise swipe if the progress is secret in combat); channels are blue and drain clockwise. Below the ring: `0.0 / 2.5s` (remaining time for channels) and the spell name. Blizzard's player cast bar is hidden by default, since this replaces it (a setting turns that off).
- ~~GCD "Harvey ball" over the big circle~~ built (a faint white pie, 30% alpha, over the resource circle; originally dark). The "scaled to attack speed, for timing shifts to autos" part isn't possible: the timings are secret in combat.
- Indicators: Faerie Fire missing on target; Tiger's Fury off cooldown; Thistle Tea off cooldown; number of shifts affordable with current mana; Enrage available; Enrage buff/debuff active.
- Short cooldowns tracked like DoTs: Tiger's Fury, Primal Bite, Faerie Fire.
- Buffs: Berserk, Frenzied Regeneration, potions/procs; a summed "proc power" fill (like the old WotLK WA) for timing Berserk.

## Cooldown widget

A separate box, apart from the HUD, for non-rotational cooldowns (requested 2026-10-01).

- **Choosing:** settings window, Cooldowns → Abilities sub-tab. Lists every spellbook spell with a cooldown of its own; tick to track. Tracked ones sit at the top and are dragged up or down to set priority. New ones go last.
- **Showing:** an icon appears only while its ability is on cooldown (not just the GCD) or its buff is up. Visible icons pack together in priority order, left to right, then top to bottom, gathered at the chosen alignment point (Layout sub-tab: a 3x3 grid of the box's corners, side middles and centre; default top centre). Rows stay in reading order; e.g. top centre fills across the top with each row centred, bottom right keeps the group flush to the bottom-right corner.
  - On cooldown: greyed-out icon with the time left.
  - Active (our buff on us, or our debuff on the current target, e.g. Growl's taunt or Faerie Fire): the aura's icon in colour (e.g. Elemental Blessing for Skysight), with thin yellow dashes running clockwise around its square border, and the buff's time left. (Yellow dots were tried first; the owner wanted thin lines.)
- **Look:** square icons (round was tried first; the owner preferred squares), sized so every tracked ability fits in the box at once.
- **List:** one entry per spell name (the spellbook can list several ranks; the highest wins). `/catnip spells` shows why any spellbook entry is or isn't offered.
- **Items:** drag an item onto the drop box under the list (Cooldowns → Abilities). Anything with a Use: effect (Hearthstone, trinkets) gets its own icon, in the same priority list. Unticking an item removes it.
- **Potions:** all potions share one cooldown, so they share one **Potions** icon, which follows whichever potion was used. Dropping a specific potion (Mighty Rage Potion) is a special case: its buff shows as the Potions icon being active. Unticking Potions forgets the special cases.
- **Cooldown only in some forms:** Faerie Fire has none in caster form but its Cat/Bear version (Faerie Fire (Feral)) does. A spell is listed if any version has a cooldown: the one your form uses now, one seen earlier (remembered in `cdFormCooldowns`), or a known name (Faerie Fire).
- **Form versions:** a spell that changes with your form (Feral Charge becomes Feral Charge (Cat) or (Bear)) is one entry, saved as the base spell. The icon and cooldown follow the version your current form uses, so after a shift it shows that form's charge.
- **Buffs with a different ID:** some abilities give a buff with another name and ID (Skysight, the Skyborne racial, gives Elemental Blessing). Catnip learns these: when a tracked ability is cast out of combat, it looks for a buff of yours that started at that moment and remembers it by ability name. Until then, that ability never shows as active.
- **Moving/resizing:** unlocks with the HUD (Catnip Edit Mode). Drag the box to move it; drag any corner to resize it. Or set exact values in the Cooldowns → Layout sub-tab: width, height, and horizontal/vertical position (offset from the screen centre), each a slider with a typeable box.
- **Cooldown only:** Faerie Fire never shows as active, only its cooldown: its ~40s debuff would keep the icon lit long after the 6s Cat/Bear cooldown that matters (`COOLDOWN_ONLY_NAMES` in `Cooldowns.lua`).
- **Limits:** in combat, an ability whose buff is up but which isn't on cooldown can't show (we can't see the buff, only the AuraContainer can). Target debuffs follow the current target only. Countdown numbers are Blizzard's and follow WoW's "Show numbers for cooldowns" option, changed in WoW's own settings (Catnip's checkbox for it was removed: setting a CVar from addon code tainted Blizzard's chat).

## Out of scope

- Utility/movement on the HUD: Dash, Leap, Charge, Bash, War Stomp. (They can go in the cooldown widget.)
- Cooldowns of 1 min or longer: Berserk, potions, Enrage, Nature's Grasp.
- Internal cooldowns: Omen, weapon procs.

## Status (as of 0.1.0-beta.3)

How each piece works is in [architecture.md](architecture.md); the API facts behind it are in [api-research.md](api-research.md).

| Feature | State |
|---------|-------|
| Resource circle (energy/rage fill + number) | Verified in combat |
| Mana shown as % | Verified |
| Combo points | Verified. **Open issue:** may not update on target switch (Forever combo points may be per-target; see api-research.md) |
| Swing timer (clockwise, Maul tint) | Verified |
| GCD Harvey ball | Verified |
| Cast bar on the swing ring | Built, **untested** in-game |
| Blizzard player cast bar hidden | Verified (incl. after Edit Mode) |
| Five-second-rule ring | Built, **untested** in-game |
| Clearcasting crescent | Claws verified in combat (AuraContainer); crescent **untested** in-game |
| Rip ring around combo dot 5 | Verified |
| Rake ring around combo dot 4 | Built, needs in-game check (Rake not yet unlocked in the beta) |
| Enrage tint (Bear: resource background turns red while Enrage is up) | Verified |
| Gradient fill textures (resource circle per power, combo points) | Built, **untested** in-game |
| Move/resize (unlock mode) | Verified. Edit Mode look verified 2026-10-02 (blue nine-slice, brighter on hover). Hover "Click To Edit" + name tag, click opens the widget's settings, and no more scroll-to-resize (scale is in settings): built, **untested** |
| Hide Action Bar 1 / Hide Stance Bar (General → Blizzard UI; keybinds still work) | Built, **untested** |
| Catnip Edit Mode: **Edit Mode** button atop `/catnip` (replaces the per-tab Lock / Reset position buttons) opens a panel like Blizzard's HUD Edit Mode, with Rotation Frame / Cooldown Frame on-off checkboxes, Reset Positions and Done | Built, **untested** |
| Settings window (`/catnip`): scale, position (X/Y from screen centre), slider values typeable, hide Blizzard cast bar, debug | Built, **untested** in-game |
| Settings tabs (General, Cooldowns → Abilities / Layout), scrolling, resizable window | Built, **untested** in-game |
| Cooldown widget items (drop box, per-item icons, shared Potions icon with special-case potion buffs) | Built, **untested** in-game |
| Cooldown widget (tracked list with drag-to-reorder, grey icon + timer on cooldown, coloured buff icon + running dashed border + timer, learns buffs with a different ID while the buff is up, move/resize) | Built, **untested** in-game |

Next candidates: fix combo points on target switch; items from "Later".
