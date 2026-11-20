---
name: reminders-mac
description: The user's Apple Reminders, from the macOS controller. Use whenever a task adds, reads, updates, completes or moves a reminder, when they say "remind me", "add a reminder", "look at my reminders", "what's on my list", or when a plan leaves follow-up tasks for them or an agent to do later.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin]
  scope: controller
  requires: "osascript and the Reminders app, with Automation access to Reminders granted to the app running the agent"
---

# Reminders

On a worker, use **reminders-worker** instead (same rules, over ssh to this machine).

## Lists

Decide on a small set of lists and write them here, so every agent files things the same way. The
author uses two:

| list | for |
| --- | --- |
| `<Personal>` | errands and life: health, shopping, plans with friends |
| `<Agent and me>` | everything else: project and work tasks, for the user or an agent |

## Name format

`<task> - <WHO> - <PROJECT>`:

- `WHO` is `ME` when only the user can do it (in person, their accounts, their money), or `AGENT`
  when an agent can. If the agent needs their OK first (sending a message, posting, a consent
  screen, anything outward facing), say so: `AGENT (needs your OK to send)`.
- `PROJECT` is the T3 project or area it belongs to. Uppercase, one word.

Example: `Reply to the landlord about the lease - AGENT (needs your OK to send) - PERSONAL`

Put what an agent needs in the notes: where the draft lives, current status, the fallback. Set a
due date when there is one.

## osascript

```bash
osascript -e 'tell application "Reminders" to get name of (reminders of list "<list>" whose completed is false)'
```

```bash
osascript <<'OSA'
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
- Build due dates from a `date` object as above, never from a string (locale parsing bites).
- The first run asks for Automation permission for whatever app launched osascript. Ask the user
  to allow it; don't work around it.
