---
name: fleet-update
description: When the user wants their machines' software updated, checked, verified or rolled back, use skill. Runs from the controller across every machine in computers.md, driven by the packages each machine has enabled.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  requires: "ssh to every machine; the fleet repo checkout"
---

# fleet-update

`/fleet-update [machine] [--check] [--deep]`. No machine means every machine in `computers.md`
with role controller or worker, in parallel lanes that do not wait on each other. Reject a
machine that is not in `computers.md` rather than guessing how to reach or update it.

Your fleet is not the author's fleet. Everything this skill updates comes from the data:

1. `computers.md`: which machines exist, their OS, how to reach them.
2. Each machine's `FLEET_PACKAGES` (`ssh <m> fleet` prints them) and that package's README
   section on updating.
3. Each machine's `machines/<name>/README.md`: its package manager, pinned versions, channel
   choices, and things never to touch.

## Safety rules

1. **Classify disconnect risk per step.** Anything that can sever the network, ssh, the service
   manager or the kernel on a worker runs as `fleet workorder` (see `packages/os-update`), never
   streamed over live ssh. That is `--deep` only.
2. **Normal runs apply everything that is not reboot-class.** Anything needing a restart is
   reported and left for `--deep`. Never install it and hope.
3. **Reboot-class work needs physical recoverability.** Refuse `--deep` on a worker unless the
   controller is verifiably on the same LAN (a real LAN address on both), or the user confirms
   someone can reach the box. A working Tailscale route proves nothing here.
4. **Never update what the user is in.** An app that quits on upgrade (their browser, the editor
   this agent runs in, the T3 app driving this thread) is reported, not upgraded, unless they say so.
5. **Things that need a human stay report-only:** anything behind an Apple ID or 2FA, store
   apps, and anything the machine's README marks manual. Report installed versus available.
6. **Agent-facing services update from here, never from a worker's own timer**, so an update
   never lands while the user is driving that worker from a phone. Keep a rollback path (the last
   healthy version) for each.
7. **Clean up conservatively.** Measure and show sizes before deleting. Only remove what
   regenerates or is superseded: package caches, old build dirs, superseded CLI versions (keep
   current plus one). Never anything with a live process (`pgrep` first), a pinned toolchain, the
   newest rollback snapshot, or a source checkout.
8. **Not done until verified and recorded.**

## Normal flow

1. **Report.** Per machine: package-manager queue (`brew outdated`, `pacman -Qu`, `apt list
   --upgradable`, `winget upgrade`), agent CLI versions vs latest, each enabled package's update
   check, disk usage. Show one table. Invoking the skill is the approval for everything that is
   not reboot-class: go straight on.
2. **Update.** One lane per machine, started together. Within a lane, package manager first,
   then agent CLIs (`claude update`, `npm i -g @openai/codex`, `cursor-agent update`, `opencode
   upgrade`), then each enabled package's update steps, then agent-facing services last so their
   restart picks up the new CLIs. Log each step to `~/.local/state/fleet/logs/update-<date>/`.
3. **Probe.** `ssh <m> fleet health --probe` on every machine. A failed login probe is a
   report item, not something to fix with credentials.
4. **Clean up** per rule 7.
5. **Record.** Update each machine's `Installed versions` table and add one line to its
   `Update log` in `machines/<name>/README.md`, in one commit from the controller. Report
   old to new, already current, fixed, health, freed space, and anything deferred to `--deep`.

`--deep`: the reboot-class work. For each worker, start its OS work order
(`packages/os-update/<os>.sh`) one machine at a time, wait for its report in `~/drop` and the
alert, then move to the next. The controller's own OS upgrade is the user's to run.

## Unattended runs

A nightly scheduled run (headless agent on this skill) is fine and still bound by every rule
above. It writes its report to the log dir and sends `fleet alert` with OK or NEEDS ATTENTION.
