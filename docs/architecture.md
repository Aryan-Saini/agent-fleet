# Architecture: one leader, one worker, phones as remotes

The fleet has one leader and the rest follow. The **controller** is a MacBook: the human works
there, and it is the only machine that authors config, runs `/fleet-update` and owns the docs.
The **worker** is an always-on Arch Linux desktop with no monitor attached. It executes. The
**phones** drive both through T3 Code and hold nothing.

```
                 phone(s): T3 Code app
                      | T3 Connect relay (anywhere) or Tailscale
   +------------------+-----------------------------------------------+
   |                          tailnet                                  |
   |  controller (MacBook)                  worker (Arch, headless)    |
   |  - you work here                       - agents in tmux and T3    |
   |  - authors every config  -- git -->    - dev servers (HTTPS)      |
   |  - /fleet-update         <-- ssh -->   - CLIProxyAPI hub          |
   |  - T3 Code desktop app   <-- T3 -->    - worker-chrome, Halo      |
   |  - owns the docs                       - backups, watchdog        |
   +-------------------------------------------------------------------+
```

## Who does what

| | controller | worker | phone |
| --- | --- | --- | --- |
| authors config, rules, skills, docs | yes, the only one | never; its edits are discarded | no |
| runs `/fleet-update` | yes, nightly and on demand | receives it | no |
| runs agents | when you are at it | all day, in tmux and T3 threads | starts and watches them |
| dev servers | rarely | yes, behind Tailscale HTTPS ([`packages/dev-server`](../packages/dev-server/)) | opens the links |
| model accounts | routes through the worker's hub, falls back to local logins | hosts the [CLIProxyAPI hub](../packages/cliproxy/) | no |
| browser an agent drives | the real one, through [Cua Driver](../packages/cua-driver/) | [`worker-chrome`](../packages/worker-chrome/) on a virtual screen | no |
| a human looks at the worker's screen | [Halo](../packages/halo/) | serves the screens | Halo in a browser tab |
| backups | its own agent history | its own history, full-system snapshots, hub logs | no |
| sleeps | yes, lid closed | never | yes |

The worker heals what it safely can, reports the rest, and never starts disruptive work on its
own. The invariant: **the worker may lose the current task; it may never stay down or stay
silent.**

## Every channel between the machines

| channel | direction | used for |
| --- | --- | --- |
| Tailscale | both | names, ssh, HTTPS for dev servers and T3 |
| ssh aliases | both | commands, scripts, `sudo` |
| T3 environment links | both | threads and subagents on the other machine, visible on the phone |
| scp helpers, T3 attachments | both | files |
| alert script | worker to controller to phone | getting a human's attention |
| git | controller to worker only | every config change |
| work orders | controller to worker | risky work that may cut the connection |

### Tailscale

Every machine joins one tailnet and gets a stable name: `<worker>`, `<controller>`, and
`<name>.<tailnet>.ts.net` for HTTPS. Nothing listens on a public port, and Funnel stays off.

- **Tailscale SSH** runs on the worker. The tailnet policy uses `"action": "accept"` for your own
  devices, not `"check"`. Check mode asks for a browser re-auth now and then, and an unattended
  job that hits that prompt hangs with no error.
- **Tailscale Serve** gives the worker real certificates: T3 Code on `/`, each dev server on
  its port plus 10000, Halo screens on their own ports. A real certificate makes the page a secure
  context, which cookies and auth SDKs need. Never reconfigure an existing mapping, add a new one.
- The macOS side runs Homebrew's `tailscale` pinned, so an upgrade does not reset its
  permissions. See [`packages/tailscale`](../packages/tailscale/).

### ssh both ways

`ssh <worker>` from the controller, `ssh <controller>` from the worker. Keys only, password auth
off. The worker's public key sits in the controller's `authorized_keys` (macOS Remote Login on),
so the worker needs no agent forwarding. The repo doubles as the key exchange: a new machine
commits its `*.pub` under its own folder, and the other side appends it.

**Non-interactive ssh gets a stripped PATH.** This looks exactly like a missing install:

```bash
ssh <controller> 'which claude'              # not found
ssh <controller> 'zsh -lc "which claude"'    # still not found: -l reads .zprofile, not .zshrc
ssh <controller> 'zsh -ic "which claude"'    # found
```

Fix it once per machine. On macOS put PATH additions in `~/.zshenv`, which every zsh reads.
On the worker the login shell is a small bash wrapper that sources one POSIX env file
(`~/.config/shell/env.sh`: PATH, locale, agent secrets) and then execs bash. Tailscale SSH
runs `<shell> -c "<cmd>"`, and plain non-interactive bash reads no startup files, so without the
wrapper `ssh <worker> '<cmd>'` gets a bare PATH. Agents write bash, so bash is the login shell;
the human types `zsh` for the interactive setup.

