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

## Panel redesign: zones and slots (2026-10-08)

Workshopped on a design canvas (private: https://claude.ai/artifact/BmLUtK7MF8E66cjaqQkjr3, board "B · Above / Circle / Below + form profiles"). The owner picked it over a HUD-map picker and a refined tree. Replaces the Rotation tab's tree; the element pages and the HUD preview, hover and click (Preview.lua) stay.

### Layout

- **HUD controls across the top**, three rows: a **Rotation Frame** on/off switch (a new control: Blizzard has none; reads Enabled or Disabled) with **Reset...** and **Move in Edit Mode** (Reset... moved there from under the element list, 2026-10-09: it resets the whole frame, so it sits with the frame-wide controls, always in view); then **Scale** and **Overall opacity**; then **Horizontal** and **Vertical position**, as sliders in pairs with room for their labels.
- **Preview strip** (2026-10-09), across the window between the HUD controls and the panes: a **Preview** label, the form buttons **Caster · Bear · Cat** (owner's order) and a **Stealth** toggle beside them, all rounded buttons in the Cooldown tab's bookmark look (`art.RoundTab`: bright with white text when picked, darker with gold text otherwise). A band of its own so it reads as changing only what the HUD shows, not settings per form (a heading above the buttons in the list read as the whole list's title) The toggle reads Prowl or Shadowmeld and is dimmed in Bear. Not an editing scope (see "Form profiles: dropped"). **Stealth is a look over the form, not a form** (owner, 2026-10-08): the form decides what shows (its module, its power), stealth only the look (periwinkle fill for energy and mana, smoke, dimmer orbs, Stealth opacity), so Shadowmeld in Caster keeps Caster's module.
- **Four zones as icons with labels**: General (Stealth Mode; the Text defaults are hidden), **Above** (a module slot), **Circle** (headings Fill and Ring), **Below** (headings Arcs and orbs, Text). Each icon draws only its zone's part of the HUD (a full mini HUD with the rest dimmed was unreadable at that size, 2026-10-08). Each element is a row with a small glyph in its colour and its name on one line (a description line under the name was dropped, owner, 2026-10-09), and a green dot when it has changed settings. The zone's name shows over its rows, without a description (dropped too). Renamed (owner, 2026-10-09): Resource number to **Resource Value**, Swing ring to **Swing Timer**, Cast bar to **Cast Timer**; the Ring group reads Swing Timer, Cast Timer, Stealth smoke (`order` 1-3).
- **Stealth Mode** (renamed from Stealth opacity, 2026-10-09): under General, an **Enabled** switch (off: stealth leaves the HUD looking as it does unstealthed: no periwinkle, smoke or dimming), and one opacity value: while stealthed (Prowl or Shadowmeld) the HUD's opacity is this share of Overall opacity (100% = no change).
- **Opacity sliders show the real opacity** (owner, 2026-10-09): 0% invisible to 100% fully opaque, defaulting to what the element draws at by design (before Overall opacity, which multiplies everything). Most elements' art is solid, so that was already so; Stealth smoke's slider became its main cloud layer's alpha (default 85%), the other layers scaled with it. New opacity options follow this.
- **No mini HUD in the window**: the real HUD is the preview.
- **Fewer options for now** (owner, 2026-10-08): Resource circle, Mana prediction, Five-second ring, GCD pie, Enrage tint and Maul orb are `hidden` (Elements.lua): their code and options stay, but the settings don't offer them and they use their defaults. Delete the flag to bring one back. Font and outline are hidden too (owner, 2026-10-09: bloat): every text element offers only Size, and General's Text page is gone, leaving General with Stealth opacity. The Shifting Power and Growl arcs, which share the spot under the ring, are one setting, **Cooldown Arc** (owner, 2026-10-09): a **Shifting Power** and a **Growl** switch (off: that arc never shows and the other takes the spot in every form), Opacity for whichever shows, and Shifting Power's ready pulse. Likewise the swing time and the cast time and spell name, which share the spot under the orbs, are one setting, **Swing/Cast Timer** (owner, 2026-10-09): Timer size and Spell name size.
- **Resets**: Reset to defaults on each element page; **Reset...** in the HUD controls opens a confirmation: **Everything back to defaults** (every element, scale, opacity, position and the switch; position included since 2026-10-09) or Cancel.

### Form profiles: dropped (2026-10-08)

Built as step 2 (form tabs All / Caster / Bear / Cat with Shadowmeld and Prowl sub-tabs; every option stored for all forms plus per-profile overrides, looked up stealth profile → form → all forms → General → default; source lines and Reset links; the HUD reapplying every element on shapeshift and stealth), then backed out before testing: the owner judged a general inheritance chain too costly for the coming performance pass. It's in `git stash` ("Step 2 form profiles (backed out ...)") if real requests ever call for it. Instead, **a per-form choice is an explicit setting where it's actually needed** (so far: the module above the circle), and everything else is one value for every form.

### Slots

- **Above is a module slot, chosen per form** (owner, 2026-10-08): a setting with a choice for each form (Combo arc, a planned **Cooldown tracker** for other cooldowns, or None). Defaults: Combo arc in Cat and Bear, None in Caster. Stealth uses its form's.
- **Combo rings are slots, the same in every form**: Ring 1-5 round the combo points, each showing one tracker (Empty, Faerie Fire, Primal Bite, Rake, Rip; Tiger's Fury etc. later as more tracker entries). A tracker brings its own look and timing (colours, segments, ticks); the ring is a position and an opacity. One tracker per ring; picking one that's on another ring swaps them. Defaults match today: FF 1, empty 2, PB 3, Rake 4, Rip 5. AuraContainer frames (Rake, Rip) can't move in combat, but assignments only change from the settings window, out of combat, so one set of frames does.

### Order of work

1. Panel layout: HUD controls (with the switch), preview buttons, zone strip, element rows, Reset.... **Done 2026-10-08** (commit 1b22123; seen in-game: hover, dots, Reset... and scrolling work). Since then: Stealth opacity under General; preview buttons reordered Caster, Bear, Cat, Prowl; the Rotation tab's build wrapped in `do ... end` (Options.lua's main chunk neared Lua's 200-locals limit).
2. ~~Form profiles~~: dropped, see above.
3. Combo ring slots: CooldownRings.lua and DotRings.lua become trackers placed on rings.
4. Above module slot: a per-form choice of module, with None. The Cooldown tracker module is separate work.

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
- **The cooldown box in the same scheme.** Partly done 2026-10-09: the Cooldown tab has the same frame controls and a preview of sample icons (design.md, Cooldown widget). Still open: its options as elements. Its opacity, alignment and icon settings as elements in the settings tree (its own zone, or the Cooldown tab built the same way), with a preview showing sample icons. It's a separate frame, not in `ns.hud`, so Preview.lua's layer and catcher would need one for it too.
- **More options per element** as wanted, e.g. hiding elements outright, text colour, the number's position.
- **Wrap-up:** fold this plan into design.md and architecture.md (both already describe what's built), leaving this file as a short history or removing it.
