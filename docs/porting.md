# Porting to another OS

The kit's scripts target macOS and Linux with systemd, because that is what the author runs. The
ideas are portable; only the mechanisms change. When something doesn't fit your OS, give this
file and the relevant package README to your agent and have it port the piece, keeping the
command names and contracts identical so the skills and docs still apply.

| piece | contract to keep | macOS | Linux | Windows (WSL2 or native) |
| --- | --- | --- | --- | --- |
| scheduler | health every 15 min, sync every 30 min, resume at boot | LaunchAgents (`units/launchd`) | systemd user units + lingering (`units/systemd`) | Task Scheduler, triggers "at startup" and "repeat every" |
| boot continuation | runs `fleet workorder resume` at boot without a login | auto-login + LaunchAgent | lingering + `default.target` | task "at startup, run whether user is logged on or not" |
| notifications | `fleet alert` never fails | osascript | notify-send | `New-BurntToastNotification`, or ntfy only |
| package manager | update steps per package README | brew | pacman / apt / dnf | winget / scoop |
| always-on | nothing can sleep it; restarts after power loss | `pmset` | mask sleep targets | power plan + BIOS |

WSL2 is the shortest path on Windows: run the worker inside it with systemd enabled
(`/etc/wsl.conf`, `[boot] systemd=true`) and the Linux units work unchanged. Keep the Windows
host itself always-on and on Tailscale.

## Rules for a port

- Same command names (`fleet health`, not `fleet-health.ps1` callers must remember).
- Same check contract: exit 0 healthy; exit 1 with one line; `--heal` optional and safe.
- Same files in `~/drop` and the same report format, so an agent on any machine reads them.
- Put the port next to the original and say in its header what it was ported from.
