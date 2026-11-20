# worker-chrome

Agents on a worker need a browser, and Playwright's bundled headless Chromium gets flagged by
every bot check: it says `HeadlessChrome`, sets `navigator.webdriver`, has no WebGL, and starts
every run logged out. [`worker-chrome`](https://github.com/Aryan-Saini/worker-chrome) runs one
real Google Chrome on the worker all the time instead: its own virtual screen, the box's real
GPU, one persistent profile you log into by hand, DevTools on `127.0.0.1:9230` only. To a website
it looks like a person at a Linux desktop. Its README is the full spec.

```bash
worker-chrome setup      # systemd user units for Xvfb :90, openbox and Chrome; starts them
worker-chrome status     # endpoint, Chrome's user agent, the GPU sites see, webdriver=false
worker-chrome browsers   # every Chrome on the box, by label, with its screen, port, profile, tabs
worker-chrome describe <name> "what it is for"   # a note shown by browsers
worker-chrome restart
```

Its window is titled `<worker> · worker-chrome`. Give any other Chrome on the box a label the
same way, `--window-name="<worker> · <name>"`, and `worker-chrome browsers` lists it by name, so an
agent can tell the shared browser from a job's private one.

## Drive it

Connect over CDP with [patchright-core](https://github.com/Kaliiiiiiiiii-Vinyzu/patchright), the
Playwright API without the `Runtime.enable` call bot checks look for. It ships in the package:

```js
// NODE_PATH=$(worker-chrome node-path) node drive.js
const { chromium } = require("patchright-core");
const b = await chromium.connectOverCDP("http://127.0.0.1:9230");
const p = await b.contexts()[0].newPage();   // your own tab in the shared, logged-in profile
await p.goto("https://example.com");
await p.close(); await b.close();            // close disconnects; Chrome keeps running
```

The `worker-chrome` skill ships in the npm package and `fleet link` puts it in every harness: open
your own tab in the shared profile, never a new context, never log out or clear data.

With [mcp](../mcp/), the `chrome-devtools` and `playwright` MCP servers attach to this Chrome
automatically on the worker, whatever flags the harness config passes.

## From the controller

DevTools stays on loopback. To drive this Chrome from another machine on the tailnet, serve the
port on one address, to the machines you name:

```bash
worker-chrome expose <worker-tailnet-ip> <controller-tailnet-ip>   # bind address, then allowed sources
worker-chrome endpoint --remote                                    # http://<worker-tailnet-ip>:9230
worker-chrome expose off
```

A small relay unit does it, so Chrome never restarts and never listens beyond loopback. It refuses
`0.0.0.0` and `::` and drops any source not on the list. Connect with the IP, not a hostname:
Chrome rejects DevTools requests whose `Host` is a name. Without `expose`, an ssh tunnel works:
`ssh -N -L 9230:127.0.0.1:9230 <worker>`.

## Install

Enable it on workers. `./install.sh` runs `npm i -g worker-chrome` and this package's
`install.sh`, which runs `worker-chrome setup`. Needs `google-chrome-stable`, Xvfb, openbox and
Node 20+ from your package manager, and lingering ([always-on](../always-on/)) so it starts at
boot. A GPU at `/dev/dri/renderD128` turns on WebGL through Vulkan; without one Chrome still runs,
minus WebGL.

| setting | default | |
| --- | --- | --- |
| `WORKER_CHROME_DISPLAY` | `90` | X display number, read at `setup` |
| `WORKER_CHROME_PORT` | `9230` | DevTools port, `127.0.0.1` only |

Profile: `~/.browser-profiles/worker-chrome`.

Then log in to the sites your agents need, once. From the controller, with [halo](../halo/)
enabled there: `halo https://site/login`. Halo shows this exact screen when worker-chrome is up,
so the login you finish is the one agents use. A voxl stream on `:90` (see halo's screen pool)
gives the same screen in any browser tab. Fallback on the box itself: `worker-chrome view` serves
it over VNC on the tailnet IP only.

## Verify

```bash
worker-chrome status    # up, Chrome's user agent, the GPU sites see, webdriver false
```

## Health

`check.sh`: the service is active and DevTools answers. Heals by restarting the service; the
profile and its logins survive.

## Updating

`npm i -g worker-chrome@latest && worker-chrome restart` on each worker. `/fleet-update` does it.
