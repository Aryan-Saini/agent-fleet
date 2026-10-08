# How machines talk to each other

Everything an agent needs to reach another machine: run a command there, start an agent there,
move files either way, use a service running there. Every direction works. A worker is not a
dead end.

| I want to | do this |
| --- | --- |
| run a command over there | `ssh <machine> '<cmd>'` |
| send a file now | `fleet send <machine> <file>` |
| share a file lazily | drop it in `~/drop` |
| start an agent over there | `ssh <machine> '~/.local/bin/claude -p "..."'` (see below for macOS) |
| use a dev server over there | `http://<machine>:3000` |
| see and click a GUI on a headless box | `screenshare` (packages/screenshare) |
| get the human's attention | `fleet alert "TITLE" "MSG"` |
| run something that may cut the connection | `fleet workorder start <name> <script>` |

## 1. Commands

Long jobs go in tmux (`tmux new -s <name>`) so they survive the connection dropping.

**Non-interactive ssh gets a stripped PATH.** This looks exactly like a missing install:

```bash
ssh mac 'which claude'                 # not found
ssh mac 'zsh -lc "which claude"'       # still not found: -l reads .zprofile, not .zshrc
ssh mac 'zsh -ic "which claude"'       # found
ssh mac '~/.local/bin/claude --version'  # or use the absolute path
```

Fix it once: put PATH additions in `~/.zshenv` (zsh reads it for every shell, including
non-interactive ssh and the agents that run through it), not `~/.zshrc`.

## 2. Agents on another machine

Headless agents take a prompt and print the result, so they compose with shell plumbing:

```bash
VERDICT=$(ssh worker '~/.local/bin/claude -p "does this build log show a real failure? yes/no"')
ssh worker 'tmux new -d -s build "~/.local/bin/claude -p \"run the tests and fix failures\" \
  > ~/drop/build-report.md 2>&1; fleet-alert build \"done, see ~/drop/build-report.md\""'
ssh worker 'cd ~ && codex exec -s read-only --skip-git-repo-check "audit ~/drop/x.py" < /dev/null'
```

**Claude Code on macOS cannot be started over non-interactive ssh.** Its credentials live in the
Keychain, which such a session cannot unlock, so it answers "Not logged in". On Linux they are a
file, so the other direction works. Codex stores auth in a file on every OS and works both ways.

**There is no message bus.** The pattern that works is a file plus a nudge:

```bash
cat > ~/drop/WORK-ORDER.md <<'MD'
Need someone on the controller to run the iOS simulator build and report back.
MD
fleet alert "work order" "WORK-ORDER.md is in ~/drop"
```

The reply comes back the same way.

## 3. Files

- **Now:** `fleet send <machine> <file>...`, straight over ssh. `-d <dir>` for another destination.
  Fails loudly with a hint if the machine is unreachable.
- **Lazily:** the drop folder. Syncthing's watcher debounces 10 s, so budget 15-25 s end to end.
  A file that "isn't there yet" is usually just that delay.
- **Images:** no clipboard across ssh. Put the image in `~/drop` and give the agent the path.

## 4. Services: dev servers, databases

Every machine is on the tailnet, so a port on one is a hostname away from every other, phone
included, from anywhere. Nobody needs to copy a project over to look at it running.

```bash
open http://worker:3000                  # a dev server on the worker, from the controller or phone
psql -h worker -p 5432 -U postgres mydb  # a database on the worker
```

The server must bind all interfaces:

```bash
next dev -H 0.0.0.0
vite --host 0.0.0.0
python3 -m http.server 8000 --bind 0.0.0.0
```

If it can't, tunnel it:

```bash
ssh -f -N -L 9300:localhost:3000 worker   # the worker's :3000 becomes local :9300
ssh -f -N -R 9400:localhost:8765 worker   # local :8765 becomes the worker's :9400
pkill -f "ssh -f -N -L 9300"              # close it
```

HTTPS (service workers, camera, clipboard APIs need it): `tailscale serve --bg --https 8443 3000`
on the worker gives `https://worker.<tailnet>.ts.net:8443` with a real certificate.
`tailscale funnel` would put it on the public internet; leave it off unless you mean that.

## What does not work

- Claude Code on a Mac, started over ssh from another machine. Use Codex, or hand the work over
  through `~/drop`.
- Config edits made on a worker. They are discarded by the next `fleet sync`. Edit on the controller.
- Reaching a sleeping machine. `fleet send` fails; the drop folder catches up on wake.
  Wake-on-LAN only works from the same LAN.
- A server bound to `127.0.0.1`, over the tailnet. Rebind or tunnel.
