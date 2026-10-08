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
- **Alpha animations can leave a texture stuck at their from-alpha** (seen 2026-10-03, cause not pinned down): ShiftingPower.lua's ready flash (an Alpha animation 0.7 → 0 on a texture whose base alpha was 0) ran while its parent frame faded out and was hidden; on every later cooldown the texture stayed at 0.7, though the group was `Stop()`ped before the frame was shown again. The first cooldown after a `/reload` was always fine. Don't rely on the animation to restore the alpha of a one-shot effect: `Hide()` the texture when its group finishes or stops, `Show()` it just before `Play()` (`OneShot` in ShiftingPower.lua). Fix untested at time of writing.
- **No script handlers on AuraContainer buttons** (verified 2026-10-01): `SetScript("OnShow", …)` on a frame we create on a button at setup fails with "Cannot assign script handler for 'onshow' (blocked by secret aspects)", even inside `initializeFrame`. Start looping animations once with `Play()` at setup instead (as Blood in the Water does).
- **Don't `SetCVar` from addon code** (suspected 2026-10-02): with Catnip's "Show cooldown numbers" checkbox (which set `countdownForCooldowns`) in use, an incoming Battle.net whisper errored in Blizzard's chat: "attempt to perform string conversion on a secret string value (execution tainted by 'Catnip')" in `SetLastTellTarget`, which upper-cases the sender's secret name. Unticking it seemed to stop the error. The checkbox was removed; players change the option in WoW's settings. EllesmereUIChat documents the same failure for any addon taint that reaches the chat handler.
- **Hiding Blizzard's Action Bar 1** (from EllesmereUI's notes, unverified by us): it's `MainActionBar` on Forever (no `MainMenuBar`). `Hide()`/`HideBase()` or reparenting it from addon code taints its protected shown state, so a later combat bar change hits ADDON_ACTION_BLOCKED. `SetAlpha(0)` (re-applied in a `hooksecurefunc(bar, "Show")`) is unprotected and combat-safe. Other bars (MultiBar*, StanceBar) are safe to reparent to a hidden frame, but EllesmereUI replaces them with its own buttons and bindings when it does. Catnip uses the alpha approach for StanceBar too, so form keybinds keep working (unverified that they do). `MainMenuBarVehicleLeaveButton` is a child of Action Bar 1, so the fade hid it too (seen in-game 2026-10-03); Catnip sets `SetIgnoreParentAlpha(true)` on it while the bar is hidden (verified: bar alpha 0, button effective alpha 1). EllesmereUI reparents it to UIParent instead, but then has to own its show/hide, which is protected (Edit Mode-managed) and blocked in combat.
- **Leave-vehicle button on flight paths** (verified 2026-10-03): Blizzard never shows `MainMenuBarVehicleLeaveButton` on a taxi on Forever, with or without Catnip. `UnitOnTaxi` and `CanExitVehicle()` are true but `IsShown()` is false; calling `MainMenuBarVehicleLeaveButton:Update()` by hand shows it. Its mixin only listens to `UPDATE_BONUS_ACTIONBAR`, `UPDATE_MULTI_CAST_ACTIONBAR`, `UNIT_ENTERED/EXITED_VEHICLE` and `VEHICLE_UPDATE`. `VehicleLeaveButton.lua` calls `Update()` for it during flights, but only when the route has a connection (`GetNumRoutes(slot) > 1`, read in `hooksecurefunc("TakeTaxiNode", …)`), so direct flights keep it hidden. After a `/reload` mid-flight the route is unknown and the button stays hidden. `PLAYER_CONTROL_LOST/GAINED`, `TakeTaxiNode` and `GetNumRoutes` are not in the generated API docs, but EllesmereUIForeverEssentials' flight timer uses all of them on Forever (not yet verified by us).
- **Forbidden objects.** Some Blizzard frames (AuraContainer buttons) error on *any* method call from addon code, even `IsShown()`, and frames we attach to them become forbidden too (verified).
- **A cast can still be reported after its stop event** (seen 2026-10-03, untested fix): after Skinning, Cast.lua's text stayed frozen at "3.0 / 3.0s Skinning". It only checked `UnitCastingInfo`/`UnitChannelInfo` on cast events, and nothing fired after the stop. Meanwhile the orbs, re-checking on mana ticks, saw no cast moments later. Cast.lua now re-checks 0.2s and 1s after any stop, fail or interrupt event.

