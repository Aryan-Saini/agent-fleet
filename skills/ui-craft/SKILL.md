---
name: ui-craft
description: Emil Kowalski's UI and motion craft library (ex Vercel/Linear, author of Sonner and Vaul), loaded through one router. Use when the user says "mobile ui", "ui vocab", "emil", or "make it feel native"; when building, polishing or reviewing UI, animations, transitions, gestures, sheets, drawers, toasts or press feedback (web or Expo); when motion janks or drops frames; when the user describes an effect without knowing its name; when picking a frontend library or a repo for 3D, shader, liquid glass or gradient effects; or when stress-testing a component with worst-case data.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "git, to fetch the guides once with ./update.sh. Reference guides only after that"
---

# UI craft (Emil Kowalski's library)

The guides are Emil Kowalski's, from [emilkowalski/skills](https://github.com/emilkowalski/skills)
(MIT). This repo ships only the router. Fetch the guides once, and again whenever you want
upstream's latest:

```bash
./update.sh      # clones upstream into emil/, renames each SKILL.md to GUIDE.md, writes emil/SOURCE
```

Layout after `update.sh`:

```
ui-craft/
  SKILL.md                      this router: the one skill harnesses register
  resources.md                  effect repos (3D, shaders, liquid glass), not an Emil guide
  update.sh                     the fetcher
  emil/SOURCE                   "emilkowalski/skills @ <sha> (<date>)"
  emil/LICENSE                  upstream's MIT notice, copied with the guides
  emil/performance-cheatsheet.md
  emil/<name>/GUIDE.md          one per upstream skill, plus siblings (RECIPES.md, STANDARDS.md, CATALOG.md...)
```

The guides were `SKILL.md` upstream. They are renamed so harnesses don't register twenty separate
skills and flood the skill list. One router keeps the trigger in one place.

Read only the guides the task needs, then follow them. Skip each guide's "Initial Response"
section: that greeting is for standalone use, not for loading as reference. When a guide points at
another by name ("use `animate`"), it means `emil/animate/GUIDE.md`. If `emil/` is missing, run
`./update.sh`, or read the guide straight from upstream.

## Loadouts

| Trigger | Read |
| --- | --- |
| **"mobile ui"**, Expo / React Native | `animate-expo` + `apple-design` + `emil-design-eng` |
| "mobile ui" on a web app / PWA | `mobile-native` + `apple-design` + `emil-design-eng` |
| **"ui vocab"**, any UI build or polish | `emil-design-eng` (the core: mostly motion, plus component taste) |
| Build an animation (web) | `animate` (+ its `RECIPES.md`) |
| Several things moving together: stagger, sequence, list entrance, view swap, morph | `choreograph` (+ its `RECIPES.md`) |
| Drag, swipe, fling, sheet, drawer, pull-to-refresh, hold-to-confirm | `gestures` (+ `animate-expo` on Expo) |
| Review a diff's motion | `review-animations` + `STANDARDS.md` |
| Audit a whole codebase's motion | `improve-animations` (+ `AUDIT.md`, `PLAN-TEMPLATE.md`) |
| "What could animate here?" | `find-animation-opportunities` |
| "Too much animation", feels slow, tone down motion | `remove-animations` (only subtracts) |
| Jank, dropped frames, `will-change` | `animation-performance` + `emil/performance-cheatsheet.md` |
| "What's it called when..." | `animation-vocabulary` |
| Which library for X (OTP input, charts, cmdk, drag and drop...) | `pick-ui-library` |
| "Which guide fits?", unsure where to start | `ask-emil` (a router over the guides; pick one, then read it) |
| Toasts with Sonner | `ask-sonner` (+ `API.md`) |
| Worst-case data, edge cases | `break-ui` (+ `CATALOG.md`). Screenshots, simulator shots or PR proof: the `ui-stress-shots` skill, which loads `break-ui` itself |
| Several variants of a UI piece | `prototype` (see the override below) |
| Native Swift / SwiftUI | `write-swift` |
| "Learn my taste": turn this session's design corrections into rules (only when asked) | `learn-taste` |
| 3D, shaders, liquid glass, gradient or liquid metal effects | `resources.md` |

Mobile web or Expo: check the repo. `expo` in `package.json` means Expo.

## Your rules win

Where a guide conflicts with your global agent rules (`AGENTS.md` / `CLAUDE.md`), the global
file wins. Write your house style here so the agent applies it on top of the guides. Examples:

- **Mocks before real components.** `prototype` builds an in-app variant picker. If you prefer
  static mocks first (inside T3 Code, through `html_render`), say so here.
- **Theme constraints.** `<your defaults: dark mode, background colour, density, chrome>`.
- **No continuously repainting animations** (pulse, shimmer, spinners, animated blur) if they peg
  the GPU on high-refresh displays. When a guide suggests one, find a finite alternative.

## Updating

Run `./update.sh` by hand, or from a nightly job (see the `automation` skill). It prints
`current (<sha>)` when nothing changed. It exits 1 with `UNROUTED <name>` when upstream adds a
guide that has no loadout row above. Add the row; the fetched files are already in place.
Commit `emil/` along with the router if you want every worker to get the same pinned version
through your normal config sync.
