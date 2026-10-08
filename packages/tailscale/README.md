# tailscale

One private network for every machine. Each machine is reachable by name from anywhere, phone
included, with no port forwarding and no public ports. ssh, dev servers, databases and the drop
folder all ride on it.

## Install

| OS | |
| --- | --- |
| Arch | `sudo pacman -S tailscale && sudo systemctl enable --now tailscaled` |
| Debian / Ubuntu / Fedora | `curl -fsSL https://tailscale.com/install.sh \| sh` |
| macOS | `brew install --cask tailscale` or the App Store app |
| Windows | the installer from tailscale.com |
| iOS / Android | the app |

Then on each machine: `sudo tailscale up --ssh` (Linux) or sign in through the app. Use the same
account everywhere.

In the admin console:

1. **Disable key expiry** on every always-on machine, or it falls off the network after 180 days
   with no warning.
2. Turn on **MagicDNS** so `ssh worker` works by name.
3. Optional: **HTTPS certificates**, for `tailscale serve`. Every name you get a cert for is
   published in public Certificate Transparency logs, permanently. Name machines accordingly.

## ssh

`tailscale up --ssh` lets the tailnet identity authorize ssh on Linux, so there are no keys to
juggle. Plain OpenSSH with keys works too, and is what macOS uses (System Settings, General,
Sharing, Remote Login). Either way, add an alias per machine on every machine in `~/.ssh/config`:

```
Host worker
    HostName worker          # the MagicDNS name, or its 100.x address
    User you
```

Workers need an alias for the controller too, so they can send files and alerts back.
Password auth off, keys only.

## Verify

```bash
tailscale status             # every machine listed, none "offline"
ssh worker true && echo ok   # from the controller
```

## Health

`check.sh` fails when tailscale is not connected and heals by bringing it up.

## Gotchas

- **`ssh worker` times out but `tailscale ping worker` answers.** The client didn't install its
  route for `100.64.0.0/10`, so traffic leaks out the LAN interface. On macOS check
  `route -n get <worker-ip>`; `interface: en0` is bad, `utun*` is good. Restart Tailscale. On
  macOS the CLI cannot start it again after `tailscale down`: use `open -a Tailscale`.
- **"REMOTE HOST IDENTIFICATION HAS CHANGED"** after a reinstall: `ssh-keygen -R <name>`.
- **A server bound to 127.0.0.1 is invisible to the tailnet.** Bind 0.0.0.0, or tunnel with
  `ssh -L`. See `docs/communicate.md`.
- **`tailscale funnel` exposes a port to the public internet.** Leave it off unless you mean it.
- Keep a LAN fallback (`ssh you@<lan-ip>`) written in the machine's README for the day the
  tailnet path breaks.