## What's readable in combat (verified in Forever unless noted)

| Data | In combat |
|------|-----------|
| Energy, rage, mana (`UnitPower`, `UnitPowerMax`) | Secret; display via StatusBar/FontString |
| Thresholds on secret power (step curves) | `C_CurveUtil.CreateCurve()` + `SetType(Enum.LuaCurveType.Step)` + `AddPoint(fractionOfMax, value)`, evaluated by `UnitPowerPercent(unit, powerType, false, curve)` C-side, so the secret never enters Lua; the result goes straight to `SetAlpha`. Blood in the Water (colour curve → `SetTextColor`) and EllesmereUI (alpha curves → `SetAlpha`; mana colour curve → `SetVertexColor`) do this on Forever. Calling `curve:Evaluate(secret)` from Lua errors in combat (Blood in the Water). Ours (`ShiftOrbs.lua`) untested. Whether `CreateCurve` works **in combat** is unverified: ShiftOrbs.lua's mana prediction makes curves at cast start (pcall'd; a failure logs "can't make prediction curves" with `/catnip debug`) |
| Mana as a percentage | `UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100)`: computed engine-side (0-100), then `string.format("%d%%", …)`. **Verified** 2026-09-27 |
| Combo points | `UnitPower("player", Enum.PowerType.ComboPoints)` is readable in combat, but Forever combo points are per-target (classic rules) and it doesn't reset when the target dies (seen 2026-10-03) or on a target switch (Blood in the Water). Catnip now reads `GetComboPoints("player", "target")` like BitW and EllesmereUI. BitW found that secret in combat, so each dot is a StatusBar (range i-1..i) fed the raw value, which never compares it in Lua. `UNIT_COMBO_POINTS` registration is wrapped; unverified it exists |
| `UnitPowerType` | Readable |
| `PLAYER_SWING(duration, slot)` | Readable number (Cat 0.99s, Bear 2.475s); slot 0 = main hand. `C_SwingTimer` exists |
| `C_Spell.IsCurrentSpell("Maul")` | Readable |
| Player's cast or channel (`UnitCastingInfo`, `UnitChannelInfo`) | Unverified. ThreatPlates (Forever-adapted, installed locally) treats start/end times as secret and uses `UnitCastingDuration`/`UnitChannelDuration` duration objects instead; `Cast.lua` does the same via `Cooldown:SetCooldownFromDurationObject`. For text, ThreatPlates passes `duration:GetRemainingDuration()` straight to `string.format` every frame; `GetElapsedDuration`/`GetTotalDuration` are assumed (unverified) and `Cast.lua` falls back to remaining-only if they're missing |
| Player's own casts (`UNIT_SPELLCAST_SUCCEEDED`, spell ID) | Readable |
| Spell costs (`C_Spell.GetSpellPowerCost(spellID)`) | Works out of combat: skinning correctly shows no mana cost (verified 2026-09-30). In combat unverified. `FiveSecondRule.lua` uses it to tell mana spells from energy/rage/free ones, and assumes "costs mana" if it can't read it. Unknown whether it reflects Clearcasting (cost 0). `ManaPrediction.lua` reads it on `UNIT_SPELLCAST_START` (spell ID from the event, assumed plain) and skips the prediction if either is secret; it also assumes `Enum.StatusBarInterpolation.Immediate` exists (nil falls back to the bar's default), and anchors frames to StatusBar fill textures whose size comes from secret mana (unverified in combat; the `SetPoint` calls are wrapped in `pcall` and the prediction is skipped if refused) |
| `UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)` | Unverified. Fires on button press, before the cast consumes Clearcasting; `FiveSecondRule.lua` records whether Clearcasting was up here, then 0.2s after `UNIT_SPELLCAST_SUCCEEDED` checks whether the cast used it up. Clearcasting only applies to damage/healing spells: shapeshifts, Wrath and buffs cast with it up still spend mana (seen 2026-09-30) |
| Ability cooldowns (`C_Spell.GetSpellCooldown`) | `startTime`, `duration`, `modRate` secret; `isOnGCD`, `isActive`, `isEnabled` readable. EllesmereUI notes `isOnGCD` can come back **nil** outside a `SPELL_UPDATE_COOLDOWN` handler (unverified by us). Suspected 2026-10-01: `isOnGCD` turns true for a spell already on a long cooldown (Enrage) whenever another spell starts the GCD, and the GCD's end fires no event. `Cooldowns.lua` therefore treats "`isActive` and no GCD running (spell 29515)" as a real cooldown, keeps its last answer during a GCD, and re-checks 1.6s later (debug lines log each change) |
| Cooldown countdown numbers | Blizzard draws them on any `Cooldown` with `SetHideCountdownNumbers(false)`, including AuraContainer buttons' duration cooldowns (Blood in the Water). EllesmereUI treats the `countdownForCooldowns` CVar as the gate for them; EllesmereUI says the CVar only gates Blizzard's own `SetHideCountdownNumbers` calls, so a frame set to `false` draws numbers regardless (unverified by us) |
| Item cooldowns (`C_Container.GetItemCooldown(itemID)` → start, duration, enable) | EllesmereUI's Cooldown Manager passes them straight to `Cooldown:SetCooldown` on Forever, implying plain numbers even in combat (it still drops secrets defensively). Unverified by us. `enable` 0 means the cooldown waits for combat to end. Items have a ~1.5s shared lockout on use (ignore durations ≤ 1.5s). `BAG_UPDATE_COOLDOWN` fires on item cooldown changes (EllesmereUI: also on every ability press) |
| Shared potion cooldown | Reports on every potion you own; after drinking the last of a kind, only on that item's ID (EllesmereUI). Potion detection: Consumable class, Potion subclass, with an English-name fallback in case classic item data files potions as plain Consumable (unverified which applies) |
| Form versions of a spell (`C_Spell.GetBaseSpell`, `C_Spell.GetOverrideSpell`) | Seen 2026-10-02: Faerie Fire wasn't listed, presumably because its caster version has no cooldown (unverified that Faerie Fire (Feral) is an override rather than a separate spell). Seen 2026-10-01: Feral Charge's spellbook entry reports a different spell (Feral Charge (Cat)/(Bear)) per form. Both functions are used by EllesmereUI on Forever; ours (`Cooldowns.lua`) is untested |
| Spellbook (`C_SpellBook.GetNumSpellBookSkillLines`, `GetSpellBookSkillLineInfo`, `GetSpellBookItemType(index, bank)`) | Used by EllesmereUI on Forever (`EllesmereUI_Range.lua`); `Cooldowns.lua` uses the same walk. `GetSpellBaseCooldown` (used to skip GCD-only spells) is unverified |
| Player buffs by ID (`C_UnitAuras.GetPlayerAuraBySpellID`) | **Returns nil** in combat (works out of combat) |
| Auras by index (`C_UnitAuras.GetAuraDataByIndex`) | **Errors** when auras are secret ("Auras cannot be accessed when secret while tainted"), rather than returning nil or a secret. Seen 2026-10-05 in a battleground **out of combat** (`InCombatLockdown()` false, 0.5s after casting Prowl), so `InCombatLockdown()` isn't a safe gate there. `Cooldowns.lua` also checks `C_Secrets.ShouldAurasBeSecret()` and wraps the call in `pcall` |
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
- **Ordering active auras (unverified by us, found 2026-10-03):** one container can hold several groups (`AddAuraGroup` per key). The container's flow layout places groups in `layout.layoutIndex` order and **collapses empty groups**, so one group per spell, each limited to that spell with `includeSpellIDs`, gives a gapless run of whichever are up, in priority order, without our code knowing which. Groups are add-only (turn one off with `SetAuraGroupMaxFrameCount(key, 0)`), and each group allocates 10 buttons. Source: EllesmereUI raid frames "Custom Order" (`EUI_RaidFrames_AuraContainers.lua`, `BmSegments`; layout helpers in `EllesmereUI_AuraKit.lua`). Limit: our own frames can't join that flow, so the cooldown icons can't be packed in after it.
- **Moving AuraContainer frames in combat is blocked**, even `SetPoint` offsets relative to UIParent (Cooldown Manager Centered, `modules/auraTracking.lua`; unverified by us). Lay them out before combat.
- **No Druid aura is readable in combat** (verified 2026-10-03 with a temporary check command, since removed): `C_Secrets.ShouldSpellAuraBeSecret(spellID)` (idea from Forever Cooldown Manager: some buffs are never secret) returns **true for every spellbook spell** in combat, all ranks and passives, plus our tracked buffs (Elemental Blessing, potions). Out of combat it's false for all, and `ShouldAurasBeSecret()` follows combat the same way (in the open world: in a battleground, auras were secret out of combat too, 2026-10-05). Out of combat, `GetPlayerAuraBySpellID` matches the exact rank's ID: only the rank cast reads as up (Mark of the Wild 6756, Thorns 1075), lower ranks read not up.

