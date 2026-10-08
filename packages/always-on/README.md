# always-on

A worker is only useful if it is there when you reach for it from a phone at 2 am. This package
makes a machine never sleep, run without a monitor, and come back by itself after a power cut.

## Linux

```bash
sudo systemctl set-default multi-user.target    # boot to a console; the desktop stays installed
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl enable --now sshd                # `enable` is what survives the reboot
sudo pacman -S tmux    # or apt/dnf: agents and long jobs live in tmux sessions
```

To use the desktop again, log in on a console and start it by hand.

## macOS

```bash
sudo pmset -a sleep 0 disksleep 0 autorestart 1   # never sleep, restart after power loss
```

Turn on Remote Login, and auto-login for the worker user: LaunchAgents only start after a login.

## Windows

Power plan: sleep Never. BIOS as below. Enable the OpenSSH server feature.

## Every OS

- **BIOS or firmware: "Restore on AC power loss" = On.** Without it a power cut is a trip home.
- Wired network if at all possible.
- Wake-on-LAN only works from the same LAN, so it is a fallback, not a plan.

## Health

`check.sh` fails if anything could still put the machine to sleep. No heal: changing power
policy is a human decision.

## Gotchas

- A wall-clock timer whose moment passes while the box is down never fires. Use
  `Persistent=true` on systemd timers that must not be skipped.
- Headless GPUs sometimes need a kernel arg or a dummy display plug to boot cleanly with no
  monitor attached. Record what your box needs in its `machines/<name>/README.md`.
