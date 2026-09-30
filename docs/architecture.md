# Catnip architecture

How the code is organised, so a new session can start a feature without reading every file. For *why* things work this way under Midnight's combat restrictions, see [api-research.md](api-research.md). For what to build, see [design.md](design.md).

## Files (load order, from `Catnip.toc`)

| File | Owns |
|------|------|
| `Catnip.lua` | Core: the HUD frame (`ns.hud`, 240×240, alpha 0.85 for everything), shared sizes, saved settings, slash commands, debug helpers |
| `Layout.lua` | Moving/resizing the HUD: unlock mode (drag, mouse wheel), `/catnip lock`/`unlock`/`scale`/`reset`; `ns.SetHudScale`, `ns.SetHudPosition`, `ns.SetHudUnlocked`, `ns.IsHudUnlocked`, `ns.ResetHudLayout` |
| `CooldownManager.lua` | `ns.CDM`: reads Blizzard's Cooldown Manager frames. Now only the Clearcasting fallback uses it; also `/catnip cdm` |
| `AuraContainer.lua` | `ns.CreateAuraContainer`: shared setup for Blizzard's AuraContainer (how we show auras in combat) |
| `Resource.lua` | Big centre circle: energy/rage/mana fill + number (mana as %) |
| `ComboPoints.lua` | Five dots on an arc above the circle; Cat Form only |
| `Swing.lua` | Swing timer ring (Cooldown swipe from `PLAYER_SWING`) + Maul-queued tint |
| `Cast.lua` | Cast bar: takes the swing ring's place while casting or channelling (duration objects); hides Blizzard's player cast bar |
| `FiveSecondRule.lua` | Five-second-rule ring over the resource border (mana forms only); empties when a mana spell lands, then two arcs grow from 6 o'clock to meet at 12 over 5s |
| `Gcd.lua` | GCD "Harvey ball": faint white pie over the resource circle |
| `Proc.lua` | Clearcasting: additive crescent of light inside the top of the resource circle (AuraContainer; Cooldown Manager fallback) |
| `DotRings.lua` | DoT timer rings: Rake around combo dot 4, Rip around dot 5 (one AuraContainer each) |
| `Enrage.lua` | Bear Form: a red disc behind the rage fill while Enrage is up (AuraContainer), so the empty part of the circle reads red |
| `Options.lua` | Settings window (plain `/catnip`): custom-drawn section/button/checkbox/slider helpers; loads last so every module's `ns.*` functions exist |

New `.lua` files must be added to `Catnip.toc`. Order matters where a file uses another's `ns.*` (e.g. `DotRings.lua` needs `ComboPoints.lua` and `AuraContainer.lua` first).

## Shared namespace (`local addonName, ns = ...`)

**Core (`Catnip.lua`)**
- `ns.hud`: the frame everything draws in. Layout.lua positions and scales it.
- Sizes: `ns.RESOURCE_SIZE` (100), `ns.SWING_RING_SIZE` (134). `ns.MEDIA`: texture folder path.
- `ns.db`: saved settings (`CatnipDB`), ready inside `ns.OnLoad` callbacks. Modules add defaults to `ns.defaults` at file load.
- `ns.OnLoad(fn)`: run `fn` once saved settings are loaded (`ADDON_LOADED`).
- `ns.SettingsChanged()` after changing a setting; `ns.OnSettingsChanged(fn)` to react (the settings window refreshes on it). To add a setting: default in `ns.defaults`, an apply function in the owning module, a control in `Options.lua`.
- `ns.commands.<name> = fn(arg)`: adds `/catnip <name> <arg>`. `ns.commands[""]` is plain `/catnip`. Update the help text in `Catnip.lua` when adding one.
- `ns.Print(...)`, `ns.Debug(...)` (only with `/catnip debug` on; secret-safe), `ns.Describe(v)`, `ns.IsSecret(v)`.
- `ns.TryRegisterEvent(frame, event)`: registers an event that may not exist in this client; returns success.

**Features**
- `ns.CreateAuraContainer{ label, unit, filter, spellIDs, width, height, x, y, level, parent, initialize }` and `ns.HideAuraButtonArt(button)` (AuraContainer.lua). `ns.HAS_AURA_CONTAINER`.
- `ns.comboGroup`, `ns.COMBO_DOT_SIZE`, `ns.ComboDotOffset(i)` (ComboPoints.lua): for things placed around combo dots.
- `ns.swingRing` (Swing.lua): the swing Cooldown. Cast.lua sets its alpha to 0 while casting, so it keeps timing underneath.- `ns.IsClearcasting()` (Proc.lua): true/false, or nil if unknown (in combat without Omen of Clarity tracked in the Cooldown Manager).
- `ns.CDM.IsActive(spellID)`, `ns.CDM.OnChange(fn)` (CooldownManager.lua).

## Layering (frame levels above `ns.hud`)

