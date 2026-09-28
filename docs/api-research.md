# Midnight API research

How Catnip's MVP features can work under Midnight's addon restrictions, which Forever inherits. Researched 2026-09-27 from web sources (listed at the bottom). **Nothing here has been verified in the Forever client yet**; see "Verify in-game".

## How the restrictions work

- **Secret values.** Restricted APIs return values that are sealed boxes. Addon code can't compare them, do math on them, or save them. Addon code *can* pass them into certain widget methods, which render them: `StatusBar:SetValue`, `StatusBar:SetMinMaxValues` (both verified), `FontString:SetText` (verified), `SetAlpha`, `SetRotation`, texture coloring. `string.format` and `C_StringUtil` accept them too. Test with `issecretvalue(v)`. **Not** `Cooldown:SetCooldown`: it rejects secrets from addon code ("Secret values are only allowed during untainted execution", verified 2026-09-27). For secret cooldowns use duration objects: `C_Spell.GetSpellCooldownDuration(id)` into `Cooldown:SetCooldownFromDurationObject`.
- **When restrictions apply:** in combat (including open world and target dummies), during boss encounters, in Mythic+, and in PvP matches. Outside those, most APIs return normal values.
- **Design rule this implies:** Catnip *displays* combat data but can't *decide* things based on it. "Show energy as a fill" works. "Glow when energy > 40" doesn't, unless the value is non-secret.

## Helper APIs built for this

