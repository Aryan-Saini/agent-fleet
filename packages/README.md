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
| `*.sh` | no | reference implementations, such as a work order per OS |

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
| [tailscale](tailscale/) | every machine | the private network and ssh from anywhere |
| [drop-folder](drop-folder/) | every machine | `~/drop` synced everywhere by Syncthing |
| [always-on](always-on/) | workers | never sleep, come back after power loss, run headless |
| [agent-clis](agent-clis/) | workers | catch expired Claude, Codex, Cursor, opencode and gh logins |
| [accounts](accounts/) | every machine | which logins and API keys you need, and how keys reach every machine |
| [t3-remote](t3-remote/) | workers, controllers | install T3 Code (stable or nightly) and drive agents from a phone |
| [postdraft](postdraft/) | every machine | agents publish plans, reports and files as links, on your own server (npm) |
| [screenshare](screenshare/) | controller + headless worker | see and click a browser on a box with no screen (npm), and a Mac from your phone (Sill) |
| [worker-chrome](worker-chrome/) | workers | one real, logged-in Chrome that agents drive instead of headless Chromium (npm) |
| [peekaboo](peekaboo/) | macOS | let an agent see and click the real screen |
| [vorssaint](vorssaint/) | macOS controllers | free menu bar toolkit, from the release or your own fork's build |
| [mcp](mcp/) | every machine | MCP servers that work on every machine without per-machine logins |
| [os-update](os-update/) | workers | OS upgrades as reboot-safe work orders |
