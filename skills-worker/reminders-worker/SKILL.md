---
name: reminders-worker
description: The user's Apple Reminders from a Linux worker. Use whenever a task adds, reads, updates, completes or moves a reminder, when they say "remind me", "add a reminder", "look at my reminders", "what's on my list", or when a plan leaves follow-up tasks for them or an agent to do later.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [linux]
  scope: worker
  requires: "an ssh alias for the macOS controller; the controller awake, with Remote Login on and Reminders automation allowed for sshd"
---

# Reminders from a worker

Reminders has no API a Linux box can use well: iCloud CalDAV exposes only legacy, pre-upgrade
lists, not the ones the Reminders app shows today. So a worker drives the Reminders app on the
controller with `osascript` over `ssh <controller>`.

**The lists and the name format live in the reminders-mac skill** (in `skills-controller/` of the
fleet repo, so it isn't linked here; read the file). The rules are the same on every machine.

## Mechanics

Pipe the AppleScript on stdin so nothing needs double quoting through ssh:

```bash
ssh <controller> osascript - <<'OSA'
tell application "Reminders" to get name of (reminders of list "<list>" whose completed is false)
OSA
```

```bash
ssh <controller> osascript - <<'OSA'
tell application "Reminders"
  set d to current date
  set year of d to 2026
  set month of d to 12
  set day of d to 3
  set time of d to 9 * hours
  make new reminder at end of list "<list>" with properties {name:"Task - AGENT - PROJECT", body:"context for the agent", due date:d}
end tell
OSA
```

- `it` and `items` are reserved words in AppleScript; don't use them as loop variables.
- Build due dates from a `date` object as above, never from a string.
- The first ssh-driven call needs Automation permission for `sshd-keygen-wrapper` (or similar)
  to control Reminders. The user grants it once on the controller.
- If `ssh <controller>` fails, the laptop is asleep or off the tailnet. Tell the user; don't queue
  the reminder anywhere else.
