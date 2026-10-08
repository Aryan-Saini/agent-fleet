---
name: capture
description: Capture screenshots or record browser video on a headless worker, document UI changes, or add before/after images to a PR. Use when the user says "screenshot", "record", "add screenshots to the PR", "document the UI changes", "before/after", or "show me what it looks like".
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [linux]
  requires: "the drop folder, playwright-core from the headless-browser skill, ffmpeg for video conversion, gh when attaching to a PR"
---

# capture

Produce visual evidence on a machine with no screen. Write it to `~/drop` and Syncthing carries
it to the controller, which is how the user sees it. Nothing needs uploading for them to look.
Upload only when a link has to reach someone else or go in a PR.

## 1. Screenshot

```bash
~/fleet/skills-worker/capture/shot http://localhost:3000 before
```

Prints the path it wrote (`~/drop/before.png`). Flags: `--full` for the full page, `--mobile` for
a 390x844 viewport. It renders in real headless Chromium, so it is the honest answer to "what
does it look like".

## 2. Record a flow

```bash
NODE_PATH=$HOME/.local/share/fleet-browser/node_modules node -e '
const { chromium } = require("playwright-core");
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({
    recordVideo: { dir: process.env.HOME + "/drop", size: { width: 1280, height: 720 } },
  });
  const p = await ctx.newPage();
  await p.goto("http://localhost:3000");
  await p.getByRole("button", { name: "Open menu" }).click();
  await ctx.close();            // the video is only written on context close
  await b.close();
})().catch(e => { console.error(e.message); process.exit(1); });
'
```

The file lands in `~/drop` under a hashed name: `ls -t ~/drop/*.webm | head -1`. WebM does not
play in iPhone Safari; convert before sending anywhere:

```bash
ffmpeg -i input.webm -c:v libx264 -c:a aac -movflags +faststart output.mp4
```

## 3. Screenshots in a PR

A PR needs public URLs. Upload each image to storage you control (an S3 bucket with a public
prefix, a GitHub release asset, an image host) under an unguessable name, then:

```bash
gh pr comment 123 --body "$(printf '### Before\n![Before](%s)\n\n### After\n![After](%s)\n' "$BEFORE_URL" "$AFTER_URL")"
```

Public URLs are permanent. Check every image for customer data, emails and tokens before it goes up.