### T3 environment links

Each machine's T3 Code is linked to the other's, so an agent on one machine can launch a thread
or a subagent on the other: `delegate_task` with the other machine's `environmentId`, or
`t3_thread_launch` through the other T3's MCP server. The thread runs with that machine's own
logins and shows up in the app and on the phone. This is the only way the worker gets a Claude
Code agent on the controller, because Claude Code on macOS keeps its credentials in the Keychain
and cannot start over non-interactive ssh. Links and sign-ins expire after 30 days and a weekly
job renews them. Details in [t3-code.md](t3-code.md).

### Files

- `to-worker <file>` and `to-controller <file>`: tiny scp wrappers that drop files in the other
  machine's `~/drop`, take `-d <dir>` for another destination, and fail loudly with a hint if the
  other side is asleep. The kit's portable version is `fleet send <machine> <file>`.
- T3 attachments: attach an image or file to a thread and it lands on whichever machine runs it.
  This is how screenshots reach a headless worker now.
- The author used to mirror a Syncthing drop folder between machines. It was retired once T3
  carried images and files. An explicit copy is easier to reason about than a folder that
  "should have synced by now". The [`drop-folder`](../packages/drop-folder/) package still works
  if you want it.

### Alerts from the headless box

The worker has no screen, so it reaches you through the controller. The alert script does three
things, each best effort, and always exits 0 so alerting never breaks the job that alerted:

1. ssh to the controller and raise a macOS notification (`terminal-notifier`, with
   `osascript` as fallback).
2. ssh to the controller and send a message to your own phone through the controller's
   Messages app. That is what reaches you when you are away from the laptop.
3. Append to a log file in `~/drop` and the journal, the durable record when the controller is
   asleep.

Message strings are base64-encoded before they cross ssh, so quotes and newlines cannot break
the remote command. The gap: with the controller asleep or away, only the log on the worker
records the alert. A push service like ntfy closes that gap if you need it.

### Git is the config bus

Config moves one way. The controller commits and pushes; every 30 minutes the worker's sync
timer does `git fetch` and `reset --hard origin/main` on each config repo. A local edit on the
worker is saved to a `refs/<worker>-local/*` ref first, then discarded, so the fleet's rules can
never fork. Need it on the worker now: `ssh <worker> 'systemctl --user start <sync-unit>'`.
Every path and its conflict rule is in [sync.md](sync.md).

### Agents handing each other work

There is no message bus. Two patterns work:

- **Inside T3**, launch a thread or a `delegate_task` subagent on the other machine with a
  self-contained brief. The result comes back as a thread you can read.
- **Outside T3**, a file plus a nudge: write `WORK-ORDER.md`, copy it across with
  `to-controller`, then send an alert. The reply comes back the same way.

## The disconnect-risk rule and work orders

The README states the rule. Here is how it plays out.

Before the controller acts on the worker, classify whether the work could cut Tailscale, ssh,
the service manager, networking, or the boot. Package upgrades that touch openssh, tailscale,
systemd or the kernel all count. If yes or unsure, the work never streams over a live ssh
session, because the session dies halfway and leaves the machine in a state nobody chose.

A work order instead:

1. Writes durable state first: what is running, the phase, how to roll back.
2. Starts detached (`systemd-run --no-block` on the worker, or `fleet workorder start`), then the
   controller disconnects.
3. Arms boot continuation before any reboot: a oneshot unit that runs phase 2 after boot.
4. After boot, phase 2 runs health checks on the worker alone (tailscale, sshd, T3 answering on
   its port). Reaching the controller goes in the report, never in the verdict: a closed laptop
   lid must not roll back a healthy worker.
5. Writes a report and alerts. State clears only once reconnection is proven. Otherwise the next
   boot tries again and the alert says a human is needed.

The author's worked example is the deep OS update: a read-only btrfs snapshot of `/` before the
transaction, `pacman -Syu` and AUR builds in phase 1, the reboot, then phase 2. New kernels get
one test boot with `grub-reboot` while the saved default still points at the proven one, so a
kernel that hangs costs one failed boot, not the box. Two lessons from those runs:

- A backup file left in `/etc/grub.d` runs as a generator on the next `grub-mkconfig` and can
  bring back a dead boot entry. Keep backups outside that directory.
- Copy `/usr/lib/modules/<running kernel>` before an upgrade if you plan to fall back to the old
  kernel. pacman deletes the old modules, and the fallback boots with no network drivers.

[`packages/os-update`](../packages/os-update/) has the generic version.

## Sudo across machines

