# Midnight API research

What we know about Forever's addon API: Midnight's (12.x) rules with Forever-specific quirks. Each fact says whether it was **verified** in Catnip in the Forever client (with the date) or comes from a source. When something new is verified or disproved, update this file.

## How the restrictions work

- **Secret values.** In combat, restricted APIs return sealed values. Addon code can't compare them, do math on them, or save them. It *can* pass them to some widget methods, which display them.
  - Accept secrets (verified 2026-09-27): `StatusBar:SetValue`, `StatusBar:SetMinMaxValues`, `FontString:SetText`, `string.format`.
  - Accept secrets (from sources, untested by us): `SetAlpha`, `SetRotation`, texture colouring, `C_StringUtil`.
  - **Reject secrets from addon code** (verified): `Cooldown:SetCooldown` ("Secret values are only allowed during untainted execution"). For secret timings use duration objects: `C_Spell.GetSpellCooldownDuration(id)` → `Cooldown:SetCooldownFromDurationObject`.
  - `issecretvalue(v)` tests a value; `ns.IsSecret` wraps it.
- **Tainted vs. untainted.** Blizzard's own code gets real numbers; addon code gets secrets. Hooking Blizzard's frames doesn't help: the hook is addon code too.
- **When restrictions apply:** in combat (including open world and target dummies), boss encounters, Mythic+, PvP. Out of combat most values are readable.
- **Design rule:** Catnip can *display* combat data but not *decide* things from it. "Fill a bar with energy" works; "glow when energy > 40" doesn't.
- **Forbidden objects.** Some Blizzard frames (AuraContainer buttons) error on *any* method call from addon code, even `IsShown()`, and frames we attach to them become forbidden too (verified).

## What's readable in combat (verified in Forever unless noted)

| Data | In combat |
|------|-----------|
| Energy, rage, mana (`UnitPower`, `UnitPowerMax`) | Secret; display via StatusBar/FontString |
| Mana as a percentage | `UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100)`: computed engine-side (0-100), then `string.format("%d%%", …)`. **Verified** 2026-09-27 |
| Combo points (`UnitPower("player", Enum.PowerType.ComboPoints)`) | Readable (dots work in combat). **Open issue:** Blood in the Water says Forever combo points are per-target and `UnitPower` doesn't reset on target switch; it uses `GetComboPoints("player", "target")`. Unverified by us |
| `UnitPowerType` | Readable |
| `PLAYER_SWING(duration, slot)` | Readable number (Cat 0.99s, Bear 2.475s); slot 0 = main hand. `C_SwingTimer` exists |
| `C_Spell.IsCurrentSpell("Maul")` | Readable |
| Player's own casts (`UNIT_SPELLCAST_SUCCEEDED`, spell ID) | Readable |
| Ability cooldowns (`C_Spell.GetSpellCooldown`) | `startTime`, `duration`, `modRate` secret; `isOnGCD`, `isActive`, `isEnabled` readable |
| Player buffs by ID (`C_UnitAuras.GetPlayerAuraBySpellID`) | **Returns nil** in combat (works out of combat) |
| `UNIT_AURA` `updateInfo.addedAuras` | The whole list is a secret table; can't loop over it |
| `auraInstanceID` | Secret (at least on Cooldown Manager items; one source claimed otherwise) |
| Cooldown Manager items | `cooldownInfo.spellID`, `cooldownID`, `IsShown()` readable; `auraInstanceID` secret |
| `COMBAT_LOG_EVENT_UNFILTERED` | Removed from the addon API (source) |

## Techniques that work

### AuraContainer: showing auras in combat (verified)

Patch 12.1.0 widget; the main tool for buffs and debuffs. Learned from the Blood in the Water addon. Catnip's shared setup is `AuraContainer.lua` (`ns.CreateAuraContainer`).

