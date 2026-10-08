# mcp

MCP servers that work on every machine and in every harness, without logging into each one, and
without loading every server into every conversation.

## Three layers, kept apart

This split is the whole design. Blur it and you are back to per-machine logins and leaked keys.

| layer | lives in | scope | committed |
| --- | --- | --- | --- |
| **keys** | `~/.config/agent-secrets.env` (mode 600), loaded by your shell and by the service manager | per machine | never |
| **definitions** | `<repo>/.mcp.json`, `<repo>/.cursor/mcp.json` | per project | yes |
| **trust** | each harness's own per-project approval | per project, per machine | never |

Config files reference `${LINEAR_API_KEY}`, never the literal key, so they are safe to commit.
Definitions are per project so a server only loads where it is useful, not in every chat.

Keyless local servers (`chrome-devtools`, `playwright`) are the exception: they are global in
every harness, because they cost nothing and need no key.

## Install the keyless servers once, don't fetch them per launch

```bash
npm i -g chrome-devtools-mcp @playwright/mcp
```

Then point every harness at `mcp-server-launch chrome-devtools` / `mcp-server-launch playwright`
(this package's `bin/`). `npx -y pkg@latest` re-resolves against the registry on every spawn:
seconds per start, and a hard timeout whenever the network is slow or the machine just woke.
The shim also finds `node` itself, because a harness launched from a dock or app menu has no node
on its PATH.

On a headless worker add `--headless` (and `--browser chromium` for playwright).

## Keys reach every way an agent can start

| started from | reads | fix |
| --- | --- | --- |
| an interactive shell | `.zshrc` | fine |
| `ssh worker '<agent>'` | `.zshenv` only (zsh), `.profile` only for some shells | source the env file from `.zshenv` |
| a GUI app (macOS dock, Spotlight, IDE) | launchd's environment | a login LaunchAgent that runs `launchctl setenv` for each key |
| a systemd service (T3 backend, timers) | nothing from your profile | `systemctl --user set-environment` before the service starts, or `EnvironmentFile=` |

The tell for a missing key: **every keyed server across unrelated providers fails at the same
moment** with `invalid_token`. Real expiry never does that.

## Rotating a key

Edit `~/.config/agent-secrets.env` on each machine, reload it into the GUI session or service
manager, restart long-running services. No repo changes, which is the point.

## Gotchas

- **Trust is the real gate.** In Claude Code an untrusted project silently ignores the repo's
  enabled-server list. Servers show "pending approval" until you accept the trust prompt once on
  that machine.
- **Local scope shadows project scope.** A stale server entry in `~/.claude.json` under the
  project path wins over the repo's `.mcp.json`.
- **Paths are resolved.** macOS `/tmp` is `/private/tmp`; per-project config keyed by the logical
  path is never read. Use `pwd -P`.
- **Claude Code walks up parent directories** for `.mcp.json`. A server you did not add may come
  from one level up.
- **Checkout paths and remotes differ per machine** (ssh vs https URLs, `~/code/x` vs `~/dev/x`).
  Anything matching a repo across machines must normalize the remote to `host/owner/repo`.
- Codex has no per-project MCP scoping. Define keyed servers with `enabled = false` and flip them
  on when needed.
