# Customization settings plan

Plan for letting players customize the HUD (opacity per element, text font and size, options such as mana as a value or a percent), with a preview mode that shows what's being changed. Started 2026-10-04 on the `ui-customization` branch. Update this file as pieces land, then fold the result into design.md and architecture.md.

## Status

| Step | State |
|------|-------|
| 1. Registry (`Elements.lua`), storage, Rotation tab tree with generated pages; text elements (Resource number, Swing time, Cast time, Cast name: font, size, outline), General font/outline, Resource number's "Mana as" Percent / Value | Verified in-game 2026-10-04: all four fonts load, outlines, sizes, inheriting and reset work, raw mana value updates in combat without errors |
| 2a. Preview hover and click (`Preview.lua`): outlines, hover tooltip, click opens the page, tree hover lights the element, open page's element in gold. Pickable: Resource circle (new element: fill, background and border opacity), Resource number, and the swing/cast texts while they show | Verified in-game 2026-10-04 (hover, click, tree hover, opacity sliders, off on tab switch / Edit Mode / combat, camera still turns over empty HUD area). Idle outlines faint enough; the cast time and name outlines overlap a little, which the owner is fine with |
| 2b. Sample state and form switcher: always samples while the Rotation tab is open (owner's call, 2026-10-04), starting from the current form; "Preview as" at the top of the tree; Prowl via a stealth override (so every stealth-aware piece follows); samples for the resource circle and number, a looping swing (Cat, Bear), and a looping 2.5s cast (Caster; a separate Casting state was merged into Caster at the owner's request); Cast time/name pages and changing "Mana as" switch to Caster, Swing time to Cat | Verified in-game 2026-10-04. Fixed after: a real cast during a Bear preview showed the mana prediction bands over the sample (now hidden while sampled, verified 2026-10-04) |
| Choice controls: clicking the value opens a menu of all values (Blizzard's `MenuUtil`, fonts drawn in their font via `SetFontObject`); the arrows still step | Verified in-game 2026-10-04 (owner's request) |
| 3a. Per-element opacity, Swing ring zone: Swing ring (bar, background), Maul orb (Bear sample shows Maul queued), Stealth smoke, Cast bar; ring-shaped hit targets (`kind = "ring"`) and `visible` functions | Verified in-game 2026-10-04 |
| 3b. Under the ring: Shifting Power arc (opacity, ready pulse on/off), Growl arc (opacity), Shift orbs (opacity, almost-ready orb on/off; previews all five, picked as one by their own circles, owner's request); part-ring hit targets (`angle`, `spread`); the arcs' samples are looping copies (`ns.ArcSampler`) while the real ones hide in `ns.cooldownArcHolder` | Verified in-game 2026-10-04 |
| 3c + 4. Combo arc: Combo points (opacity, picked as one), Faerie Fire, Primal Bite, Rake and Rip rings (opacity each; Rake/Rip with their ticks). Real rings move into `ns.comboLive` (hidden in preview); Rake/Rip get stand-ins (same art on a plain Cooldown, looping) and FF/PB looping sample arcs, in `ns.comboSample`. Rake/Rip opacity is a gate frame around the AuraContainer, so no /reload needed | Verified in-game 2026-10-04 (a real Rake ring can't be checked yet: Rake isn't unlocked in the beta) |
| 3d. Resource circle, the rest (list only unless noted): GCD pie, Five-second ring, Clearcasting (stand-in; picked at the top of the circle), Enrage tint (stand-in), Mana prediction (on/off and opacity; a sample band in Caster) | Verified in-game 2026-10-04 |

## Panel redesign: zones, form profiles, slots (planned 2026-10-08)

Workshopped on a design canvas (private: https://claude.ai/artifact/BmLUtK7MF8E66cjaqQkjr3, board "B · Above / Circle / Below + form profiles"). The owner picked it over a HUD-map picker and a refined tree. Replaces the Rotation tab's tree; the element pages and the HUD preview, hover and click (Preview.lua) stay.

### Layout

- **HUD controls across the top** (every form, never overridden), two rows: a **Rotation Frame** on/off switch (a new control: Blizzard has none) with "Every form" and **Move in Edit Mode**; then **Scale** and **Overall opacity**, then **Horizontal** and **Vertical position**, as sliders in pairs with room for their labels. They all leave the General page.
- **Stealth opacity** lives under Prowl → General and Shadowmeld → General (owner, 2026-10-08), listed only on those tabs: a share of Overall opacity while stealthed (100% = no change), one value per stealth profile.
- **Form tabs: All · Cat · Bear · Caster.** The tab is both what you edit and what the HUD previews (owner, 2026-10-08). All forms edits the shared values and previews the last form picked. A dot on a tab means it holds changes.
- **Stealth sub-tabs** under Cat (**Cat Form | Prowl**) and Caster (**Caster | Shadowmeld**), as their own profiles. Bear shows "Bear Form can't stealth" (unverified: can a night elf Shadowmeld in Bear Form?), All shows "Changes here apply to every form".
- **Four zones as icons with labels**: General (default text), **Above** (a module slot), **Circle** (headings Fill and Ring), **Below** (headings Arcs and orbs, Text). Each element is a row with a small glyph in its colour, its name and a one-line description, and a dot when it has changes in this tab.
- **No form gating in settings**: every element is listed and editable in every tab (owner, 2026-10-08). The HUD preview shows the selected element whatever the form, rather than jumping to the form it shows in.
- **No mini HUD in the window**: the real HUD is the preview.
- **Each option shows where its value comes from** ("Default", "From All forms", "Bear Form only", "Changed") with a ↺ to drop an override.
- **Resets**: Reset to defaults on each element page (this tab's values only); **Reset…** pinned under the element list opens a confirmation: **Everything back to defaults** (every form and stealth profile, the HUD controls, modules and rings; not position, which Edit Mode's Reset Position handles) or **Only <tab> changes**.

### Form profiles (storage)

Overrides, not copies: `CatnipDB.elements[id]` keeps the shared value; a form or stealth profile stores only what differs. Lookup: stealth profile → its form → All forms → General (for `inherit` options) → default. Profiles: `cat`, `bear`, `caster`, `cat_s` (Prowl), `caster_s` (Shadowmeld). Elements reapply on shapeshift and on stealth changes; our own frames' colour, font and alpha are known to change in combat (the resource fill already recolours per form).

### Slots

- **Above is a module slot, locked to each form** (owner, 2026-10-08): each form picks its module (Combo arc, a planned **Cooldown tracker** for other cooldowns, or None); All forms can't. Defaults: Combo arc in Cat and Bear, None in Caster. Prowl and Shadowmeld inherit their form's.
- **Combo rings are slots**: Ring 1-5 round the combo points, each showing one tracker (Empty, Faerie Fire, Primal Bite, Rake, Rip; Tiger's Fury etc. later as more tracker entries). A tracker brings its own look and timing (colours, segments, ticks); the ring is a position and an opacity. One tracker per ring; picking one that's on another ring swaps them. Defaults match today: FF 1, empty 2, PB 3, Rake 4, Rip 5.
- **Combat**: AuraContainer frames (Rake, Rip) can't move in combat, so each form's module is its **own set of frames**, built out of combat, and shifting fades one set out and the next in (alpha on our gate frames, as Rake/Rip opacity already works). Costs one Rake and one Rip container per form that shows them. **Needs an in-game test** that gate alpha changes on a shift in combat.

### Order of work

1. Panel layout: HUD controls (with the switch), zone strip, element rows, Reset…; storage unchanged. **Built 2026-10-08, untested in-game.** "Preview as" stays at the top of the list until step 2's form tabs replace it; the HUD controls gained a third row, Horizontal and Vertical position (owner, 2026-10-08), so General has only its Text page; Reset... offers only "Everything back to defaults" until profiles exist.
2. Form profiles: scoped storage and lookup, form tabs and stealth sub-tabs, value sources and ↺, reapply on shift/stealth, Stealth opacity.
3. Combo ring slots: CooldownRings.lua and DotRings.lua become trackers placed on rings.
4. Above module slot per form, with None; per-form frame sets for the combo arc. The Cooldown tracker module is separate work.

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
- **Look, borrowed from Blizzard's Edit Mode:** on entering preview, every selectable element gets a faint blue outline in its own shape. The hovered element brightens, and a small name tag ("Rip ring") shows by the cursor. The selected element (whose settings are open) turns gold. (A spotlight dimming the rest of the HUD to 25% while a page is open was built on 2026-10-04 and dropped the same day: the owner didn't like it. It scaled every element's opacity options through a shared `ns.OpacityOption` marked `dims`; don't rebuild it unasked.)
- **Highlight art:** each element names the textures to outline (often an outline texture it already has, such as `sp_arc_outline`). The fallback is the hit shape drawn with `ring_thin` / `ring_small`, cut with `half_plane` masks for arcs.
- **Click:** opens the settings window at that element (opening the window beside the HUD if it was closed). Uses the same idea as `ns.FollowSettings`.

## Framework

1. **Element registry.** `ns.RegisterElement{ id, zone, name, frames, hit, highlight, states, options, apply, preview }`. Settings pages, preview, hover and click are all generated from this list, rather than writing every control by hand in Options.lua.
2. **Storage.** `CatnipDB.elements[id][key]`, falling back to General, then to the option's default. Everything, position included, is shared across Edit Mode layouts (per-layout saving was removed 2026-10-08).
3. **Opacity.** First choice (2026-10-04): the colour's alpha (swipe colour, vertex colour), which multiplies with the frame and texture alpha the modules animate, so no new frames are needed (the Swing ring zone works this way). Wrappers only where that isn't possible. Many elements already set their own alpha (shift orb curves, smoke fades, the Shifting Power pulse gate), so a user opacity can't simply call `SetAlpha` on them. Each element gets a parent frame whose alpha belongs only to the setting (the `shiftingPowerPulseGate` pattern; alphas multiply). Textures drawn directly on `ns.hud` (backdrop, swing glow, smoke) move into frames first. Keep the frame levels in architecture.md's layering table. The biggest refactor here; done zone by zone.
4. **Combat.** Our own frames' font and alpha can change in combat, but AuraContainer button art is fixed after setup. Settings that change those elements apply after a `/reload` or a rebuild out of combat (needs testing in-game).

## Open questions to verify

- Mana as a raw value: `UnitPower` straight to `SetText` works in combat (verified 2026-10-04). Short forms ("12.3k") need maths on a secret number; possible only if `AbbreviateNumbers` accepts secrets (`/dump` test).
- Fonts: Friz Quadrata (`STANDARD_TEXT_FONT`), `Fonts\ARIALN.TTF`, `Fonts\skurri.ttf` and `Fonts\MORPHEUS.TTF` all load in the Forever client (verified 2026-10-04).
- Colours: most art has its colour baked in, so a "colour" option there means choosing between preset textures. Elements tinted in code (smoke, Maul tint, dashes) could take any colour. Decide per element.

## Order of work

1. Registry, storage and a generated settings page, starting with the three text elements (font, size) and the mana format. Small, and tests the whole pipeline.
2. Preview mode: sample state, form switcher, mouse catcher with hit shapes, hover outlines, click to select (the spotlight was dropped).
3. Opacity, zone by zone (colour alpha first, wrappers only where needed).
4. Stand-ins for the AuraContainer elements.

## Next steps

Steps 1-4 are done and verified (released in 0.1.0-beta.10). Still open, in no fixed order; ask the owner which first:

- **Colours where the art allows.** Art tinted in code can take any colour: the stealth smoke, the Maul amber, the five-second ring's indigo, the cast and channel colours, the GCD shade, the Enrage red. Art with its colour baked in (power fills, combo points, orbs, arcs, the coloured rings) would need preset textures to pick from. Needs a colour control in Options.lua (Blizzard's `ColorPickerFrame`, unverified on Forever).
- **The cooldown box in the same scheme.** Its opacity, alignment and icon settings as elements in the settings tree (its own zone, or the Cooldown tab built the same way), with a preview showing sample icons. It's a separate frame, not in `ns.hud`, so Preview.lua's layer and catcher would need one for it too.
- **More options per element** as wanted, e.g. hiding elements outright, text colour, the number's position.
- **Wrap-up:** fold this plan into design.md and architecture.md (both already describe what's built), leaving this file as a short history or removing it.
