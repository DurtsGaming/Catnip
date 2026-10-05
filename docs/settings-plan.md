# Customization settings plan

Plan for letting players customize the HUD (opacity per element, text font and size, options such as mana as a value or a percent), with a preview mode that shows what's being changed. Started 2026-10-04 on the `ui-customization` branch. Update this file as pieces land, then fold the result into design.md and architecture.md.

## Status

| Step | State |
|------|-------|
| 1. Registry (`Elements.lua`), storage, Rotation tab tree with generated pages; text elements (Resource number, Swing time, Cast time, Cast name: font, size, outline), General font/outline, Resource number's "Mana as" Percent / Value | Verified in-game 2026-10-04: all four fonts load, outlines, sizes, inheriting and reset work, raw mana value updates in combat without errors |
| 2a. Preview hover and click (`Preview.lua`): outlines, hover tooltip, click opens the page, tree hover lights the element, open page's element in gold. Pickable: Resource circle (new element: fill, background and border opacity), Resource number, and the swing/cast texts while they show | Verified in-game 2026-10-04 (hover, click, tree hover, opacity sliders, off on tab switch / Edit Mode / combat, camera still turns over empty HUD area). Idle outlines faint enough; the cast time and name outlines overlap a little, which the owner is fine with |
| 2b. Sample state and form switcher: always samples while the Rotation tab is open (owner's call, 2026-10-04), starting from the current form; "Preview as" at the top of the tree; Prowl via a stealth override (so every stealth-aware piece follows); samples for the resource circle and number, a looping swing (Cat, Bear), and a looping 2.5s cast (Caster; a separate Casting state was merged into Caster at the owner's request); Cast time/name pages and changing "Mana as" switch to Caster, Swing time to Cat | Verified in-game 2026-10-04. Fixed after: a real cast during a Bear preview showed the mana prediction bands over the sample (now hidden while sampled, **untested**) |
| Choice controls: clicking the value opens a menu of all values (Blizzard's `MenuUtil`, fonts drawn in their font via `SetFontObject`); the arrows still step | Verified in-game 2026-10-04 (owner's request) |
| 3. Opacity wrappers | Not started |
| 4. AuraContainer stand-ins | Not started |

## Decisions (owner, 2026-10-04)

- **Organised by zone, then element.** Zones follow the HUD from the centre out; each zone lists its elements. A **General** entry holds global defaults (font, outline, HUD opacity, scale) that elements inherit unless they override them.
- **Blizzard fonts only** for now (no LibSharedMedia).
- **Preview on the real HUD**, not a copy in the settings window.
- **In preview mode, clicking an element opens its settings**, and **elements react to the mouse on hover**, so it's clear what a click will select.

## Zones and elements

| Zone | Elements |
|------|----------|
| Resource circle | Fill, backdrop and border, number, GCD pie, Clearcasting crescent, Enrage tint, five-second ring, mana prediction bands, Shifting Power ready pulse |
| Combo arc | Combo points, Faerie Fire ring, Primal Bite ring, Rake ring, Rip ring, still-up ticks |
| Swing ring | Swing bar, glow, Maul orb, cast bar, stealth smoke |
| Under the ring | Shifting Power / Growl arc, shift orbs, ghost orb |
| Text | Swing time, cast time, cast name |
| Cooldown box | Already its own tab; joins this scheme later |

## Settings window

The Rotation side tab becomes two panes, like the WeakAuras group list: a tree of zones and elements on the left and the selected element's settings on the right. The window's minimum width grows on this tab to fit both panes. Hovering a row in the tree highlights that element on the HUD, the same way hovering the HUD does.

## Preview mode

- **When:** while the settings window is open on the Rotation tab, out of combat. Combat (`PLAYER_REGEN_DISABLED`) or closing the window ends it, and every element goes back to its live state.
- **Sample state:** each element draws a representative sample: about 70% energy, 3 combo points, Rip and Rake partway through, a swing running, 2 shift orbs, the Shifting Power arc half full. Existing previews (`/catnip sp|ff|pb|growl`, `ns.Cooldowns.SetPreview`) are reused where they fit.
- **Form switcher:** "Preview as: Cat / Bear / Caster / Prowl / Casting". Opening an element whose settings only apply in one state switches to it (the mana format switches to Caster).
- **Stand-ins:** elements drawn by AuraContainers (Rip, Rake, ticks, Clearcasting, Enrage) can't be forced to show, so each gets a static copy made from the same textures, shown only in preview.
- **Edit Mode:** while Blizzard's Edit Mode (or Catnip Edit Mode) is open, dragging the HUD belongs to it, and preview hover and click are switched off.

