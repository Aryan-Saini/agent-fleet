# Automations: two designs, and every job the author runs

Scheduled jobs run differently on the two machines, on purpose. This page explains both designs,
the rule that keeps them apart, and lists every automation in the author's fleet with what it
does, why it exists, when it fires and where it lives. Your registry is
[`templates/automations-README.md`](../templates/automations-README.md); the `automation` skill
adds a job the native way.

## Two designs side by side

| | controller (macOS) | worker (Linux) |
| --- | --- | --- |
| mechanism | one dispatcher script, run by one signed runner app | one systemd user timer per job |
| triggers | two LaunchAgents: hourly at :30, and every minute | one `.timer` per job |
| schedule | a `cadence` file per tool: `every <N>m`, `hourly`, or none for daily (first fire after 23:30) | any `OnCalendar=` or `OnUnitActiveSec=` |
| a new job | drop a folder in `tools/` | write a `.service` and `.timer`, `enable --now` |
| permissions | every tool inherits the runner's Full Disk Access | none to inherit; `sudo` is passwordless |
| missed runs | daily tools run on the first fire after wake | `Persistent=true` catches up after downtime |
| logs | `tools/<name>/logs/<name>.log`, gitignored | `journalctl --user -u <name>` |
| reference | [`packages/mac-automations`](../packages/mac-automations/) | [`packages/linux-automations`](../packages/linux-automations/) |

**Why a dispatcher on macOS.** macOS grants privacy permissions (Full Disk Access, Calendar,
Automation) to the *responsible process*. If each job were its own LaunchAgent running bash, each
would need its own grant, and a grant silently disappears when the binary changes. One small
runner app holds the grants once. Every tool runs as its child and inherits them, so a new tool
never needs a new permission dialog.

**Why per-job timers on Linux.** There is no permission system to inherit, and systemd already
gives each job its own schedule, status, journal and failure state. A dispatcher would hide all
of that behind one unit.

**Never port one design to the other.** A dispatcher on Linux throws away what systemd gives you.
A LaunchAgent per job on macOS brings back the permission problem the dispatcher exists to
solve. A clock time other than the dispatcher's slots is a real limit of the macOS design; say
so instead of building a parallel mechanism.

Both sides keep the script and unit files in the fleet repo. The live copy is the one that runs;
the repo copy is what survives a rebuild. Logs never go in git.

## The catalog

Machine names are roles. "Both" means the same job runs on each machine.

### Fleet upkeep

| job | where | when | what and why |
| --- | --- | --- | --- |
| nightly fleet update | controller, T3 scheduled task | 02:00, Mac woken at 01:58 by `pmset repeat wake MTWRFSU 01:58:00` | starts a fresh T3 thread that runs `/fleet-update` on both machines: updates, fixes what failed, cleans up, records versions in the docs, commits. The report's first line is `OK` or `NEEDS ATTENTION`, and the thread shows on the phone. It is a T3 task, not a LaunchAgent, so a human can read the whole run afterwards |
| provider updates | controller dispatcher | hourly | updates `claude`, `codex` and `opencode` on both machines and `worker-chrome` on the worker. T3 Code checks npm hourly for new agent CLIs; this keeps the fleet in step instead of waiting for the night. Never restarts T3; skips while the nightly holds its lock |
| T3 peer renewal | inside the nightly update | weekly | renews the T3 environment links and the cross-machine MCP sign-ins, which expire after 30 days. See [t3-code.md](t3-code.md) |
| config sync | worker timer | every 30 min, and after every resume | `reset --hard` of every config repo onto `origin/main`, then applies settings overlays. Local edits saved to a ref, never merged. See [sync.md](sync.md) |
| repo sync | worker timer, controller dispatcher | every 15 min, daily safety net | keeps the "no PRs, just sync" repos (notes vault, coursework, a deploy-from-main app) identical on both machines. The worker runs the controller's half over ssh first, so the controller pushes before the worker rebases |
| settings capture | controller LaunchAgent | daily 03:00 | copies live agent settings and generated config into the fleet repo, commits, pushes |
| secrets loader | controller LaunchAgent, worker user service | at login, before T3 starts | publishes `~/.config/agent-secrets.env` to GUI apps (`launchctl setenv`) and to systemd user services (`systemctl --user set-environment`). Neither a Dock-launched app nor a systemd service reads `~/.zshenv`, so without this every keyed MCP server fails with `invalid_token` |

