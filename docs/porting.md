# Porting to another OS

The kit's scripts target a macOS controller and a Linux worker with systemd, because that is
what the author runs. The ideas are portable; only the mechanisms change. When something doesn't
fit your OS, give this file and the relevant package README to your agent and have it port the
piece, keeping the command names and contracts identical so the skills and docs still apply.

| piece | contract to keep | macOS | Linux | Windows (WSL2 or native) |
| --- | --- | --- | --- | --- |
| scheduler | health every 15 min, sync every 30 min, resume at boot, missed runs catch up | one dispatcher run by one signed runner app ([`packages/mac-automations`](../packages/mac-automations/)) | one systemd user timer per job, lingering on, `Persistent=true` ([`packages/linux-automations`](../packages/linux-automations/)) | Task Scheduler, "at startup" and "repeat every", "run as soon as possible after a missed start" |
| boot continuation | runs `fleet workorder resume` at boot without a login | auto-login + LaunchAgent | lingering + a oneshot unit | task "at startup, run whether user is logged on or not" |
| root for unattended jobs | no human types a password | `sudo -A` with an askpass helper reading the Keychain | a sudoers drop-in, `NOPASSWD`, scoped to the user | an elevated scheduled task, or WSL with a sudoers drop-in |
| secrets for GUI apps and services | every app and service sees the keys | `launchctl setenv` at login | `systemctl --user set-environment` before the services that need it | user environment variables, set once |
| notifications | `fleet alert` never fails | `terminal-notifier` or `osascript` | `notify-send`, or ssh to a machine with a screen | `New-BurntToastNotification`, or ntfy |
| package manager | update steps per package README | brew | pacman / apt / dnf | winget / scoop |
| always-on | nothing can sleep it; restarts after power loss | `pmset` | mask the sleep targets, BIOS restore-on-AC | power plan + BIOS |
| rollback before risky updates | a snapshot exists before the transaction | Time Machine local snapshot | btrfs snapshot of `/` ([storage.md](storage.md)) | System Restore point |

**Do not port one scheduler design onto the other OS.** The macOS dispatcher exists because
macOS grants privacy permissions per responsible process; Linux has no such thing, and a
dispatcher there hides what systemd already gives each job. See
[automations.md](automations.md).

WSL2 is the shortest path on Windows: run the worker inside it with systemd enabled
(`/etc/wsl.conf`, `[boot] systemd=true`) and the Linux units work unchanged. Keep the Windows
host itself always on and on Tailscale. A WSL2 worker's disk is a single virtual file, so the
[storage](storage.md) layout collapses to one volume plus data drives mounted from Windows.

## Rules for a port

- Same command names (`fleet health`, not a `fleet-health.ps1` callers must remember).
- Same check contract: exit 0 healthy; exit 1 with one line; `--heal` optional and safe.
- Same report format and the same alert command, so an agent on any machine reads them.
- Same direction for config: the controller authors, workers receive and discard local edits.
- Put the port next to the original and say in its header what it was ported from.
