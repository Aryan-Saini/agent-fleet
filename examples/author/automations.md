# Automations

The laptop runs one dispatcher; the worker runs one systemd timer per job. Why, and the full
catalog with reasons: [`docs/automations.md`](../../docs/automations.md). This is the registry as
it stands, anonymized.

## Laptop

| job | when | why it exists |
| --- | --- | --- |
| nightly fleet update | 02:00, a T3 Code scheduled task; Mac woken at 01:58 by `pmset repeat` | runs `/fleet-update` on both machines in a fresh thread: updates, fixes failures, cleans up, records versions, commits. First line `OK` or `NEEDS ATTENTION` |
| provider updates | hourly (dispatcher) | keeps claude, codex, opencode and worker-chrome current on both machines between nightlies |
| hub failover | every minute (dispatcher) | points the laptop's agents at local logins after three failed hub checks, back after two good ones |
| agent history backup | daily (dispatcher) | Claude Code prunes transcripts after 30 days. One restic snapshot a day into S3, kept forever |
| repo sync | daily (dispatcher) | safety net for the worker's 15-minute sync of the no-PR repos |
| calendar mirror | daily (dispatcher) | safety net for the worker's availability mirror |
| personal tools | hourly or daily (dispatcher) | wallpaper rotation, dictation export, Instagram saves to notes, short videos to YouTube with a metrics snapshot, vault `node_modules` hider, fork-ahead notice |
| settings capture | daily 03:00 (LaunchAgent) | live agent settings and generated rules into the fleet repo, commit, push |
| secrets loader | at login (LaunchAgent) | publishes API keys to GUI-launched apps |

## Worker, user timers

| job | when | why it exists |
| --- | --- | --- |
| health watchdog | every 15 min, after every resume | heals Tailscale, T3, the relay, Serve mappings, the hub, phone control. Alerts on logins, keep-awake, hub accounts. Caught a Codex refresh token consumed by the other machine, an invalid `gh` token, a relay that died silently |
| config sync | every 30 min, after every resume | `reset --hard` of every config repo onto the laptop's push. Local edits saved to a ref, never merged |
| repo sync | every 15 min | the no-PR repos, laptop's half first over ssh |
| agent history backup | 06:00, `Persistent=true` | same restic repo as the laptop, its own host tag |
| hub log archive | 05:30, `Persistent=true` | hub request logs to S3 as one zstd tar a day, then deleted locally |
| MCP refresh | daily, `Persistent=true` | keyless MCP servers updated in place, so the worker never waits on the laptop |
| dev-server reaper | hourly | removes dev servers older than 24 h unless kept |
| CI runner status | every minute | flips a repo variable so workflows fall back to a hosted runner while the self-hosted box is down |
| CI box toolchain | nightly, `Persistent=true` | updates the tools CI uses on the self-hosted box |
| web build host | every 30 min | moves web builds to the self-hosted box when the hosting bill crosses a monthly threshold, and back |
| test-data cleanup | hourly, `Persistent=true` | deletes throwaway users and customers from test runs 24 h after last use |
| availability mirror | every 30 min | busy blocks from personal calendars to a shared team calendar |

## Worker, system timers

| job | when | why it exists |
| --- | --- | --- |
| full-system snapshot | 03:00, `Persistent=true` | rsync of `/` to the HDD, hard-linked, 3-day retention, never deletes what `latest` points to |
| boot continuation | at boot, only with an open work order | finishes a deep update after its reboot, verifies, reports |

## Deliberately disabled

The worker's T3 auto-update timer is versioned and disabled: T3 updates start from the laptop,
which verifies and rolls back.

## Retired

Several retired jobs stay in the real registry with the reason they were removed. One unit carried
a live token in plaintext in an `Environment=` line, which is why the automation rules forbid
secrets in unit files. Another was a cron job that sat inside the worker's old nightly sleep
window and never fired for weeks, which is why every job that must not be skipped uses
`Persistent=true`.
