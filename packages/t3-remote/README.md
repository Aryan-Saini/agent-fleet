# t3-remote

Drive agents on any machine from your phone. [T3 Code](https://github.com/pingdotgg/t3code) runs
a backend on each machine, and T3 Connect links those backends to the web, desktop and mobile
apps through a relay. It works from school or cellular with no VPN and no open ports.

This is the "phones driving it remotely" part of the fleet: start a thread on the worker from
your phone, put the phone away, get a push when the agent is done.

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
| macOS | the desktop app, which runs its own backend | `brew install --cask t3-code` or `t3-code@nightly` |
| phone | the T3 Code app (TestFlight on iOS) | nothing; install it yourself |

Then the part only you can do, on each machine: sign in to T3 Connect. On Linux run
`t3 connect link --headless`, open the link it prints, then `t3 service restart` and
`t3 connect publish` so finished agents push to your phone. On macOS, sign in from the app's
Settings and turn on T3 Connect.

Optional second path: `tailscale serve --bg --https=443 http://127.0.0.1:3773` puts the backend
on `https://<machine>.<tailnet>.ts.net` for anything already on the tailnet. The relay is what
matters away from home; Tailscale Serve is the fallback.

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

## Updating

Linux: `t3 update --channel "$T3_CHANNEL" --yes`, which also restarts the service. macOS: the app
updates itself. Keep every machine and the phone app compatible; the phone usually sets the floor. Update workers
from the controller (`/fleet-update`), not from a timer on the worker, so an update never lands
while you are driving that worker from your phone.

## Gotchas

- A systemd service gets no shell profile, so MCP keys exported in `.zshenv` never reach agents
  started from the phone. See `packages/mcp`, "services do not read your profile".
- Don't remap the root path of an existing `tailscale serve` config; add a new port or path.
