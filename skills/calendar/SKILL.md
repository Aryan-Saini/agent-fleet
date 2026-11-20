---
name: calendar
description: The user's calendar and availability. Use when the user wants their week planned, asks anything about their calendar or when they are free, wants their shift roster pulled, or wants something added, moved or removed from their calendar. Also for the availability mirror (the shared team calendar of busy blocks) and the timer that keeps it current.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "uv; ~/.config/calendar-mirror/config.json, an iCloud app-specific password file and a Google service account key on each machine (none in git)"
---

# Calendar

Apple Calendar (iCloud) is the source of truth. A Google work calendar is read alongside it.
Everything in `scripts/` runs the same on the controller and the worker, because it talks to
iCloud and Google over their APIs instead of through Calendar.app: no macOS permission to
fight, and the laptop can be asleep.

| Need | Command |
| --- | --- |
| List calendars | `scripts/cal calendars` |
| Read a range | `scripts/cal list [--calendar <name>] --from YYYY-MM-DD --to YYYY-MM-DD` |
| Add events | `scripts/cal add --calendar <name> --json <file\|->` (each: `title, date, start, end[, location, notes]`) |
| Delete | `scripts/cal delete --id <id>`, or a range with `--calendar --from --to [--title] --dry-run`, then `--confirm` |
| Move to another calendar | `scripts/cal move --id <id> --calendar <name>` |
| Publish availability now | `scripts/mirror.py sync [--from --to] [--dry-run]` |
| Pull the shift roster | `<your roster command>` (see "Shift roster") |

All output is JSON. Ids are `<calendar>:<uid>`. Exit **1** means usage error or refused, **2**
means a source failed (credentials, network, a Google calendar not shared with the service
account).