- `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`. We configure: `SetUnit("player"/"target")`, `SetAuraGroupFilterString("main", "HELPFUL|PLAYER")` (or `HARMFUL|PLAYER`), `SetAuraGroupCandidateFilters("main", { includeSpellIDs = {[id]=true} })`, `SetAuraGroupMaxFrameCount`, `SetAuraGroupLayout`, `SetFlowLayoutAnchorPoint`/`SetFlowLayoutGrowthDirection` (required, or nothing shows), `SetEnabled(true)`.
- Blizzard's engine fetches and filters the auras and shows an `AuraButton` while a match is up. Our code never learns whether it's up.
- **Containers can't be created in combat.** Unit and filters can change any time; re-apply on `PLAYER_TARGET_CHANGED` for target containers.
- **Buttons are pooled (10) and created at setup**, out of combat, when `initializeFrame(button)` runs. They start **empty and zero-sized**: size them there, or nothing on them shows.
- **Buttons are forbidden after setup**, and so is anything we parent to them. So our look must be **static** (textures, animations). Anything that needs updating must live outside the button, and the button can't tell our code when it's shown (an `OnShow`-script "gate" idea is untested).
- **Register our own widgets** and Blizzard drives them with real aura data: `button:SetDurationCooldown(cooldownFrame)` (timer swipe; used for Rip), `SetIcon(texture)`, `SetApplicationCount(fontString)`, `AddPandemicRegion(region)`.
- Feature check: `C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")`.

### Global cooldown (verified)

- Retail's GCD dummy spell 61304 **doesn't exist in Forever**. Forever reports the GCD on **Classic's GCD spell 29515** (from [EllesmereUI PR #2240](https://github.com/EllesmereGaming/EllesmereUI/pull/2240)).
- In combat, start and duration are secret, but `isActive`/`isOnGCD` are readable. So: when `isActive`, `C_Spell.GetSpellCooldownDuration(29515)` → `SetCooldownFromDurationObject`. Backup if that's ever rejected: on `isOnGCD`, run our own sweep of the Classic length (1.0s energy abilities, 1.5s otherwise).
- Can't scale anything to the GCD or attack speed in combat: the numbers are secret.

### Swing timer (verified)

`PLAYER_SWING` gives a plain duration, so `Cooldown:SetCooldown(GetTime(), duration)` works. If Blizzard ever makes it secret, SetCooldown will reject it. An earlier counter-clockwise version used two rotated half-ring textures in clip frames (`SetClipsChildren` + `SetRotation`); it worked, but was dropped when the design went clockwise.

### Cooldown Manager reading (verified; now only a fallback)

The Cooldown Manager viewers (`BuffIconCooldownViewer`, `BuffBarCooldownViewer`, `EssentialCooldownViewer`, `UtilityCooldownViewer`) are ordinary frames; each tracked spell is a child. Identify an item by `cooldownInfo.spellID` and read `IsShown()`. Needs the player to track the spell in the Cooldown Manager, so AuraContainer replaced it. Technique from [EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager/blob/HEAD/Modules/BuffBars.lua). `/catnip cdm` dumps the items.

## Forever spell and aura IDs

| What | IDs |
|------|-----|
| Clearcasting (buff) | 16870 |
| Omen of Clarity (talent; Cooldown Manager tracks this) | 16864 |
| Rip ranks (each rank's aura has its own ID) | 1079, 9492, 9493, 9752, 9894, 9896 |
| Rake ranks | 1822, 1823, 1824, 9904 (not yet unlocked in the beta) |
| GCD spell | 29515 |
| Tiger's Fury / Berserk (from Blood in the Water) | 5217 / 417141 |

## Dead ends (don't retry)

- Reading the GCD from spell 61304 (doesn't exist in Forever).
- Passing secret cooldowns to `Cooldown:SetCooldown`.
- Matching new auras via `UNIT_AURA` `addedAuras` + `auraInstanceID` (both secret in combat).
- A cast-event timer for Rip (guessed the duration, lost track on target switches); replaced by AuraContainer.
- Updating frames attached to AuraContainer buttons (forbidden).
- `C_UnitAuras.GetPlayerAuraBySpellID` in combat (returns nil).

## Sources

- [Warcraft Wiki: Patch 12.0.0 planned API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes): the main technical reference (some claims turned out wrong for Forever; trust verified facts above)
- [Blizzard: Combat philosophy and addon disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- Blood in the Water addon (local, see [architecture.md](architecture.md#reference-addons))
- [EllesmereUI PR #2150](https://github.com/EllesmereGaming/EllesmereUI/pull/2150) (swing timer), [PR #2240](https://github.com/EllesmereGaming/EllesmereUI/pull/2240) (Forever GCD)
- [EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager)
- [C_Spell.GetSpellCooldown](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown), [Cooldown:SetCooldown](https://warcraft.wiki.gg/wiki/API_Cooldown_SetCooldown)
