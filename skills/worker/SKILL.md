---
name: worker
description: Operate one of the user's always-on worker machines. Use whenever they say "on the worker", "on the box", "on the server", "ssh into <worker>", "run this there", or ask to check, run or move anything on a worker. Covers connecting, tmux, files both ways, services across the tailnet, agents on another machine, and safety rules.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  requires: "ssh aliases for each machine and Tailscale"
---

# worker

Workers are listed in `computers.md` with role `worker`. Their storage rules, hardware and
quirks are in `machines/<name>/README.md`. Read it before writing anything large.

## Connect

- **Are you already on it?** Run `fleet` (or `hostname`). If it names the worker, run commands
  locally. Do not ssh to yourself.
- Otherwise `ssh <worker>`. If it times out, the box is off or wedged, not asleep: workers never
  sleep. Check `tailscale status`, then the LAN fallback in the machine's README.
- Long jobs and agents go in tmux so a dropped connection doesn't kill them:
  `ssh <worker>` then `tmux new -s <name>`, or detached:
  `ssh <worker> 'tmux new -d -s build "make test > ~/drop/build.log 2>&1; fleet-alert build done"'`

## Disruptive work

Anything that could cut the network, ssh, the service manager or the boot (OS upgrades, network
or firewall changes, kernel or bootloader work) is a work order, never a live session:

```bash
ssh <worker> 'fleet workorder start <name> <script>'
```

Then disconnect and wait for the report in `~/drop` and the alert. `fleet workorder status` on
the worker shows where it is. See `packages/os-update/README.md` for the contract.

## Files, both directions

- Now: `fleet send <machine> <file>...` (`-d <dir>` for somewhere other than `~/drop`).
- Lazily: write to `~/drop`. Syncthing carries it in ~15-25 s. If a file "isn't there yet", wait
  and look again before calling sync broken.
- Images: no clipboard over ssh. Drop the file, reference it by path.

## Services across machines

Every machine is on the tailnet, so a port on one is a hostname away from the other, and from the
phone: `http://<worker>:3000`. The server must bind `0.0.0.0`, not `127.0.0.1`
(`next dev -H 0.0.0.0`, `vite --host 0.0.0.0`). If it can't, tunnel:
`ssh -f -N -L 9300:localhost:3000 <worker>`.

## Agents on another machine

- `ssh <worker> '~/.local/bin/claude -p "<task>"'` returns the result on stdout.
- Codex: `ssh <worker> 'cd ~ && codex exec --skip-git-repo-check -s read-only "<task>" < /dev/null'`
- Claude Code on a **macOS** machine cannot be started over non-interactive ssh: its login is in
  the Keychain. Use Codex there, or leave a work file in `~/drop` plus `fleet alert`.
- There is no message bus. Handoffs are a file in `~/drop` plus `fleet alert`.

## Gotcha: ssh strips PATH

`ssh <machine> 'which claude'` says not found even when it is installed, because a
non-interactive shell skips `.zshrc`. Use absolute paths or `zsh -ic "..."`, and check this before
concluding something isn't installed.

## A human needs to see the screen

Logins, 2FA, captchas on a headless worker: the `screenshare-tunnel` skill on the controller.