The two controller LaunchAgents outside the dispatcher predate it and are plumbing rather than
tools. The nightly update is the one approved exception to "everything goes through the
dispatcher": it relaunches apps, so it cannot share the 23:30 slot while you might be working.

### Health

| job | where | when | what and why |
| --- | --- | --- | --- |
| worker watchdog | worker timer | every 15 min, and after every resume | **heals** what is safe and idempotent: Tailscale down, the T3 service dead or not answering, the T3 relay tunnel down, a missing Tailscale Serve mapping, the CLIProxyAPI hub dead or not answering `/v1/models`, the phone-control services stopped. **Alerts** on what needs a human: the T3 Connect link, the keep-awake lock, an expired `gh` login, a hub error, any hub account whose login died, and every account of a provider at its limit at once. Writes an alert file and clears it once everything passes |
| hub failover | controller dispatcher | every minute | three failed checks of the worker's hub in a row point the controller's Claude Code and Codex at their own logins; two good checks point them back. Notifies both ways and leaves a manual override alone. Running sessions keep their old setting. See [`packages/cliproxy`](../packages/cliproxy/) |

"After every resume" is a system-sleep hook that waits for the network, then runs the watchdog
and config sync. It turns "the box woke up" into a checked fact, not an assumption.

### Backups

| job | where | when | what and why |
| --- | --- | --- | --- |
| agent history | both | daily; worker at 06:00 `Persistent=true`, `Nice=10`, idle IO | Claude Code deletes transcripts after 30 days. This backs up Claude, Codex, Cursor, opencode and T3 history into one restic repo in S3, one snapshot per machine per day, kept forever. Live sqlite databases are copied with `.backup` first, never read mid-write. Content dedupes across both machines and all days. See [`packages/agent-history-backup`](../packages/agent-history-backup/) |
| full-system snapshot | worker root timer | 03:00 `Persistent=true` | rsync of `/` to the hard drive, hard-linked against `latest`, 3-day retention. See [storage.md](storage.md#nightly-full-system-snapshots) |
| hub log archive | worker timer | 05:30 `Persistent=true` | packs the hub's request logs into one `zstd --long` tar, uploads it to S3, verifies, deletes the local copy. On failure it alerts and keeps the data |

Never run `restic forget` or `prune` on the history repo. Old transcripts exist only in old
snapshots. Keep the restic password in a mode-600 file on each machine and one copy somewhere
that survives losing both.

### Dev infrastructure

| job | where | when | what and why |
| --- | --- | --- | --- |
| dev-server reaper | worker timer | hourly | removes every dev-server instance added more than 24 h ago unless it was added with `--keep`, so servers agents start for you do not pile up and run forever. See [`packages/dev-server`](../packages/dev-server/) |
| MCP server refresh | worker timer | daily `Persistent=true` | updates the keyless global MCP servers (browser automation, devtools) in place, so the worker never depends on the controller being awake. Never rolls back: a failed update leaves the working version. See [`packages/mcp`](../packages/mcp/) |
| CI runner status | worker timer | every minute | reads the self-hosted GitHub Actions runners' status and sets a repo variable to `online` or `offline`. Workflows read it in `runs-on` and fall back to a hosted runner while the self-hosted box is down. It also cancels and re-runs jobs stranded on a box that died, alerts when runners drop, and writes only on change |
| CI box toolchain | worker timer | nightly `Persistent=true` | updates the tools CI uses on the self-hosted box over ssh, upgrade-only, skipped on a night a job is running |
| web build host | worker timer | every 30 min | reads this billing cycle's usage at the web hosting provider. Over a monthly threshold, it moves web builds to the self-hosted box (a repo variable plus each project's "ignored build step"); under it, back. The side taking over switches on before the other switches off, so there is no gap |
| test-data cleanup | worker timer | hourly `Persistent=true` | deletes the throwaway users, chat channels and payment customers that automated app test runs create in third-party dev services, 24 h after their last use |