| Level | What |
|-------|------|
| hud | Resource backdrop (soft circle), swing glow |
| +1 | Enrage tint (behind the fill), swing ring, cast ring (same spot; only one visible), combo dots group |
| +2 | Resource bar |
| +3 | GCD Harvey ball (over the fill) |
| +4 | Five-second-rule ring (over the resource border) |
| +5 | DoT ring AuraContainers (Rake, Rip) |
| bar +5 (+7) | Resource number (above the GCD shading) |
| +10 | Clearcasting AuraContainer (crescent) |
| +20 | Unlock overlay (Layout.lua) |

Gotcha: `CooldownFrameTemplate` pins its frame to fill the parent; call `ClearAllPoints()` before sizing it (see `Gcd.lua`).

## Patterns to reuse

- **Showing a secret number**: pass it straight to `StatusBar:SetValue`/`SetMinMaxValues` or `FontString:SetText`/`string.format`. Never compare or do math on it.
- **Showing an aura in combat** (buff on player, debuff on target): `ns.CreateAuraContainer`. Blizzard shows a button while the aura is up; our look goes on the button in `initialize` and must be static after that (the button and its children are off-limits to our code later). For a timer, create a `Cooldown` in `initialize` and register it with `button:SetDurationCooldown(cooldown)`: Blizzard drives it with the real duration. Examples: `Proc.lua` (static cap), `DotRings.lua` (timer rings).
- **Filling a round shape from the bottom**: a vertical `StatusBar` with a flat texture, masked (`CreateMaskTexture` + `AddMaskTexture`) to a circle or ring. Example: `Resource.lua`.
- **Arcs growing along a ring from any point** (a Cooldown swipe always starts at 12 o'clock): per side, a clip frame (`SetClipsChildren(true)`) showing half the ring, holding a half-ring texture that `SetRotation` swings into view. Example: `FiveSecondRule.lua` (two arcs from 6 o'clock meeting at 12).
- **Timer rings**: a `Cooldown` frame with `SetSwipeTexture(<ring texture>)`, `SetDrawEdge(false)`, `SetDrawBling(false)`, `SetHideCountdownNumbers(true)`. Starts full and empties clockwise. Plain-number timings go to `SetCooldown`; secret ones need a duration object (`SetCooldownFromDurationObject`).

## Textures

`py tools/make_textures.py` regenerates everything in `media/` (32-bit TGA). Textures are white shapes with transparency, tinted in-game with `SetVertexColor`/`SetSwipeColor`. To add one, write a shape function and add it to `TEXTURES`. After changing a ring's thickness, update any Lua constant that depends on it (they're commented, e.g. `ComboPoints.lua` `RING_THICKNESS`, `DotRings.lua` `RING_SIZE`). Preview textures before shipping: an earlier bug left a texture's corners opaque.

Current set: `circle_hard` (combo fills), `circle_feather` (soft ~3px edge: resource fill mask, GCD, Enrage), `crescent_line` and `crescent_bloom` (Clearcasting, drawn with `SetBlendMode("ADD")`) over `crescent_shadow` and `crescent_edge` (tinted black, normal blend; on the full `circle_feather` canvas, so they line up with the fill), `circle_soft`, `ring_thin` (resource border), `ring_small` (combo dots), `ring_rip` (DoT rings), `ring_mana_half` (five-second rule: a ring's left half on a full-size canvas, for rotating), `ring_glow`, `ring_bar` (swing).

## Debugging and testing

The user tests in-game; Claude can't run the game. Each change ends with exact steps and what to look for.

- `/catnip debug` toggles grey debug lines (saved). Modules print startup facts, e.g. which detection method is active.
- `/catnip cdm` lists what the Cooldown Manager is tracking and what's readable.
- Errors: BugSack is **not** installed in the Forever client (checked 2026-09-27); ask the user for the full error text.
- `/reload` picks up code, `.toc` file lists and textures, but **not a new `## SavedVariables` name** (probably needs a restart); keep new saved data inside `CatnipDB`.
- To verify an unknown API, add debug output that prints what the game actually returns (with `ns.Describe`, which shows `<secret>`), test in and out of combat, then record the result in api-research.md.

## Reference addons

Check these before general web searching, in this order:

1. **[EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI)**: a large Midnight UI suite with many active contributors, now being adapted for Forever. The best source for current API usage. Search its code and pull requests: Forever-specific fixes land as PRs, e.g. the swing timer via `PLAYER_SWING` (PR #2150) and the Forever GCD fix (PR #2240).
2. **Blood in the Water** (another Forever Feral addon), installed locally at `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\BloodInTheWater\`. Its comments document many Forever quirks; it's where the AuraContainer technique came from.
3. **[EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager)**: the Cooldown Manager reading technique.

## Releasing

1. Bump `## Version` in `Catnip.toc` (e.g. `0.1.0-beta.3`).
2. The user commits, pushes, then tags and pushes the tag: `git tag v0.1.0-beta.3`, `git push origin v0.1.0-beta.3`.
3. `.github/workflows/release.yml` builds `Catnip-<tag>.zip` (a `Catnip/` folder) and publishes it on the Releases page. Tags containing `-` become pre-releases. `.gitattributes` keeps dev files (`docs/`, `tools/`, `CLAUDE.md`, etc.) out of the zip.
4. Keep `README.md` (player-facing install and usage) in sync with features.
