# T3 Code: what ties the fleet together

[T3 Code](https://github.com/pingdotgg/t3code) runs coding agents (Claude Code, Codex, opencode)
as threads in an app. In this fleet it does more than that. It is how the phone reaches both
machines, how an agent on one machine starts work on the other, and where scheduled agent runs
live. Install steps are in [`packages/t3-remote`](../packages/t3-remote/); this page is how the
pieces connect.

```
   phone (T3 app)                       phone (T3 app)
        \  T3 Connect relay, anywhere   /
   +-----\-----------------------------/------+
   | controller                      worker   |
   | T3 desktop app  <== env links ==> t3code.service (systemd user)
   |   MCP: t3-<worker>  <-- tailnet -->  MCP: t3-<controller>
   |   scheduled task: nightly fleet update   |
   +------------------------------------------+
```

## On each machine

### Controller: the desktop app

The controller runs the desktop app (the author uses the nightly channel). The app owns the T3
Connect credential, so `npx t3 connect status` in a terminal reports authorization missing even
while the app's tunnel is up. Trust the app's Connections panel, not the CLI, on macOS.

Agent sessions started from the app are its child processes. Anything that quits or relaunches
the app kills the session running it, which is why the controller has the `t3-handoff` helper
([architecture.md](architecture.md#when-something-insists-on-a-real-terminal)). The nightly
fleet update never updates the controller's own app for the same reason; it reports the
installed version and you update it.

### Worker: a systemd user service

The worker has no display, so T3 runs headless as `t3code.service`, a systemd user unit with
lingering enabled so it runs without a login. `t3 service install` generates the unit; it starts
T3's versioned launcher, which keeps several versions side by side and records the active one.

- Install a specific build with pnpm, then reconcile the service:
  `pnpm add -g t3@<exact-version> && t3 service update`. Tracking nightly, never install
  `t3@latest`: that selects stable.
- Tailscale HTTPS: `tailscale serve --bg http://127.0.0.1:3773` maps `https://<worker>.<tailnet>.ts.net`
  to T3. It needs `sudo tailscale set --operator=<user>` first, or `tailscale serve` fails and T3
  logs that it could not configure Serve.
- T3 Connect from a headless box: `t3 connect link --headless` prints a URL. Open it on any
  device, sign in, paste the one-time code back. Run it in tmux, or the prompt dies with the ssh
  session.
- Push notifications and Live Activities on the phone: `t3 connect publish`.
- The service runs with a minimal PATH, so every agent CLI it launches must be reachable from
  `/usr/local/bin` or `/usr/bin`. Symlink them there.

**The updater runs detached.** Restarting `t3code.service` kills every agent session inside it,
including the one running the update. So T3 updates on the worker are started from the
controller over ssh, or launched with `systemd-run --user --no-block` so they outlive the
session. The author's updater, run on the controller, does this:

1. Records the current version as last-healthy.
2. Installs the target and restarts the service.
3. Verifies for up to two minutes: service active, port 3773 returns 200, Connect exposure
   enabled, environment link provisioned, relay running, Serve mapped.
4. Rolls back to last-healthy on its own if any check fails.

It does not wait for the phone. The worker's own auto-update timer exists and stays disabled:
unattended updates restart the backend under live threads.

### Phones: T3 Connect

The phone app reaches both machines through T3 Connect's relay, with no VPN and no home network.
Tailscale Serve is a second path for when the phone is on the tailnet. The worker must stay
awake for this to work: Wake-on-LAN does not cross the internet. Nothing syncs to the phone. It
starts, watches and answers threads, and receives push when one finishes.

## Between the machines

### Environment links

Each T3 is linked to the other as a remote environment. That lets the controller's T3 list,
launch and read threads on the worker, and the reverse. Links are made over Tailscale with the
Connect relay kept as fallback.

Each machine's T3 also serves MCP at `https://<machine>.<tailnet>.ts.net/mcp`. Claude Code on
the other machine is signed in to it at user scope, as `t3-<worker>` on the controller and
`t3-<controller>` on the worker. That gives any Claude session, inside T3 or not, tools such as
`t3_project_list`, `t3_thread_launch` and `t3_thread_read` against the other machine.

### Renewal

Both the environment links and the MCP sign-ins expire after 30 days, and the MCP token has no
refresh. A `t3-peer-renew` script renews all four, each machine its own side:

1. Mints a one-time pairing code on the other machine over ssh
   (`t3 auth pairing create --ttl 10m`).
2. Relinks the environment over Tailscale and keeps the relay address as fallback.
3. Reruns `claude mcp login --no-browser` on a pty and approves it through the same endpoint the
   browser approval page calls.

The nightly fleet update runs it weekly on both machines and stores the last run, so a lapsed
sign-in shows up in the report before it breaks anything. Manual fallback: mint a pairing code
on the target and approve in a browser on the controller. For the worker's side, forward its
callback port first (`ssh -fN -L <port>:127.0.0.1:<port> <worker>`) so the controller browser's
`localhost` redirect reaches it.

Reaching the worker over its tailnet IPv6 address avoids a macOS quirk where the Tailscale IPv4
route goes missing and every call to the other T3 times out.

### A subagent on the other machine

Inside T3, `delegate_task` starts a child agent that shows as a card in the parent thread and
wakes the parent when it finishes. Add the other machine's `environmentId` to the target and the
child runs over there, with that machine's logins, disks and dev servers:

```json
{
  "title": "[<model> <effort>] run the e2e suite",
  "target": {
    "providerInstanceId": "claudeAgent",
    "model": "<model>",
    "options": { "effort": "medium" },
    "environmentId": "<worker-env-id>"
  },
  "task": "<self-contained brief>"
}
```

`orchestrator_capabilities` lists the providers, models and options each machine offers. Find
the environment ids with `t3_environment_links`. Put them in your `subagents`
skill so agents never guess. This is how the worker gets Claude Code on the controller, which
ssh cannot do (the Keychain problem in [communicate.md](communicate.md)), and how the controller
offloads a heavy build to the worker.

### Handing a thread to the other machine

Moving work, not just delegating it, has two modes:

- **Fresh**: a new worktree on the other machine from a base branch, and a new thread there with
  a self-contained brief.
- **Move**: take the current checkout, with its commits plus uncommitted and untracked changes,
  and continue it over there. A script snapshots the working tree without touching the local
  index, pushes it to the other machine's repo over ssh, creates the worktree, re-applies the
  changes, and runs the worktree setup script. If the push is rejected, stop; never force-push.

Either way the result is an ordinary top-level thread on the other T3, visible on the phone. The
source checkout is left untouched until you say otherwise.

### Worktree setup

T3 can run a project script whenever it creates a worktree. Both machines point it at one fleet
script that copies the main checkout's gitignored `.env` files into the new worktree (never
overwriting) and installs dependencies. A thread or subagent that starts in a fresh worktree can
run the app straight away. T3 passes `T3CODE_PROJECT_ROOT` and `T3CODE_WORKTREE_PATH`; the script
sets its own PATH because T3 may launch it with a GUI or systemd PATH.

## Scheduled tasks

T3 can start a fresh thread on a schedule. The nightly fleet update is one: at 02:00 it runs the
`/fleet-update` skill in a new thread, so the whole run is readable afterwards in the app and on
the phone, and the report's first line says `OK` or `NEEDS ATTENTION`. It needs the app running,
and the controller awake: `pmset repeat wake MTWRFSU 01:58:00` wakes it two minutes early. A
controller on battery with the lid closed can still miss it, and the next run's report says so.

Manage tasks with `schedule_task`, `list_scheduled_tasks` and `run_scheduled_task_now`, or in the
app's settings. Before a manual fleet update, read the latest nightly thread; most of the work
may already be done.

## Projects on both machines

A repo you work on from either machine is registered as a T3 project on both, with the same
default model, so a thread started from the phone on either machine gets the model you meant.
The `create-project` skill does it: make the repo, clone it on the worker, register it on both
T3s, set the default model, add an icon. It goes through T3's own tools
(`t3_project_create`, `t3_project_update`). Each machine also has a machine-wide project rooted
at the home directory (and on the worker, one at the work volume) for threads that are not about
one repo.

**Never write T3's database directly.** An early version of that skill inserted rows into T3's
sqlite store to set the default model. T3 decodes its event store only at boot, so the bad rows
sat there harmlessly until the next restart, when the service crash-looped and took the phone
path down. The lesson: a long-running healthy process is not evidence the service can start.
Use T3's tools or CLI.

## Settings and keybindings from the repo

`settings-sync` treats T3 like the other harnesses ([sync.md](sync.md)). Keybindings are shared,
one file in the fleet repo applied on every machine. `settings.json` and the client settings are
per machine, because the headless worker has no desktop client to configure. The controller
captures, the worker applies.

## Accounts

Every Claude Code and Codex session T3 starts, on both machines, goes through the CLIProxyAPI
hub on the worker, which picks an account from a pool. T3 never switches accounts itself. See
[`packages/cliproxy`](../packages/cliproxy/).

## Keeping agents from flattening the worker

T3 runs every agent under its own systemd slices. Capping those slices with drop-ins keeps a
runaway chat or a pile of parallel builds from freezing the box. See
[architecture.md](architecture.md#load-limits-on-the-worker).
