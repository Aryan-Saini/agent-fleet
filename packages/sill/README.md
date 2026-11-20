# sill

[halo](../halo/) puts a worker's screen on the controller. Sill covers the other direction: any
window on a Mac, or the whole desktop, on your iPhone or iPad, driven with touch, a trackpad or a
keyboard. Use it to click through a permission prompt, a login or a stuck app on the controller
while you are away from it.

Free and open source, no account and no server in between. Upstream is
[Saffsanity/sill](https://github.com/Saffsanity/sill) ([getsill.app](https://getsill.app)); the
author keeps a fork at [Aryan-Saini/sill](https://github.com/Aryan-Saini/sill) for his own iOS
signing.

## Install

| where | what |
| --- | --- |
| each Mac you want to reach | `brew install --cask saffsanity/sill/sill`, then grant Screen Recording, Accessibility and Local Network |
| iPhone or iPad | the free [Sill app](https://apps.apple.com/app/id6816359860) |
| both | Tailscale, for Remote Access away from home |

Pair once on the same network by scanning the Mac's code. Then turn on **Remote Access** in Sill
on the Mac and connect once more from home, so the phone learns the tailnet route. After that it
reaches the Mac from anywhere over Tailscale.

## Verify

From the phone on cellular, with Wi-Fi off: open Sill, pick the Mac, and see a window.

## Health

`check.sh`, on any Mac with `/Applications/Sill.app`: Sill is running. A quit Sill means no way
in while you are away. Heals by clearing quarantine and relaunching it in the background.
`fleet health` runs it; on a Mac outside the fleet (a shared family or office Mac), the same
three lines as a frequent tool in the [mac-automations](../mac-automations/) dispatcher do the
job:

```bash
pgrep -x Sill >/dev/null || { open -ga /Applications/Sill.app && echo "started Sill"; }
```

## Updating

Don't let a generic `brew upgrade --cask` touch it. An upgrade quits Sill and nothing reopens it,
and a quarantined first launch waits on a prompt nobody can click behind a locked screen. Upgrade
it on its own:

```bash
was_running=$(pgrep -x Sill >/dev/null && echo 1)
brew upgrade --cask --greedy saffsanity/sill/sill
xattr -dr com.apple.quarantine /Applications/Sill.app
[ -n "$was_running" ] && open -g /Applications/Sill.app
```

If you keep a fork, rebase your branch onto upstream in the same step and abort on a conflict
instead of guessing.
