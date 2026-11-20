# linux-automations

Every scheduled job on a Linux worker is its own systemd **user** timer: one `.service` plus one
`.timer` per job, any cadence, each one inspectable on its own. There is no dispatcher and no
permission system to inherit, so the macOS design ([mac-automations](../mac-automations/)) would
only add a layer. Don't port it here, and don't use cron.

## Where things go

| what | where |
| --- | --- |
| unit files | `~/.config/systemd/user/<name>.service` and `<name>.timer` |
| the script | `~/.local/bin/<name>` (units say `%h/.local/bin/<name>`), or `/usr/local/bin/<name>` |
| repo copy, script | `~/fleet/automations/<worker>/bin/<name>` |
| repo copy, units | `~/fleet/automations/<worker>/units/<name>.{service,timer}` |
| registry row | `~/fleet/automations/README.md` (from `templates/automations-README.md`) |
| logs | `journalctl --user -u <name>`, not a log file |

`~/.config/systemd/user/` is not in any repo, so a unit that only exists there is gone on a
rebuild. Keep both copies. The live file is what runs; the repo copy is what survives.

**Lingering** must be on (`sudo loginctl enable-linger $USER`; `./install.sh` does it on workers),
or user timers stop the moment you log out and never start after a reboot.

## Adding one

The [`example/`](example/) folder is a working pair plus a script. Copy and rename it:

```bash
install -m 755 example/nightly-report ~/.local/bin/nightly-report
cp example/nightly-report.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now nightly-report.timer
systemctl --user list-timers --all | grep nightly-report
```

Then prove a real run instead of assuming:

```bash
systemctl --user start nightly-report.service
journalctl --user -u nightly-report -n 30 --no-pager
```

Timer shapes:

```ini
OnCalendar=*-*-* 03:00:00        # wall clock, daily
OnCalendar=Mon *-*-* 09:00:00    # weekly
OnBootSec=2min                   # interval: first run after boot...
OnUnitActiveSec=15min            # ...then every 15 min after the last run
```

## Downtime is what bites

An always-on box still reboots for updates and loses power. A wall-clock timer whose moment
passes while the box is down never fires. **Use `Persistent=true`** on any `OnCalendar=` job where
a skipped day matters (backups, archives, refreshes), so the missed run fires on the next boot.
Leave it off for jobs that must never run late, such as anything that makes a sound or messages a
person at a fixed time. Say which you chose and why in the registry row.

## Rules

- One `.service` and one `.timer` per job. Never chain jobs inside one script.
- `Type=oneshot`. These are tasks, not daemons. A long-running thing is a plain service with
  `Restart=always` and no timer.
- Idempotent and safe to run twice. A `Persistent=true` catch-up does exactly that.
- **systemd reads no shell profile.** No `.zshenv`, no `.bashrc`. Set `PATH` in the script, use
  absolute paths for files, and get keys into the manager's environment
  (`systemctl --user set-environment`, see [mcp](../mcp/)) or read them from a mode 600 file.
- **Never commit a secret in a unit file.** `Environment=` lines are the trap: a unit pasted into
  the repo with a live token is now in git history. Keep a placeholder in the repo copy.
- Background jobs get `Nice=10` and `IOSchedulingClass=idle` so they stay out of interactive work.
- Need to tell a human? `fleet alert "<title>" "<message>"` from the script on failure.

## Debugging

```bash
systemctl --user list-timers --all            # next and last run of every timer
systemctl --user status <name>.service        # last result
journalctl --user -u <name> --since today     # its output
systemctl --user --failed                     # anything broken
```

A script's child processes log under their own PID. If output vanishes from `journalctl -u`,
capture it into a variable and `echo` it from the script itself.
