# phoneuse

Let agents see and operate a real, unmodified iPhone through the worker.
[lxe/phoneuse](https://github.com/lxe/phoneuse) ([phoneuse.tech](https://phoneuse.tech)) brings
the screen in over AirPlay and sends input out with the worker acting as a Bluetooth mouse and
keyboard (AssistiveTouch on the phone). No jailbreak, no cable. Agents use it through the
`phoneuse` CLI and the skill upstream ships in `skill/`.

Spec only: upstream's README and `ARCHITECTURE.md` are the real docs, and its desktop releases
(Flatpak, Mac app) are the easy path on a machine with a screen. This page covers running it on a
headless Linux worker.

## Pieces on a headless worker

| piece | what |
| --- | --- |
| HID daemon | a root systemd service (`phoneuse-hid`) owning the Bluetooth HID channels, socket under `/run`. Written by upstream's `scripts/install.sh` |
| bluetoothd override | runs bluetoothd with `--noplugin=input,hostname` and a keyboard/mouse device class, so the daemon owns HID. The worker then no longer accepts Bluetooth keyboards or mice of its own |
| mirror side | `phoneuse up`: UxPlay (the AirPlay receiver), a video hub, a frames service and the browser mirror. Run it as a kept [dev-server](../dev-server/) instance: `worker-expose add --keep phoneuse ~/dev/phoneuse 8777 'bin/phoneuse up'` |
| browser mirror | loopback `8777`, published tailnet-only at `https://<worker>.<tailnet>.ts.net:18777`. Watch and drive the phone from any browser |
| UxPlay | advertised over mDNS by avahi. LAN ports TCP 7000, 7001, 7100 and UDP 6000, 6001, 7011 |
| vision models | OCR and a click-target model on the CPU for `phoneuse text`, `find`, `tap-on`, in their own venv |
| MCP server | `bin/phoneuse-mcp` (stdio), optional |
| companion app | the Phone Use iPhone app (App Store, or build `ios/` yourself), paired with `phoneuse app pair`. Required: with no app paired, the AirPlay receiver stays off and every agent action is refused |

## Headless config

Upstream's `phoneuse up` wants a Hyprland session for its mirror window. Without one (or with
`headless = true` in `~/.config/phoneuse/config.toml`) it runs like `phoneuse serve`: everything
but the window. To use the browser mirror through Tailscale, list the proxy's origin:

```toml
headless = true
web_origins = ["https://<worker>.<tailnet>.ts.net:18777"]
```

The page and its WebSocket accept only listed origins and localhost.

## Limits

- **The phone must be home.** AirPlay does not cross Tailscale; the phone has to be on the
  worker's LAN. Bluetooth reaches a few metres from the worker's adapter.
- **Only you can start it.** Screen Mirroring (Control Center) and Bluetooth pairing are taps on
  the phone. Agents can't do either.
- **Push to the companion app** goes through upstream's relay unless you configure your own APNs
  key. Decide whether you're fine with that before pairing.
- No GPU encode on most small workers: decode and re-encode run on the CPU.

## Operate

```bash
phoneuse status                                   # HID, Bluetooth link, mirror
journalctl --user -u devserver@phoneuse -f        # mirror side
journalctl -u phoneuse-hid -f                     # Bluetooth daemon
systemctl --user restart devserver@phoneuse       # restart the mirror side
```

Uninstall: `worker-expose rm phoneuse`, then `sudo scripts/install.sh --uninstall`.

## Updating

Keep any local patch on a branch and rebase it onto upstream nightly from `/fleet-update`:

1. Fetch. If upstream added an outbound host or changed code that runs as root (the HID
   daemon, `install.sh`), stop with REVIEW (exit 3) for a human to read the diff.
2. Rebase, rerun `install.sh` and the venv setup scripts only when they or the root daemon
   changed, restart `devserver@phoneuse`, health-check.
3. On failure, reset to the previous commit and restart.
4. If a phone is mirroring right now, defer the restart to the next run: only you can start
   mirroring again.

## Health

The worker's watchdog restarts `phoneuse-hid` or `devserver@phoneuse` if either stopped, and
alerts if one won't start.
