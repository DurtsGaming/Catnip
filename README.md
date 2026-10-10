# Catnip

A compact circular HUD for Feral Druids in **World of Warcraft: Forever** (currently in beta). It shows your energy, rage or mana (as a %, with a five-second-rule ring and the cost of the spell you're casting marked), combo points with rings for your DoTs and short cooldowns (Rip, Rake, Faerie Fire, Primal Bite and Omen of Clarity's internal cooldown), a swing timer that becomes a cast bar while you cast, the global cooldown, Clearcasting procs, Enrage (in Bear Form), the Shifting Power and Growl cooldowns and how many shapeshifts your mana pays for, all in one place. A separate box tracks the other cooldowns you pick. No setup needed beyond installing it, but nearly every part can be adjusted (see **Customizing**).

## Installing

1. Go to the [**Releases**](https://github.com/DurtsGaming/Catnip/releases) page and download the latest `Catnip-vX.Y.Z.zip`. (Use the release zip, not the green **Code → Download ZIP** button. That one names the folder `Catnip-main`, which WoW won't load unless you rename it to `Catnip`.)
2. Extract the zip. You'll get a folder called `Catnip`.
3. Move the `Catnip` folder into your Forever client's AddOns folder:

   ```
   World of Warcraft\_classic_beta_\Interface\AddOns\
   ```

   During the beta, Forever uses the `_classic_beta_` folder. This may change at launch.

   When you're done, `Catnip.toc` should be directly inside `AddOns\Catnip\`, not in a folder below it.
4. Start the game (or type `/reload` if it's running). On the character select screen, click **AddOns** and make sure Catnip is ticked.

The HUD appears below the centre of your screen when you log in.

## Using it

| Command | What it does |
|---------|--------------|
| `/catnip` | Open the settings window (also under **Options → AddOns → Catnip**). It has three tabs: **General** (hide Blizzard's cast bar, Action Bar 1 or Stance Bar), **Rotation** (customize the HUD) and **Cooldown** (pick the cooldowns to track and lay out their box). Drag the window's bottom-right corner to resize it. |
| `/catnip edit` | Open the settings window and Blizzard's Edit Mode together (also the **Move in Edit Mode** button at the top of the Rotation and Cooldown tabs). In Edit Mode, drag the Rotation Frame and Cooldown Frame to move them; click either one for a **Catnip Settings** button and **Reset Position**. |
| `/catnip sp`, `ff`, `pb`, `growl`, `omen` | Preview the Shifting Power arc, the Faerie Fire, Primal Bite and Omen of Clarity rings, or the Growl arc without casting. The rings show in Cat or Bear Form. |

Your settings are saved between sessions. The cooldown list is saved per character, everything else is shared across your characters.

**Combo rings.** Each of the five combo points can carry a ring: Faerie Fire's cooldown on the first, Omen of Clarity's 10-second internal cooldown on the second, Primal Bite on the third, Rake on the fourth and Rip on the fifth. DoT rings drain as the DoT runs out, with a small red tick at the top while it's still up. Cooldown rings drain until the ability is ready. In `/catnip` → **Rotation** → **Above**, each **Combo ring** lets you pick what it shows (or None), whether its segments are **Angular** or **Circular**, and its opacity.

**Shifting Power and Growl.** If you know Shifting Power, a four-segment arc under the HUD fills from left to right while it's on cooldown. When it's ready, the arc fades away and, in Cat Form, the circle flashes blue once if you have the mana to cast it. Small orbs under the arc show how many shapeshifts (or Shifting Power casts, which cost the same) your mana pays for, in every form. A grey orb on the right means the next one is almost paid for. Growl's cooldown uses the same arc and wins the spot in Bear Form. Under **Cooldown Arc**, you can turn either one off.

**Cooldowns.** In `/catnip` → **Cooldown**, turn the **Cooldown Frame** on, then under **Abilities** tick the abilities you want to watch (Barkskin, Tiger's Fury, and so on) and drag them into priority order. They show in a separate box only while they're on cooldown (greyed out) or while their buff on you or debuff on your target is up, like Growl's taunt (in colour, with thin yellow dashes running around its border), each with its time left. If an ability's buff has a different name (Skysight gives Elemental Blessing), use it once out of combat so Catnip can learn which buff it gives. To track an item, drag it from your bags onto **Drop an item here to track it**: Hearthstone and trinkets get their own icon, and all potions share one Potions icon (drop a specific potion, like Mighty Rage Potion, to have its buff show as active). Under **Icons**, set the icon size, what happens when they don't fit (**Hidden** or **Spill** out of the box), alignment, and separate opacity for active and greyed-out icons. The countdown numbers follow WoW's own "Show numbers for cooldowns" option (Options > Action Bars).

**Customizing.** In `/catnip` → **Rotation**, the top of the tab turns the HUD on or off and sets its scale, overall opacity and position. Below that, pick a zone: **General** (Stealth Mode, the look while you Prowl or Shadowmeld), **Above** (the combo points and their rings), **Circle** (the resource circle and swing ring) or **Below** (the cooldown arc, shift orbs and swing/cast text). Each part has its own opacity, and some have more: text sizes, mana as a percent or a value, colours for the swing timer (and while Maul is queued) and the cast bar, and on/off switches. **Reset...** puts everything back to defaults. While this tab is open (out of combat), the HUD shows a sample instead of your real state so every part is visible. Use the **Preview** buttons (**Caster**, **Bear**, **Cat**, and **Stealth** for the Prowl look) to switch it. Hover a part of the HUD to see its name, and click it to open its settings.

## Updating

Download the latest release zip and replace your `AddOns\Catnip` folder with the new one. Your settings are stored separately and are kept.
