---
name: fleet-add-device
description: When the user wants to add a new machine (a worker, a second laptop, a phone) to their fleet, use skill.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  requires: "the fleet repo checkout on the controller, Tailscale admin access, and a terminal on the new machine"
---

# fleet-add-device

Run from the controller. Reject a name that is already in `computers.md`. Ask for the role
(worker, controller, remote) and the OS if not given; both change every step below.

## Steps

1. **Network.** Install Tailscale (`packages/tailscale`), sign in to the same account, **disable
   key expiry** for anything always on, confirm `tailscale status` on both ends.
2. **ssh.** Keys only. Add the controller's public key to the new machine's
   `authorized_keys` (or use `tailscale up --ssh` on Linux). Add an ssh alias for the new machine
   on the controller and every worker, and one for the controller on the new machine.
3. **The repo.** Clone the user's private fleet repo to `~/fleet` on the new machine.
4. **Install.** `~/fleet/install.sh --role <role> --name <name> --controller <alias> --packages "<list>"`.
   Pick packages from `packages/` that match the role and OS. For an OS a package doesn't cover,
   port its scripts following its README, in the fleet repo, on the controller.
5. **Package setup.** Walk each enabled package's README install section on the new machine:
   pair Syncthing for the drop folder, apply always-on settings on a worker, install agent CLIs.
6. **Logins, by the human.** Every agent CLI and `gh` login is per machine and never synced.
   List them and wait for the user.
7. **Register.** Add the `computers.md` row, create `machines/<name>/README.md` from
   `templates/machine-README.md`, add its scheduled jobs to `automations/README.md`. Commit and
   push from the controller.

## Verify by running, not by reading

- `ssh <name> fleet` shows the right role and packages.
- `ssh <name> fleet health --probe` passes, or every failure is a login still waiting on the human.
- Workers: `fleet send <name> <file>` lands; a file dropped in `~/drop` arrives within 25 s both
  ways; `ssh <name> 'fleet alert test "hello from <name>"'` reaches the user; the timers are
  listed (`systemctl --user list-timers` or `launchctl list | grep fleet`).
- Workers: `ssh <name> fleet workorder status` says no open order, and lingering (Linux) or
  auto-login (macOS) is on, so boot continuation will run.

## Things that bite

- **Nothing reaches a worker until it is pushed.** Workers only see the remote.
- **Config edited on a worker is discarded** by the next sync. Make changes on the controller.
- A phone (role remote) needs only Tailscale and the T3 Code app. Nothing syncs to it; add its
  row to `computers.md` and stop.
