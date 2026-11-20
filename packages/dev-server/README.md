# dev-server

Run a web app's dev server on the worker and open it from the controller or your phone, at home
or away, over a real HTTPS URL on the tailnet. One command to start, one to stop, and every
server cleans itself up after 24 hours.

```bash
ssh <worker> "worker-expose add myapp ~/dev/myapp 3000 'pnpm dev -H localhost'"
#   devserver@myapp: https://<worker>.<tailnet>.ts.net:13000
ssh <worker> 'worker-expose ls'      # name, state, time left, URL, dir
ssh <worker> 'worker-expose rm myapp'
```

## Why HTTPS on the tailnet, and why loopback only

Plain `http://<worker>:3000` works for a static page and fails for real apps. Auth SDKs (Clerk
and friends), secure cookies, service workers and clipboard APIs need a secure context, and a
bare hostname over http isn't one. Apps would sit on "Loading..." or loop on sign-in.

`tailscale serve` gives each server a real certificate at `https://<worker>.<tailnet>.ts.net:<port+10000>`,
reachable only from your tailnet. The dev server itself binds `localhost`, because a typical
worker's firewall accepts LAN traffic: an app on `0.0.0.0` is open to anyone on the home Wi-Fi
(and maybe public IPv6) with no auth at all. That exact hole turned up in the author's own
review, which is why `add` now checks.

## How it works

| piece | what |
| --- | --- |
| [`bin/worker-expose`](bin/worker-expose) | `add`, `rm`, `ls`, `reap`. Writes `~/.config/devservers/<name>.conf` (mode 600, shell-quoted `DIR`, `PORT`, `CMD`, `KEEP`), enables `devserver@<name>`, maps the HTTPS port |
| [`bin/devserver`](bin/devserver) | what the unit runs: sources the conf, exports `PORT` and `HOST=127.0.0.1`, `cd`s, execs `CMD` |
| [`units/devserver@.service`](units/devserver@.service) | template unit, one instance per server, `Restart=always`, `NoNewPrivileges=yes` |
| [`units/devserver-reap.timer`](units/devserver-reap.timer) | hourly, runs `worker-expose reap` |

What `add` enforces:

- **Loopback only.** It waits for the port to listen, then stops the server and fails if
  anything listens beyond `127.0.0.1` or `::1`. `ls` flags `EXPOSED` if one later does.
  Next: `pnpm dev -H localhost` (not `127.0.0.1`, which breaks Next's internal rewrites behind
  the proxy). Vite: `--host localhost`.
- **No root.** It refuses to run as root, and the unit sets `NoNewPrivileges=yes`, so a dev
  dependency can't use passwordless `sudo`.
- **No clobbering.** Ports are 1 to 55535, so HTTPS ports are 10001 and up and never hit `443`
  (where T3 Code lives, see [t3-remote](../t3-remote/)). It refuses a port another server uses, a
  port something else listens on, or an HTTPS port mapped to something else. `rm` only drops a
  mapping that proxies to its own port.
- **Names and dirs are validated**, and `CMD` is stored shell-quoted, so a name or path can't
  inject a command into the conf the unit sources.
- **Temporary by default.** A server lives 24 hours from its last `add` (the conf's mtime);
  `reap` removes it. `--keep` exempts long-lived infra other tools rely on.

Remove a server when its worktree goes away. Otherwise it crash-loops until the start limit stops
it, and `ls` shows `(dir missing)`.

## Install

Enable `dev-server` on workers. `./install.sh` links both scripts into `~/.local/bin` and runs
this package's `install.sh`, which copies the units and enables the reap timer. Needs `tailscale`
(with HTTPS certificates on in the admin console), `jq`, `ss` (iproute2), lingering
([always-on](../always-on/)), and once, by you:

```bash
sudo tailscale set --operator=$USER   # lets your user run tailscale serve
```

`WORKER_EXPOSE_HOST` overrides the hostname if MagicDNS gives the machine a different name.

## Verify

```bash
mkdir -p /tmp/hello && echo hi > /tmp/hello/index.html
worker-expose add hello /tmp/hello 8099 'python3 -m http.server 8099 --bind 127.0.0.1'
curl -s https://<worker>.<tailnet>.ts.net:18099/          # from the controller: hi
curl -s -m 3 http://<worker-lan-ip>:8099/ || echo refused  # must be refused
worker-expose rm hello
```

## Gotchas

- **Host allowlists.** Next needs the hostname in `allowedDevOrigins`, Vite in
  `server.allowedHosts`, or the page loads and HMR or API calls fail.
- **OAuth clients registered for `localhost` only.** Use an ssh tunnel for those instead:
  `ssh -N -o AddressFamily=any -L 127.0.0.1:3000:localhost:3000 <worker>` and open
  `http://localhost:3000`.
- **Never remap `tailscale serve /` on the worker.** The root path belongs to T3 Code. Add ports.
- **`tailscale funnel` would put it on the public internet.** Don't.
- Who reaches the URL: every device in your tailnet, and anyone you share the worker itself with.
  Machines other people share *into* your tailnet can't connect to it. See [tailscale](../tailscale/).
- Logs: `journalctl --user -u devserver@<name> -f`.
