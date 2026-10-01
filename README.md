# Catnip

A compact circular HUD for Feral Druids in **World of Warcraft: Forever** (currently in beta). It shows your energy, rage or mana (as a %, with a five-second-rule ring), combo points, swing timer (which becomes a cast bar while you cast), global cooldown, Rip duration, Clearcasting procs and Enrage (in Bear Form) in one place. While you prowl, the HUD fades, your energy turns Prowl purple and teal, and night motes circle it. No setup needed beyond installing it.

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
| `/catnip` | Open the settings window: move (by dragging or exact position) and resize the HUD, set how faded the HUD is while you prowl, and choose whether to hide Blizzard's cast bar. |
| `/catnip unlock` | Unlock the HUD: drag to move, scroll to resize. `/catnip lock` when done. |
| `/catnip scale 1.2` | Set an exact size (0.5 to 2.5). |
| `/catnip reset` | Put the HUD back in its default spot and size. |
| `/catnip stealth` | Preview the stealth look without prowling. Type it again to turn it off. |

Catnip hides Blizzard's own cast bar by default, since the HUD shows your casts. Your settings are saved between sessions.

## Updating

Download the latest release zip and replace your `AddOns\Catnip` folder with the new one. Your settings are stored separately and are kept.
