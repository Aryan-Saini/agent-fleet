---
name: fleet
description: When the user asks about their machines, the tailnet, ssh and access, what runs on which box, how files or config move between machines, or which machine this is, use skill.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  requires: "the fleet repo checkout; `fleet` on PATH"
---

# fleet

The user's machines are documented in their **fleet repo**, synced to every machine. Answer from
it. Do not guess hostnames, paths or roles.

## Start here

1. Run `fleet`. It prints this machine's name, role, OS, the repo path, and enabled packages.
2. Read `computers.md` in that repo: every machine, its role, how to reach it.
3. For one machine, read `machines/<name>/README.md`. Scheduled jobs: `automations/README.md`.
4. If the docs disagree with reality, say so and offer to fix the docs.

## Roles

- **controller**: where the user works. The only machine that authors config.
- **worker**: always on, runs agents and long jobs in tmux, heals itself, reports what it can't
  fix, never starts disruptive work on its own.
- **remote**: a phone or tablet driving the fleet. Nothing syncs to it.

## Rules that bind every agent

- **Disconnect risk.** Before acting on a worker, ask whether the work could sever the network,
  ssh, the service manager or the boot. If yes or unsure, it goes as
  `fleet workorder start <name> <script>`, never over a live ssh session. The worker may lose the
  task; it may never stay down or stay silent.
- **Config flows one way.** Rules, skills and the fleet repo are edited on the controller,
  committed and pushed. Workers `reset --hard` onto it every 30 minutes, so an edit made on a
  worker is discarded (saved first under `refs/fleet-local/*`). Make the change on the controller.
- **Secrets never enter the repo.** They live in `~/.config/fleet/machine.env` or
  `~/.config/agent-secrets.env` on each machine.

## Moving things between machines

| want | do |
| --- | --- |
| run a command there | `ssh <machine> '<cmd>'` (non-interactive ssh has a stripped PATH: use absolute paths) |
| a file there now | `fleet send <machine> <file>` |
| a file there lazily | put it in `~/drop`; Syncthing carries it in ~15-25 s |
| show an image to an agent there | drop it, then reference `~/drop/<file>` by path. Clipboards don't cross ssh |
| a dev server there | `http://<machine>:<port>`, server bound to 0.0.0.0 |
| the human's attention | `fleet alert "title" "message"` |

Details and gotchas: `docs/communicate.md` in the fleet repo.

## Keeping it current

When something changes (a machine, a service, an access path) update the doc in the same change,
commit and push from the controller. Use the `edit-md-files` skill for rules and skills.

Related: **worker** to operate a worker, **automation** to schedule something,
**fleet-update** and **fleet-add-device** (controller only, user-invoked).
