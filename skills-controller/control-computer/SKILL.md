---
name: control-computer
description: REQUIRED before touching a browser or the screen by any means. Covers reading a page, clicking, and operating a Mac application.
metadata:
  harness: [claude]
  platform: [darwin]
  requires: 'osascript for the browser path; the Codex CLI, a running ChatGPT.app, and its Computer Use plugin for GUI work; peekaboo (packages/peekaboo) as the fallback'
---

# Control computer

Work down this table and stop at the first row that fits. It runs cheapest to most expensive,
and a GUI run is the most expensive thing here: it costs minutes and can fail silently, where a
CLI call takes seconds and returns a real exit code.

| Task | Use |
| --- | --- |
| Test results, build output, logs | **bash** |
| System state: processes, disk, files, network | **bash** |
| Anything with a CLI or API | **that CLI.** `gh`, `aws`, a cloud provider's CLI, all beat clicking |
| Anything another skill already owns | **that skill.** Several wrap a real binary or API and have solved the GUI problem already |
| A public web page's content | **`curl`** or `WebFetch` |
| Read a tab the user already has open: title, URL, `document.body.innerText` | **osascript**, below |
| Run a one-off JS expression and read the result | **osascript** |
| A site the user is logged into | **a browser**. The session is the point |
| Click, type, log in, or complete a flow in a browser | **Codex** |
| Anything in a native app: Finder, Xcode, Simulator, System Settings, Mail | **Codex, always** |
| Anything with a screenshot as the deliverable | **Codex** |

The rule in one line: **script it if you can, osascript to read, Codex to do, and applications
are always Codex.**

**Peekaboo instead of Codex** in two cases: the user says "peekaboo", or Codex is out of usage
(`cu_run` fails, or its report says the usage or rate limit was hit). Peekaboo is a CLI Claude
drives from bash with real mouse and keyboard events. How to use it, and the traps:
**[references/peekaboo.md](references/peekaboo.md)**.

**Before using Computer Use, check whether basic bash commands such as `open`, `cd`, or `ls`
can complete the task. If they can, use them. Only use Computer Use when the task genuinely
requires seeing or interacting with the GUI.**

Reach for the screen only when the answer genuinely lives there: the page is client-rendered,
the app has no scripting interface, the check needs real layout, or the user asks to *see* something.

Use the `chrome-devtools` or `playwright` MCPs only when the user names them: they drive a separate browser, not the session the user is logged into.

## Reading a browser

Chrome, Brave and any other Chromium browser share one osascript interface, so swap the
application name and everything else is identical.

Enumerate before you act. Never open a window or tab.

```bash
osascript -e 'tell application "Google Chrome"
  set out to ""
  set wi to 0
  repeat with w in windows
    set wi to wi + 1
    set ti to 0
    repeat with t in tabs of w
      set ti to ti + 1
      set out to out & wi & ":" & ti & "  " & (title of t) & "  |  " & (URL of t) & linefeed
    end repeat
  end repeat
  return out
end tell'
```

That prints `window:tab` indices. Use them to read any tab without focusing it:

```bash
osascript -e 'tell application "Google Chrome" to execute (tab 3 of window 2) javascript "document.title"'
```

The front tab, when that is clearly the one they mean:

```bash
osascript -e 'tell application "Google Chrome" to execute front window'\''s active tab javascript "document.body.innerText"'
```

Bring a tab forward, only when the user asked you to show them something:

```bash
osascript -e 'tell application "Google Chrome"
  set index of window 2 to 1
  set active tab index of window 2 to 3
  activate
end tell'
```

If no open tab matches what the user is referring to, ask which one. Do not guess and do not open
anything.

**Stop here and switch to Codex the moment the task needs a click.** `execute javascript` can
fake one, but it bypasses the real event path, so a passing result proves nothing about what a
person would experience.

## Codex Computer Use

