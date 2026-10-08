---
name: automation
description: When the user wants something to run automatically or on a schedule on one of their machines (a cron job, a timer, a nightly script, a watcher), use skill.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  requires: "the fleet repo checkout; the target machine's scheduler"
---

# Automation

Every machine already has a way to run things on a schedule. Add to it. Never invent a second
scheduler beside it.

## 1. Pick the machine

Ask if it is not obvious. The answer changes everything downstream.

| signal | machine |
| --- | --- |
| touches the user's files, apps, screen, calendar or desktop | the controller |
| needs a GUI or a logged-in desktop session | the controller |
| long-running, heavy, or must work while the laptop is shut | a worker |
| watches a service, scrapes, or polls on its own cadence | a worker |

## 2. Use that OS's native scheduler

| OS | mechanism | lives at |
| --- | --- | --- |
| Linux | one systemd **user** timer + oneshot service per job | `~/.config/systemd/user/<name>.{service,timer}` |
| macOS | one LaunchAgent per job, or one dispatcher agent that runs every tool folder (below) | `~/Library/LaunchAgents/` |
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

macOS: a dispatcher pattern scales better than one agent per job when jobs need protected access.
One LaunchAgent fires `run-all.sh` hourly; each job is a folder `tools/<name>/<name>.sh` with an
optional `cadence` file. macOS grants privacy permissions to the *responsible process*, so if the
dispatcher runs through one app you granted Full Disk Access, every tool inherits it and no new
permission prompt ever appears. Test through launchd, not from an agent shell: the shell has a
different responsible process and reports false denials.

## 3. Rules on every OS

- Idempotent. It will run again whether or not the last run did anything.
- Absolute paths. No shell profile, no useful working directory.
- Exit non-zero on real failure, and call `fleet alert` when a human must act. Silence is the bug.
- **No secrets in unit files or scripts.** `Environment=` lines get committed. Read secrets from
  `~/.config/agent-secrets.env` or similar, outside the repo.
- Version the script and unit in the fleet repo under `automations/<machine>/`, because the live
  copy in `~/.config` does not survive a rebuild. Logs are never committed.
- Add a row to `automations/README.md` in the same commit: what, why, when, where, logs.

## 4. Verify one real run before saying done

```bash
systemctl --user start <name>.service && journalctl --user -u <name>.service -n 30 --no-pager
systemctl --user list-timers | grep <name>
```

Both platforms fail silently by default: Linux when a wall-clock timer's moment passes while the
box is down, macOS when the job lacks a permission.
