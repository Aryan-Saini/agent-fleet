# drop-folder

`~/drop` on every machine: the one path agents and people use to hand each other files,
screenshots, reports and alerts. An agent on a headless worker can't see your clipboard (a pasted
image reads the local clipboard, which does not cross ssh), so the workflow is always "put the file
in `~/drop`, tell the agent the path".

There are two ways to move files into another machine's `~/drop`:

| | how | when |
| --- | --- | --- |
| **push** | `to-worker <file>` on the controller, `to-controller <file>` on a worker ([`bin/`](bin/), thin wrappers over `fleet send`). Over ssh, lands immediately, fails loudly if the other side is asleep | the next step depends on the file being there |
| **sync** | [Syncthing](https://syncthing.net) keeps `~/drop` identical everywhere, ~15-25 s behind | files should just show up, no command |

**The author retired Syncthing in his own fleet.** T3 Code attachments now carry most images and
files with the thread itself ([t3-remote](../t3-remote/)), and the push helpers cover the rest, so
a background sync daemon on every machine stopped earning its keep. His `~/drop` folders are no
longer synced; each machine's is a local inbox that the other pushes into. The Syncthing setup
below still works and is the right choice if you'd rather not run a command. Pick one and say so
in `computers.md`, because "is it synced?" is the first question an agent asks when a file isn't
there.

Push helpers:

```bash
to-worker report.md shot.png         # controller -> <worker>:~/drop/
to-worker -d ~/Downloads build.zip   # somewhere other than ~/drop
to-controller build-report.md        # worker -> controller; pair with `fleet alert` so you look
```

`to-worker` uses `FLEET_WORKER` from `machine.env` (default `worker`), `to-controller` uses
`FLEET_CONTROLLER`. Both take several files and whole directories.

With Syncthing, the workflow is:

1. Screenshot on the controller. Point your screenshot tool (macOS: Shottr, CleanShot, or
   `defaults write com.apple.screencapture location ~/drop`) at the drop folder.
2. Syncthing carries it to every worker in ~15-25 s.
3. Tell the agent on the worker: `look at ~/drop/Shot-0412.png`.
4. Anything a worker writes to `~/drop` (reports, screenshots, alert files) comes back the same way.

## Install Syncthing (optional)

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

Push: `to-worker /etc/hostname`, then `ssh <worker> ls ~/drop/hostname`.

Syncthing: drop a file on one machine. It shows up on the other within ~25 s. If it "isn't there", wait
and look again before calling it broken: the watcher debounces 10 s.

## Health

`check.sh` fails when `~/drop` is missing, and, where Syncthing is installed, when it is not
answering. Heals by creating the folder and restarting Syncthing.

## Conventions

Files fleet tooling writes here, so you know what you are looking at:

| file | written by |
| --- | --- |
| `FLEET-ALERTS.log` | `fleet alert`, one line per alert, every machine |
| `FLEET-HEALTH-<machine>.txt` | `fleet health` while something is broken. Gone when healthy |
| `FLEET-SYNC-<machine>.txt` | `fleet sync` while config sync is failing |
| `WORKORDER-<machine>-<name>.txt` | `fleet workorder`, the report for each order |

Never put secrets in the drop folder. With Syncthing it is copied to every machine; without it,
files still sit there unencrypted until someone cleans up.
