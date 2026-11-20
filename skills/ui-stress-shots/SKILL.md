---
name: ui-stress-shots
description: Break a UI with worst-case data, then prove it with before/after screenshots, on web or mobile. Loads Emil Kowalski's break-ui (from ui-craft) to build the worst-case fixtures and hunt the breaks, then adds the proof half, a dev-only stress harness, a DOM overflow probe, and repeatable captures through Playwright at phone and desktop widths (web) or the iOS Simulator and Android emulator (Expo / React Native). Use when the user says something "bleeds off the screen", is "cut off", "overflows", "doesn't fit on mobile", asks to stress-test or "try the worst case", when a layout must be proven at a long-string edge case, or when a PR needs before/after screenshots of a UI change.
disable-model-invocation: true
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "the ui-craft skill with its guides fetched; Playwright in the target repo for web; Xcode simulators or the Android SDK for mobile (darwin)"
---

# UI stress shots

Two halves:

1. **Break it.** Read `../ui-craft/emil/break-ui/GUIDE.md` and its `CATALOG.md` (upstream:
   [emilkowalski/skills, break-ui](https://github.com/emilkowalski/skills/tree/main/skills/break-ui)).
   Run its phases 1 to 4: map every rendered value and its real limit, build one worst-case
   fixture from the catalog (plus Empty / One / Huge), wire the **Demo / Worst case** switch at
   the data boundary, and look for each failure signature. Skip its "Initial Response" greeting.
   Its rules hold here, especially *change the data, not the component* and *report before fixing*.
2. **Prove it.** This file. Break-ui's dev-only switch becomes the stress harness: every scene is
   a pure function of the fixtures, so two captures across a code change differ only where the
   code did. No live data, no session, no clock.

Pick the platform from the repo: `expo` or `react-native` in `package.json` means mobile,
otherwise web. An Expo app that also runs on web gets a cheap first pass from the web probe
(`npx expo start --web`), but native text metrics differ, so the simulator shots are the proof.

## Do it in this order

1. **Reproduce before you fix.** Build the harness and get a failure for each surface the user
   pointed at: a `BLEED` line from the probe on web, a screenshot on mobile. If the probe says
   `ok` where the user says it bleeds, the harness is wrong. Check its container widths against
   the real shell.
2. **Report** the breaks with a proposed fix each (break-ui's output format), then stop unless
   the user already asked for the fix.
3. **Capture "before" by stashing only the fix.** `git stash push -- <the app files you changed>`,
   leaving the harness and scripts in the tree. Capture, pop, capture "after". This is the only
   way both shots come from the same harness.
4. **Fix, then re-run.** All `ok` from the probe (web), or a clean pass over break-ui's failure
   signatures at the smallest device and largest text size (mobile), is the acceptance
   criterion. The screenshots are for the reader.

## Web: Playwright

```
app/(dev)/ui-stress/           # dev-only route, own root layout, no auth provider
  page.tsx                     #   404s outside `next dev`; ?scene=... picks a surface
  Stress.tsx                   #   client component: one scene per surface
  stress-fixtures.ts           #   break-ui's worst-case fixture, copied, not imported
scripts/screenshots/
  capture.mjs                  # boots the dev server, screenshots each scene x viewport
  overflow.mjs                 # the probe: names what is cut off, exits 1 if any
```

`templates/` has all of it: `capture.mjs` and `overflow.mjs` to copy and adjust (`SCENES`,
`VIEWPORTS`, the env block), and `harness-route.md` with the three route files and the two
non-obvious bits in them, the stub backend provider and the mount gate. The templates come from
a Next 16 + Clerk + Convex app. Copy fixture values rather than importing them when the source
module pulls in a backend client.

### Web gotchas that cost an hour each

- **Next 16: never pass `--hostname 127.0.0.1`.** `next dev` fronts the real server with a proxy
  that dials `localhost`. Pinning the inner one to the IPv4 literal leaves them unable to reach
  each other, and every request hangs 30 s and dies as `socket hang up`. Pass `--port` only.
- **Auth middleware eats the harness.** `clerkMiddleware` (or similar) throws without keys,
  taking the dev server down, and with fake keys it redirects to a handshake, so you screenshot
  the auth provider's error page. Fix both: pass a syntactically valid dummy key *and* skip the
  middleware for the harness path in dev. A Clerk test key is `pk_test_` + base64 of
  `something.clerk.accounts.dev$`.
- **A `fixed` overlay inside a transformed ancestor is not fixed.** A card that animates in with
  a transform becomes the containing block, so a modal opened from inside it is laid out within
  the card. Render dialogs through `createPortal(..., document.body)`.
- **`break-words` is not enough.** `overflow-wrap: break-word` wraps the text but does not shrink
  the element's `min-content` width, so a flex or grid parent still sizes itself to the unbroken
  string and blows past `max-w-*`. Use `wrap-anywhere` (`overflow-wrap: anywhere`, Tailwind 4.1+)
  and `min-w-0` on the box that must shrink.
- **Two `display` utilities fight silently.** In `block line-clamp-3` the clamp sets
  `display: -webkit-box`, and whichever Tailwind emits last wins. Drop the redundant one.
- **A cap wider than the phone is not a cap.** `max-w-[30rem]` on a 390 px screen does nothing.
  Make it responsive (`max-w-[13rem] sm:max-w-[30rem]`).
- **Touch has no hover.** A hover-only recovery path (a tooltip over clamped text) does not exist
  on the device where the clamp bites hardest. Pair it with a tap route such as a bottom sheet,
  gated on `event.pointerType !== "mouse"` rather than `(hover: none)`, because a touchscreen
  laptop is both.

### Writing the probe

"Anything whose right edge is past the viewport" is useless on a shell that is
`overflow-hidden` from the body down: nothing ever exceeds the viewport, it just gets cut.
Measure against **the nearest clipping ancestor** instead, and exempt exactly one thing: a box
with `text-overflow: ellipsis`, which overflows by design. Everything else that runs past its
clipper is a defect. `templates/overflow.mjs` does this.

### Capture settings that matter

- `deviceScaleFactor: 2`. A 1x screenshot of small type is unreadable in a PR.
- `isMobile: true, hasTouch: true` on the phone context, or `(hover: none)` rules and `.tap()`
  won't behave like a phone.
- Route-block third-party image services (favicons, avatars) so a capture doesn't depend on them.
- `waitUntil: "networkidle"` plus about 900 ms for entry animations to settle.
- Give a scene an optional `act(page)` step for states a URL can't express (open a sheet, focus a
  field). Have it return `false` when it finds nothing, so the same script runs against a
  revision that predates the feature and skips that shot. That is what makes a before/after
  pair possible.

## Mobile: iOS Simulator and Android emulator

No DOM, so no probe. The screenshot is the evidence, and the acceptance pass is break-ui's
failure signatures checked by eye on each capture. Capture the worst combinations, not every one.

**Harness.** A dev-only Expo Router screen, `app/(dev)/ui-stress.tsx`, that renders
`<Redirect href="/" />` unless `__DEV__`, reads `scene` (and break-ui's `data` switch) from
`useLocalSearchParams`, and renders the real component with the fixture swapped at the data
boundary. Stub auth and the backend as on web. Open a scene by deep link with `expo.scheme`
from `app.json`:

```bash
xcrun simctl openurl booted "<scheme>://ui-stress?scene=results&data=worst"
adb shell am start -a android.intent.action.VIEW -d "<scheme>://ui-stress?scene=results&data=worst"
```

**Devices.** The smallest and the largest phone, not the default: an iPhone SE (375x667, no
notch) and a Pro Max on iOS, a small and a large emulator on Android.
`xcrun simctl list devices available` shows what is installed. Inside T3 Code, `device_list`
and `device_open` put the device in the Device panel so the user can watch.

**Make every capture repeatable**, the same way the web harness drops the clock and session:

```bash
# iOS
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl ui booted appearance dark
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large   # reset with `large`
xcrun simctl io booted screenshot before/results-se-ax.png

# Android
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb shell cmd uimode night yes
adb shell settings put system font_scale 2.0                               # reset with 1.0
adb exec-out screencap -p > before/results-small-ax.png
```

Shoot each scene at default text size and at the largest accessibility size, where clamps, rows
and fixed-height buttons break. Name files `<scene>-<device>-<size>.png` so pairs match by name.
Metro hot-reloads on `git stash` and `pop`. Wait for the reload, then re-open the deep link so
the screen remounts from the fixture.

### Mobile gotchas

- **Text in a row needs `flexShrink: 1`.** RN defaults to `flexShrink: 0`, so a long string in a
  `flexDirection: "row"` pushes its siblings off screen. This is the native `min-w-0`. Truncate
  with `numberOfLines` + `ellipsizeMode`, not a fixed width.
- **Fixed heights are the native `max-w` trap.** A `height: 44` button clips its label at large
  text sizes. Use `minHeight` and padding.
- **`allowFontScaling={false}` is not a fix.** It hides the break from the people who need the
  large size. Cap with `maxFontSizeMultiplier` only where the design truly can't grow.
- **Safe areas.** The SE has no notch and a Pro Max has a Dynamic Island. Use
  `react-native-safe-area-context`, not hard-coded insets.
- **The simulator is not the phone.** Captures prove layout. For feel, say what still needs a
  real device.

## Putting them in the PR

Repo-relative image paths render in a README and show nothing in a PR body. Push the images,
then reference them pinned to the commit:

```
https://raw.githubusercontent.com/<owner>/<repo>/<sha>/<path>.png            # public repo
https://github.com/<owner>/<repo>/blob/<sha>/<path>.png?raw=true             # private repo
```

Use `<img src="..." width="380">`: a 2x phone capture is 780 px wide and swamps the table. Then
check every image URL answers, rather than assuming:

```bash
gh pr view <n> --json body -q .body | grep -oE 'src="[^"]+"' | sed 's/src="//;s/"//' \
  | while read -r u; do curl -s -o /dev/null -w "%{http_code} $u\n" "$u"; done
```

One before/after table per surface beats one big table. The reader compares two images at a time.

## Tools and other frameworks

`pnpm add -D playwright`, then `pnpm exec playwright install chromium` once. ImageMagick helps
with side-by-side composites: `magick before.png after.png +append side-by-side.png`.

For a non-Next web app, point the scripts at the already-running dev server (keep `--port`,
drop the `spawn`) and add the harness route however that framework does routes. The probe is
framework-agnostic. Don't start a second dev server if one is already up. Use a distinct port
and kill stale ones first.