### Global cooldown (verified)

- Retail's GCD dummy spell 61304 **doesn't exist in Forever**. Forever reports the GCD on **Classic's GCD spell 29515** (from [EllesmereUI PR #2240](https://github.com/EllesmereGaming/EllesmereUI/pull/2240)).
- In combat, start and duration are secret, but `isActive`/`isOnGCD` are readable. So: when `isActive`, `C_Spell.GetSpellCooldownDuration(29515)` → `SetCooldownFromDurationObject`. Backup if that's ever rejected: on `isOnGCD`, run our own sweep of the Classic length (1.0s energy abilities, 1.5s otherwise).
- Can't scale anything to the GCD or attack speed in combat: the numbers are secret.
- Order (seen 2026-10-08, Rejuvenation): the GCD's `SPELL_UPDATE_COOLDOWN` arrives before the cast's `UNIT_SPELLCAST_SUCCEEDED`, which came 0.12s after the GCD's start.
- Out of combat the GCD's start and duration are plain numbers (**verified** 2026-10-08: duration 0.99 for Rejuvenation with Gift of the Earthmother, so the talent does shorten the real GCD). `Gcd.lua` sweeps with them, and learns each instant spell's GCD length from them (`CatnipDB.lengths.gcd`, SpellTiming.lua) for use in combat.

