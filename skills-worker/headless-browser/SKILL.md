---
name: headless-browser
description: When work on a headless machine needs a real browser to load a page, click through a flow, or read what actually rendered, use skill. There is no desktop and no open browser to attach to.
metadata:
  harness: [claude, codex, cursor]
  platform: [linux]
  requires: "playwright-core in ~/.local/share/fleet-browser/node_modules and its Chromium (install below)"
---

# Headless browser

Drive a real Chromium on a worker. The box is server mode with no `DISPLAY`, so there is no
window to attach to and nothing to see. You launch a browser, ask it questions, and read the
answers back as text.

Reach for this when bash genuinely cannot answer the question: the page is client rendered,
the check needs real layout, or a flow only breaks after a click. `curl` is faster and enough
for a status code, a redirect, or server rendered HTML.

## Install, once per worker

```bash
npm i --prefix ~/.local/share/fleet-browser playwright-core
node ~/.local/share/fleet-browser/node_modules/playwright-core/cli.js install --with-deps chromium
```

## Run one

```bash
NODE_PATH=$HOME/.local/share/fleet-browser/node_modules node -e '
const { chromium } = require("playwright-core");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto("http://localhost:3000", { waitUntil: "networkidle" });

  console.log(await p.title());
  console.log(await p.locator("main").innerText());

  await b.close();
})().catch(e => { console.error(e.message); process.exit(1); });
'
```

`NODE_PATH` is what makes this work from any directory. Playwright is installed once, in the
`fleet-browser` folder, not globally, so a bare `require("playwright-core")` fails anywhere else.
Never `npm install playwright` to work around that: it downloads another browser build and the
two drift.

Use `playwright-core`, not `playwright`. The core package is the one installed here.

## Read what rendered

```js
await p.locator("h1").innerText()                  // one element
await p.locator("body").innerText()                // whole page as text
await p.locator("[data-testid=row]").allInnerTexts()  // every match
await p.locator(".error").count()                  // is it there at all
await p.evaluate(() => document.title)             // anything else
```

Prefer `getByRole`, `getByText` and `data-testid` over CSS descendant chains. A selector tied
to layout breaks the moment someone restyles the page, and you will not be watching when it
does.

## Click through a flow

```js
await p.getByRole("button", { name: "Sign in" }).click();
await p.getByLabel("Email").fill("test@example.com");
await p.waitForURL("**/dashboard");
console.log(await p.getByRole("heading").innerText());
```

Playwright auto-waits for an element to be actionable, so a fixed `waitForTimeout` is almost
always the wrong fix for a flaky step. Wait for the thing you actually mean: `waitForURL`,
`waitForSelector`, or `waitForResponse`.

## Catch what the page hides

A blank render is usually a console error or a failed request, and neither shows up in the DOM.

```js
p.on("console", m => m.type() === "error" && console.log("console:", m.text()));
p.on("pageerror", e => console.log("pageerror:", e.message));
p.on("requestfailed", r => console.log("failed:", r.url(), r.failure()?.errorText));
```

Attach these before `goto`, or the events fire before anything is listening.

## Report back in text

Nobody is looking at this machine, so a screenshot proves nothing until it reaches the user.
Print what you found. If a picture is genuinely the answer, that is the **capture** skill:
`shot <url> <name>` writes to `~/drop` and Syncthing carries it to the controller.

## Notes

Always `await b.close()`, including on the error path, or headless Chromium processes pile up
on a machine nobody is watching.

Localhost on the worker means the worker's own localhost. A dev server on the controller is
`http://<controller>:<port>` over the tailnet, not localhost.

The controller has the opposite tool, **control-computer**, which drives the real browser the
user already has open. There the point is their live session and logged-in tabs; here there is
no session and no tabs. If a flow here needs a human (login, 2FA), that is **screenshare-tunnel**.
