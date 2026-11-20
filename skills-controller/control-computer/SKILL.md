---
name: control-computer
description: REQUIRED before touching a browser or the screen by any means. Covers reading a page, clicking, and operating a Mac application.
metadata:
  harness: [claude]
  platform: [darwin]
  scope: controller
  requires: "osascript for the browser path; Cua Driver (CuaDriver.app plus the cua-driver CLI, see the cua-driver skill) for everything else; peekaboo (packages/peekaboo) as an optional fallback"
---

# Control computer

Work down this table and stop at the first row that fits. It runs cheapest to most expensive,
and a GUI run is the most expensive thing here: it costs minutes and can fail silently, where a
CLI call takes seconds and returns a real exit code.

| Task | Use |
| --- | --- |
| Test results, build output, logs | **bash** |
| System state: processes, disk, files, network | **bash** |
| Anything with a CLI or API | **that CLI.** `gh`, a cloud provider's CLI, all beat clicking |
| Anything another skill already owns | **that skill.** Several wrap a real binary or API and have solved the GUI problem already |
| A public web page's content | **`curl`** or `WebFetch` |
| Your own app inside T3 Code: load a dev server or preview URL, click through, screenshot, console | **T3's `preview_*` tools.** Headless, built in |
| Your own app in iOS Simulator or Android Emulator, inside T3 Code | **T3's `device_*` tools**, then the `agent-device` command `device_open` returns |
| Read a tab the user already has open: title, URL, `document.body.innerText` | **osascript**, below |
| Run a one-off JS expression and read the result | **osascript** |
| A site the user is logged into | **a browser**. The session is the point |
| Click, type, log in, or complete a flow in a browser | **Cua Driver** |
| Anything in a native app: Xcode, System Settings, Mail, Numbers | **Cua Driver** |
| Anything with a screenshot as the deliverable | **Cua Driver** (`--screenshot-out-file`) |

The rule in one line: **script it if you can, osascript to read, Cua Driver to do.** File moves
and renames are `mv`, never Finder.

Reach for the screen only when the answer genuinely lives there: the page is client-rendered,
the app has no scripting interface, the check needs real layout, or the user asks to *see*
something. Use the `chrome-devtools` or `playwright` MCPs only when the user names them: they
drive a separate browser, not the session the user is logged into.

## Reading a browser

Chrome, Brave and any other Chromium browser share one osascript interface, so swap the
application name and everything else is identical. Enumerate before you act. Never open a window
or tab to read.

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

That prints `window:tab` indices. Read any tab without focusing it:

```bash
osascript -e 'tell application "Google Chrome" to execute (tab 3 of window 2) javascript "document.title"'
osascript -e 'tell application "Google Chrome" to execute front window'\''s active tab javascript "document.body.innerText"'
```

Bring a tab forward only when the user asked you to show them something:

```bash
osascript -e 'tell application "Google Chrome"
  set index of window 2 to 1
  set active tab index of window 2 to 3
  activate
end tell'
```

If no open tab matches what the user means, ask which one. Do not guess and do not open anything.

**Switch to Cua Driver the moment the task needs a click.** `execute javascript` can fake one,
but it bypasses the real event path, so a passing result proves nothing about what a person
would experience.

## Cua Driver

