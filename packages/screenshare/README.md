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

## Sill: your Mac's screen on your phone

`screenshare` puts a worker's screen on the controller. [Sill](https://getsill.app) covers the
other direction: any window on a Mac, or the whole desktop, on your iPhone or iPad, driven with
touch, a trackpad or a keyboard. I use it to click through a permission prompt, a login or a
stuck app on the controller while I'm away from it. Free, open source
([Saffsanity/sill](https://github.com/Saffsanity/sill)), no account and no server in between.

| where | what |
| --- | --- |
| each Mac you want to reach | `brew install --cask saffsanity/sill/sill`, then grant Screen Recording, Accessibility and Local Network |
| iPhone or iPad | the free [Sill app](https://apps.apple.com/app/id6816359860) |
| both | Tailscale, for Remote Access away from home |

Pair once on the same network by scanning the Mac's code. Then turn on **Remote Access** in Sill
on the Mac and connect once more from home, so the phone learns the tailnet route. After that it
reaches the Mac from anywhere over Tailscale.

- **Sill must stay running.** It is a menu bar app, and a quit Sill means no way in while you are
  away. `check.sh` relaunches it on any Mac that has it installed, and `fleet health` runs that.
- **Upgrades quit it.** After `brew upgrade --cask saffsanity/sill/sill`, clear quarantine and
  relaunch: `xattr -dr com.apple.quarantine /Applications/Sill.app && open -g /Applications/Sill.app`.
  A quarantined first launch waits on a prompt nobody can click behind a locked screen.
