# Computers

## Roles

| Device | Role |
| --- | --- |
| laptop | **Controller.** MacBook. Where I work. Authors every config change, runs `/fleet-update`, owns these docs. |
| worker | **Worker.** Arch Linux desktop, headless, always on. Runs agents in tmux and T3 Code for the phones. Heals known service failures, reports the rest, never self-initiates deep updates. |
| phone-1, phone-2 | **Remote.** iPhones. Drive both machines through T3 Connect from anywhere. Nothing syncs to them. |

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
| laptop | controller | macOS | no | runs the T3 desktop app, Peekaboo, Codex Computer Use |
| worker | worker | Arch Linux, linux-zen | yes, sleep targets masked, BIOS restore-on-AC | AMD GPU, 32 GB RAM. 125 GB system partition, a separate XFS work volume for repos and ML envs, a 2 TB HDD for nightly snapshots |
| phone-1 | remote | iOS | n/a | T3 Code via TestFlight |
| phone-2 | remote | iOS | n/a | same |

Machines on other people's tailnets, shared into mine, are listed separately with their owner,
and are explicitly **not part of the fleet**: nothing syncs to them.

## Storage rules on the worker

- Big data (repos, worktrees, the pnpm store, ML environments) goes on the work volume, surfaced
  at the usual home paths by bind mounts so tools never need to know.
- A data drive with irreplaceable files is mounted **read-only**. No agent can write there even
  by mistake.
- The system partition is small. Agents are told never to stage large transfers in `$HOME`.

## Packages

| machine | packages |
| --- | --- |
| laptop | tailscale drop-folder t3-remote peekaboo mcp screenshare |
| worker | tailscale drop-folder always-on agent-clis t3-remote mcp os-update |

## Drop folder

The laptop's screenshot folder is the shared folder, and `~/drop` points at it on both machines.
Every screenshot I take is on the worker about 20 seconds later, so "look at ~/drop/Shot-0412.png"
works from my phone.
