# cliproxy

Every Claude and Codex account signs in once, on the worker, into a
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) hub. Claude Code and Codex on every
machine talk to the hub instead of logging in themselves. You get one pool of accounts for the
whole fleet, one place to see usage, a full log of every call, and traffic to the providers from
one IP. The setup follows Theo's
[guide](https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af).

**Read the terms first.** Subscription plans are licensed to a person, for use through the
official clients. Routing them through a proxy, and pooling several accounts to stretch limits,
may break a provider's terms and can get accounts suspended. This package documents how the
author runs it on his own accounts. Never share hub access with anyone else. Your accounts, your
call.

```
controller ──┐                                  ┌── api.anthropic.com
phone (T3) ──┼── https://<worker>.<tailnet>.ts.net:8317 ── hub ──┤
worker ──────┘     tailscale serve, tailnet only     127.0.0.1:8317  └── chatgpt.com
```

| | |
| --- | --- |
| hub | `127.0.0.1:8317` on the worker, published tailnet-only with `tailscale serve --bg --https=8317 http://127.0.0.1:8317` |
| dashboard | `/management.html` on the same URL, behind the management key |
| service | `cliproxyapi.service`, systemd user unit, `Restart=always` ([`units/`](units/)) |
| install dir | `~/cliproxyapi`: the binary, `config.yaml` (mode 600), `static/management.html`, `logs/` |
| accounts | `~/.cli-proxy-api/*.json`, one OAuth login per account. `"disabled": true` benches one |
| keys | `~/.config/cliproxy/access-key` (clients send it) and `management-key` (dashboard), mode 600, never committed |

## Build from source, from your forks

Nothing prebuilt has to run. Fork both repos and keep your patches on a `my-changes` branch on top
of upstream's newest release tag:

| checkout | upstream (`origin`) |
| --- | --- |
| `~/dev/cliproxyapi` | `router-for-me/CLIProxyAPI` |
| `~/dev/cliproxyapi-panel` | `router-for-me/Cli-Proxy-API-Management-Center` |

Build the server as upstream's no-plugin variant (`CGO_ENABLED=0 go build ./cmd/server`), the
panel with `bun`, and copy both into the install dir. The author's only patch so far hides the
panel's sponsor banner and affiliate links.

An updater worth writing, run nightly by `/fleet-update`:

1. Fetch upstream. Before rebasing, diff the outbound hostnames hard-coded in upstream's source
   between your tag and the new one. A new host stops the update for a human to read (exit 3).
2. Rebase `my-changes` onto the new tag, build both, swap them in keeping `.prev` copies.
3. Health-check `/v1/models`; roll back to `.prev` on failure.
4. Push `my-changes` to your fork.

## Config choices

```yaml
# config.yaml, the parts that matter (start from upstream's config.example.yaml; keys move
# between major versions, so check them against the example you build from)
server:
  host: 127.0.0.1               # loopback only; tailscale serve does the rest
  port: 8317
management:
  disable-auto-update-panel: true   # no panel downloads from GitHub
routing:
  strategy: fill-first          # one account carries everything until it hits a limit
  session-affinity: false
observability:
  logs:
    request-log: true           # one file per request, auth headers masked
    logs-max-total-size-mb: 0   # the hub never deletes logs; the archive job does
```

The management key goes in `management.secret-key` and client keys in the client key list;
both live only in the worker's `config.yaml`, mode 600.

- **Fill-first, no load balancing.** Order is the `priority` field in each account's JSON (higher
  first, ties by file name); the hub reloads on change. When the first account resets, traffic
  returns to it.
- **Fewer phone-homes.** Run with `-local-model` so it never fetches a remote model catalog, leave
  plugins off, and don't pass `-home-jwt`. Audit what it contacts on every upgrade; the
  updater's host diff is that audit.

## Point the clients at it

Claude Code, in `~/.claude/settings.json` on each machine:

```json
{
  "env": { "ANTHROPIC_BASE_URL": "https://<worker>.<tailnet>.ts.net:8317" },
  "apiKeyHelper": "cat ~/.config/cliproxy/access-key"
}
```

Codex, in `~/.codex/config.toml`:

