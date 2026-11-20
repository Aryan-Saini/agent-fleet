# t3-remote

Drive agents on any machine from your phone. [T3 Code](https://github.com/pingdotgg/t3code) runs
a backend on each machine, and T3 Connect links those backends to the web, desktop and mobile
apps through a relay. It works from school or cellular with no VPN and no open ports.

This is the "phones driving it remotely" part of the fleet: start a thread on the worker from
your phone, put the phone away, get a push when the agent is done. It is also how the controller
and the worker hand work to each other.

## Install

Pick a channel per machine: **stable** (`t3@latest`, the `t3-code` cask) or **nightly** (new
every day, fixes land first, occasionally breaks). `./install.sh` runs this package's
`install.sh`, which installs T3 Code on that channel and records `T3_CHANNEL` in `machine.env`:

```bash
T3_CHANNEL=nightly ./install.sh --role worker ...    # default: stable
```

| machine | how T3 runs | what install.sh does |
| --- | --- | --- |
| Linux worker | the `t3` CLI as a systemd user service | `npm i -g t3@latest` or `t3@nightly`, then `t3 service install` |
| macOS | the desktop app, which runs its own backend and updates itself | `brew install --cask t3-code` or `t3-code@nightly` |
| phone | the T3 Code app | nothing; install it yourself |

Then the part only you can do, on each machine: sign in to T3 Connect. On Linux run
`t3 connect link --headless` inside tmux (the prompt dies with the ssh session otherwise), open the
link it prints, then `t3 service restart` and `t3 connect publish` so finished agents push to your
phone. On macOS, sign in from the app's Settings and turn on T3 Connect.

## The worker's service

`t3 service install` writes `t3code.service`, a systemd **user** unit. It starts T3's versioned
launcher, which owns the active version under `~/.t3/runtime/` and records it there; don't
replace its `ExecStart` with your own drop-in. Lingering ([always-on](../always-on/)) keeps it
running without a login. Logs: `~/.t3/userdata/logs/`, and `journalctl --user -u t3code`.

Two paths to each machine, kept on both:

- **The T3 Connect relay**, which works anywhere. This is the one that matters away from home.
- **Tailscale Serve**, the fallback for anything on the tailnet:
  `tailscale serve --bg --https=443 http://127.0.0.1:3773` puts the backend on
  `https://<machine>.<tailnet>.ts.net`. It needs `sudo tailscale set --operator=$USER` first, or
  T3 logs `Failed to configure Tailscale Serve`. That root path belongs to T3 from then on.

## Updating without killing yourself

Restarting `t3code.service` kills every agent session it runs, **including the session running the
update**. An agent that updates T3 from inside T3 dies halfway, with nobody watching. So the
updater always runs detached from the thing it restarts:

- **Worker:** drive it from the controller over ssh (`/fleet-update` does), or start it as its own
  transient unit: `systemd-run --user --unit=t3-update --collect t3 update --channel "$T3_CHANNEL" --yes`.
- **macOS:** anything that quits or relaunches the app kills its children. Run such commands in a
  process tree the app doesn't own, such as a new Terminal window
  (`osascript -e 'tell application "Terminal" to do script "<cmd>; exit"'`), and have the agent
  poll a log or status file afterwards.

A good updater also checks health afterwards (service active, port answers 200, connect status
linked, relay process up) and rolls back to the previous version if it doesn't come back. Keep
the last healthy version in a file on the controller.

**The phone sets the floor.** The mobile app can't be downgraded or side-loaded, and a backend too
far ahead of it fails in a confusing way: every server check passes, the phone authenticates, then
drops the socket and reconnects in a backoff loop. If the phone loses a machine right after an
update, suspect version skew before the network. Update workers from the controller, not from a
timer on the worker, so an update never lands while you're driving that worker from your phone.

## Linking the controller and the worker

Each machine can register with the other's T3, two ways, so agents on one can work on the other:

| link | what it gives | lasts |
| --- | --- | --- |
| **environment link** (`t3 environment link <url> --pairing-code <code>`) | this T3's agents can open threads on the other machine; it shows in the app as a second environment | 30 days |
| **MCP sign-in** (`claude mcp add --transport http t3-<other> https://<other>.<tailnet>.ts.net/mcp`, then `claude mcp login t3-<other>`) | Claude Code on this machine gets the other T3's tools: list projects, launch and read threads, schedule tasks | 30 days, no refresh |

Pairing codes are one-time: `t3 auth pairing create --ttl 15m` on the target. Link over the
Tailscale URL first and keep the relay URL as a fallback address; T3 refuses to relink at a
different first address, so a link made over the relay alone has to be dropped and remade.

Both expire after 30 days, quietly. **Renew them weekly from a script** (the author's is
`t3-peer-renew`, run weekly by `/fleet-update` on both machines), each machine renewing its own
side:

1. Mint a pairing code on the other machine over ssh.
2. Relink the environment over Tailscale, with the relay kept as a fallback.
3. For the MCP sign-in, run `claude mcp login t3-<other> --no-browser` on a pseudo-terminal (it
   refuses to run without one), read the authorize URL it prints, follow its redirect to the
   connect page's parameters, and approve with the pairing code by posting the same decision the
   page would. Then confirm the stored token's expiry moved out.

By hand, if the script fails: run the login in a real terminal on the controller (it opens the
browser), or on the worker run it in tmux with `--no-browser` and forward its callback port from
the controller with `ssh -fN -L <port>:127.0.0.1:<port> <worker>`.

## Working across machines

- **`delegate_task` to the other machine.** Inside T3, an agent hands work to a subagent with
  `delegate_task`; adding the other machine's `environmentId` to the target runs it there, with
  that machine's own logins, as a card that wakes the parent when done. `orchestrator_capabilities`
  lists the environment ids. The `subagents` skill covers when to use it.
- **Why not just ssh?** Claude Code on macOS keeps its login in the Keychain, which a
  non-interactive ssh session can't unlock. The worker can run Codex on the controller over ssh,
  but not Claude. Through T3 it can run either.
- **Scheduled tasks.** T3 can start a fresh thread on a schedule (`schedule_task`, or Settings,
  Scheduled tasks). Use it for agent runs whose report you want to read in a thread on your phone,
  such as the nightly `/fleet-update`. On a laptop, wake it first: `sudo pmset repeat wake MTWRFSU 01:58:00`
  for a 02:00 task. Everything that is a plain script belongs in
  [mac-automations](../mac-automations/) or [linux-automations](../linux-automations/) instead.
- **Attachments.** Images and files attached to a thread travel with it to whichever machine runs
  it, which replaces most manual file shuffling.

## Settings

In `fleet.env` or `machine.env`:

```bash
T3_CHANNEL=stable          # stable | nightly, written by install.sh
T3_PORT=3773               # the backend's port
T3_SERVICE=t3code.service  # the systemd user unit name on Linux workers
```

## Health

`check.sh`, on Linux: the service is active, the port answers 200, `t3 connect status` shows
exposure on and the environment linked, and the relay tunnel process is alive. Heals by
restarting the service and re-applying the Tailscale Serve mapping. On macOS it checks only that
the port answers, because the app owns the connection and the CLI reports it as missing.

## Gotchas

- A systemd service gets no shell profile, so MCP keys exported in `.zshenv` never reach agents
  started from the phone. See [mcp](../mcp/), "Keys reach every way an agent can start".
- Don't remap the root path of an existing `tailscale serve` config; add a new port or path.
- On macOS, `t3 connect status` from a terminal says unauthorized even when the app's tunnel is
  up. The app owns the credential. Trust the app and the web Connections panel there.
- The Mac app has no CLI on PATH. When a script needs one, run the CLI version that matches the
  app (`pnpm dlx t3@<app version> ...`) so the two agree.
