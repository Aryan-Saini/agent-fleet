# worker-chrome

Agents on a worker need a browser, and Playwright's headless Chromium gets flagged by every bot
check: `HeadlessChrome`, `navigator.webdriver`, no WebGL, logged out every run.
[`worker-chrome`](https://github.com/Aryan-Saini/worker-chrome) runs one real Google Chrome on
the worker all the time instead: its own virtual screen, the real GPU, one persistent profile you
log into once, DevTools on `127.0.0.1:9230`. Its README is the full spec.

The `worker-chrome` skill ships in the npm package: agents open their own tab in the shared
profile, never a new context, never log out.

## Install

Enable it on workers. `./install.sh` runs `npm i -g worker-chrome` and this package's
`install.sh`, which runs `worker-chrome setup` (systemd user units for Xvfb `:90`, openbox and
Chrome). Needs `google-chrome-stable`, Xvfb and openbox from your package manager, and lingering
(`packages/always-on`) so it starts at boot.

Then log in to the sites your agents need, once. From the controller, with `screenshare`
enabled there: `screenshare https://site/login`. It shows this same Chrome when worker-chrome is
up.

With `packages/mcp`, the `chrome-devtools` and `playwright` MCP servers attach to this Chrome
automatically on the worker.

## Verify

```bash
worker-chrome status    # up, Chrome's user agent, the GPU sites see, webdriver false
```

## Health

`check.sh`: the service is active and DevTools answers. Heals by restarting the service; the
profile and its logins survive.

## Updating

`npm i -g worker-chrome@latest && worker-chrome restart` on each worker.
