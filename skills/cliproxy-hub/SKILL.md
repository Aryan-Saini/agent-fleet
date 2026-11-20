---
name: cliproxy-hub
description: The user's Claude and Codex accounts, all signed into one CLIProxyAPI hub on the worker that every Claude Code and Codex on every machine routes through. Use when they ask how many accounts there are, which one is in use, how much of a limit is used, when the 5h or weekly limits reset, whether there are banked resets, to spend a reset, to add, remove or reorder an account, when Claude Code or Codex hits a usage limit, or when the worker is down and sessions can't reach the model.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "CLIProxyAPI running on the worker behind tailscale serve; an ssh alias for the worker; the hub's client key at ~/.config/cliproxy/access-key (mode 600) on each machine; `hub` on the controller"
---

# CLIProxyAPI hub

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (router-for-me) is a local proxy that
speaks the Anthropic and OpenAI APIs and forwards to subscription accounts you sign in to it. The
author's setup follows [Theo's guide](https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af):
every account signs in **once, on the worker**, and Claude Code and Codex on each machine talk to
the hub instead of logging in themselves.

**Read the providers' terms first.** Pooling several subscription accounts behind one proxy and
switching between them when one hits a limit may conflict with Anthropic's or OpenAI's terms of
service. This skill documents how the author does it. Whether you should is your call.

Install, units, the `hub` failover script and the log archiver: `packages/cliproxy` in the fleet
repo. This skill is the operating manual.

Why one hub: one place to add or bench an account, one residential IP that every account's
traffic comes from, a request log of every call, and automatic fallback when an account hits a
limit.

## Layout

| | |
| --- | --- |
| URL | `https://<worker>.<tailnet>.ts.net:8317`. The hub binds `127.0.0.1:8317`; `tailscale serve` adds HTTPS, tailnet only |
| dashboard | `<URL>/management.html`, behind a separate management key |
| service | a user unit with `Restart=always`, copy in `automations/<worker>/units/` |
| accounts | `~/.cli-proxy-api/*.json` on the worker, one OAuth login per account. `"disabled": true` benches one |
| keys | `~/.config/cliproxy/access-key` (clients send it) and `management-key` (dashboard). Mode 600, never committed |

Clients: Claude Code gets `env.ANTHROPIC_BASE_URL=<URL>` and `"apiKeyHelper": "cat
~/.config/cliproxy/access-key"` in `~/.claude/settings.json`. Codex gets a `cliproxy` model provider
in `~/.codex/config.toml` and `model_provider = "cliproxy"`.

Config worth setting:

- `routing.strategy: fill-first`, `session-affinity: false`. One account carries everything until
  it hits a limit, then the next by `priority` (higher first, ties by file name). Traffic returns
  to the default once it resets. No load balancing.
- Turn off what phones home: panel auto-update, remote model catalogs (`-local-model`), the plugin
  store. Audit the outbound hosts in the source once, and diff them on every update (the
  `fleet-update` skill's leak guard).
- `request-log: true` if you want every call on disk. Auth headers are masked. The hub never
  deletes logs, so archive them on a timer (compress with a long zstd window, upload, verify, then
  delete) or set a size cap.

Building from your own fork, on top of upstream's newest release tag, lets you strip things like
affiliate banners from the panel and gives the updater a place to roll back to.

## Limits and resets

Write a small `hub-usage` script on the worker that reads the OAuth tokens in
`~/.cli-proxy-api/` and prints, per account: 5h and weekly use, when each resets, any banked
resets, and `*` on each provider's default. `--json` for agents.

```bash
ssh <worker> hub-usage
ssh <worker> hub-usage default <account>    # that account to priority 100, the rest of its provider to 0
```

The hub reloads account files on change; no restart. The user also changes order in the dashboard
(Auth Files, gear, Priority, or the Enabled switch). Don't change the default unless they ask.

**Banked resets** (some plans grant one-off limit resets) are spent for good. Spend one without
asking only when the user asked you to keep work going and **every** account of that provider is
at its limit. Pick the account whose reset is furthest away, earliest-expiring credit first, and
report what you spent. Never when another account still has room.

## When the worker is down: controller failover

Every session on the controller depends on the hub. Keep a `hub` command there:

```bash
hub status   # which way this machine points, and whether the hub answers
hub off      # point new sessions at this machine's own logins
hub on       # back through the hub; refuses while the hub doesn't answer (--force skips that)
hub tick     # one automatic check
```

`off` removes `ANTHROPIC_BASE_URL` and `apiKeyHelper` from Claude's settings and comments out the
`model_provider` line in Codex's config, backing both up first. While off there is no call
logging and no account fallback. Running sessions keep their old setting; start new ones. A shell
started inside a Claude Code session inherits `ANTHROPIC_BASE_URL`, so test from a fresh terminal.

An every-minute automation runs `hub tick`: three failed probes of `<URL>/v1/models` in a row
switch it off, two good ones switch it back, each with a notification. It only switches back what
it switched off itself, so a manual `hub off` stays off until a manual `hub on`. Send the key to
curl on stdin, never in argv.

On the worker, the health watchdog restarts a dead hub and alerts when an enabled account's usage
check errors (a dead login) or when every account of a provider is at its limit.

## Adding and removing accounts

Add: dashboard, OAuth Login, in a private browser window signed in as the new account. The OAuth
callbacks land on the worker's localhost, so forward them from the machine with the browser
while logging in:

```bash
ssh -f -N -L 54545:localhost:54545 -L 1455:localhost:1455 <worker>   # Claude, Codex callbacks
```

Codex also supports a headless device login from the hub binary (`-codex-device-login`).

Remove: set `"disabled": true` in its JSON. Delete the file only when the user asks.