- **Duration objects:** `C_DurationUtil.CreateDuration()`, `:SetTimeFromStart(start, duration)`, `:SetTimeSpan(start, end)`.
- **Self-updating timers:** `StatusBar:SetTimerDuration(durationObj, interpolation)` and `StatusBar:SetTimer(expirationTime, duration, modRate)`. The bar animates on its own, and addon code never sees the numbers.
- **Booleans:** `SetAlphaFromBoolean(bool, alphaIfTrue, alphaIfFalse)` and `SetVertexColorFromBoolean(bool, colorIfTrue, colorIfFalse)` show or tint something based on a secret true/false.
- **Auras:** `C_UnitAuras.GetUnitAuras(unit, filter, max, sortRule, sortDir)` (the list itself isn't secret, but its contents are) and `C_UnitAuras.GetAuraDurationRemainingPercent(auraInstanceID, curve)`.
- **Cooldowns:** `C_Spell.GetSpellCooldownRemaining(spellID)` returns a duration object.
- **Restriction state:** `C_RestrictedActions.IsRestrictionActive(Enum.AddOnRestrictionType.X)`.

## What's secret and what isn't

| Data | Status |
|------|--------|
| Energy, rage, mana (`UnitPower`/`UnitPowerMax`, primary power) | **Secret**, always |
| Combo points | **Not secret** (secondary resource) |
| Player's own casts (`UNIT_SPELLCAST_*` on `player`) | **Not secret**, even in combat |
| `auraInstanceID` | **Never secret** |
| Aura spell IDs, names, durations | Secret while restricted (player buffs less restricted than target debuffs) |
| Spell cooldowns | Secret while restricted (some whitelisted) |
| `COMBAT_LOG_EVENT_UNFILTERED` | **Removed** from the addon API entirely |
| `UnitAttackSpeed`, `PLAYER_SWING` args, `C_Spell.IsCurrentSpell` | May be secret; addons guard with `issecretvalue` |

## MVP feature plan

| Feature | Approach | Risk |
|---------|----------|------|
| Energy/rage circle fill | Vertical `StatusBar` with a circle texture; pass the secret `UnitPower`/`UnitPowerMax` to `SetMinMaxValues`/`SetValue` | **Verified in combat** 2026-09-27 (Cat, Bear, caster) |
| Energy/rage number | `FontString:SetText(UnitPower(...))`, which accepts secrets | **Verified in combat** 2026-09-27 |
| Combo points | Plain logic; not secret. `UnitPower("player", Enum.PowerType.ComboPoints)` works (player-based, not Classic target-based) | **Verified** 2026-09-27 |
| Swing timer | `PLAYER_SWING(duration, weaponSlot)` fires at the start of each swing. `C_SwingTimer` exists too. The duration is a **plain number, not secret, even in combat** (Cat 0.99s, Bear 2.475s); slot is `0` for main hand. Because it's readable, `Cooldown:SetCooldown(GetTime(), duration)` accepts it; the swipe empties clockwise. (A counter-clockwise version used two rotated half-ring textures in clip frames; dropped when the design went clockwise.) If Blizzard makes it secret later, SetCooldown will reject it. | **Verified** 2026-09-27 |
| Global cooldown | GCD dummy spell 61304 **doesn't exist in Forever**; Forever reports the GCD on **Classic's GCD spell 29515** (from [EllesmereUI PR #2240](https://github.com/EllesmereGaming/EllesmereUI/pull/2240), which fixed exactly this). In combat `C_Spell.GetSpellCooldown` returns start/duration/modRate as secrets but **`isOnGCD`, `isActive` and `isEnabled` as plain booleans** (verified). `SetCooldown` rejects the secrets, so: duration object via `GetSpellCooldownDuration` + `SetCooldownFromDurationObject`, with an `isOnGCD` + Classic GCD length (1.0s energy, 1.5s otherwise) backup. | Harvey ball in `Gcd.lua`, duration-object route being tested 2026-09-27 |
| Maul queued | `C_Spell.IsCurrentSpell("Maul")` on `ACTIONBAR_UPDATE_STATE` / `CURRENT_SPELL_CAST_CHANGED`. Not secret in combat. | **Verified** 2026-09-27 |
| Clearcasting | **Via the Cooldown Manager** (see below): watch the CDM item for Omen of Clarity (16864). The direct `C_UnitAuras.GetPlayerAuraBySpellID(16870)` works out of combat but **returns nil in combat**. In combat `UNIT_AURA`'s `updateInfo.addedAuras` is also a *secret table*. | CDM signal verified 2026-09-27; claws being tested |
| Rip/Rake rings | **AuraContainer** on `target`, `HARMFUL\|PLAYER`, filtered to every Rip rank; our own Cooldown frame (swipe = our ring) registered via `button:SetDurationCooldown`, so Blizzard drives the real timing. Replaces the earlier plan (cast-event timer + Cooldown Manager presence), which guessed the duration and lost track on target switches. The `addedAuras` matching trick doesn't work in combat (secret table). Rake: same approach once unlocked. | Being tested 2026-09-27 |
| Round ring fills (DoTs, swing) | A `StatusBar` can't draw a curved fill. Common approach: two half-circle textures rotated with `SetRotation`, which accepts secrets. | Medium: technique question, not API |

**Cooldown Manager as a data source (verified in Forever 2026-09-27).** The CDM viewers (`BuffIconCooldownViewer`, `BuffBarCooldownViewer`, plus `EssentialCooldownViewer`, `UtilityCooldownViewer`) are ordinary frames; each tracked spell is a child. In combat: `item.cooldownInfo.spellID` and `item.cooldownID` stay **readable**, `item.auraInstanceID` is **secret** (contrary to one source), and `item:IsShown()` is **readable and follows the buff**. So: identify the item by spell ID, read `IsShown()`. The user has to add the spell to the CDM's tracked buffs/bars. Rip (1079) can be tracked there; Rake not testable yet (not unlocked at the current beta level). Technique from [EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager/blob/HEAD/Modules/BuffBars.lua). `/catnip cdm` dumps what's readable.

**AuraContainer (found 2026-09-27 in the Blood in the Water addon, works in Forever).** Patch 12.1.0 added a Blizzard widget made for this: `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`. The addon only configures it (`SetUnit`, `SetAuraGroupFilterString("main", "HELPFUL|PLAYER")`, `SetAuraGroupCandidateFilters("main", { includeSpellIDs = {...} })`, `SetAuraGroupMaxFrameCount`, `SetEnabled`), and Blizzard's engine fetches, filters and updates the auras itself, showing an `AuraButton` (with its own `Cooldown` swipe) while a matching aura is up. No Cooldown Manager setup needed from the user. Caveats: containers can't be *created* in combat (filters and units can change any time); AuraButtons can only be restyled out of combat (`initializeFrame` callback), and the addon never learns in Lua whether the aura is up, so visuals must live on the button. Feature check: `C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")`. **Verified in Catnip 2026-09-27** (Clearcasting claws): the container pre-creates a pool of 10 buttons at setup, out of combat, so `initializeFrame` runs then; buttons start at **zero size** and must be sized there or nothing on them shows; our own child frame (textures + animation) on the button shows and hides with the aura, in combat. AuraButtons are **forbidden objects** to addon code: even `button:IsShown()` errors ("Attempt to access forbidden object"), so don't query them after setup. **Frames we parent to a button become forbidden too** (2026-09-27: `SetShown` on our own child StatusBar errored in combat), so anything on a button must be static after setup (textures, animations). For something that must update, keep it outside the button. An untested idea: a tiny child frame's `OnShow`/`OnHide` scripts on the button as the on/off signal (tried for a Clearcasting energy preview, which was removed before it was verified). Buttons start **empty**: the addon creates its own widgets and registers them, and Blizzard then drives them with the real aura data: `button:SetIcon(texture)`, `button:SetDurationCooldown(cooldownFrame)` (timer swipe), `button:SetApplicationCount(fontString)` (stacks), `button:AddPandemicRegion(region)` (shown in the refresh window). Catnip's shared setup is `AuraContainer.lua`.

**Forever combo points (from Blood in the Water's comments, unverified by us):** combo points are per-target, Classic-style. `UnitPower("player", 4)` does *not* reset on `PLAYER_TARGET_CHANGED`; that addon reads `GetComboPoints("player", "target")` instead. Catnip's combo dots currently use `UnitPower`. Forever aura IDs from that addon: Clearcasting 16870; Rip ranks 1079, 9492, 9493, 9752, 9894, 9896; Rake ranks 1822, 1823, 1824, 9904.

**Earlier fallback idea:** the built-in Cooldown Manager already supports Druid and has Blizzard-level data access. Addons like BetterCooldownManager and TerribleBuffTracker restyle its icons instead of reading the data themselves. If the Rip/Rake matching fails, Catnip could place Blizzard's tracked-debuff display inside our layout.

## Verify in-game (next step)

A probe module that prints, in and out of combat on a target dummy:
1. `issecretvalue()` on energy, rage, energy max, combo points.
2. Whether `PLAYER_SWING` can be registered, and whether `C_SwingTimer` exists; if so, its payload.
3. `UnitAttackSpeed("player")`, and whether it's secret.
4. `UNIT_SPELLCAST_SUCCEEDED` spell IDs for Rake/Rip/Maul.
5. `UNIT_AURA` `addedAuras` on target: which fields come through, and which are secret.
6. `C_Spell.IsCurrentSpell` for Maul while queued.
7. Whether the helper APIs above exist in Forever (`C_DurationUtil`, `StatusBar.SetTimerDuration`, `C_RestrictedActions`, etc.).

## Sources

- [Warcraft Wiki: Patch 12.0.0 planned API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes): the main technical reference
- [Blizzard: Combat philosophy and addon disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- [EllesmereUI PR #2150: swing timer via PLAYER_SWING](https://github.com/EllesmereGaming/EllesmereUI/pull/2150)
- [SwingBarMidnight: UnitAttackSpeed-based prediction](https://github.com/UnknownAlienHuman/swing-bar-midnight)
- [Spiritbloom.Pro: tracking specific buffs in Midnight (auraInstanceID matching)](https://spiritbloom.pro/blog/tracking-buffs-in-midnight)
- [Warcraft Tavern: secret values, Cooldown Manager](https://www.warcrafttavern.com/wow/news/wow-midnight-developer-talk-new-secret-values-combat-info-cooldown-manager-combat-addons-nerfed/)
