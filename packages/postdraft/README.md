# postdraft

Agents write a plan, report, set of mocks or screenshot, and you get a link you can open on
your phone. [`postdraft`](https://github.com/Aryan-Saini/postdraft) renders Markdown into one
self-contained HTML page and publishes it to **your own** server, so nothing goes through anyone
else's.

```bash
postdraft upload plan.md         # renders, publishes, prints the URL
postdraft upload shot.png        # permanent URL for a screenshot, e.g. to embed in a PR
postdraft send build.apk         # a download page you open on your phone
```

It ships four skills that `fleet link` puts in every harness: `html-communication`,
`file-upload`, `send-file-link` and `request-upload-link`.

## Install

1. Enable it on every machine that runs agents. `./install.sh` runs `npm i -g postdraft`.
2. **Once, from the controller:** deploy your server. Paste this into your agent:

   ```text
   Set up postdraft for me by following https://raw.githubusercontent.com/Aryan-Saini/postdraft/main/SETUP.md
   ```

   It creates a Convex project on your account, deploys the server, locks it with an API key
   and authenticates this machine. You approve the Convex login and choose Convex storage or S3.
   Skip its "install the skills" step: the fleet links them.
3. **Every other machine:** the same server, the same key. `fleet secrets push <machine>` copies
   `~/.postplan/config.json` along with your other keys (see `packages/accounts`).

## Verify

```bash
postdraft whoami                  # prints your account and key name
echo '# hello' > /tmp/t.md && postdraft upload /tmp/t.md
```

## Health

`check.sh`: the CLI is installed and `~/.postplan/config.json` exists. With `FLEET_PROBE=1` it
also runs `postdraft whoami` against your server. No heal: a missing key needs you.

## Updating

`npm i -g postdraft@latest` on each machine. The server updates separately, from your server
checkout (`git pull && npx convex deploy`), and only when a release note says it changed.
