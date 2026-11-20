---
name: worker
description: Operate one of the user's always-on worker machines. Use whenever they say "on the worker", "on the box", "on the server", "ssh into <worker>", "run this there", or ask to check, run or move anything on a worker. Covers connecting, tmux, files both ways, storage, services across the tailnet, agents on another machine, and safety rules.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "ssh aliases for each machine and Tailscale. Runs commands locally when already on the worker"
---

# worker

Workers are listed in `computers.md` with role `worker`. Their storage rules, hardware and
quirks are in `machines/<name>/README.md`. Read it before writing anything large.

## Connect

- **Are you already on it?** Run `fleet` (or `hostname`). If it names the worker, run commands
  locally. Do not ssh to yourself.
- Otherwise `ssh <worker>`. If it times out, the box is off or wedged, not asleep: workers never
  sleep. Check `tailscale status`, then the LAN fallback (or Wake-on-LAN) in the machine's README.
- Long jobs and agents go in tmux so a dropped connection doesn't kill them:
  `ssh <worker>` then `tmux new -s <name>`, or detached:
  `ssh <worker> 'tmux new -d -s build "make test > ~/drop/build.log 2>&1; fleet alert build done"'`
- If the worker has passwordless sudo, say so in its README. Agents then run `sudo -n` directly
  instead of stalling on a prompt nobody sees.

## Disruptive work

Anything that could cut the network, ssh, the service manager or the boot (OS upgrades, network
or firewall changes, kernel or bootloader work) is a work order, never a live session:

```bash
ssh <worker> 'fleet workorder start <name> <script>'
```

Then disconnect and wait for the report in `~/drop` and the alert. `fleet workorder status` on
the worker shows where it is. See `packages/os-update/README.md` for the contract.

## Storage

Write down in the machine README which disk holds what, and keep agents to it:

| kind | where | example |
| --- | --- | --- |
| checkouts, worktrees, package stores, toolchains, datasets | the big fast work volume | `~/dev/<repo>` as a bind mount of `/mnt/work/dev` |
| system, configs | the root partition | keep it small and clean |
| cold archives, snapshots | a slow bulk disk | `/mnt/backup/archive/` |
| data that must never change | mounted **read-only** | agents never write or delete there |

A bind mount keeps the short path (`~/dev/<repo>`) while the bytes land on the right disk.

## Files, both directions

- Now: `fleet send <machine> <file>...` (`-d <dir>` for somewhere other than `~/drop`). Works from
  the worker back to the controller too.
- Lazily: write to `~/drop`. Syncthing carries it in ~15-25 s. If a file "isn't there yet", wait
  and look again before calling sync broken.
- Images: no clipboard over ssh. Send the file, reference it by path.

## Reaching the controller from the worker

The worker is not one-way. Put the worker's own key in the controller's `authorized_keys` and an
`ssh <controller>` alias in the worker's `~/.ssh/config`. If it fails to resolve, the laptop is
asleep or off the tailnet (`tailscale status`). On macOS, Remote Login must be on.

## Services across machines

Every machine is on the tailnet, so a port on one is a hostname away: `psql -h <worker> ...`,
`http://<controller>:3000`.

**Do not bind worker servers to `0.0.0.0`.** A home firewall that accepts LAN traffic exposes them
to everyone on the Wi-Fi with no Tailscale auth. For a web app the user should open from their
laptop or phone, use the **dev-server** skill: the app binds loopback and `tailscale serve` gives
it an HTTPS tailnet URL. For a one-off, tunnel: `ssh -f -N -L 9300:localhost:3000 <worker>`.

## Agents on another machine

- Inside T3 Code: `delegate_task` with the worker's `environmentId` (the **subagents** skill), or
  a whole thread over there (the **t3-environment-handoff** skill). No ssh needed.
- `ssh <worker> '~/.local/bin/claude -p "<task>"'` returns the result on stdout.
- Codex: `ssh <worker> 'cd ~ && codex exec --skip-git-repo-check -s read-only "<task>" < /dev/null'`
- Claude Code on a **macOS** machine cannot be started over non-interactive ssh: its login is in
  the Keychain. Use Codex there, or leave a work file in `~/drop` plus `fleet alert`.

## Gotchas

- **ssh strips PATH on macOS.** `ssh <mac> 'which claude'` says not found even when it is
  installed, because a non-interactive zsh skips `.zshrc` (and `zsh -lc` doesn't help). Use
  absolute paths or `zsh -ic "..."`. A Linux worker whose login shell is bash with a full PATH
  doesn't have this problem. Check before concluding something isn't installed.
- **Nested quotes over ssh break silently.** sqlite then reads `"value"` as a column name. Send
  SQL, Python and JS on stdin with a quoted heredoc:
  `ssh <worker> 'sqlite3 ~/data.db' <<'SQL'` ... `SQL`.
- **Shared monitors or peripherals.** If the worker shares a monitor with the laptop, note in its
  README never to power it off with `ddcutil` or similar.

## A human needs to see the screen

Logins, 2FA, captchas on a headless worker: the **halo** skill on the controller.
