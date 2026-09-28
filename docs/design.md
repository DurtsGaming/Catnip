# Catnip design

Text summary of [design.pdf](design.pdf) ("Feral Forever: Resource Manager / Rotation Addon") and [layout-sketch.svg](layout-sketch.svg). The originals are the source of truth for visuals; this file is the working spec.

## Concept

A compact, circular Feral Druid HUD, ported from a WeakAuras setup. Inspiration: [Rabble's energy WA](https://wago.io/Ak7NxBdCc) plus the same author's Rage and Mana WAs ([wago.io/p/Rabble](https://wago.io/p/Rabble)).

Layout, from the centre out: the resource circle (with the GCD pie over it), the swing timer ring, then five combo point dots along an arc above, with the Rake ring around dot 4 and the Rip ring around dot 5. Clearcasting claws sit at the top of the resource circle.

- **Combo points follow the arc** of the big circle's top edge (a paw-print shape), not a flat row. See the sketch.
- Ignore the thin inner ring in the reference WA — it's the old Classic 2s energy ticker.

## Textures

We need to make these (with transparency):

| # | Texture | Used for | Static/Dynamic | Style |
|---|---------|----------|----------------|-------|
| 1 | Circle – hard edge | Resource fill; combo points | Dynamic | Flat |
| 2 | Circle – soft/glow | Background of big circle | Static | Gradient |
| 3 | Ring – very thin | Borders of combo points and big circle | Static | Flat, thin and sharp |
| 4 | Ring – glow | Background behind swing timer ring | Static | Gradient |
| 5 | Ring – thin | Small DoT timers | Dynamic | Flat |
| 6 | Ring – thin partial | Segmented DoT timers (later) | Dynamic | Flat |
| 7 | Ring – bar | Swing timer (cast bar later) | Dynamic | Gradient |
| – | Proc texture | Clearcasting | Dynamic | TBD (e.g. white claw marks / crescents at top of circle) |

## MVP

1. **Resource circle (#1 on #2, bordered by #3).** Energy in Cat, Rage in Bear. Fills from the bottom; raw value as text in the middle.
2. **Combo points (#1 bordered by #3).** Five small circles; fill/fade in by count. Hide the borders when not in Cat Form.
3. **DoT rings (#5).** Rip is a red ring (~5px band) around the 5th combo point and Rake the same around the 4th (one AuraContainer each), hidden with the dots outside Cat Form. Full when applied, drains clockwise to empty. (A thin red layer outside the swing ring was tried and dropped.)
4. **Swing timer (#7 on #4).** Ring around the big circle that appears full on each swing and empties clockwise from 12 o'clock (earlier versions filled, then emptied counter-clockwise), over the soft glow (#4) with a small gap from the resource circle. (A crisp black outline was tried and dropped in favour of the feathered look.) Turns red/pink when Maul is queued. The `0.2 / 1.0` text was tried and dropped: the ring alone is the swing timer.
5. **Clearcasting proc texture.** Mirrored claw marks at the top of the resource circle. (A translucent "phantom" +10 energy preview was tried and removed.)

## Later

- ~~Mana (as %) in caster/other forms~~ done: shown as a % whenever the power is mana (via `UnitPowerPercent`). Lacerate stacks still to do.
- ~~Five-second rule~~ built: whenever the power is mana (out of Cat/Bear), a dark blue ring over the resource circle's border. Full while regenerating (and during a cast: mana is only spent when it lands), and after a mana spend it empties, then two arcs grow from 6 o'clock up both sides and meet at 12 o'clock over 5 seconds. (A bottom-up "water level" fill was tried first; the arcs read better.) Only casts that really spend mana reset it: not ones with no mana cost (skinning) or made free by Clearcasting. In combat, Clearcasting is only known if Omen of Clarity is tracked in the Cooldown Manager; otherwise a free cast still resets the ring. Doesn't know when mana is full (secret in combat), so it shows then too.
- Segmented DoT rings (#6): Rip in 6 segments (12s, 2s ticks), Rake in 3 (9s, 3s ticks).
- ~~Cast bar on the #7 ring~~ built: a gold ring replaces the swing ring while casting (fills clockwise); channels are blue and drain. Below the ring: `0.0 / 2.5s` (remaining time for channels) and the spell name.
- ~~GCD "Harvey ball" over the big circle~~ built (a dark pie over the resource circle). The "scaled to attack speed, for timing shifts to autos" part isn't possible: the timings are secret in combat.
- Indicators: Faerie Fire missing on target; Tiger's Fury off cooldown; Thistle Tea off cooldown; number of shifts affordable with current mana; Enrage available; Enrage buff/debuff active.
- Short cooldowns tracked like DoTs: Tiger's Fury, Primal Bite, Faerie Fire.
- Buffs: Berserk, Frenzied Regeneration, potions/procs; a summed "proc power" fill (like the old WotLK WA) for timing Berserk.

## Out of scope

- Utility/movement: Dash, Leap, Charge, Bash, War Stomp.
- Cooldowns of 1 min or longer: Berserk, potions, Enrage, Nature's Grasp.
- Internal cooldowns: Omen, weapon procs.

## Status (as of 0.1.0-beta.2)

How each piece works is in [architecture.md](architecture.md); the API facts behind it are in [api-research.md](api-research.md).

| Feature | State |
|---------|-------|
| Resource circle (energy/rage fill + number) | Verified in combat |
| Mana shown as % | Verified |
| Combo points | Verified. **Open issue:** may not update on target switch (Forever combo points may be per-target; see api-research.md) |
| Swing timer (clockwise, Maul tint) | Verified |
| GCD Harvey ball | Verified |
| Cast bar on the swing ring | Built, **untested** in-game |
| Five-second-rule ring | Built, **untested** in-game |
| Clearcasting claws | Verified in combat (AuraContainer) |
| Rip ring around combo dot 5 | Verified |
| Rake ring around combo dot 4 | Built, needs in-game check (Rake not yet unlocked in the beta) |
| Move/resize (`/catnip`) | Verified |

Next candidates: fix combo points on target switch; items from "Later".
