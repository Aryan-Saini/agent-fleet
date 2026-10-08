# Computers

The map of this fleet. Identical on every machine. Agents read it to learn which machine they
are on (`fleet` prints the name) and how to reach the others. Per-machine detail lives in
`machines/<name>/README.md`.

Network: one Tailscale tailnet. Every machine is reachable by name from anywhere, with no port
forwarding. Keep real secrets out of this file. Hostnames and tailnet IPs are fine here only
because this repo is private; never publish it.

## Roles

| Role | Job |
| --- | --- |
| controller | Where the human works and the only machine that authors config. Orchestrates workers and updates. |
| worker | Always on. Runs agents and long jobs in tmux. Heals itself, reports what it can't fix, never self-initiates disruptive work. |
| remote | Phone or tablet. Drives the fleet from anywhere. Nothing syncs to it. |

**Delegation rule.** Before the controller acts on a worker, classify whether the work could
sever the network, ssh, the service manager or the boot. If yes or unsure, never stream it over
a live ssh session: send it as a work order (`fleet workorder start`), disconnect, and wait for
the report. **The worker may lose the current task; it may never stay down or stay silent.**

## Machines

| name | role | OS | tailscale name | ssh | always on | details |
| --- | --- | --- | --- | --- | --- | --- |
| <laptop> | controller | <macOS 26> | <laptop> | `ssh <laptop>` | no | [machines/<laptop>](machines/<laptop>/README.md) |
| <worker> | worker | <Arch Linux> | <worker> | `ssh <worker>` | yes | [machines/<worker>](machines/<worker>/README.md) |
| <phone> | remote | <iOS> | <phone> | none | no | drives via <T3 Connect / an ssh app> |

## How they reach each other

- controller to worker: `ssh <worker>`, files with `fleet send <worker> <file>`
- worker to controller: `ssh <laptop>`, files with `fleet send <laptop> <file>`
- either way, lazily: drop it in `~/drop`, Syncthing carries it in ~15-25s
- a dev server on the other machine: `http://<worker>:3000` (bind it to 0.0.0.0)
- get the human's attention from anywhere: `fleet alert "title" "message"`

## Drop folder

| machine | path | synced with |
| --- | --- | --- |
| <laptop> | `~/drop` (or your screenshot folder, with `~/drop` symlinked to it) | Syncthing |
| <worker> | `~/drop` | Syncthing |

## Enabled packages

| machine | packages |
| --- | --- |
| <laptop> | tailscale drop-folder peekaboo |
| <worker> | tailscale drop-folder agent-clis t3-remote screenshare os-update |