### Swing timer (verified)

`PLAYER_SWING` gives a plain duration, so `Cooldown:SetCooldown(GetTime(), duration)` works. If Blizzard ever makes it secret, SetCooldown will reject it. An earlier counter-clockwise version used two rotated half-ring textures in clip frames (`SetClipsChildren` + `SetRotation`); it worked, but was dropped when the design went clockwise. The cast bar now uses the same technique for its counter-clockwise fill (`ring_bar_half`); that needs the cast's progress as a plain number, which is unverified in combat (`Cast.lua` falls back to a clockwise swipe if it's secret).

### Hiding Blizzard's player cast bar (verified 2026-09-29)

From EllesmereUI (`EllesmereUI_SharedHelpers.lua`, `SetPlayerCastBarSuppressed`): re-parent `PlayerCastingBarFrame` to a hidden frame instead of unregistering its events. Edit Mode re-parents the bar during layout changes, so hook `SetParent` and park it again on the next frame, but never in combat or while `EditModeManagerFrame` is shown (SetParent there runs Blizzard's layout code under addon taint). EllesmereUI warns against re-arming the bar via `SetUnit`: it iterates a table that errors when tainted. `Cast.lua` does this.

### Stealth detection (unverified)

`Stealth.lua` uses retail's `IsStealthed()` and `UPDATE_STEALTH`, with player `UNIT_AURA` as a backup. None of the reference addons use them, so check on Forever: `/dump IsStealthed()` in and out of Prowl, and whether the HUD changes the moment Prowl goes on and off (`/catnip debug` prints "stealth mode: true/false" and, on load, whether the event registered).

### StatusBar textures: crop or stretch? (unverified)

When a StatusBar is part-full, does it show the matching part of its texture (crop) or squeeze the whole texture into the filled part (stretch)? It matters for the gradient fills (`Resource.lua`): crop keeps the gradient fixed to the circle (low energy is all dark gold), stretch keeps the pale end on top of the fill. Both look acceptable, but shading that varies in two directions (a sphere, a rim) only works with crop. Check by eye at low energy. Stock bars in Forever are pre-coloured atlases (`UI-HUD-UnitFrame-Player-PortraitOn-Bar-<Power>`); EllesmereUI's resource bars put one on a StatusBar with `bar:GetStatusBarTexture():SetAtlas(atlas, true)`.

### Fonts and raw mana text (verified 2026-10-04)

Blizzard's font files load in Forever through `FontString:SetFont`: `STANDARD_TEXT_FONT` (Friz Quadrata), `Fonts\ARIALN.TTF`, `Fonts\skurri.ttf`, `Fonts\MORPHEUS.TTF`, with `""`, `OUTLINE` and `THICKOUTLINE` flags, changed at any time (`Elements.lua`). A raw `UnitPower("player", Mana)` passed straight to `SetText` keeps updating in combat with no errors (Resource number, "Mana as: Value").

**A FontString showing a secret value has a secret size and position, even out of combat**: `GetRect()` on the resource number (energy from `UnitPower`) returned four secret numbers out of combat, and comparing them errored ("attempt to perform arithmetic on a secret number value"). Never measure a text that shows game values; place our own frame at its anchor instead (Preview.lua's text boxes). `IsVisible()` on it was fine.

**Blizzard's menu (`MenuUtil.CreateContextMenu`) works in Forever** (EllesmereUI uses it; Catnip's choice controls since 2026-10-04), but its labels are wrapped by the menu compositor, which **forbids `SetFont`** ("Use of function 'SetFont' is disallowed"; reported through the error handler, so `pcall` doesn't hide it). Use `SetFontObject` with a Font object of our own (`ns.FontObject`) from an `AddInitializer` instead. `CreateFont(nil)` errors ("Usage: CreateFont("name")"): it needs a name, which becomes a global (ours are `CatnipFont1`, `CatnipFont2`...).

### Blizzard's Professions frame art (found 2026-10-02 with `/catnip art`)

The Forever Professions window (`ProfessionsFrame`) is built on `PortraitFrameTemplate`: `NineSlice` with `UI-Frame-PortraitMetal-CornerTopLeft` (95×95, includes the portrait ring) and `UI-Frame-Metal-CornerTopRight` / `-CornerBottomLeft` / `-CornerBottomRight`, `_UI-Frame-Metal-EdgeTop` (95 tall, includes the title bar) / `-EdgeBottom`, `!UI-Frame-Metal-EdgeLeft` / `-EdgeRight`. Portrait: a 62×62 texture under `PortraitContainer.CircleMask` (file 130924, 58×58). Close button atlas `RedButton-Exit`. Background: `Profession-Background-Overview` (669×571). Overview panels are single atlases with border, shading and illustration baked in (no separate nine-slice): `Profession-overview-Card-<Profession>` (664×142, primary) and `Profession-overview-card-generic-<Cooking|Fishing|FirstAid>` (225×275, all on file 8166368). Skill bars: `Profession-ProgressBar-BG` / `-frame`, `Skillbar_Fill_Flipbook_<Profession>`. Icon frame: `Profession-square-frame`. Side tabs: `common-sidetab`, `-selected`, `-hover`, `-mask`. Inner panel edges elsewhere: `UI-Frame-Inner*`. The full dump is in `CatnipDB.artDump` in the SavedVariables file. Whether `PortraitFrameTemplate` can be used by an addon in Forever: **untested** (`OptionsArt.lua` tries it, with a drawn fallback).

### Cooldown Manager reading (verified; now only a fallback)

The Cooldown Manager viewers (`BuffIconCooldownViewer`, `BuffBarCooldownViewer`, `EssentialCooldownViewer`, `UtilityCooldownViewer`) are ordinary frames; each tracked spell is a child. Identify an item by `cooldownInfo.spellID` and read `IsShown()`. Needs the player to track the spell in the Cooldown Manager, so AuraContainer replaced it. Technique from [EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager/blob/HEAD/Modules/BuffBars.lua). `/catnip cdm` dumps the items.

## Forever spell and aura IDs

| What | IDs |
|------|-----|
| Clearcasting (buff) | 16870 |
| Omen of Clarity (talent; Cooldown Manager tracks this) | 16864 |
| Rip ranks (each rank's aura has its own ID) | 1079, 9492, 9493, 9752, 9894, 9896 |
| Rake ranks | 1822, 1823, 1824, 9904 (not yet unlocked in the beta) |
| Enrage (Bear; buff, 10s) | 5229 (**verified** 2026-09-27) |
| GCD spell | 29515 |
| Tiger's Fury / Berserk (from Blood in the Water) | 5217 / 417141 |

## Dead ends (don't retry)

- Reading the GCD from spell 61304 (doesn't exist in Forever).
- Passing secret cooldowns to `Cooldown:SetCooldown`.
- Matching new auras via `UNIT_AURA` `addedAuras` + `auraInstanceID` (both secret in combat).
- A cast-event timer for Rip (guessed the duration, lost track on target switches); replaced by AuraContainer.
- Updating frames attached to AuraContainer buttons (forbidden).
- `C_UnitAuras.GetPlayerAuraBySpellID` in combat (returns nil, not a secret or an error, even while the buff is up: it looks exactly like "not up"; seen again 2026-10-03 with Mark of the Wild and Thorns).
- Detecting the Gift of the Earthmother talent with `ns.FindKnownSpell("Gift of the Earthmother")` (2026-10-08): the pie never shortened, so the lookup almost certainly came back nil: a passive talent adds no spell to the spellbook (Shifting Power is found because it does). SpellTuner (installed locally, `Spells/Tabs.lua`) probed Forever's talent API: `GetTalentInfo` is absent and `C_SpecializationInfo.GetTalentInfo` returns nil, so it reads talents only from the spells they add and skips passive ones. EllesmereUI's `C_Traits` talent checks are retail-only (its talent reminders are off on Forever; it uses `C_Traits` there only for the Adventure Legacy tree). Untried: `IsPlayerSpell(id)` with the talent's own spell ID (unknown; talentsforever.com's data may have it). Replaced by learning each spell's GCD.
- Shortening the GCD pie during Nature's Grace (2026-10-04): the buff isn't readable in combat (see above) and crits can't be seen, so the pie keeps the full length.
- Sorting the cooldown box active-first from Lua: no Druid aura is readable in combat (`ShouldSpellAuraBeSecret` is true for all, 2026-10-03). The remaining route is AuraContainer groups, which Blizzard lays out itself (see the AuraContainer section).
- A vertical `Slider` as a scrollbar (2026-10-04): a player reported dragging it moved the wrong way up/down (unverified why; we never checked which end the minimum sits at in this client). `OptionsScroll.lua` now does its own thumb and drag maths instead.
- Per-tick pulses on the DoT rings (2026-10-04): the ticks can't be seen in combat. Aura timing is secret, `C_UnitAuras.GetAuraDuration` hard-errors under 12.1 aura restrictions (EllesmereUIQoL `_Bloodlust.lua`, unverified by us), so `DurationObject:EvaluateRemainingDuration(curve)` (which EllesmereUI uses for spell cooldowns) can't be reached, and the combat log is gone. A looping animation started at setup isn't tied to the DoT's phase. Left without pulses; the only option left is a cast-timed clock driving decoration only.

## Sources

- [Warcraft Wiki: Patch 12.0.0 planned API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes): the main technical reference (some claims turned out wrong for Forever; trust verified facts above)
- [Blizzard: Combat philosophy and addon disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- Blood in the Water addon (local, see [architecture.md](architecture.md#reference-addons))
- [EllesmereUI PR #2150](https://github.com/EllesmereGaming/EllesmereUI/pull/2150) (swing timer), [PR #2240](https://github.com/EllesmereGaming/EllesmereUI/pull/2240) (Forever GCD)
- [EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager)
- [C_Spell.GetSpellCooldown](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown), [Cooldown:SetCooldown](https://warcraft.wiki.gg/wiki/API_Cooldown_SetCooldown)
