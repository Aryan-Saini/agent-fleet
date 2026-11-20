# mcp

MCP servers that work on every machine and in every harness, without logging into each one, and
without loading every server into every conversation. The short version: **keys are global,
definitions are per project, trust is per machine.**

| I want to | do this |
| --- | --- |
| add the keyed servers to a project | `mcp-optin` in the repo, commit the three files it writes |
| add just one | `mcp-optin --only linear` |
| use them on another machine | pull there, run `mcp-optin` (or set `MCP_OPTIN_PEER` and it trusts the peer for you) |
| rotate a key | edit `~/.config/agent-secrets.env` everywhere, then `load-agent-secrets` |
| a keyed server says `invalid_token` | check whether the harness was launched from the Dock or a service (below) |

## Three layers, kept apart

This split is the whole design. Blur it and you are back to per-machine logins and leaked keys.

| layer | lives in | scope | committed |
| --- | --- | --- | --- |
| **keys** | `~/.config/agent-secrets.env` (mode 600), sourced by `~/.zshenv`, published to GUI apps and services by `load-agent-secrets` | per machine | never |
| **definitions** | `<repo>/.mcp.json`, `<repo>/.cursor/mcp.json` | per project | yes |
| **preapproval** | `<repo>/.claude/settings.json` (`enabledMcpjsonServers`) | per project | yes |
| **trust** | `~/.claude.json`, `projects[<path>].hasTrustDialogAccepted` | per project, per machine | never |

The key is the same everywhere, so it lives once per machine. Definitions are scoped so keyed
servers only load in projects that use them, not in every chat. Config files reference
`${LINEAR_API_KEY}`, never the literal key, so they are safe to commit.

Keyless local servers (`chrome-devtools`, `playwright`, and [cua-driver](../cua-driver/) on a
Mac) are the exception: every harness gets them globally, because they cost nothing and need no
key.

## Opting a project in

```bash
cd ~/dev/myapp
mcp-optin                  # every server in its list
mcp-optin --only linear    # exactly this list; narrower re-runs remove servers
```

[`bin/mcp-optin`](bin/mcp-optin) writes `.mcp.json`, `.cursor/mcp.json` and
`.claude/settings.json` (only when the parsed JSON changes, so a re-run is no diff), then trusts
the project in `~/.claude.json`. With `MCP_OPTIN_PEER=<ssh alias>` in `machine.env` it finds the
same repo on that machine by normalized git remote and trusts it there too. Its server list is a
small JSON blob at the top; the examples are Linear and PostHog. Add a server there and its key to
`agent-secrets.env` on every machine.

Codex has no per-project MCP scoping. Define keyed servers in `~/.codex/config.toml` with
`bearer_token_env_var = "LINEAR_API_KEY"` and `enabled = false`, and flip them on when needed.

## The keyless servers: installed once, fresh daily

```bash
npm i -g --prefix ~/.npm-global chrome-devtools-mcp @playwright/mcp
```

Point every harness at the shim, [`bin/mcp-server-launch`](bin/mcp-server-launch):

```jsonc
// Claude Code (~/.claude.json, user scope) and Cursor (~/.cursor/mcp.json)
"chrome-devtools": { "command": "<home>/.local/bin/mcp-server-launch", "args": ["chrome-devtools"] }
"playwright":      { "command": "<home>/.local/bin/mcp-server-launch", "args": ["playwright"] }
// Codex (~/.codex/config.toml): command = "<home>/.local/bin/mcp-server-launch", args = ["playwright"]
// opencode (opencode.jsonc, synced between machines): "command": ["mcp-server-launch", "playwright"]
```

Absolute paths everywhere except a config file that syncs between machines with different home
directories; there use the bare name and make sure `~/.local/bin` is on PATH.

Why not `npx -y <pkg>@latest`: it hits the registry on every spawn, seconds per start, and a hard
`CONNECT_TIMEOUT` whenever the network is slow or the machine just woke. The tell is both servers
timing out at the same timestamp. Installed globally, startup is about a tenth of a second. The
shim also finds `node` itself, because a harness launched from the Dock has no node on its PATH.

**On a worker they attach to [worker-chrome](../worker-chrome/).** When `127.0.0.1:9230` answers,
the shim ignores whatever flags the harness passed and starts chrome-devtools with
`--browser-url` and playwright with `--cdp-endpoint` against that real, logged-in Chrome instead
of a headless Chromium that sites flag. One rule in the shim covers every harness.
`WORKER_CHROME=off` opts out. Without worker-chrome, pass `--headless` (and
`--browser chromium` for playwright) on a box with no display.

