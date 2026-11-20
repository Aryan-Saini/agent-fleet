# halo

A worker has no screen. Some steps still need a human in front of a browser: a login, a 2FA
prompt, a captcha, an OAuth consent page. Halo puts the worker's screen in a window on the
controller in one command, AnyDesk style. You click through it, close the window, and the agent
carries on with a browser that is now logged in.

```bash
halo                       # bring up whatever is missing on the worker, open the viewer
halo https://site/login    # same, and open that URL in the remote Chrome
halo goto <url>            # open a tab remotely, no viewer
halo shot [out.png]        # PNG of the remote screen, no human needed
halo status                # every link in the chain
halo down                  # close the viewer; the remote session and its logins keep running
halo stop                  # also stop what halo started on the worker
```

The CLI is its own npm package, [`fleet-halo`](https://github.com/Aryan-Saini/fleet-halo)
(formerly `screenshare-tunnel`; `screenshare` still works as an alias). Its README is the full
spec. It ships the `halo` skill, which `fleet link` puts in every harness: screenshot first, and
only ask you to look when the page really needs a human.

With [worker-chrome](../worker-chrome/) on the worker, halo shows that Chrome's screen, so a login
you finish in the viewer is the one your agents use. Without it, halo starts its own Xvfb `:99`
and Chrome. `SCREENSHARE_CHROME=own` forces that even when worker-chrome is up.

## How it works

```
worker:      Xvfb :N  <- draws -  Chrome (persistent profile, CDP on loopback)
               |
               +-- voxl     loopback 69NN  -> tailscale serve https :169NN (browser, 60 fps)
               +-- rustdesk --server, direct IP on 211NN (native client, fallback)
               |   firewall: the RustDesk port dropped on every interface but lo and tailscale0
controller:  Halo.app tab, a browser tab, or the RustDesk client
```

1. **Xvfb** is an X server with no hardware. It gives the worker a framebuffer any X app can draw
   into.
2. **Chrome** draws into it with a persistent `--user-data-dir`, so a login done once through the
   viewer stays logged in for later headless runs.
3. **voxl** ([tembo/voxl](https://github.com/tembo/voxl)) streams the screen as H.264 over a
   WebSocket to any browser tab, with mouse, keyboard, touch, clipboard and file transfer. It
   listens on loopback only; `tailscale serve` publishes it tailnet-only on HTTPS, which browsers
   need before they will decode the stream. Its password is `VOXL_PASSWORD` in
   `~/.screenshare/voxl.env` on the worker (mode 600, generated on first run).
4. **RustDesk** is the fallback and the native-client path. It is configured for direct IP only,
   with rendezvous and relay pointed at `127.0.0.1`, so no public RustDesk server is involved. The
   password is random per worker, generated there at `~/.screenshare/password` and read over ssh
   by the viewer.
5. **The firewall rule** is the security model for RustDesk, which binds every interface. The rule
   lives in tailscale's nft table, which is rebuilt on boot, so `halo` re-adds it on every run.

Everything halo starts runs as transient systemd user units (`screenshare-xvfb`,
`screenshare-chrome`, `screenshare-rustdesk`), so it survives the ssh session dropping. It adopts
an Xvfb, Chrome or voxl that is already running instead of starting a second one.

### voxl vs RustDesk

Measured on the author's worker: one 1600x900 screen, each viewer alone, latency from a marker
drawn on the source to it showing in the viewer.

| | voxl | RustDesk |
| --- | --- | --- |
| 60 Hz animation, loopback | 60 fps, p50 14 ms, p99 16 ms | 16 fps seen (29 sent), p50 130 ms |
| 10 Hz UI updates | p50 13 ms | p50 107 ms |
| 60 Hz over 10 Mbps / 40 ms RTT | 59.6 fps, p50 49 ms | 16 fps, p50 164 ms |
| server CPU, busy / idle | 0.63 / 0.00 cores (x264 on CPU) | 0.21 / 0.10 cores |
| bandwidth, busy | 4.5 Mbps | 2.7 Mbps |

The RustDesk viewer ran under software GL in that test; on a real controller expect about 30 fps.
voxl is the default, RustDesk stays for the native client and as a fallback.

## A pool of screens

One screen is enough for a login. Agents that run several GUI jobs at once want more. The
author's worker keeps a small pool next to worker-chrome's `:90`:

| display | what | voxl | RustDesk |
| --- | --- | --- | --- |
| `:90` | worker-chrome | loopback `6990`, https `:16990` | |
| `:91`-`:94` | pool screens, fixed size, one per agent job | loopback `69N`, https `:169N` | `2119N`, tailnet only |
| `:99` | halo's own Chrome when worker-chrome is off | loopback `6999`, https `:16999` | `21118` |

Each pool screen is three systemd user units: the screen (`Xvfb :N` plus a window manager), and a
voxl and a RustDesk server bound to it with `BindsTo=`, so stopping the screen stops its streams.
A voxl template unit looks like this:

```ini
# ~/.config/systemd/user/screen-voxl@.service   (one per display: screen-voxl@91 ...)
[Unit]
Description=voxl browser stream for screen :%i (tailnet only)
BindsTo=screen@%i.service
After=screen@%i.service

[Service]
Environment=DISPLAY=:%i
EnvironmentFile=%h/.screenshare/voxl.env
ExecStart=%h/.local/bin/voxl --addr=127.0.0.1 --port=69%i --allowed-hosts=<worker>.<tailnet>.ts.net --audio-enabled=false
Restart=always
RestartSec=3

[Install]
WantedBy=screen@%i.service
```

then `tailscale serve --bg --https=169<N> http://127.0.0.1:69<N>` once per screen. Agents skip
the viewer entirely: `curl -u ":$VOXL_PASSWORD" 127.0.0.1:69<N>/screenshot` returns a PNG,
`/record?seconds=10` an MP4, `/wait?idle=300` returns once the screen settles.

## Halo.app on the controller

`SCREENSHARE_VIEWER_URL` replaces the RustDesk viewer with any URL, `{worker}` and `{display}`
filled in. The author points it at Halo.app, a small desktop viewer (Tauri) of his own:

```bash
export SCREENSHARE_VIEWER_URL='halo://open?worker={worker}&display={display}'
```

so `halo` raises the app on that screen's tab. One window, a tab per screen, each switchable
between voxl and RustDesk (RustDesk drawn inside the app). It finds workers by probing tailnet
peers for a small per-worker agent served over `tailscale serve`, which trusts the
`Tailscale-User-Login` header for your own login and refuses everyone else. It syncs the
clipboard both ways, maps Mac editing shortcuts to their Linux equivalents, and keeps Cmd+Q on
the controller. Any app that handles a URL scheme can take its place, and so can a plain
browser tab on the voxl URL.

## Install

Enable it on the controller. `./install.sh` runs `npm i -g fleet-halo` and `fleet link` links the
`halo` skill. Nothing is installed on the worker by the CLI; it drives the worker over ssh. The
worker needs the programs:

| where | what |
| --- | --- |
| worker (Linux) | `rustdesk`, Xvfb (`xorg-server-xvfb` / `xvfb`), Chrome or Chromium, ImageMagick (`import`), `nftables`; optional `voxl` on PATH (`cargo install voxl-server`, or a release build) |
| controller | Node 20+, the RustDesk client (macOS: halo installs it with Homebrew), optional Halo.app or another viewer |
| both | Tailscale, and an ssh alias for the worker |

In the controller's `~/.zshenv` or `~/.profile`:

```bash
export SCREENSHARE_HOST=<worker alias>          # default: worker
# export SCREENSHARE_IP=<worker tailnet ip>     # only if `tailscale ip -4 <alias>` can't resolve it
# export SCREENSHARE_VIEWER_URL='...'           # a custom viewer, see above
```

## Verify

```bash
halo status
nc -z -w 3 <worker-tailnet-ip> 21118   # must connect
nc -z -w 3 <worker-lan-ip> 21118       # must be refused
```

## Updating

`npm i -g fleet-halo@latest` on the controller. On the worker, update voxl from its newest release
tag, keep the previous binary, and roll back if a voxl unit fails to answer after the swap. voxl
links the system's x264 and libyuv, so rebuild it when an OS upgrade bumps either library.

## Gotchas

- **RustDesk overwrites its own config while running.** Edit it only while the process is stopped.
- **The firewall rule disappears on boot.** Running `halo` re-adds it.
- **Black viewer:** the server is capturing another display. `halo` restarts it onto the right one.
- **Password rejected:** delete `~/.screenshare/password` on the worker and run `halo` again.
- **voxl shows nothing over plain http.** Browsers only decode it in a secure context. Use the
  `tailscale serve` HTTPS URL and list that hostname in `--allowed-hosts`.
- **Don't resize pool screens to fit a window.** Agents depend on a fixed size.
- Not Linux? The chain works anywhere you can run a virtual display and a streaming server. Port
  the remote half and keep the command names.

The other direction, your controller's screen on your phone, is [sill](../sill/).
