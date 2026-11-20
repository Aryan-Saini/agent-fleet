# tailscale

One private network for every machine. Each machine is reachable by name from anywhere, phone
included, with no port forwarding and no public ports. ssh, dev servers, the hub, screens and
T3 Code all ride on it.

## Install

| OS | |
| --- | --- |
| Arch | `sudo pacman -S tailscale && sudo systemctl enable --now tailscaled` |
| Debian / Ubuntu / Fedora | `curl -fsSL https://tailscale.com/install.sh \| sh` |
| macOS, a Mac you sit at | the standalone app from tailscale.com, or the App Store app |
| macOS, a Mac others reach over Tailscale SSH | the Homebrew formula (`brew install tailscale`), pinned. See below |
| Windows | the installer from tailscale.com |
| iOS / Android | the app |

Then on each machine: `sudo tailscale up --ssh` (Linux) or sign in through the app. Use the same
account everywhere.

In the admin console:

1. **Disable key expiry** on every always-on machine, or it falls off the network after 180 days
   with no warning. Tagged machines (below) have expiry off by default.
2. Turn on **MagicDNS** so `ssh worker` works by name.
3. Turn on **HTTPS certificates**, for `tailscale serve`. Every name you get a cert for is
   published in public Certificate Transparency logs, permanently. Name machines accordingly.

### macOS: the Homebrew formula, pinned

Only the open-source `tailscaled` (the Homebrew formula) can be a Tailscale SSH *server* on macOS;
the app variants can't. Its Screen Recording, Accessibility and Full Disk Access grants are tied to
the versioned path `/opt/homebrew/Cellar/tailscale/<version>/bin/tailscaled`, so a casual
`brew upgrade` silently drops all three. Pin it:

```bash
brew pin tailscale
# to upgrade: brew unpin tailscale && brew upgrade tailscale && brew pin tailscale,
# then re-toggle tailscaled in all three Privacy & Security panes
```

On a Mac you sit at, the standalone app updates itself and plain OpenSSH (Remote Login) handles
incoming ssh.

## ssh

`tailscale up --ssh` lets the tailnet identity authorize ssh on Linux, so there are no keys to
juggle. Add an alias per machine on every machine in `~/.ssh/config`:

```
Host worker
    HostName worker          # the MagicDNS name
    User you
```

Workers need an alias for the controller too, so they can send files and alerts back. The
controller (macOS app) takes ssh through plain OpenSSH: System Settings, General, Sharing, Remote
Login, keys only, password auth off.

### The SSH rule in your policy

Tailscale SSH is governed by the `ssh` block of the destination tailnet's policy file. For your own
devices, use `accept`, not `check`:

```json
"ssh": [
  { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"],
    "users": ["autogroup:nonroot", "root"] }
]
```

`check` mode makes `ssh worker` periodically print a browser re-auth URL and wait. Interactively
that is an annoyance; for a script it is a silent hang, and the author's updater stalled on it.

### Tags

A tag makes a machine owned by the tag instead of a person: key expiry off by default, and it can
be an SSH destination for people outside your tailnet. Declare who may apply it:

```json
"tagOwners": { "tag:ssh": ["autogroup:admin"] },
```

then apply it in the console (Machines, the machine, Edit ACL tags) or with
`sudo tailscale up --advertise-tags=tag:ssh`.

## Sharing nodes across tailnets

A friend's or a family member's machine can join your fleet's reach without joining your tailnet.
For you to ssh into their machine, three things on **their** side:

1. **Share the node** to your login (Machines, the machine, Share). It shows as "Shared in" on
   your side and becomes pingable.
2. **Tag it** `tag:ssh`. A user-owned device can't be an SSH destination for someone outside its
   tailnet; a tagged one can.
3. **An SSH accept rule** in their policy: `{"action": "accept", "src": ["<you>@example.com"],
   "dst": ["tag:ssh"], "users": ["<their-user>", "autogroup:nonroot"]}`.

Until all three are in place it fails with `tailnet policy does not permit you to SSH to this
node`. If it breaks later, the tag or the rule changed on their end.

**Filter shared-in nodes out of your tooling.** Sharing is one way: they can't open connections to
your machines, so your `tailscale serve` URLs stay closed to them. But anything that enumerates
peers (a viewer probing for workers, a fan-out update, a status page) will find them. Skip them
explicitly:

```bash
tailscale status --json | jq -r '.Peer[] | select(.ShareeNode != true) | .DNSName'
```

Machines you share *out* are the other way round: the person you share with can reach that
machine, its serve URLs included, unless an app checks who is calling (`tailscale serve` adds a
`Tailscale-User-Login` header an app can match against your own login). Share workers sparingly.

## tailscale serve: HTTPS on the tailnet

`tailscale serve` puts a loopback port behind a real certificate at
`https://<machine>.<tailnet>.ts.net[:port]`, reachable only from your tailnet. That makes it a
secure context, which auth SDKs, cookies, voxl and service workers need. Bind the app to
`127.0.0.1`, never `0.0.0.0`, and let serve do the rest:

```bash
sudo tailscale set --operator=$USER                         # once, so your user can run serve
tailscale serve --bg --https=8317 http://127.0.0.1:8317     # one mapping per port
tailscale serve status
tailscale serve --https=8317 off
```

Conventions that keep mappings from colliding: `443` (the root path) for T3 Code
([t3-remote](../t3-remote/)), `<port>+10000` for dev servers ([dev-server](../dev-server/)),
`169NN` for screens ([halo](../halo/)), `8317` for the hub ([cliproxy](../cliproxy/)). Never remap
the root path of an existing config; add a port.

**Funnel stays off.** `tailscale funnel` publishes a port to the whole internet. Check
`tailscale funnel status` shows nothing, and leave the `funnel` node attribute out of your policy
so it can't be turned on by accident.

## Verify

```bash
tailscale status             # every machine listed, none "offline"
ssh worker true && echo ok   # from the controller, no browser prompt
tailscale serve status       # the mappings you expect, nothing else
```

## Health

`check.sh` fails when tailscale is not connected and heals by bringing it up.

## Gotchas

- **`ssh worker` times out but `tailscale ping worker` answers.** The client didn't install its
  route for `100.64.0.0/10`, so traffic leaks out the LAN interface. On macOS check
  `route -n get <worker-ip>`; `interface: en0` is bad, `utun*` is good. Restart Tailscale. On
  macOS the CLI cannot start the app again after `tailscale down`: use `open -a Tailscale`.
  Reaching the peer over its tailnet IPv6 address often works when the IPv4 route is missing.
- **"REMOTE HOST IDENTIFICATION HAS CHANGED"** after a reinstall: `ssh-keygen -R <name>`.
- **A server bound to 127.0.0.1 is invisible to the tailnet.** Use `tailscale serve`, or tunnel
  with `ssh -L`. See `docs/communicate.md`.
- **`tailscale serve` fails without root** until you set yourself as operator.
- Keep a LAN fallback (`ssh you@<lan-ip>`) written in the machine's README for the day the
  tailnet path breaks.
