---
name: automation
description: All automations run through here. Use when creating, editing, moving, pausing, retiring or debugging anything that runs on a schedule on any of the user's machines (hourly or nightly jobs, background checks, watchers, recurring scripts, "run this every X", "automate this"), and BEFORE writing any LaunchAgent, cron entry, systemd timer or T3 scheduled task.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "the fleet repo checkout; the rest depends on the target machine's scheduler"
---

# Automation

**All automations run through here.** Every machine already has exactly one way to run things on a
schedule. Creating, editing or retiring a job means changing that system, never registering a
new job beside it. Every job also gets a row in `automations/README.md`, the registry, in the same
commit.

## 1. Pick the machine

Ask if it is not obvious. The answer changes everything downstream.

| signal | machine |
| --- | --- |
| touches the user's files, apps, screen, calendar or desktop | the controller |
| needs a GUI or a logged-in desktop session | the controller |
| long-running, heavy, or must work while the laptop is shut | a worker |
| watches a service, scrapes, or polls on its own cadence | a worker |
| needs an exact wall-clock time the controller's dispatcher doesn't offer | a worker |

## 2. Read that machine's instructions, in full, before writing anything

Keep one file per machine at `automations/<machine>/SPECIAL_AUTOMATION_INSTRUCTION.md`: the
layout, how to add a job, how to prove it ran, and the traps specific to that box. The machines
work completely differently (different mechanisms, not just different permissions), so never
work from memory of the other one's setup.

## 3. The native scheduler per OS

| OS | mechanism | lives at |
| --- | --- | --- |
| Linux | one systemd **user** timer + oneshot service per job | `~/.config/systemd/user/<name>.{service,timer}` |
| macOS | one dispatcher LaunchAgent that runs every tool folder (below) | `automations/<controller>/tools/<name>/` |
| Windows | Task Scheduler | `schtasks /create ...` |

Linux, the house shape:

```ini
# <name>.service
[Unit]
Description=<what it does>

[Service]
Type=oneshot
ExecStart=%h/.local/bin/<name>
```

```ini
# <name>.timer
[Unit]
Description=Run <name> every <cadence>

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min      # or OnCalendar=*-*-* 03:00:00
Persistent=true            # a run missed while the box was down fires on next boot

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload && systemctl --user enable --now <name>.timer
```

Lingering must be on (`loginctl show-user $USER -p Linger`) or user timers stop at logout.

macOS, the dispatcher: two LaunchAgents fire `run-all.sh` (hourly, and every minute for frequent
tools). Each job is a folder `tools/<name>/<name>.sh` with an optional `cadence` file (`hourly`,
`every <N>m`; absent means daily). Adding a job is dropping a folder in. Never a new LaunchAgent,
`crontab` or `launchctl submit`. The only standalone LaunchAgents are plumbing listed in the
registry; don't add to that list without the user saying so.

Why one dispatcher: macOS grants privacy permissions to the *responsible process*. If the
dispatcher runs through one small runner app you granted Full Disk Access, every tool inherits it
and no new permission prompt ever appears. Test through launchd, not from an agent shell: the
shell has a different responsible process and reports false denials.

T3 Code scheduled tasks are a third kind: an agent run whose report the user reads in a thread
(a nightly `/fleet-update`, for example). Add one only when the user asks for exactly that.

## 4. Rules on every OS

- Existing systems only. Never add a parallel scheduler.
- Idempotent. It will run again whether or not the last run did anything.
- Absolute paths. No shell profile, no useful working directory.
- Exit non-zero on real failure, and call `fleet alert` when a human must act. Silence is the bug.
- **No secrets in unit files or scripts.** `Environment=` lines get committed. Read secrets from
  `~/.config/agent-secrets.env` or similar, outside the repo.
- Version the script and unit in the fleet repo under `automations/<machine>/`, because the live
  copy in `~/.config` does not survive a rebuild. Logs are never committed. If the fleet repo
  uses a denylist `.gitignore`, check what you are adding rather than assuming it is excluded.
- Add the registry row in the same commit: what, why, when, where, logs.

## 5. Verify one real run before saying done

```bash
systemctl --user start <name>.service && journalctl --user -u <name>.service -n 30 --no-pager
systemctl --user list-timers | grep <name>
```

On macOS, run the dispatcher through launchd for just that tool and read its log.

Both platforms fail silently by default: Linux when a wall-clock timer's moment passes while the
box is down for a reboot (hence `Persistent=true`), macOS when the job lacks a permission.
