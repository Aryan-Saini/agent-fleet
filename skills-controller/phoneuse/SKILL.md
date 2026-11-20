---
name: phoneuse
description: See and operate the user's real phone (iPhone) through the worker with the `phoneuse` CLI, AirPlay mirror in, Bluetooth mouse and keyboard out. Use when a task needs the phone itself, such as opening or using an app, reading what is on the phone screen, tapping, typing, swiping, checking a notification, changing a phone setting, or testing an app on the device, or when the mirror or the Bluetooth link needs starting or fixing.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: controller
  requires: "phoneuse installed on a Linux worker with Bluetooth and on the same LAN as the phone; an ssh alias for the worker; the phone paired over Bluetooth and within a few metres of the worker"
---

# phoneuse

[phoneuse](https://github.com/lxe/phoneuse) by lxe lets an agent see and operate an unmodified
iPhone. The screen comes in over AirPlay (UxPlay on the worker), and input goes out with the
worker acting as a Bluetooth mouse and keyboard (AssistiveTouch on the phone). Nothing is
jailbroken. Credit and the full upstream guide go to lxe; this skill is how to run it on a
headless worker and drive it from the controller.

**Where to run it.** On the worker: `phoneuse ...` directly. Anywhere else:
`ssh <worker> 'phoneuse ...'`.

## Setting it up on a headless worker

Upstream's `phoneuse up` wants a desktop for its mirror window. On a worker with no display, keep
a small local branch that makes `up` behave like `serve` (no mirror window, no desktop mouse
handler), and allow the tailnet HTTPS origin for the browser mirror page. Rebase it onto upstream
on every update.

| piece | what |
| --- | --- |
| HID daemon | system unit, **runs as root**, owns the Bluetooth HID channels. bluetoothd runs with `--noplugin=input,...` so the daemon gets them, which means the worker stops accepting Bluetooth keyboards and mice of its own |
| mirror service | `phoneuse up` (UxPlay, frames, browser mirror) as a user unit. The **dev-server** skill's `worker-expose add --keep phoneuse ...` gives it restart, boot start and a tailnet HTTPS URL |
| UxPlay | the AirPlay receiver, advertised by avahi. LAN ports only |
| vision | OCR plus a grounding model on the CPU for `text`, `find`, `tap-on` |
| companion app | recent upstream versions require a paired iOS companion app (built from the repo's `ios/`). Its pushes go through the author's relay unless you configure your own APNs key; decide which you accept |

Limits: **the phone must be home.** AirPlay does not cross Tailscale, and Bluetooth reaches a few
metres. Only the user can start Screen Mirroring and pair Bluetooth.

## Before acting

1. `phoneuse status`. You need the HID service active, `connected=True`, and the mirror showing
   the phone.
2. Not mirroring: ask the user to open Control Center, Screen Mirroring, **PhoneUse** on the
   phone. Every input command refuses until it runs.
3. `connected=False`: wait a few seconds (the daemon reconnects), then check again. Still down: ask
   them to tap PhoneUse in the phone's Bluetooth settings.
4. Show them the phone once per task: `https://<worker>.<tailnet>.ts.net:<mirror https port>`. Act
   through `phoneuse`, never by clicking in that page. Their **Take over** button there makes your
   next command fail with a stop message: stop and wait.

## The loop

Look, decide, act, look again. Read with text first: a few hundred tokens against ~1,300 for an
image.

```bash
phoneuse text                  # every text line: "x y  text", plus [switch on/off], [back]
phoneuse tap-on "Wi-Fi"        # tap a text label (exact, from OCR)
phoneuse tap-on "gear icon"    # something visual (grounding model; check the result)
phoneuse tap 0.5 0.35 --text   # any action + --text: act, wait for the screen to settle, read it
phoneuse open Settings | home | back | scroll down | type "hello" | key cmd+space
phoneuse done                  # end the session and hand control back
```

Coordinates are fractions (0..1) of the screen. `phoneuse --help` lists every command. Read the
upstream `skill/SKILL.md` and `docs/RECIPES.md` in the checkout before anything beyond simple taps.

An image, from the controller:
`ssh <worker> 'phoneuse screenshot /tmp/p.png' && scp <worker>:/tmp/p.png /tmp/p.png`.

## Rules

- Never type into the lock screen. `phoneuse unlock` asks the user to approve on the page; the
  passcode is theirs to save there, never yours to know.
- Never tap the middle of the status bar: the Dynamic Island opens the Stop Mirroring popup.
- Messages, purchases, deletions, posts and hard-to-undo settings: confirm with the user before the
  final tap.
- Run `phoneuse done` when finished.

## Updates

The daemon runs as root and the tool can see and drive the phone, so its updater gets the
`fleet-update` leak guard: rebase the local branch, and stop for review (exit 3) when upstream
adds an outbound host or changes code that runs as root. Approve only if it stays local
(Bluetooth, the phone, loopback). Never restart the mirror while a phone is mirroring, since only
the user can start it again; defer to the next run.
