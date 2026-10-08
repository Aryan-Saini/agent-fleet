# Peekaboo

Peekaboo is the second way to drive the screen. It's a macOS CLI that sees the screen and
clicks, types and presses keys. Claude runs it straight from bash, with no Codex and no
ChatGPT.app, so it still works when Codex is out of usage.

## When to use it

- **The user says "peekaboo".** Use it, even if Codex is available.
- **Codex is out of usage.** `cu_run` fails, or its report says the usage or rate limit was
  hit. Switch to Peekaboo for the rest of the task rather than waiting.
- Otherwise, Codex stays the default for GUI work. Peekaboo puts every step on Claude: find
  the element, work out the coordinates, click, check. Codex does that loop itself.

Everything else in SKILL.md still applies: bash before the GUI, osascript to read a
browser, one GUI run at a time, and close what you opened.

## Setup

Install and permissions: `packages/peekaboo/README.md` in the fleet repo. Check grants with
`peekaboo permissions status`.

Run from T3 Code or Terminal, it inherits that app's Screen Recording and Accessibility
grants, so nothing prompts.

Commands moved in v4. `peekaboo image` is now `peekaboo see --no-elements`. `peekaboo list` is
now `peekaboo window list` or `peekaboo app list`. `peekaboo learn` prints the full current
guide.

## Look

```bash
peekaboo window list --app "Brave Browser"                            # windows, ids, positions
peekaboo see --window-id <id> --no-elements --path /tmp/w.png          # screenshot one window
screencapture -x /tmp/screen.png                                       # the whole screen
```

Then `Read` the PNG. A screenshot shows up in Claude scaled down, and the tool tells you the
factor. Screen points are the PNG's pixels divided by 2 on a Retina display. Use points for
clicks.

`peekaboo see --app <App>` also lists accessibility elements you can click by ID
(`peekaboo click --on <id>`). It fails when the app's windows are minimized, or are on another
Space. Chromium browsers often show `no_matching_accessibility_window` too.

## Click, the way that works

Google sign-in, consent screens and most anti-bot pages reject a JavaScript `el.click()`,
because the event isn't trusted. Background accessibility clicks can report success while the
page doesn't move. What does work is a real mouse event at global screen coordinates, with the
app in front:

```bash
peekaboo click --foreground --global --at 485,560 --input-strategy synthOnly
```

For a browser, don't guess coordinates from a screenshot. Ask the page, then add the window's
position. **Brave reports fake `window.screenX` and `screenY`**, an anti-fingerprinting
feature. Take the window's origin from AppleScript's `bounds` instead:

```bash
# Center of the visible element whose text is "Continue", in global screen points.
osascript <<'EOF'
tell application "Brave Browser"
  set w to front window
  set b to bounds of w                     -- {left, top, right, bottom}, real values
  set r to execute (active tab of w) javascript "(()=>{
    const e=[...document.querySelectorAll('a,button,span,div,label,input')]
      .filter(e=>e.getBoundingClientRect().width>0 && (e.innerText||e.value||'').trim()==='Continue').pop();
    e.scrollIntoView({block:'center'});
    const r=e.getBoundingClientRect();
    return Math.round(r.x+r.width/2)+','+Math.round(r.y+r.height/2)+','+innerHeight })()"
  return r & "," & (item 1 of b) & "," & (item 4 of b)
end tell
EOF
# x = left + cx      y = bottom - innerHeight + cy
```

Scroll the element into view first. A button below the fold gives a y past the bottom of the
screen, and the click lands on whatever is there. A click once went to the Dock that way.

After every click, read the page again (`document.body.innerText` through osascript) and decide
the next step from what's actually there.

## Type and press

```bash
peekaboo type "hello" --app TextEdit            # into a specific app
peekaboo type "hello" --foreground              # into whatever has focus
peekaboo press cmd+shift+t --foreground
```

Never type a password or a 2FA code. The user does those.

## Rules that bite

- **The user's screen is live.** A `--foreground` click goes wherever the mouse is when it fires.
  If they are using the machine, it lands in their window. Before a foreground run, ask them to
  keep their hands off, and wait for a yes.
- **Bring the window forward first.** Clicks go to whatever is on top. For a browser, use
  AppleScript: `set index of window id <id> to 1`, `set active tab index`, `activate`. That also
  switches Spaces if it needs to. `peekaboo window focus` can't find windows on another Space.
- **One flow at a time.** Drive one tab start to finish before the next. Several flows fighting
  over one mouse is how clicks end up in the wrong place.
- **Stop at anything only the user can do.** Passkeys, "Verify it's you", 2FA and password fields.
  Poll the page every few seconds and carry on once it moves past that screen.

## A full example

A multi-account OAuth consent run, driven this way. Each step read the page text, matched a
stage, and clicked the one element for that stage:

| Page says | Click |
| --- | --- |
| "Google hasn't verified this app" | `Advanced` |
| "Go to <app> (unsafe)" visible | that link |
| "Sign in to <app>" | `Continue` |
| a list of permissions with "Select all" | `Select all`, then `Continue` |
| "Verify it's you", passkey | nothing. Wait for the user |
| "The authentication flow has completed" | done |