### Hover and click

Edit Mode frames are rectangles, but the HUD is circles and rings that overlap, so ordinary mouse frames can't tell what's under the cursor. Instead:

- **One mouse catcher** covers the HUD, shown only in preview. While the mouse is over it, it works out the cursor's distance and angle from the HUD's centre (in HUD units, so scale doesn't matter) and asks each element's **hit shape** whether the cursor is inside it:
  - `circle` (x, y, radius): combo points, shift orbs, the Maul orb
  - `band` (inner, outer radius, optional angle range): the swing ring, the Shifting Power arc, the five-second ring, rings around combo points (a band around the dot's centre)
  - `rect`: text
  Smaller shapes are checked first, so a combo point beats the swing ring behind it. Elements that sit on top of another and can't be picked out (GCD pie, mana prediction bands, Enrage tint) are selected only from the tree.
- **Look, borrowed from Blizzard's Edit Mode:** on entering preview, every selectable element gets a faint blue outline in its own shape. The hovered element brightens, and a small name tag ("Rip ring") shows by the cursor. The selected element (whose settings are open) turns gold, and the rest of the HUD dims to about 25% (the spotlight), so the changed part stands out.
- **Highlight art:** each element names the textures to outline (often an outline texture it already has, such as `sp_arc_outline`). The fallback is the hit shape drawn with `ring_thin` / `ring_small`, cut with `half_plane` masks for arcs.
- **Click:** opens the settings window at that element (opening the window beside the HUD if it was closed). Uses the same idea as `ns.FollowSettings`.

## Framework

1. **Element registry.** `ns.RegisterElement{ id, zone, name, frames, hit, highlight, states, options, apply, preview }`. Settings pages, preview, hover and click are all generated from this list, rather than writing every control by hand in Options.lua.
2. **Storage.** `CatnipDB.elements[id][key]`, falling back to General, then to the option's default. Appearance is shared across Edit Mode layouts; only position, scale and opacity stay per layout, as they are now.
3. **Opacity wrappers.** Many elements already set their own alpha (shift orb curves, smoke fades, the Shifting Power pulse gate), so a user opacity can't simply call `SetAlpha` on them. Each element gets a parent frame whose alpha belongs only to the setting (the `shiftingPowerPulseGate` pattern; alphas multiply). Textures drawn directly on `ns.hud` (backdrop, swing glow, smoke) move into frames first. Keep the frame levels in architecture.md's layering table. The biggest refactor here; done zone by zone.
4. **Combat.** Our own frames' font and alpha can change in combat, but AuraContainer button art is fixed after setup. Settings that change those elements apply after a `/reload` or a rebuild out of combat (needs testing in-game).

## Open questions to verify

- Mana as a raw value: `UnitPower` straight to `SetText` works in combat (verified 2026-10-04). Short forms ("12.3k") need maths on a secret number; possible only if `AbbreviateNumbers` accepts secrets (`/dump` test).
- Fonts: Friz Quadrata (`STANDARD_TEXT_FONT`), `Fonts\ARIALN.TTF`, `Fonts\skurri.ttf` and `Fonts\MORPHEUS.TTF` all load in the Forever client (verified 2026-10-04).
- Colours: most art has its colour baked in, so a "colour" option there means choosing between preset textures. Elements tinted in code (smoke, Maul tint, dashes) could take any colour. Decide per element.

## Order of work

1. Registry, storage and a generated settings page, starting with the three text elements (font, size) and the mana format. Small, and tests the whole pipeline.
2. Preview mode: sample state, form switcher, mouse catcher with hit shapes, hover outlines, click to select, spotlight.
3. Opacity wrappers, zone by zone.
4. Stand-ins for the AuraContainer elements.
