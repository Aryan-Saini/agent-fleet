---
name: fleet-update
description: When the user wants their machines' software updated, checked, verified or rolled back, use skill. Runs from the controller across every machine in computers.md, driven by the packages each machine has enabled.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: controller
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
9. **Every update gets a danger check before it installs.** Supply-chain attacks land through
   exactly this kind of nightly job.
   - **npm releases, scripted.** Compare each pending release with the installed one before
     installing: a GitHub advisory on the version is **BLOCK** (never install, report it); a new
     install script, an unknown publisher or dropped provenance is **REVIEW** (read the changelog
     and the flagged script; approve only if it is plainly the vendor's own release). Either one
     holds the whole run.
   - **Everything else, by reading.** Skim the upstream commits of any fork you rebase (anything
     touching network calls, credentials, install or update scripts), casks you don't recognise
     or whose download host changed, and the release notes of the agent CLIs and computer-use
     tools for new telemetry or permission changes. When in doubt, hold the item and report it.
   - Every report names what was checked and what was held.
10. **Your own forks rebase without asking.** For tools you run from a fork (`my-changes` on top
    of upstream): resolve conflicts, rebuild, `git push --force-with-lease` to your fork. Never
    push to upstream. Report what was resolved.
11. **Tools that see secrets or run as root get a leak guard.** A model-account hub sees every
    prompt and holds every login; a phone-control daemon runs as root. Their updaters diff the
    outbound hostnames hard-coded in upstream (and, for root code, the root-run files) between the
    old and new version, and stop with exit 3 (REVIEW) on anything new. Approve only when each new
    host is the provider's own endpoint or fetches public data without sending request content,
    account data or tokens. Never approve a host because its name looks harmless.

## Normal flow

1. **Report.** Per machine: package-manager queue (`brew outdated`, `pacman -Qu`, `apt list
   --upgradable`, `winget upgrade`), agent CLI versions vs latest, each enabled package's update
   check, disk usage. Show one table. Invoking the skill is the approval for everything that is
   not reboot-class: go straight on.
2. **Update.** One lane per machine, started together. Within a lane, package manager first,
   then agent CLIs (`claude update`, `npm i -g @openai/codex`, `cursor-agent update`, `opencode
   upgrade`), then the npm packages enabled packages ship as (`npm i -g <name>@latest` for each
   line of `packages/<p>/npm`, then `fleet link` in case their skills changed), then each enabled
   package's update steps, then agent-facing services last so their
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

## Sudo without a human

Steps that need root run unattended, the nightly included, without the password ever reaching a
repo, a log or a prompt:

- **macOS:** `sudo -A` with `SUDO_ASKPASS` pointing at a tiny helper that reads the password from
  a login Keychain item. Never echo it or pipe it through `sudo -S`. If the helper fails, the
  password probably changed: report it.
- **Linux worker:** passwordless sudo for the user, so `sudo -n` works in scripts.

Sudo changes nothing about the safety rules: still nothing reboot-class, no `sudoers` edits.

## One script, parallel lanes

Put the deterministic part in a script (`fleet-update`, versioned in the repo) and keep the agent
for judgment. The author's shape:

```bash
fleet-update --check      # versions vs available, queues, cleanup sizes, health
fleet-update              # every lane in parallel, one summary, non-zero if any step failed
fleet-update <machine>    # one lane
fleet-update providers    # agent CLIs only, every machine
```

Within a lane, steps that share a lock or toolchain run in sequence (brew, then anything built
with brew's toolchain); everything else runs alongside. Per-step logs go to a dated directory.
Things the script must never touch stay with the agent: browsers, the app the agent runs in,
reboot-class work, worktrees, toolchains, snapshots.

Steps worth copying:

- **Agent CLIs hourly.** T3 Code flags a provider update within the hour, so a nightly alone
  leaves the fleet up to a day behind. An hourly `fleet-update providers` (through the
  `automation` skill) updates `claude`, `codex` and `opencode` everywhere without restarting
  anything: running sessions keep their CLI, new ones get the update. It skips while the nightly
  holds its lock.
- **Weekly T3 peers.** Environment links and MCP sign-ins between machines are 30-day tokens with
  no refresh. A weekly step re-pairs each machine with the others (mint a pairing code over ssh,
  relink over Tailscale, approve the MCP login) and records the last good run. A failure here means
  a link is about to lapse.
- **Tailscale last.** Relaunching the Tailscale app to apply an update drops the tailnet for a
  moment, so it is the final step of the controller lane. A worker's Tailscale goes with `--deep`.

## Unattended runs

A nightly scheduled run (a T3 Code scheduled task or a headless agent on this skill) is fine and
still bound by every rule above. Nothing in it may quit the app it runs inside. It writes its
report to the log dir and sends `fleet alert` with OK or NEEDS ATTENTION. Before a manual run,
read the latest nightly report: most of the work may already be done.

When the user ran `/fleet-update` alone in a T3 Code thread and the run was clean (no unresolved
failure, no failed login probe), settle the thread as the last action
(`t3_thread_organize` with `action: "settle"`). Anything else in the thread, or anything left for
the user, leaves it open.
