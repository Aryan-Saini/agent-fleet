---
name: dev-server
description: Run a web app's dev server on a worker and hand the user a tailnet HTTPS link they can open from their laptop or phone, at home or away. Use whenever they ask to spin up, run, start, serve, stop or check on a web app ("local dev build", "dev server", "let me run it", "let me try it", "pull it up", "I want to click around"), or a dev page hangs on "Loading...", loops on sign-in or won't open from another device. Also when an agent on the controller needs a dev server on a worker. Web apps only, not mobile/Expo/Metro, simulators, tests, production builds or deploys.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "worker-expose and the devserver@ user unit on the worker (you write them, shape below), Tailscale with HTTPS certificates enabled, jq. From the controller, prefix commands with ssh <worker>"
---

# Dev servers on the worker

The user doesn't sit at the worker. They open what you start from the laptop or a phone, over
Tailscale, often away from home. So "run it locally" means **run it on the worker and hand them an
HTTPS tailnet URL**. Never give them `http://localhost:<port>`, the tailnet IP or the LAN IP.
Those hang or break: Next blocks dev assets from other hosts ("Loading..." forever), and over plain
HTTP auth SDKs (Clerk, Auth.js, Supabase) can't use Web Crypto or secure cookies.

On the controller, run every command below as `ssh <worker> '<cmd>'`. On the worker, directly.

## The pieces

You build three small things once. They are worth it: every dev server after that is one command.

| piece | what it does |
| --- | --- |
| `devserver@.service` | systemd user template unit. `ExecStart=devserver %i`, `Restart=always`, `NoNewPrivileges=yes` (blocks direct sudo from npm code; not isolation, use a separate account for untrusted code) |
| `devserver <name>` | sources `~/.config/devservers/<name>.conf` (`DIR`, `PORT`, `CMD`, `KEEP`; mode 600), exports `PORT` and `HOST=127.0.0.1`, `cd "$DIR"`, `exec sh -c "$CMD"`. Set PATH explicitly: units get no profile |
| `worker-expose` | the only interface: `add [--keep] <name> <dir> <port> ['<cmd>']`, `rm <name>`, `ls`, `reap` |

`worker-expose add` writes the conf, enables `devserver@<name>`, waits for the port, then maps it
with `tailscale serve --bg --https=<port+10000> http://localhost:<port>`. The rules it enforces:

- **Loopback only.** After the app listens, check `ss -Hltn "sport = :<port>"`. Anything other than
  `127.x` or `[::1]` means it is reachable from the LAN with no Tailscale auth: stop the unit and
  fail. `ls` flags `EXPOSED` if one later rebinds.
- **HTTPS port is always `<port> + 10000`**, with ports limited to 1-55535, so a dev mapping can
  never land on 443 or another hand-made mapping. `rm` only drops a mapping that proxies to its own
  port.
- **Temporary by default.** A server lives 24 hours from its last `add` (the conf's mtime). An
  hourly `devserver-reap` timer runs `worker-expose reap`. Only `--keep` exempts one.
- Refuse a port another conf already uses, or one something else is listening on.
- Run as the user, never root (`systemctl --user` and `$HOME` would be root's).

Never use Tailscale Funnel here. Serve keeps it on the tailnet.

## Steps

1. **Deps.** `pnpm install --frozen-lockfile` in the checkout (fresh worktrees have no
   `node_modules`).
2. **Env.** A worktree has no `.env.local` (gitignored). Copy it from the main checkout. It points
   at the user's own dev backend; never swap in staging or production values.
3. **Host allowlist.** The dev server must accept `<worker>.<tailnet>.ts.net`:
   Next `allowedDevOrigins`, Vite `server.allowedHosts`. Reading it from an env var
   (`DEV_ORIGINS`, comma-separated) keeps the hostname out of the repo.
4. **Expose it.**
   ```bash
   worker-expose add <repo>-<app> <app dir> <port> 'pnpm dev -H localhost'
   ```
   URL: `https://<worker>.<tailnet>.ts.net:<port + 10000>`. Next needs `-H localhost` (not
   `127.0.0.1`, which breaks its internal rewrites behind the proxy); Vite needs
   `--host localhost`.
5. **Verify before handing over.**
   ```bash
   curl -sL -o /dev/null -w '%{http_code}\n' https://<worker>.<tailnet>.ts.net:<https port>/
   journalctl --user -u devserver@<name> --since -2min | grep -iE 'blocked|error'
   ```
   200 and no "Blocked cross-origin" lines. Then give them the URL.

## When it breaks

| symptom | cause | fix |
| --- | --- | --- |
| stuck on "Loading...", log says "Blocked cross-origin" | host not in the allowlist | step 3, then `rm` and `add` again |
| sign-in reload loop, auth SDK logs `secure-context: false` | opened over plain HTTP | use the HTTPS URL |
| 502 from the HTTPS URL | app not listening yet, or bound to `127.0.0.1` only | `-H localhost`; check `journalctl` |
| `add` refuses | app listens on `0.0.0.0` or a LAN address | pass the localhost flag in the command |
| a redirect (payment checkout, an emailed link) lands on `localhost:<port>` | the dev backend builds links from an app-URL env var still set to localhost | set that var to the HTTPS URL on the **dev** deployment only, and tell the user |
| app only works on `http://localhost` (OAuth client registered for it) | | from the controller: `ssh -N -L <port>:localhost:<port> <worker>`, open `http://localhost:<port>` |

## Close it

Run `worker-expose rm <name>` as soon as the PR it serves merges or closes, the task is finished,
the user says they're done, or its worktree is about to be removed (a server whose directory is
gone crash-loops until the start limit stops it). Mention the `rm` in your handback. Don't leave
one running in case they want it later; `add` brings it back in seconds.

`--keep` is for infrastructure other tools depend on (a phone mirror page, a remote-desktop
viewer). Never for an app you are showing the user unless they ask.

## Manage

- `worker-expose ls`: name, state, time left (or `keep`), URL, directory. Check it before picking
  a port.
- Don't start dev servers as plain background shells for the user: they die with the session and
  listen only where the agent is.
- Record the units and scripts in the fleet repo (`automations/<worker>/`) and the reap timer in
  `automations/README.md`.
