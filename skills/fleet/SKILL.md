---
name: fleet
description: When the user asks about their machines or homelab, the tailnet, ssh and access, what runs on which box, how files, config, settings or skills move between machines, or which machine this is, use skill.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "the fleet repo checkout; `fleet` on PATH. The controller owns the map"
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

- **controller**: where the user works. The only machine that authors config. Orchestrates
  work and updates.
- **worker**: always on. Nothing suspends it on a schedule or on idle. Runs agents and long jobs
  in tmux, restarts known services, reports what it can't fix (a dead login, a failed boot), and
  never starts deep updates on its own.
- **remote**: a phone or tablet driving the fleet through T3 Code or an ssh app. Nothing syncs
  to it.

## Rules that bind every agent

- **Disconnect risk.** Before acting on a worker, ask whether the work could sever the network,
  ssh, the service manager or the boot. If yes or unsure, it goes as
  `fleet workorder start <name> <script>`, never over a live ssh session. After any disruption the
  worker restores its services, proves the controller can reach it, writes a report to `~/drop`
  and alerts. The worker may lose the task; it may never stay down or stay silent.
- **Config flows one way.** Rules, skills, settings and the fleet repo are edited on the
  controller, committed and **pushed** in the same pass. Workers `reset --hard` onto the remote
  every 30 minutes, so an edit made on a worker is discarded (saved first under
  `refs/fleet-local/*`). Make the change on the controller. To push it out now:
  `ssh <worker> fleet sync`.
- **Skill scope is enforced.** `skills-controller/` and `skills-worker/` are linked by role, and
  each SKILL.md's `platform` and `harness` keys decide the rest. A skill missing on a machine is
  usually scoped away on purpose. See `docs/skills.md`.
- **Secrets never enter the repo.** They live in `~/.config/fleet/machine.env` or
  `~/.config/agent-secrets.env` on each machine.

## Moving things between machines

| want | do |
| --- | --- |
| run a command there | `ssh <machine> '<cmd>'` (non-interactive ssh can have a stripped PATH: use absolute paths) |
| a file there now | `fleet send <machine> <file>` |
| a file there lazily | put it in `~/drop`; Syncthing carries it in ~15-25 s |
| show an image to an agent there | send or drop it, then reference `~/drop/<file>` by path. Clipboards don't cross ssh |
| a web app on the worker, for the user's laptop or phone | the **dev-server** skill: loopback bind plus a `tailscale serve` HTTPS URL |
| a database or API on another machine | `psql -h <machine> ...`, `http://<machine>:<port>` over the tailnet |
| an agent on another machine | inside T3 Code, `delegate_task` with that machine's `environmentId` (the **subagents** skill); a whole thread there, the **t3-environment-handoff** skill |
| the human's attention | `fleet alert "title" "message"` |

Details and gotchas: `docs/communicate.md` in the fleet repo.

## Keeping it current

When something changes (a machine, a service, an access path) update the doc in the same change,
commit and push from the controller. Use the `edit-md-files` skill for rules and skills.

Each worker runs `fleet health` every 15 minutes: it heals what is safe to heal (tailnet, T3,
known services) and alerts on what needs a human (logins). Updates are controller-initiated.

Related: **worker** to operate a worker, **automation** to schedule something, **dev-server** to
show a web app running on a worker, **cliproxy-hub** for shared model accounts, **halo** when a
human must see a worker's screen. **fleet-update** and **fleet-add-device** are controller only
and user-invoked: an agent cannot start them, so tell the user to run `/fleet-update` or
`/fleet-add-device` (`$fleet-update` in Codex).