```toml
model_provider = "cliproxy"

[model_providers.cliproxy]
name = "CLIProxyAPI"
base_url = "https://<worker>.<tailnet>.ts.net:8317/v1"
wire_api = "responses"
requires_openai_auth = false
env_key = "CLIPROXY_ACCESS_KEY"   # exported from ~/.config/agent-secrets.env, see packages/mcp
```

Copy `access-key` to each machine with `fleet secrets push` or by hand, mode 600. A shell started
inside a Claude Code session inherits `ANTHROPIC_BASE_URL`, so test from a fresh terminal.

## Adding an account

Dashboard, **OAuth Login**, in a private browser window signed in as the new account. The OAuth
callbacks land on the worker (Claude on port 54545, Codex on 1455), so tunnel them first from the
machine with the browser:

```bash
ssh -f -N -L 54545:localhost:54545 -L 1455:localhost:1455 <worker>
```

Codex also logs in headless: `cd ~/cliproxyapi && WRITABLE_PATH=$PWD ./cli-proxy-api -config config.yaml -codex-device-login`.

## Usage view

Worth a small script of your own (the author's is `hub-usage`): read each account's OAuth token
from `~/.cli-proxy-api/`, ask the provider for that account's 5-hour and weekly use and reset
times, and print one row per account with the default marked. A `default <account>` subcommand
that sets that account's priority to 100 and the rest of its provider to 0 makes switching a
one-liner. Have the worker's watchdog alert when an enabled account's row errors (a dead login)
and once when every account of a provider is at its limit.

## When the worker is down

Every session on the controller depends on the hub. [`bin/hub`](bin/hub) flips this machine
between the hub and its own logins:

```bash
export CLIPROXY_URL=https://<worker>.<tailnet>.ts.net:8317
hub status    # which way it points, whether the hub answers
hub off       # own logins: no call logging, no account fallback
hub on        # back through the hub; refuses while it does not answer
hub tick      # one failover check
```

Run `hub tick` every minute and failover is automatic: three failed checks in a row switch off,
two good ones switch back, each with a notification, and a manual `hub off` is never undone. On a
macOS controller that is a [mac-automations](../mac-automations/) tool:

```bash
mkdir -p ~/fleet/automations/mac/tools/hub-failover
printf '#!/bin/bash\nexport CLIPROXY_URL=https://<worker>.<tailnet>.ts.net:8317\nexec hub tick\n' \
  > ~/fleet/automations/mac/tools/hub-failover/hub-failover.sh
chmod +x ~/fleet/automations/mac/tools/hub-failover/hub-failover.sh
echo "every 1m" > ~/fleet/automations/mac/tools/hub-failover/cadence
```

Running sessions keep their old setting; only new ones switch. "Own logins" needs each machine
to still have a working Claude and Codex login of its own.

## Request log archive

[`cliproxy-log-archive`](cliproxy-log-archive) runs daily from
[`units/cliproxy-log-archive.timer`](units/) (`Persistent=true`). It moves finished request logs
into staging, packs them oldest first into one `tar.zst` (`zstd -19 --long=30`; repeated thread
context collapses well, roughly 4x), verifies every file is inside, uploads to
`s3://<your-bucket>/<prefix>/YYYY/MM/DD/`, checks the size S3 reports, and only then deletes the
local copy. A failure alerts and keeps the data local; the next run retries it first. Use a
private bucket with versioning and default encryption (the same settings as
[agent-history-backup](../agent-history-backup/)); these logs hold every prompt and reply.

## Install

1. Enable `cliproxy` on the worker and the controller (`bin/hub` lands on PATH everywhere; the
   service only matters on the worker).
2. On the worker: build the hub, write `config.yaml`, generate the two keys
   (`openssl rand -hex 32 > ~/.config/cliproxy/access-key`, same for `management-key`,
   `chmod 600`), copy [`units/cliproxyapi.service`](units/) to `~/.config/systemd/user/`,
   `systemctl --user enable --now cliproxyapi`, then the `tailscale serve` line above.
3. Sign in each account through the dashboard.
4. Point each machine's clients at it, then copy the archive units and script if you want logs in S3.

## Health

`check.sh` on the worker: the service is active and `/v1/models` answers 200 with the client key.
Heals by restarting the service. On the controller, `hub status`.