### Personal productivity

One line each, to show the range. None of these need the worker; they run in the controller's
dispatcher unless noted.

- **Wallpaper rotation**, hourly: steps to the next image in a folder, through NSWorkspace, so it
  needs no Automation grant.
- **Dictation export**, daily: dictation history from a voice-typing app into dated markdown.
- **Instagram to notes**, daily: new saved posts become notes in the vault.
- **Short videos to YouTube**, daily: finds new posts, downloads and transcribes them, queues
  them, uploads a few a day from a resumable manifest. A sibling job snapshots post metrics.
- **Vault `node_modules` hider**, daily: hides every project's `node_modules` from the notes
  app's file watcher, so the vault stays fast.
- **Calendar availability mirror**, every 30 min on the worker with a daily controller safety
  net: publishes busy blocks from personal calendars to a shared team calendar. The worker reads
  the calendars over CalDAV and the Google API directly, so the controller need not be awake.
- **Fork update notice**, daily: says when upstream is ahead of a forked app you build yourself.
  Updating stays manual.

### Keep-alives on a second Mac

A shared Mac in the house is on the tailnet as a remote-desktop and test target. It is not part
of the fleet: it pulls no config. It runs the same dispatcher shape, one LaunchAgent firing every
60 seconds through a privileged runner, deployed by rsync from the fleet repo. Two tools:

- **Sill**: restarts it if it is gone, so phones can always stream its windows.
- **The remote-desktop app**: restarts it, because it has no system service of its own.

It only runs while someone is logged into the GUI.

### Deliberately not scheduled

- **T3 auto-update on the worker.** The timer exists, versioned, and stays disabled. T3 updates
  are started from the controller, which checks health after the restart and rolls back on its
  own. Unattended, the worker could not tell whether the phone still connects.
- **Deep OS updates.** Never scheduled. They run as work orders, on request. See
  [architecture.md](architecture.md#the-disconnect-risk-rule-and-work-orders).

## Lessons

**launchd gives a bare PATH.** A job that works in your terminal fails under launchd. The worse
version: four jobs pinned install paths (`/usr/local/bin/aws`, `~/.nvm/versions/node/v25.x/bin`)
and broke silently for five weeks when those tools moved. Fix: the dispatcher exports one PATH,
and tools call commands by name, never by install path.

**Build venvs on uv-managed Python.** `uv venv --managed-python`. Xcode's and Homebrew's Python
vanish or change minor version on upgrade, and every venv built on them dies with it.

**Test through launchd.** Running the runner from an agent's shell proves nothing: macOS
attributes permissions to whatever launched it, and an agent shell has no grant, so you get a
false denial. Load a temporary plist that runs the one tool, `launchctl start` it, read the log,
remove the plist.

**`Persistent=true` for anything that must not be skipped.** A wall-clock timer whose moment
passes while the box is down or rebooting never fires. The author's first worker sync was a cron
inside the old nightly sleep window. Its log was empty for weeks. Leave `Persistent` off only
for jobs that must not fire late, and say why in the unit.

**Never put a secret in a unit file.** `Environment=` lines get committed with the repo copy.
One retired unit carried a live token in plaintext that way. Use `EnvironmentFile=` pointing at
a mode-600 file outside the repo.

**systemd does not read your shell profile.** A service gets the user manager's environment,
not `~/.zshenv`. Agents started from the phone through T3 sent empty API keys while the same repo
worked over ssh. The secrets loader service, ordered `Before=` the T3 unit, fixed it. Note that
`set-environment` only reaches units started afterwards.

**Small shell traps that bit real jobs.** Under `set -o pipefail`, `cmd | grep -q` can report
failure on a match, because grep exits early and SIGPIPEs the producer; capture to a variable,
then grep. `codex exec` with no tty blocks reading stdin; always pass `</dev/null`. A child's
output piped through `sed` is filed under the child's pid, and `journalctl -u` then hides it;
echo from the unit's own shell.

**One job, one unit, `Type=oneshot`, idempotent.** A `Persistent=true` catch-up runs it twice in
a row; that must be safe.