`cal` refuses ambiguous input on purpose: abbreviated options are rejected (a `--titel` typo
can't silently widen a delete), the two delete modes are exclusive, a range delete needs
`--confirm` or `--dry-run` and removes only events that **start** inside the window, and nothing
is deleted if any target is a recurring series. It writes only the iCloud calendars in the
config, never Google. Recurring series are edited in Calendar.app.

## How the sync works

```
 iCloud (CalDAV, app password) ─┐
                                ├─> mirror.py sync ──> "<Your Name> - Availability"   opaque busy blocks, shared with the team
 Google work cal (svc account) ─┘        │
                                         └──────────> "<Your Name> Apple Calendar"    full detail, private, iCloud calendars only
 worker:     calendar-mirror.timer, every 30 min (:00, :30)
 controller: safety-net.sh, once a day
```

1. **Read the sources directly.** `calendars.py` logs in to iCloud over CalDAV
   (`https://caldav.icloud.com/`) with an Apple ID app-specific password, and reads Google with a
   service account that holds a **reader** share on each Google calendar. Recurring events are
   expanded per occurrence. Cancelled events, events marked Free and invites you declined are
   dropped.
2. **Busy target.** Every timed event on an allowlisted calendar becomes `<Your Name> - Busy`
   with the same start and end. Titles, notes, locations and attendees never cross. All-day
   events, deadline markers (`skip_prefixes`) and anchors you don't want shown (`skip_titles`)
   are left out. Touching or overlapping blocks merge.
3. **Private copy.** The iCloud calendars only, full detail, coloured per source calendar. Your
   Google calendars are already in Google, so copying them would duplicate every event.
4. **Idempotent apply.** Each event id is a hash: of start, end and title for busy blocks, of
   every visible field for the copy. The script lists the target over the window, inserts
   missing ids and deletes ids that should no longer exist. A run with no changes makes no
   writes. An insert that returns 409 becomes an update, a delete that returns 404 or 410 is
   ignored, so a manual run overlapping the timer is safe.
5. **Rolling window.** 14 days back (so recent deletions get cleaned up) to 120 days ahead.
   Deletion only ever touches the target calendar inside that window.
6. **Never from a partial read.** If any source fails, that target is skipped and the run exits
   non-zero. Syncing a half-read would delete real busy time.

The worker runs it every 30 minutes, so availability stays current while the laptop is closed.
The controller runs `safety-net.sh` daily as a backstop for days the worker is down: same
script, same result. The controller is also where Calendar.app lives, so an EventKit-based
reader is possible there (see "macOS Calendar access" below), but you don't need one.

## Set it up

1. **Config.** Copy `scripts/config.example.json` to `~/.config/calendar-mirror/config.json`
   on every machine and fill in the time zone, the iCloud calendar names exactly as iCloud
   shows them, the Google calendar ids, and the two target calendar names.
2. **iCloud.** appleid.apple.com > Sign-In and Security > App-Specific Passwords. Save it as
   `~/.config/icloud/caldav.json`, `{"username": "<apple id>", "password": "<app-specific password>"}`,
   mode 600, on each machine, never committed.
3. **Google.** Create a service account in a Google Cloud project with the Calendar API
   enabled, download its JSON key to the path in the config (mode 600). In Google Calendar,
   share each source calendar with the service account's email ("See all event details"). A
   personal gmail.com calendar has to be shared by hand there; Workspace admins can do it in
   bulk. The service account needs **no domain-wide delegation**: it owns the two targets and
   only reads the sources. Keep it that way, so a routine sync never carries credentials that
   could rewrite other people's calendars.
   No service account? An OAuth client with your own account's refresh token works too. Swap
   the credential builder in `google_service()`.
4. **Targets.** `scripts/mirror.py bootstrap` creates both calendars, owned by the service
   account, and grants your account the roles in `access`. Accept the emailed invites.
   `scripts/mirror.py share <team-group>@<company>.com --scope group` shares the busy calendar.
5. **Timer on the worker.** Copy `scripts/systemd/calendar-mirror.*` to
   `~/.config/systemd/user/`, then `systemctl --user daemon-reload && systemctl --user enable --now calendar-mirror.timer`.
   `journalctl --user -u calendar-mirror -n 20` shows recent runs. Fix `WorkingDirectory` if
   your skills link somewhere else.
6. **Safety net on the controller.** Schedule `scripts/safety-net.sh` daily with your
   automation runner (the `automation` skill), and add both jobs to your automations registry.

Run `mirror.py sync --dry-run` first. It prints every `+` and `-` it would apply.

## Planning a week

Fill these in for yourself. Keep them in a `references/constraints.md` next to this file:

- Time zone `<tz>`. Plan one week at a time, Sunday to Saturday or whatever you use.
- Calendars: `<anchors calendar>` for fixed daily blocks (sleep, gym), `<work calendar>` for
  shifts, `<courses calendar>` for classes, `<personal calendar>` for everything else.
- Fixed commitments: shifts, appointments, classes, exams, deadlines.
- Anchors that never move: `<sleep block>`, `<training block>`. A late commitment overlaps an
  anchor; it never shifts it.
- Titles: short and stable (`Course <code>`, `<Job> Shift`, `DUE <thing>`), so the skip rules
  and the roster replace can match them.

Workflow:

1. Resolve the target week in `<tz>` and state the exact dates.
2. Read every calendar for that week (`cal list`). Existing commitments are fixed unless the
   user changes them. Read the Google work calendar too: its meetings are real.
3. Pull the roster for that week (below).
4. Draft the week in priority order: fixed commitments, then anchors, then what the user asked
   for by name. Leave travel and transition buffers. Don't fill empty time with filler blocks.
5. Find overlaps. Move flexible blocks, never a fixed commitment, and say what you moved.
6. Write only if the user asked to plan or change the calendar. A review or draft stays read-only.
7. Re-read the week and verify every event against the plan.
8. If you wrote anything, run `mirror.py sync --from <start> --to <end>` so the team sees it
   now instead of at the next timer run.

**Change requests** ("dentist Friday at 3"): add the fixed event with a travel buffer, find what
it displaces, rehome that, touch only the target week, verify.

**Availability questions** ("am I free Thursday afternoon?", "when can I meet X this week?"):
read every calendar for the range and answer from that, including the work calendar. Don't
answer from the mirror. It drops all-day events and deadlines on purpose.

## Shift roster

If your employer publishes shifts on a portal, script it once and keep the work calendar as an
exact copy of the portal:

```bash
<roster-command> --events <week> > /tmp/shifts.json                 # {"events":[{title,date,start,end,...}]}
scripts/cal delete --calendar <work calendar> --from <start> --to <end> --dry-run   # only shifts listed?
scripts/cal delete --calendar <work calendar> --from <start> --to <end> --confirm
scripts/cal add --calendar <work calendar> --json /tmp/shifts.json
```

Replace the week wholesale instead of diffing event by event. Lessons from a real portal:

- **An empty week is ambiguous.** An unpublished week can look exactly like a week off. Make
  the scraper flag it and refuse `--events` for it, so the wholesale replace can't wipe real
  shifts.
- **One login attempt per run, never a loop.** A few rapid failures can lock the account for
  hours. Cache the session (mode 600) and reuse it.
- Portals that compute a proof-of-work or reject headless user agents need a real headless
  browser with a normal Chrome user agent, not plain HTTP.
- Map the portal's job strings to a short title table. A job family not in it gets reported,
  not guessed.
- Portal credentials live in an untracked file, mode 600. Never print them.

## macOS Calendar access (only if you read through Calendar.app)

The scripts here don't need it. If you build an EventKit reader on the controller anyway:

- Calendar access is granted to the *responsible app* that launched the process (the terminal,
  T3 Code, the automation runner), not to the script.
- The Calendars toggle is two levels. **On** means *Add Only*: writes work and every read fails.
  Full Access is behind the row's **Options...** button.
- A wrapper can't escape a restricted host: a terminal launched by AppleScript from a
  restricted app inherits that app's grant.
- Never drive Calendar.app with `osascript`. It times out with AppleEvent error `-1712` even
  when Calendar is running. Importing a generated `.ics` file is the GUI fallback.

## Google Calendar traps

- **Group sharing grants access but subscribes nobody and sends no email.** A teammate shared
  through a group sees nothing until the calendar is added to their list
  (`calendarList.insert` as them, or "Add calendar > Subscribe").
- **A calendar has two names.** `calendars.summary` is the real title.
  `calendarList.summaryOverride` is a per-viewer rename that wins forever for that viewer.
  `bootstrap` finds targets by the real title, so rename the calendar and the config together,
  or it creates a duplicate.
- **ACL scope must match the address kind.** A group address shared as `user` is accepted and
  silently grants nobody.
- **Workspace super admins report `owner` on every calendar in the domain.** Never infer
  ownership from `accessRole`; read the ACL.
- **Never mirror an availability calendar.** Teammates' availability calendars subscribed in
  your Google account sync into Calendar.app too. Leave them off `publish_calendars`, or the
  mirror republishes their time under your name.
- **Changing `busy_title` rewrites every event id.** The next sync deletes and rebuilds the
  whole window. Safe, not free.
- **Time zones come from the `tzdata` package**, never the host. A stale host database
  shifted every block after a DST rule change by an hour and churned hundreds of events.

## Output

Lead with what changed: dates, fixed commitments, anything tight or compromised, and that the
calendar was re-read after writing. Keep it short. The calendar is the source of truth.
