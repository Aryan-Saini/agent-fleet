# Packages

A package is one capability a machine can opt into: a network, a drop folder, a watchdog check,
a remote screen. Enable packages per machine in `~/.config/fleet/machine.env`:

```bash
FLEET_PACKAGES="tailscale drop-folder always-on agent-clis"
```

then re-run `./install.sh` so any `bin/` scripts land on PATH.

## What is in a package

| file | required | purpose |
| --- | --- | --- |
| `README.md` | yes | what it is, why, install per OS, verify, update, gotchas. The spec |
| `check.sh` | no | health check run by `fleet health`. Exit 0 healthy, exit 1 broken with one line on stdout. `--heal` tries a safe fix, exits 1 when it has none |
| `bin/` | no | commands linked into `~/.local/bin` |
| `npm` | no | npm packages this package ships as, one per line. `./install.sh` installs them globally, `fleet link` links each one's `skills/`, `/fleet-update` updates them |
| `install.sh` | no | setup `./install.sh` runs for this package. Idempotent; prints steps only a human can do (a login) instead of attempting them |
| `units/`, `*.plist` | no | systemd units and launchd plist templates (`__HOME__` placeholders) that `install.sh` or the README copies into place |
| other files | no | reference implementations to copy and adapt, such as a work order per OS or a job script |

## Any OS

The reference scripts target the OS the author runs: macOS controllers and Linux workers. The
README is the real contract. When your OS is not covered, give the README to your agent and have
it port the scripts, keeping the same check contract and the same command names. Put the port
next to the original (`check.sh` handling one more `uname -s` case, or `windows.ps1` beside
`arch.sh`) and send it upstream if it works.

## Writing a package

1. `packages/<name>/README.md` first. Cover install, verify, update, and what breaks.
2. A `check.sh` if the thing can silently die. Keep it fast; gate slow work on `FLEET_PROBE=1`.
3. If the tool is useful outside the fleet, publish it to npm on its own and list it in an
   `npm` file, so the package stays a thin spec and the tool versions independently.
4. Heal only what is safe and idempotent: restarting a service, re-applying a mapping. Never
   heal a login, a reboot or anything that needs a human. Report it instead.
5. If it needs updating, say how in the README; `/fleet-update` reads it.

| package | for | what |
| --- | --- | --- |
| [tailscale](tailscale/) | every machine | the private network, ssh from anywhere, `serve` for HTTPS, sharing across tailnets |
| [drop-folder](drop-folder/) | every machine | `~/drop` on every machine; `to-worker` / `to-controller` push files, Syncthing optional |
| [always-on](always-on/) | workers | never sleep, come back after power loss, run headless |
| [agent-clis](agent-clis/) | workers | catch expired Claude, Codex, Cursor, opencode and gh logins |
| [accounts](accounts/) | every machine | which logins and API keys you need, and how keys reach every machine |
| [settings-sync](settings-sync/) | every machine | Claude, Codex and T3 settings shared one way with per-machine overlays; `repo-sync` for no-PR repos |
| [mcp](mcp/) | every machine | MCP servers without per-machine logins: keys global, definitions per project, trust per machine |
| [t3-remote](t3-remote/) | workers, controllers | T3 Code as a service, phone access, controller and worker linked to each other |
| [cliproxy](cliproxy/) | worker + controller | one CLIProxyAPI hub for every Claude and Codex account, failover, request log archive |
| [mac-automations](mac-automations/) | macOS | every scheduled job through one signed runner granted Full Disk Access once |
| [linux-automations](linux-automations/) | Linux workers | one systemd user timer per job, `Persistent=true` where downtime matters |
| [agent-history-backup](agent-history-backup/) | every machine | every agent conversation kept forever in restic on S3, with a restore helper |
| [dev-server](dev-server/) | workers | run a web app on the worker, open it over tailnet HTTPS from anywhere, reaped after 24h |
| [postdraft](postdraft/) | every machine | agents publish plans, reports and files as links, on your own Convex server (npm) |
| [halo](halo/) | controller + headless worker | see and click a worker's screen from the controller: Xvfb, voxl, RustDesk, a screen pool (npm) |
| [sill](sill/) | macOS + phone | any window on your Mac on your iPhone or iPad, over Tailscale, kept running |
| [worker-chrome](worker-chrome/) | workers | one real, logged-in Chrome that agents drive instead of headless Chromium (npm) |
| [cua-driver](cua-driver/) | macOS controllers | agents drive native apps in the background, CLI and MCP (trycua) |
| [peekaboo](peekaboo/) | macOS | let an agent see and click the real screen, fallback for cua-driver |
| [phoneuse](phoneuse/) | headless worker + phone | agents see and tap a real iPhone over AirPlay and Bluetooth (spec) |
| [vorssaint](vorssaint/) | macOS controllers | free menu bar toolkit, from the release or your own fork's build |
| [os-update](os-update/) | workers | OS upgrades as reboot-safe work orders |