Unattended work needs root without a human typing a password. Two patterns follow, one per OS.
Pick per machine, and choose the narrowest one your automations can live with.

### Linux worker option: passwordless sudo for its user

```bash
echo '<user> ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/90-<user>-nopasswd
sudo chmod 440 /etc/sudoers.d/90-<user>-nopasswd
sudo visudo -cf /etc/sudoers.d/90-<user>-nopasswd     # syntax check, or sudo breaks
```

Then `ssh <worker> sudo systemctl restart <unit>` works from the controller with no prompt. What
keeps this from being reckless:

- Only tailnet members reach the worker's ssh. No public port, keys are the only login method.
- Agents still follow the disconnect-risk rule. Passwordless sudo removes a prompt, not the
  judgment about what to run.

The cost, stated plainly: **any code running as that user is root.** That includes every npm
dependency a dev server or test suite runs. `NoNewPrivileges=yes` on a unit only stops processes
inside that unit from gaining privileges directly (setuid, sudo). The same code can still ask
your user's systemd manager to start a fresh unit without the flag, or edit a script your
automations run later, and get root that way. It is a speed bump, not a boundary.

If the worker runs untrusted code, the boundary that holds is a **separate account**: run dev
servers and test suites as a user with no sudo, no access to your user's systemd manager, and no
write access to your home, automations or keys. Narrowing sudoers to `systemctl` or `pacman` does
not help either: both can run arbitrary code as root (load a unit you wrote, install a package
with a hook). To narrow sudo for real, allow only root-owned wrapper scripts that perform one
fixed operation each and validate their arguments, for example
`NOPASSWD: /usr/local/sbin/fleet-restart-unit`, where the wrapper accepts only names on a list.

### macOS controller option: a password in the Keychain and `sudo -A`

The controller keeps its sudo password. Unattended jobs, nightly updates and the worker (over
`ssh <controller>`) use `sudo -A`, which asks a helper program for the password instead of a
terminal. The helper reads it from the macOS login Keychain. The password never enters the repo.

```bash
# once, by hand. -w last makes `security` prompt, so nothing lands in shell history
security add-generic-password -U -a "$USER" -s fleet-sudo -T /usr/bin/security -w

# ~/.local/bin/fleet-askpass, mode 700
#!/bin/sh
exec /usr/bin/security find-generic-password -a "$USER" -s fleet-sudo -w
```

```bash
export SUDO_ASKPASS="$HOME/.local/bin/fleet-askpass"
sudo -A softwareupdate -l
brew upgrade --cask <cask>          # Homebrew honours SUDO_ASKPASS too
ssh <controller> 'SUDO_ASKPASS=$HOME/.local/bin/fleet-askpass sudo -A <cmd>'   # from the worker
```

`-T /usr/bin/security` adds `security` to the item's access list. Without it macOS shows a GUI
"allow access" dialog that nobody answers over ssh. The login Keychain must also be unlocked,
which means you are logged in.

Tradeoffs: any process running as your user on the controller can run the helper and read the
password, so for local code this is close to passwordless sudo. What you gain is that the
password is not a file on disk, it stops working when you log out, and the human-facing `sudo`
prompt is unchanged. Rotate it with the same `add-generic-password -U` command.

### When something insists on a real terminal

A few things refuse askpass or want a human anyway: some Homebrew casks whose installers call
`sudo` in ways that ignore `SUDO_ASKPASS`, `sudo xcodebuild -license`, and anything that quits the
T3 Code app the agent session lives in. The controller has a `t3-handoff` helper for these. It
walks its own process tree to see whether it runs inside T3 Code. If it does, it opens
Terminal.app with the command, writes a log and a status file the agent polls, and closes the
window on success. The human types the password there. Outside T3 Code it runs the command
inline, so the same call is always correct. Hand off a session that owns the rest of the run,
not a bare command, or whatever is still owed dies with the old session.

## Load limits on the worker

One more lesson that shaped the worker. Under heavy combined CPU and memory load (six dev
servers, parallel production builds, monorepo type checks) the author's worker hard-froze, with
nothing in the kernel log. The hardware watchdog did not fire because the chipset froze too. The
fix was to keep agents from reaching that load:

- CPU boost off.
- systemd slice drop-ins cap every T3 agent together and each session alone (`MemoryHigh`,
  `MemoryMax`, `MemorySwapMax`, `AllowedCPUs`). Set the cap on the parent slice: T3 rewrites the
  limits on its own agents slice at every start.
- earlyoom kills dev servers and builds first.
- `kernel.panic=10` and lockup panics on, so a lockup the kernel can see reboots the box.

A remote box needs a way back from a freeze it cannot detect. A smart plug that another device
on the LAN power-cycles, plus BIOS "restore on AC power loss", is the only full answer.
