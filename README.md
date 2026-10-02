# Catnip

A compact circular HUD for Feral Druids in **World of Warcraft: Forever** (currently in beta). It shows your energy, rage or mana (as a %, with a five-second-rule ring), combo points, swing timer (which becomes a cast bar while you cast), global cooldown, Rip duration, Clearcasting procs and Enrage (in Bear Form) in one place. No setup needed beyond installing it.

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

You should see "Catnip loaded" in chat when you log in.

## Using it

| Command | What it does |
|---------|--------------|
| `/catnip` | Open the settings window: move (by dragging or exact position) and resize the HUD, choose whether to hide Blizzard's cast bar, and (Cooldowns tab) pick the cooldowns to track. |
| `/catnip unlock` | Unlock the HUD and the cooldown box: drag to move, scroll over the HUD to resize it, drag the box's corners to resize it. `/catnip lock` when done. |
| `/catnip scale 1.2` | Set an exact size (0.5 to 2.5). |
| `/catnip reset` | Put the HUD back in its default spot and size. |

Catnip hides Blizzard's own cast bar by default, since the HUD shows your casts. Your settings are saved between sessions.

**Cooldowns.** In `/catnip` → **Cooldowns**, tick the abilities you want to watch (Barkskin, Tiger's Fury, and so on) and drag them into priority order. They show in a separate box, only while they're on cooldown (greyed out) or their buff on you or debuff on your target is up, like Growl's taunt (in colour, with thin yellow dashes running around its border), each with its time left. If an ability's buff has a different name (Skysight gives Elemental Blessing), use it once out of combat so Catnip can learn which buff it gives. To track an item, drag it from your bags onto the box under the list: Hearthstone and trinkets get their own icon, and all potions share one Potions icon (drop a specific potion, like Mighty Rage Potion, to have its buff show as active). The numbers come from WoW's "Show numbers for cooldowns" option; the Cooldowns tab has a checkbox for it.

## Updating

Download the latest release zip and replace your `AddOns\Catnip` folder with the new one. Your settings are stored separately and are kept.
