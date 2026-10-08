# os-update

Operating system upgrades on a worker you are not sitting next to. The upgrade itself is easy.
The risk is the part where it replaces ssh, the network stack or the kernel underneath the
session that started it, and the box never comes back.

So an OS upgrade is never streamed over a live ssh session. It runs as a work order:

```bash
ssh worker 'fleet workorder start os-update ~/fleet/packages/os-update/arch.sh'
# disconnect. Go to class. The phone buzzes when it is done, or when a human is needed.
```

## The continuation ladder

Each rung covers the failure of the one above it.

1. **Durable state first.** Before anything changes, the order is written to disk.
2. **Scripts carry the deterministic work** across the gap: the upgrade, the reboot, and the
   continuation armed before the reboot. `fleet workorder reboot` refuses to reboot unless boot
   continuation is installed and lingering is on.
3. **The worker resumes, heals and verifies by itself** after boot: `fleet health --probe`, then
   ssh to the controller to prove it can be reached.
4. **It always reports**: a report in `~/drop`, and an alert. State clears only after rejoin is
   proven, so a half-verified run comes back around on the next boot instead of going silent.
5. **Agents enter only at judgment points.** If no agent is available, the scripts still restore
   service and say exactly where a human is needed.

Invariant: **the worker may lose the current task; it may never stay down or stay silent.**

## Safety rules

- Run reboot-class work only when someone can physically reach the box, or at least when the
  controller is on the same LAN. Wake-on-LAN does not cross the internet and cannot fix a failed
  boot. Check for a real LAN address; a working Tailscale route proves nothing here.
- Take a rollback target first when the filesystem allows it (`arch.sh` snapshots btrfs `@`).
- Keyring before packages on Arch. Abort on file conflicts rather than `--overwrite` blindly.
- AUR, Flatpak and agent CLIs are best effort and reported per item. None of them may block the
  reboot that keeps the box reachable.
- Reboot only when needed: the running kernel's modules are gone, or the distro says so.
- Agent-facing services (T3, MCP servers) update from the controller, not inside the OS order.

## Reference implementations

| file | for |
| --- | --- |
| `arch.sh` | Arch Linux: pacman, paru, flatpak, btrfs snapshot |
| `debian.sh` | Debian and Ubuntu: apt full-upgrade |

Other OSes: copy one, keep the `run` / `resume` contract and the `put KEY VALUE` facts, swap the
package manager. macOS release upgrades and Windows feature updates need a human at the
keyboard at least once; have the order prepare and report, and leave the click to you.

## Health

No `check.sh`. An order that fails or is interrupted reports itself through
`fleet workorder` and its boot continuation.
