# drop-folder

`~/drop` on every machine, kept identical by [Syncthing](https://syncthing.net). It is how files,
screenshots, reports and alerts move between machines without anyone running a command.

Why it matters: an agent on a headless worker cannot see your clipboard. Pasting an image reads
the local clipboard, which does not cross ssh. So the workflow is:

1. Screenshot on the controller. Point your screenshot tool (macOS: Shottr, CleanShot, or
   `defaults write com.apple.screencapture location ~/drop`) at the drop folder.
2. Syncthing carries it to every worker in ~15-25 s.
3. Tell the agent on the worker: `look at ~/drop/Shot-0412.png`.
4. Anything a worker writes to `~/drop` (reports, screenshots, alert files) comes back the same way.

In a hurry, skip the wait: `fleet send <machine> <file>` lands it over ssh immediately.

## Install

| OS | |
| --- | --- |
| Arch | `sudo pacman -S syncthing && systemctl --user enable --now syncthing` |
| Debian / Ubuntu | `sudo apt install syncthing && systemctl --user enable --now syncthing` |
| macOS | `brew install syncthing && brew services start syncthing` |
| Windows | SyncTrayzor, or syncthing as a scheduled task |

On Linux enable lingering (`sudo loginctl enable-linger $USER`) so it runs without a login.

## Pair

The web UI is `http://localhost:8384`. A headless worker's UI is reachable from the controller
with `ssh -L 8385:localhost:8384 worker`, then `http://localhost:8385`.

1. On each machine, Add Remote Device with the other's device ID (`syncthing --device-id`).
2. Share one folder, any folder ID you like, mapped to `~/drop` on every machine. If your
   screenshots must live elsewhere, share that folder and symlink `~/drop` to it, so the path
   agents use is the same everywhere.
3. Both sides Send & Receive.

## Verify

Drop a file on one machine. It shows up on the other within ~25 s. If it "isn't there", wait
and look again before calling it broken: the watcher debounces 10 s.

## Health

`check.sh` fails when Syncthing is not answering or `~/drop` is missing, and heals by
restarting Syncthing.

## Conventions

Files fleet tooling writes here, so you know what you are looking at:

| file | written by |
| --- | --- |
| `FLEET-ALERTS.log` | `fleet alert`, one line per alert, every machine |
| `FLEET-HEALTH-<machine>.txt` | `fleet health` while something is broken. Gone when healthy |
| `FLEET-SYNC-<machine>.txt` | `fleet sync` while config sync is failing |
| `WORKORDER-<machine>-<name>.txt` | `fleet workorder`, the report for each order |

Never put secrets in the drop folder. It is copied to every machine.
