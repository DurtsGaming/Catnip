# Midnight API research

How Catnip's MVP features can work under Midnight's addon restrictions, which Forever inherits. Researched 2026-09-27 from web sources (listed at the bottom). **Nothing here has been verified in the Forever client yet**; see "Verify in-game".

## How the restrictions work

- **Secret values.** Restricted APIs return values that are sealed boxes. Addon code can't compare them, do math on them, or save them. Addon code *can* pass them into certain widget methods, which render them: `StatusBar:SetValue`, `StatusBar:SetMinMaxValues`, `Cooldown:SetCooldown`, `FontString:SetText`, `SetAlpha`, `SetRotation`, texture coloring. `string.format` and `C_StringUtil` accept them too. Test with `issecretvalue(v)`.
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
| Energy/rage circle fill | Vertical `StatusBar` with a circle texture; pass the secret `UnitPower`/`UnitPowerMax` to `SetMinMaxValues`/`SetValue` | Low |
| Energy/rage number | `FontString:SetText(UnitPower(...))`, which accepts secrets | Low |
| Combo points | Plain logic; not secret | Low |
| Swing timer | **Option A:** `PLAYER_SWING(duration, weaponSlot)` event plus a duration object plus `StatusBar:SetTimerDuration` (as in EllesmereUI). **Option B:** predict from `UnitAttackSpeed` alone (as in SwingBarMidnight, which says retail 12.1 has no exact hit timestamp). A may be new in 12.1.5 or Forever-only. | Medium: need to check if `PLAYER_SWING` exists |
| Maul queued | `C_Spell.IsCurrentSpell(maul)` on `ACTIONBAR_UPDATE_STATE`; treat a secret answer as "not queued", or use `SetVertexColorFromBoolean` | Medium |
| Rip/Rake rings | Catch our own Rake/Rip in `UNIT_SPELLCAST_SUCCEEDED` (not secret). Match it to the target's new aura in `UNIT_AURA` `updateInfo.addedAuras` and remember its `auraInstanceID`. Feed its (secret) duration into a self-updating timer widget. | **High:** refreshes, target switching and false matches are hard; the exact duration-object API for auras is unconfirmed |
| Clearcasting | Player buff: find via `GetUnitAuras("player", "HELPFUL")`; identify by spell ID if not secret, else by the matching trick (it's triggered by our own casts) | Medium |
| Round ring fills (DoTs, swing) | A `StatusBar` can't draw a curved fill. Common approach: two half-circle textures rotated with `SetRotation`, which accepts secrets. | Medium: technique question, not API |

**Fallback:** the built-in Cooldown Manager already supports Druid and has Blizzard-level data access. Addons like BetterCooldownManager and TerribleBuffTracker restyle its icons instead of reading the data themselves. If the Rip/Rake matching fails, Catnip could place Blizzard's tracked-debuff display inside our layout.

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
