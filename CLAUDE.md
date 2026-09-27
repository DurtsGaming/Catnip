# Catnip

A World of Warcraft addon for the **Druid** class, targeting **WoW Forever** (currently in beta). Written in Lua. This is a mostly AI-built side project; the owner is an experienced engineer but new to addon development (formerly a WeakAuras power user).

Design: read `docs/design.md` (the working spec) before feature work. It summarizes the owner's originals, `docs/design.pdf` and `docs/layout-sketch.svg`.

## Git: hands off

**Never run git commands** (no commit, push, branch, stash, checkout, etc.), even in auto mode. When work reaches a sensible commit point, stop and tell the user it's time to commit, with a suggested commit message. The user runs git themselves.

## Environment

- Game client: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\` (Forever, build 1.60.x). `_classic_era_` is regular Classic — not our target.
- `_classic_beta_\Interface\AddOns\Catnip` is a **junction to this repo**. Edits are live in-game after `/reload`; no copying or build step.
- TOC `## Interface: 16001` (verified in-game).
- Git is not on PowerShell's PATH; it works from the Bash tool.

## Dev loop

1. Claude edits files.
2. User runs `/reload` in-game and reports what happened (chat output, errors, screenshots).
3. Repeat. Claude cannot run the game, so ask the user to test anything that needs in-game verification, and say exactly what to look for.

New `.lua` files must be added to `Catnip.toc` or they won't load. Changes to the `.toc` itself require restarting the game, not just `/reload`.

## The API: verify, don't trust memory

Forever does **not** use the Classic API. It uses the modern retail (Midnight, 12.x) API, including Midnight's **combat restrictions on addons** — much of what WeakAuras did in combat is limited or blocked. Claude's training knowledge of the WoW API largely predates this, and the beta changes frequently.

- Read `docs/api-research.md` for how the restrictions work and the planned approach per feature. Update it as things get verified in-game.
- Don't assume a function, event, or field exists or behaves as remembered. When unsure, say so and verify: have the user run `/dump <expr>` or `/api` in-game, or check Blizzard's shipped UI source.
- Prefer approaches that are robust to combat restrictions; flag early if a feature may be impossible under them.
- Blizzard's addon rules for Forever: free, with visible (non-obfuscated) code.

## Conventions

- Use the addon namespace (`local addonName, ns = ...`); no unnecessary globals.
- Keep files small and focused.
- Ask before adding third-party libraries.
