# How machines talk to each other

Everything an agent needs to reach another machine: run a command there, start an agent there,
move files either way, use a service running there. Every direction works. A worker is not a
dead end. The map of channels and why each exists is in [architecture.md](architecture.md); this
page is the working commands.

| I want to | from the controller | from the worker |
| --- | --- | --- |
| run a command over there | `ssh <worker> '<cmd>'` | `ssh <controller> '<cmd>'` |
| send a file now | `to-worker <file>` or `fleet send <worker> <file>` | `to-controller <file>` or `fleet send <controller> <file>` |
| start an agent over there | T3 `delegate_task` with the worker's `environmentId`, or `ssh <worker> 'claude -p "..."'` | T3 `delegate_task` with the controller's `environmentId`, or Codex over ssh |
| use a dev server over there | `https://<worker>.<tailnet>.ts.net:<port+10000>` | `http://<controller>:<port>` |
| see and click a GUI on the headless box | `halo` ([`packages/halo`](../packages/halo/)) | not needed, the controller has a screen |
| get the human's attention | you are already on their screen | `fleet alert "TITLE" "MSG"` |
| run something that may cut the connection | `fleet workorder start <name> <script>` | n/a |

## 1. Commands

Long jobs go in tmux (`tmux new -s <name>`) so they survive the connection dropping. `sudo` on
the worker is passwordless; on the controller use `sudo -A` with the Keychain askpass helper
([architecture.md](architecture.md#sudo-across-machines)).

**Non-interactive ssh gets a stripped PATH.** This looks exactly like a missing install:

```bash
ssh <controller> 'which claude'                 # not found
ssh <controller> 'zsh -lc "which claude"'       # still not found: -l reads .zprofile, not .zshrc
ssh <controller> 'zsh -ic "which claude"'       # found
ssh <controller> '~/.local/bin/claude --version'  # or use the absolute path
```

Fix it once per machine: PATH additions in `~/.zshenv` on macOS (zsh reads it for every shell),
and on a Linux worker a login-shell wrapper that sources one env file before exec'ing bash.
Tailscale SSH runs `<shell> -c "<cmd>"`, and non-interactive bash reads no startup files. If a
binary seems missing on a machine you know has it, check this before reinstalling.

## 2. Agents on another machine

### Through T3 (both directions, every harness)

Each machine's T3 Code is linked to the other's. From a T3 thread, `delegate_task` with the
other machine's `environmentId` in its target starts a subagent over there that wakes you when it
finishes. From any Claude session, the other T3's MCP server (`t3-<worker>` / `t3-<controller>`)
gives `t3_thread_launch` and `t3_thread_read`. The work runs with that machine's own logins and
shows on the phone. Setup and renewal: [t3-code.md](t3-code.md).

### Over ssh

Headless agents take a prompt and print the result, so they compose with shell plumbing:

```bash
VERDICT=$(ssh <worker> '~/.local/bin/claude -p "does this build log show a real failure? yes/no"')
ssh <worker> 'tmux new -d -s build "~/.local/bin/claude -p \"run the tests and fix failures\" \
  > ~/drop/build-report.md 2>&1; fleet alert build \"done, see ~/drop/build-report.md\""'
ssh <worker> 'cd ~ && codex exec -s read-only --skip-git-repo-check "audit ~/drop/x.py" < /dev/null'
```

Codex needs both extra flags over ssh: it refuses to run outside a trusted git repo, and it
blocks reading stdin unless you close it.

**Claude Code on macOS cannot be started over non-interactive ssh.** Its credentials live in the
Keychain, which such a session cannot read, so it answers "Not logged in". On Linux they are a
file, so the controller-to-worker direction works. Codex keeps auth in a file on every OS and
works both ways. For Claude on the controller from the worker, go through T3.

### Handing work over without T3

There is no message bus. A file plus a nudge works:

```bash
cat > ~/drop/WORK-ORDER.md <<'MD'
Need someone on the controller to run the iOS simulator build and report back.
MD
to-controller ~/drop/WORK-ORDER.md
fleet alert "work order" "WORK-ORDER.md is in ~/drop"
```

The reply comes back the same way.

## 3. Files

- **`to-worker` / `to-controller`** (the kit's `fleet send <machine>`): scp into the other
  machine's `~/drop`. Multiple files and directories fine, `-d <dir>` for another destination,
  fails loudly with a hint if the other side is asleep or unreachable.
- **T3 attachments:** attach an image or file to a thread and it lands on whichever machine runs
  the thread. The usual way to get a screenshot to the headless worker.
- **No clipboard across ssh.** Put the image somewhere on the other machine and give the agent
  the path. On the worker's virtual screens, Halo carries the clipboard both ways.
- `tailscale file cp` also works, but the receiver must run `tailscale file get`.

A Syncthing-mirrored drop folder used to do this lazily. It was retired once T3 carried files,
because an explicit copy either worked or failed, where a sync folder left you wondering. The
[`drop-folder`](../packages/drop-folder/) package still sets one up if you want it.

## 4. Services: dev servers, databases

Every machine is on the tailnet, so a port on one is a hostname away from every other, the phone
included, from anywhere. Nobody needs to copy a project over to look at it running.

### On the worker: loopback plus Tailscale Serve

Do **not** bind a dev server on the worker to `0.0.0.0`. The worker's firewall accepts home LAN
traffic, so `0.0.0.0` also opens it to anyone on the Wi-Fi with no Tailscale auth. Bind
localhost and put it behind Tailscale Serve:

```bash
ssh <worker> "worker-expose add myapp ~/dev/myapp 3000 'pnpm dev -H localhost'"
# -> https://<worker>.<tailnet>.ts.net:13000, tailnet only, real certificate
ssh <worker> 'worker-expose ls'
ssh <worker> 'worker-expose rm myapp'
```

The HTTPS URL matters beyond security: a real certificate makes the page a secure context, so
cookies, auth SDKs, service workers and clipboard APIs work. Plain `http://<worker>:3000` left
auth SDKs stuck in a reload loop. The app may still need the hostname in its dev host allowlist
(Next `allowedDevOrigins`, Vite `server.allowedHosts`). Details, the `systemd` template unit and
the 24-hour reaper: [`packages/dev-server`](../packages/dev-server/).

Never touch the worker's existing `tailscale serve /` mapping. It is T3 Code, and the phone's
fallback path depends on it.

### Everywhere else

On the controller, binding all interfaces is the quick way:

```bash
next dev -H 0.0.0.0
vite --host 0.0.0.0
```

Or tunnel instead of rebinding:

```bash
ssh -f -N -L 9300:localhost:3000 <worker>   # the worker's :3000 becomes local :9300
ssh -f -N -R 9400:localhost:8765 <worker>   # local :8765 becomes the worker's :9400
pkill -f "ssh -f -N -L 9300"                # close it
```

If your ssh config pins `AddressFamily inet6` for the worker (useful when the macOS Tailscale
IPv4 route goes missing), a plain `-L` listens on IPv6 only and tools that dial `127.0.0.1` see a
closed port. Add `-o AddressFamily=any` and bind `127.0.0.1:9300:` explicitly.

`tailscale funnel` would put a port on the public internet. Leave it off unless you mean that.

## 5. Getting the human's attention

`fleet alert "TITLE" "MESSAGE"` from a headless box: a notification on the controller over ssh,
a message to your phone sent through the controller's Messages app, and a line in a log file
plus the journal for when the controller is asleep. It never fails its caller. Use it when a long
job finishes, a job needs a decision, or something broke unattended.

## What does not work

- **Claude Code on a Mac, started over ssh.** Keychain. Use T3, or Codex over ssh.
- **Config edits made on a worker.** The next config sync discards them. Edit on the
  controller. See [sync.md](sync.md).
- **Reaching a sleeping machine.** The copy helpers fail, and Wake-on-LAN only works from the
  same LAN. Keep the worker always on.
- **A server bound to `127.0.0.1`, over the tailnet.** Serve it, rebind it, or tunnel it.
- **Writing to the worker's read-only data drive, or staging big transfers in `$HOME`.** See
  [storage.md](storage.md).
