# screenshare

A worker has no screen. Some steps still need a human in front of a browser: a login, a 2FA
prompt, a captcha, an OAuth consent page. `screenshare` puts the worker's browser in a window on
the controller in one command. You click through it, close the window, and the agent carries on
with a browser that is now logged in.

```bash
screenshare                       # bring it all up, open the viewer
screenshare https://site/login    # same, and open that URL on the worker
screenshare shot                  # PNG of the remote screen, no human needed
```

With [worker-chrome](../worker-chrome/) on the worker, the viewer shows that Chrome, so a login
you finish there is the one your agents use.

The tool is its own npm package, [`screenshare-tunnel`](https://github.com/Aryan-Saini/screenshare-tunnel).
Its README is the full spec: how the Xvfb, Chrome and RustDesk chain works, the firewall rule
that keeps it on the tailnet, and the gotchas.

## Install

Enable it on the controller. `./install.sh` runs `npm i -g screenshare-tunnel`, which puts
`screenshare` on PATH, and `fleet link` links the `screenshare-tunnel` skill it ships.

| where | what |
| --- | --- |
| worker (Linux) | `rustdesk`, `xorg-server-xvfb` / `xvfb`, Chrome or Chromium, ImageMagick (`import`), `nftables` |
| controller | Node 20+, and the RustDesk client (macOS: `screenshare` installs it with Homebrew on first run) |
| both | Tailscale, and an ssh alias for the worker |

Export `SCREENSHARE_HOST=<worker alias>` in the controller's `~/.zshenv` or `~/.profile` (default `worker`).

## Verify

```bash
screenshare status
nc -z -w 3 <worker-tailnet-ip> 21118   # must connect
nc -z -w 3 <worker-lan-ip> 21118       # must be refused
```

## Updating

`npm i -g screenshare-tunnel@latest` on the controller. Nothing is installed on the worker.
