# Catnip

A World of Warcraft addon for the **Druid** class, targeting **WoW Forever** (currently in beta). Written in Lua. This is a mostly AI-built side project; the owner is an experienced engineer but new to addon development (formerly a WeakAuras power user).

Before feature work, read:
- `docs/design.md`: the working spec and current **status** of each feature. It summarizes the owner's originals, `docs/design.pdf` and `docs/layout-sketch.svg`.
- `docs/architecture.md`: code map, shared `ns` helpers, layering, reusable patterns, textures, debugging and releasing.
- `docs/api-research.md`: what the Forever API allows in combat, verified facts, and dead ends not to retry.

Keep these current: when a feature changes or a fact is verified, update the relevant doc in the same piece of work.

## Dev loop

1. Claude edits files.
2. User runs `/reload` in-game and reports what happened (chat output, errors, screenshots).
3. Repeat. Claude cannot run the game, so ask the user to test anything that needs in-game verification, and say exactly what to look for.

New `.lua` files must be added to `Catnip.toc` or they won't load. In this client, `/reload` picks up everything — new files, `.toc` changes, and textures (verified 2026-09-27) — so no game restart is needed.

## The API: verify, don't trust memory

Forever does **not** use the Classic API. It uses the modern retail (Midnight, 12.x) API, including Midnight's **combat restrictions on addons** — much of what WeakAuras did in combat is limited or blocked. Claude's training knowledge of the WoW API largely predates this, and the beta changes frequently.

- `docs/api-research.md` has what's been verified and what failed; check it before trying an approach.
- Look at the Blood in the Water addon (installed locally; path in `docs/architecture.md`) before searching online: it's a working Forever Feral addon with well-commented workarounds.
- Don't assume a function, event, or field exists or behaves as remembered. When unsure, say so and verify: have the user run `/dump <expr>` or `/api` in-game, or check Blizzard's shipped UI source.
- Prefer approaches that are robust to combat restrictions; flag early if a feature may be impossible under them.
- Blizzard's addon rules for Forever: free, with visible (non-obfuscated) code.

## Conventions

- Use the addon namespace (`local addonName, ns = ...`); no unnecessary globals.
- Keep files small and focused.
- Ask before adding third-party libraries.
