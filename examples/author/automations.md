# Automations

| machine | job | when | why it exists |
| --- | --- | --- | --- |
| worker | health watchdog | every 15 min, after every resume | Tailscale, T3 backend, relay tunnel, Tailscale Serve mapping, and agent logins. Heals infrastructure, alerts on logins. Caught a Codex refresh token consumed by the other machine, an invalid `gh` token, a relay that died silently |
| worker | config sync | every 30 min, `Persistent=true` | receives rules, skills and fleet docs from the laptop with `reset --hard`. Local edits saved to a ref, never merged |
| worker | boot continuation | at boot, only with an open work order | finishes a deep update after its reboot, verifies, reports |
| worker | MCP refresh | daily, `Persistent=true` | updates the two keyless MCP servers in place, so the worker never depends on the laptop being awake |
| worker | update notice | daily | counts pending pacman and AUR updates into the journal. Read-only; applies nothing |
| worker | full-system snapshot | daily 03:00, `Persistent=true` | rsync snapshot with hard-link dedup to the HDD, 7-day retention |
| worker, laptop | agent history backup | daily | Claude Code prunes its transcripts on a rolling 30-day window. Archives Claude, Codex, Cursor and opencode history to a private, versioned S3 bucket, per-machine prefixes, no `--delete` |
| laptop | nightly fleet update | daily 02:00, Mac woken by `pmset repeat` | a headless agent runs `/fleet-update` on both machines end to end, fixes what failed, records versions, commits, and sends OK or NEEDS ATTENTION |
| laptop | dispatcher | hourly | one LaunchAgent runs every tool folder through one app holding Full Disk Access, so new tools never need a new permission |

Two retired jobs are kept in the real registry with the reason they were removed, including one
whose unit file carried a live token in plaintext. That is why the automation rules forbid
secrets in `Environment=` lines.