**Workers refresh themselves.** [`bin/mcp-update`](bin/mcp-update) runs daily from
[`units/mcp-update.timer`](units/) (`Persistent=true`): `npm install -g ...@latest`, then it
proves the shim still starts with a bare PATH. It never rolls back and never alerts; a failure
just means it stayed on the version that worked. So a worker never needs the controller awake to
have working servers. `/fleet-update` refreshes the controller.

## Keys reach every way an agent can start

| started from | reads | fix |
| --- | --- | --- |
| an interactive shell | `.zshrc` and `.zshenv` | fine |
| `ssh <worker> '<agent>'` | `.zshenv` only (zsh); nothing for a bare bash | source the env file from `.zshenv`, or a login-shell wrapper that sources it |
| a GUI app (Dock, Spotlight, IDE) | launchd's environment | `load-agent-secrets` at login: `launchctl setenv` per key ([`units/fleet.agent-secrets.plist`](units/)) |
| a systemd service (T3 backend, timers) | nothing from your profile | `load-agent-secrets` as `agent-secrets.service`, `Before=` the agent service: `systemctl --user set-environment` per key |

[`bin/load-agent-secrets`](bin/load-agent-secrets) reads only plain `export NAME=VALUE` lines and
never evaluates the file. This package's `install.sh` loads the LaunchAgent on macOS and the user
unit on Linux.

## Rotating a key

Edit `~/.config/agent-secrets.env` on the controller, `fleet secrets push <machine>`, run
`load-agent-secrets` on each machine, and restart long-running services
(`systemctl --user restart agent-secrets t3code`). No repo changes, which is the point.

## T3 Code across machines

Each machine's T3 Code serves MCP at its tailnet URL (`https://<machine>.<tailnet>.ts.net/mcp`),
and Claude Code on the other machine is signed in to it at user scope (`t3-<worker>` on the
controller, `t3-<controller>` on the worker). An agent on one machine can then list projects and
launch threads on the other, running with that machine's own logins and showing up on your phone.
The sign-in lasts 30 days with no refresh; [t3-remote](../t3-remote/) covers renewing it.

## Gotchas

Each of these looks like "MCP is broken".

- **A GUI-launched harness has no keys.** `.zshenv` reaches shells, not the Dock. Every keyed
  server across unrelated providers fails with `invalid_token` at the same instant, which real
  expiry never does. The same repo works from `claude` in a terminal. Check
  `launchctl getenv LINEAR_API_KEY`; empty means run `load-agent-secrets`.
- **systemd doesn't read `.zshenv` either.** Agents started from your phone through a T3 backend
  running as a service send an empty bearer token while the same repo over ssh works. Check the
  service's own environment:
  `tr '\0' '\n' < /proc/$(systemctl --user show -p MainPID --value t3code.service)/environ | grep _API_KEY`.
  `set-environment` reaches only units started after it, so restart the service.
- **`~/.local/bin` missing from the non-interactive PATH.** Agents over ssh and from systemd are
  not login shells; `claude` and `mcp-server-launch` resolve interactively and vanish otherwise.
- **Trust is the real gate.** Until `hasTrustDialogAccepted` is true, Claude Code strips
  `enabledMcpjsonServers` on every run and servers show "Pending approval".
- **Local scope shadows project scope.** A stale `projects[<path>].mcpServers` entry in
  `~/.claude.json` wins over the repo's `.mcp.json`, and you keep getting OAuth prompts.
- **`~/.claude.json` is keyed by the resolved path.** macOS `/tmp` is `/private/tmp`. Use `pwd -P`.
- **Remotes and checkout paths differ per machine** (ssh vs https, `~/Desktop/x` vs `~/dev/x`).
  Match repos across machines by remote normalized to `host/owner/repo`, never by path.
- **Claude Code walks up parent directories** for `.mcp.json`. A server you didn't add may come
  from one level up.
- **Per-machine config files don't sync.** If `~/.codex/config.toml` or `~/.cursor/mcp.json` is
  gitignored in your dot-repo, fix it on each machine or carry it in your fleet repo.

## Troubleshooting

| symptom | cause |
| --- | --- |
| "Pending approval" | project untrusted on this machine: `mcp-optin` |
| server missing | repo not opted in, or files not pulled |
| `401` / `invalid_token` on every keyed server | key missing from this launch path's environment |
| works in a terminal, fails in the app | GUI session has no keys: `load-agent-secrets` |
| works over ssh, fails from the phone | the service has no keys: restart `agent-secrets` then the service |
| works interactively, fails over ssh | keys in `.zshrc` instead of `.zshenv` |
| chrome-devtools and playwright time out together | back on `npx @latest`, or the global install is missing |
| committed config ignored | local-scope entry in `~/.claude.json` |
