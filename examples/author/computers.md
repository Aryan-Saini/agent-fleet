# Computers

## Roles

| Device | Role |
| --- | --- |
| laptop | **Controller.** MacBook. Where I work. The only machine that authors config, runs `/fleet-update`, and owns these docs. |
| worker | **Worker.** Arch Linux desktop, headless server, always on, no monitor attached. Runs agents in tmux and T3 Code threads, dev servers, the CLIProxyAPI hub, worker-chrome, Halo screens and the backups. Heals known service failures, reports the rest, never self-initiates deep updates. |
| phone-1, phone-2 | **Remote.** iPhones. Drive both machines through T3 Code (TestFlight) over T3 Connect from anywhere. Nothing syncs to them. |

**Delegation rule:** before the controller acts on the worker, classify whether the work could
sever Tailscale, ssh, systemd, networking, or kernel/reboot reachability. If yes or uncertain,
never stream it over live ssh: send a self-contained work order with verification, reconnect and
report requirements; start it detached; watch for rejoin, and alert me if it misses the window.

**Continuation ladder:** risky work starts with durable state. Scripts carry deterministic work
across the gap and arm boot continuation before a restart; the worker resumes, heals and verifies
by itself; agents enter only at judgment points. If no agent is available, scripts still restore
service and report exactly where a human is needed. State clears only after reconnection is
proven. **Invariant: the worker may lose the current task; it may never stay down or stay silent.**

## Machines

| machine | role | OS | always on | notes |
| --- | --- | --- | --- | --- |
| laptop | controller | macOS | no; woken at 01:58 for the nightly update | T3 Code desktop app (nightly), Cua Driver, Halo app, Sill. sudo by Keychain askpass |
| worker | worker | Arch Linux, stock kernel, server only (about 700 packages after removing the desktop and games) | yes: sleep targets masked, hardware watchdog, `kernel.panic=10` | AMD GPU, 32 GB RAM, 16 threads. CPU boost off and T3 agents capped by systemd slices after hard freezes under load. Passwordless sudo |
| phone-1 | remote | iOS | n/a | T3 Code via TestFlight, push notifications on |
| phone-2 | remote | iOS | n/a | same |

Machines on other people's tailnets, shared into mine, are listed separately with their owner,
and are explicitly **not part of the fleet**: nothing syncs to them. Today that is a cofounder's
Linux box, a shared house Mac used as a test and remote-desktop target, a family laptop, and a
GPU box that runs a team's CI. Devices that are only on the home LAN (a game console) get their
own short section too.

## How they reach each other

- `ssh <worker>` from the laptop, `ssh <laptop>` from the worker. Keys only. Tailscale SSH on
  the worker in `accept` mode; macOS Remote Login on the laptop.
- T3 environment links both ways, renewed weekly. Agents start threads and subagents on the
  other machine through them.
- Files: `to-worker` / `to-controller` (scp into `~/drop`) and T3 attachments. The Syncthing
  drop folder was retired.
- Alerts from the worker: a notification on the laptop and a message to my phone, sent through
  the laptop.
- Dev servers on the worker: loopback only, behind Tailscale Serve HTTPS at port + 10000.
- Model accounts: every Claude Code and Codex session on both machines goes through the hub on
  the worker. The laptop fails over to its own logins after three failed checks.

## Storage on the worker

Full layout and the reasons: [`docs/storage.md`](../../docs/storage.md).

- 125 GB btrfs system partition (`@`, `@home`, `@log`, `@pkg`, zstd), rollback snapshots
  before deep updates.
- 340 GB XFS work volume on LVM VDO (shown as 660 GB) for repos, worktrees, the pnpm store,
  ROCm, the Android SDK and ML envs, bind-mounted at the usual home paths. No bulk data there.
- 2 TB ext4 hard drive for bulk data, nightly rsync snapshots and archives, `nofail`.
- An old NTFS drive with irreplaceable files, mounted **read-only**.
- zram swap.

## Packages

| machine | packages |
| --- | --- |
| laptop | tailscale t3-remote mcp postdraft halo sill cua-driver mac-automations agent-history-backup settings-sync cliproxy |
| worker | tailscale always-on agent-clis t3-remote mcp postdraft os-update cliproxy dev-server worker-chrome halo phoneuse linux-automations agent-history-backup settings-sync |