[Cua Driver](https://github.com/trycua/cua) (by trycua) drives apps **in the background**: it
acts on a target pid through Accessibility, so the user keeps the keyboard, mouse and focus while
it works, and several runs can go at once. Drive it yourself, from bash (`cua-driver call <tool>
'<json>'`) or through its MCP server (`cua-driver mcp`, same tools). No delegation. Install and
the upstream skill: the **cua-driver** skill.

The author benchmarked it against Peekaboo and Codex Computer Use on the same Mac: same or better
pass rate, 3 to 7 times faster, and no focus steals on everything it could do in the background.

### The loop

Snapshot, act by element token, verify at checkpoints.

```bash
cua-driver call list_apps                                    # running apps + pids
cua-driver call list_windows '{"pid":844}'                   # window ids
cua-driver call get_window_state '{"pid":844,"window_id":10725}' --screenshot-out-file "$TMPDIR/s.png"
cua-driver call get_window_state '{"pid":844,"window_id":10725,"query":"Next week"}'   # filter the AX tree
cua-driver call run_steps '{"steps":[{"tool":"click","args":{"pid":844,"window_id":10725,"element_token":"s0000002a:12"}}],"observe":{}}'
cua-driver call verify_state '{"pid":844,"window_id":10725,"expect":[{"element":{"selector":{"label_contains":"Saved"},"exists":true}}]}'
```

- **Read narrowly.** `get_window_state` with a `query` returns the matching part of the AX tree.
  Re-read with `since:"latest"` to get only what changed. Read the screenshot file when layout
  matters.
- **Act on element tokens, not coordinates.** Row `[N]` in a snapshot is `<snapshot_id>:N`.
  Tokens go stale once the window changes, so re-read before acting again. Pixels only for
  surfaces missing from the tree.
- **Batch through `run_steps`**, even for one step. It stops at the first failure and returns what
  changed. Loops, branches or retries go in one `run_script` call.
- **Verify at checkpoints** with `verify_state`. `unknown` and `effect:"unverifiable"` are not
  success.
- `set_value` / `type_text` fill fields, `invoke_menu` runs a menu path (`["Edit","Copy"]`),
  `launch_app` opens an app without focusing it, `set_window_frame` sets exact geometry.
- `cua-driver call get_guide '{"topic":"overview"}'` (also `browser`, `menus`, `batching`, `drag`,
  `permissions`) is the driver's own manual. `cua-driver list-tools` lists every tool.

### Browser pages

Chromium pages have typed tools: `get_browser_state`, then `browser_click`, `browser_type`,
`browser_pointer` (hover, drag), `browser_navigate`. They attach over CDP, which needs the daemon
started with consent to use existing browser profiles (`--grant existing-profile`, then a
`browser_prepare` approval; a refusal's `detail.next_call` names the exact call). That consent exposes every logged-in
profile, so the author leaves it off and drives browsers through the AX tree like any app; that
passed every non-upload browser task in the benchmark. Turn it on only if you accept that trade.
When a browser tool refuses with a consent error, fall back to the AX tree rather than granting.

### Preflight

```bash
cua-driver status                  # "daemon is running"; if not: open -ga CuaDriver
cua-driver permissions status      # Accessibility + Screen Recording must say granted
```

`permissions_pending` or `unknown` with grants already given means the daemon started before the
grant: `cua-driver stop`, then `cua-driver permissions grant`. Ask the user before approving any
permission prompt. A locked screen kills captures too:

```bash
ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers json -o - - | grep -o '"CGSSessionScreenIsLocked":[a-z]*'
```

`true` means locked. Only the user can unlock it; say so and wait.

### Background only, unless the user is away

Every action defaults to background delivery. Some things refuse it, and Cua then offers
`"delivery_mode":"foreground"` or `bring_to_front`. **Foreground input takes over the user's
screen**: keystrokes land in whatever they are typing in. Use it only when they asked, or when
they are away (`ioreg -c IOHIDSystem | awk -F'= ' '/HIDIdleTime/{print $2/1e9; exit}'` above
~120 s). Otherwise stop and say which step needs the foreground.

Known to need the foreground: **native file pickers** (any upload) and **Finder renames and
moves** (use `mv` instead).

### Traps

- **The clipboard is the user's.** Copy steps (`hotkey cmd+c`, `invoke_menu Edit > Copy`) can
  silently fail in the background, and the next paste then uses whatever the user had copied. In
  the benchmark that moved one of the author's real files. Before any paste, set the clipboard
  yourself with `clipboard_write` and check it with `clipboard_read`.
- **Autocorrect in Numbers, Pages and TextEdit** rewrites typed text. Read the cell back after
  typing; prefer `set_value` over typed keys.
- **Memory.** The daemon idles around 600 MB and has spiked to 8 GB on file-picker tasks.
- **Telemetry.** Check `~/.cua-driver/config.json` and turn telemetry off if you don't want it.

### Parallel runs

Background runs on different apps or windows can go in parallel (a browser booking and a
spreadsheet edit at once, no interference). Two runs must never drive the same window.
Foreground steps are one at a time.

### Close what you opened

Leave the screen the way you found it. A browser window, a tab, a Terminal, a Simulator, System
Settings, anything a run opened only to read or screenshot, gets closed before you report. If the
run launched the app and it had no windows before, quit the app too.

Three things stay open: anything **already there** before the run (never close it or the window
holding it), anything **the user asked to see** (say so in the report), and anything **another run
is using**. Enumerate windows (`list_windows`) and tabs before you open anything; that list is how
you know at the end which ones were yours. Navigation is not opening: a tab the user already had
open stays where you left it.

### Only if you are opening a new browser or tab

Reusing something already open is always the answer when it exists. Otherwise open a window in
the profile the task belongs to, named by its directory, not its display name (which users
rename). `-g` keeps it in the background:

```bash
open -gna "Google Chrome" --args --profile-directory="<Profile N>" "https://example.com"
```

If the right profile is not obvious, ask. Never start a second instance of a browser the user
already runs (`open -n` on Firefox-family browsers, a new `-P` profile): it gets its own Dock icon
and hides their real one.

### If you need a terminal

Use Terminal.app. It refuses to close a window while a process is still running, silently, so let
the command finish before closing.

## Alternative: Peekaboo

[Peekaboo](https://github.com/steipete/Peekaboo) drives the real screen with real mouse and
keyboard events. It steals focus, so it is a fallback: when Cua Driver is not installed, or the
user says "peekaboo". How to use it and its traps:
**[references/peekaboo.md](references/peekaboo.md)**. Install: `packages/peekaboo`.