Everything else. Codex drives the real screen through the `cua` runtime (the `cua_repl` MCP
server's `js` tool), so it works on any app, not just browsers.

This interface is versioned and it moves. The older `computer-use:computer-use` skill with
`node_repl` + `@oai/sky` is gone: that plugin now ships an empty `skills/` directory, so a
prompt naming it gets an honest BLOCKED. If a run comes back BLOCKED on a missing capability,
read the current contract in
`~/.codex/plugins/cache/openai-bundled/unified-computer-use/*/resources/js-tool-description.md`
and `.mcp.json` beside it, then update the routing block below to match.

The rename is API-level only. Underneath, the same Sky service still drives the screen, so
every path and process name here (`SkyComputerUseService`, `node_repl`, the `CU_SKYCLIENT`
teardown) is current, verified against a live run.

Paste the helpers once per session, then a run is three calls.

```bash
# --- control-computer helpers ---
cu_ready(){ pgrep -x ChatGPT >/dev/null || { open -ga "ChatGPT"; sleep 3; }; }
cu_new(){ export CU_ART="$(mktemp -d "${TMPDIR:-/tmp}/codex-cu.XXXXXX")"; echo "$CU_ART"; }
cu_run(){ codex exec -C "$PWD" --skip-git-repo-check --add-dir "$CU_ART" -c model_reasoning_effort=low \
            -s danger-full-access -o "$CU_ART/report.md" "$(cat "$CU_ART/prompt.md")" </dev/null; \
          cat "$CU_ART/report.md"; }
CU_SKYCLIENT="$HOME/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
```

```bash
cu_ready                # ChatGPT.app must be running; starts it without stealing focus
cu_new                 # prints $CU_ART; write your prompt to $CU_ART/prompt.md
cu_run                 # one shot, prints the report
```

Low reasoning effort is the default. `-s danger-full-access` is required for GUI work; drop to
`-s workspace-write` for a non-GUI check.

### The routing block

Paste this at the top of every prompt, unchanged. Without it Codex quietly routes to its
Browser or Chrome skill and you get a different, worse thing.

```text
Use Computer Use for every GUI interaction, driven through the persistent `js` tool of the `cua_repl` MCP server (the `cua` API). The session is persistent across calls; `js_reset` clears it.

Your FIRST `js` call must be exactly one API call and nothing else. No extra calls, waits, or snapshots. Use `await cua.getApp("<App Name>")` when the task names an app, or `await cua.getState()` for an inventory of every app, browser, and tab. That first result returns the live API documentation. READ IT before continuing, and use only APIs it describes.

Do NOT use the Browser skill, Chrome skill, browser-client runtime, Playwright, Selenium, AppleScript, osascript, JXA, System Events, or shell-based GUI automation.

After every UI action or short action sequence, re-read state before deciding what to do next, and re-derive element references from that fresh state rather than reusing stale ones.

If the `js` tool or the `cua` API is unavailable, return BLOCKED and identify the missing capability. Do not silently substitute another automation mechanism.
```

Never write "whatever method is available" or list alternative automation tools. That phrasing
is exactly what lets Codex route away from Computer Use.

### What else the prompt needs

Name the app by display name or bundle identifier. Give the exact flow, the repo path, launch
commands or test credentials, where to write screenshots, and ask for pass / fail / blocked
plus the steps performed. Default to no source edits. Write it so Codex never needs this
conversation.

For a browser task, tell it to **enumerate every open browser and its tabs first** and reuse a
tab that already has the site open and logged in. Opening a new browser is a last resort.

Tell it to record what was already open before it starts, and to close only its own additions
before it finishes.

### Only if you are opening a new browser or tab

Reusing something already open is always the answer when it exists. Only when nothing open has
what you need, open a new window in the profile the task belongs to, named by its directory
(`--profile-directory="Profile 1"`), not by its display name, which users rename. If the right
profile is not obvious, ask.

### Preflight

Two things kill a run before it starts, and both fail the same opaque way.

**ChatGPT.app must be running.** Computer Use is driven by the Sky service, which is signed in
through ChatGPT.app. Quit it and every `cua` call dies exactly like a locked screen does, with
no hint that auth is the cause. `cu_ready` handles this; check by hand if you skipped it:

```bash
pgrep -x ChatGPT >/dev/null && echo running || open -ga "ChatGPT"
```

Leave it running when the run ends. It is not something a run "opened". See below.

**The screen must be unlocked.**

A locked screen is the top cause of a dead GUI run: every state call times
out with `Computer Use server error -10005: timeoutReached`, on every app, no matter how
you name it. Check before launching, and check again if you see that error:

```bash
ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers json -o - - | grep -o '"CGSSessionScreenIsLocked":[a-z]*'
```

No output means unlocked. `true` means locked. Do not start (or retry) a GUI run.
`caffeinate -u` wakes the display but cannot unlock it; only the user can. Say the
screen is locked and wait.

### If captures come back empty mid-session

A different failure from the lock-screen timeout: `get_app_state` succeeds but returns
**no accessibility content and no screenshot** for an app that captured fine minutes
earlier. The Sky service is wedged. Fix from bash, then retry the run:

```bash
pkill -f SkyComputerUseService
```

It relaunches on demand and the next capture works.

### Two rules that bite

**One GUI run at a time.** Several Codex sessions can run in parallel, but there is one screen,
one mouse, one keyboard, and parallel GUI runs fight over focus. Non-GUI Codex runs are fine
alongside a single Computer Use run.

**Always tear the session down when `cu_run` returns.** This runs on every path out of a run,
a clean pass, a failure, a BLOCKED report, an abandoned attempt. Signal the turn ended, then kill
the session. Otherwise the
translucent Sky cursor sits on screen and the service plus its `node_repl` children stay
resident, holding accessibility state that makes the next run flaky:

```bash
"$CU_SKYCLIENT" turn-ended '{"type":"agent-turn-complete"}' 2>/dev/null
pkill -f SkyComputerUseService
pkill -f "cua_node/bin/node_repl"
```

Both relaunch on demand, so killing them costs nothing and the next `cu_run` starts clean.
Confirm nothing is left behind:

```bash
ps axo pid,etime,command | grep -E "SkyComputerUseService|node_repl" | grep -v grep
```

The one time to hold off: another Codex GUI session is genuinely mid-run. These processes are
shared, so check `etime` against your own run before killing. A much younger process than
yours belongs to someone else.

### Close what you opened

Leave the screen the way you found it. A browser window, a tab, a Terminal, a Simulator,
System Settings, anything a run opened only to read or screenshot, gets closed before you
report. If the run launched the app itself and it had no windows before, quit the app too.

Four things stay open:

- **ChatGPT.app.** Computer Use needs it. Never quit it in teardown, even if your run started it.
- **It was already there.** You reused a tab or a window that existed before the run. Never
  close it, and never close the window holding it.
- **The user asked to see it.** Anything opened so the user can look at it stays up. Say so in the report.
- **Another GUI run is using it.** Check before closing, same as the process teardown.

This is why you enumerate windows and tabs before you open anything. That list is how you know
at the end which ones were yours.

Navigation is not opening. If you drove a tab the user already had open somewhere else, leave it
where it is. Do not try to restore the old URL and lose their place.

### If you need a terminal

Terminal.app refuses to close a window while a process is still running in it, silently, so let
the command finish before closing.

## When a run needs a live confirmation

Computer Use raises a confirmation immediately before a consequential action, creating a key,
deleting data, sending a message, changing a setting. `codex exec` is one shot and cannot answer
it, so that run stalls.

Usually you can remove the gate rather than answer it. The per-app "Allow Computer Use to use
&lt;App&gt;?" prompt is the only hard one: run it interactively once, choose **Always allow**
(`Down Down Enter`), and every later run on that app is headless. The model's own "shall I go ahead?" pause is just caution, so pre-authorize it in the prompt:

```text
You are fully pre-authorized by the user for THIS exact action (<name it>).
Do NOT ask for confirmation or a go-ahead. Perform it and print the result.
```

With both in place a consequential run completes under plain `cu_run`.

If a hard gate still fires every time, drive a live session instead of handing the user a command.
That is **[references/interactive.md](references/interactive.md)**: the tmux helpers, the
background watcher that avoids token-burning polling, the auto-forward guardrails, and how to
clear a ghost cursor left by an abrupt exit.
