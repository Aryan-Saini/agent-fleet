# agent-fleet

How I run AI-assisted engineering across my machines, packaged so you can run it too.

A laptop is the **controller**: I work there and it owns every config. An always-on Linux box
is the **worker**: it runs coding agents in tmux around the clock. My **phone** drives both from
anywhere. Every agent on every machine, in every harness (Claude Code, Codex, Cursor, opencode),
gets the same rules and the same skills. The worker heals itself, reports what it can't fix, and
follows one rule above all others: **it may lose a task, but it may never stay down or stay silent.**

This repo is the kit: a few small portable commands, opt-in packages, agent skills, and a prompt
you hand to your own agent to build your fleet on whatever machines you have.

```
            phone  (T3 Code app, ssh app)
              |  T3 Connect relay / Tailscale
   +----------+-----------------------------------------+
   |                    tailnet                          |
   |   controller (laptop)           worker (always on)  |
   |   - you work here      ssh -->  - agents in tmux     |
   |   - authors config    <-- ssh   - health watchdog    |
   |   - /fleet-update               - config sync        |
   |        \                        /                    |
   |         +--- ~/drop (Syncthing)+                     |
   +-----------------------------------------------------+
```

## Get started

**With an agent (recommended).** Open Claude Code, Codex, Cursor or opencode on the machine you
work on and paste the prompt in [`quicksetupprompt.md`](quicksetupprompt.md). It interviews you
about your machines, OSes and tools, creates your own private `fleet` repo from this template,
installs what you picked, ports anything your OS needs, and proves each piece works. Paste it
again later to add a machine or a tool.

**By hand.**

```bash
gh repo create <you>/fleet --private --template Aryan-Saini/agent-fleet --clone
cd fleet
./install.sh --role controller --packages "tailscale drop-folder"
# then on each worker, after cloning your fleet repo there:
./install.sh --role worker --controller <laptop-ssh-alias> --packages "tailscale drop-folder always-on agent-clis"
```

Then fill in `computers.md`, and walk each package's README.

## Why a headless worker

Agents are long-running and you are not. A laptop sleeps when you close it, changes networks,
and is the machine you are trying to use while an agent hammers its CPU. A worker box doesn't:

- **Agents outlive your session.** Start a job from your phone on the bus, close the app, get a
  push when it is done. tmux keeps it alive across dropped connections.
- **It is always reachable.** Tailscale gives every machine a name on a private network, from
  anywhere, with no open ports. `http://worker:3000` works from your phone on cellular.
- **Your laptop stays yours.** Builds, test suites, ML jobs and three parallel agents run
  somewhere else.
- **Any old desktop works.** Mine is a retired gaming PC running Arch with no monitor attached.

## The same rules and skills everywhere

One private git repo holds my rules (`rules/AGENTS.md`, `rules/CLAUDE.md`) and skills.
`fleet link` symlinks them into each harness's place: Claude Code, Codex, Cursor (which needs a
generated `.mdc`) and opencode. `CLAUDE.md` imports `AGENTS.md`, so shared rules live once and
only Claude-specific guidance lives in Claude's file.

Config flows **one way**. I author on the controller, commit and push. Every 30 minutes each
worker `reset --hard`s onto it. An edit made on a worker is saved to a ref and discarded, so the
fleet's brain can never fork. Skill placement decides scope: `skills/` everywhere,
`skills-controller/` and `skills-worker/` by role, frontmatter by harness and OS, `skills-local/`
for your own. New to symlinks, or want the full walkthrough of keeping skills in sync across many
workers: [`docs/skills.md`](docs/skills.md). Harness wiring: [`docs/harnesses.md`](docs/harnesses.md).

## Delegation and safety

The controller delegates. The worker executes. The rules that keep that safe:

- **Classify disconnect risk first.** Before acting on a worker, ask whether the work can cut
  the network, ssh, the service manager or the boot. If yes or unsure, it never runs over a live
  ssh session.
- **Risky work is a work order.** `fleet workorder start <name> <script>` writes durable state,
  detaches, and returns. If the script needs a reboot, it refuses unless boot continuation is
  armed. After boot the worker resumes on its own, runs its health checks, proves it can reach
  the controller, writes a report to the drop folder and alerts. State clears only when all of
  that passes. Otherwise the next boot tries again and the alert says a human is needed.
- **The watchdog heals what is safe.** `fleet health` runs every 15 minutes: restart a dead
  service, bring the tailnet back up, re-apply a mapping. It never "heals" a login or a reboot.
  It reports those, through a file in the drop folder and an alert on your phone.
- **Agents enter at judgment points only.** Scripts carry the deterministic work, so a failure
  with no agent around still ends in a restored machine and a precise report.

The worker may lose the current task. It may never stay down or stay silent.
[`packages/os-update`](packages/os-update/) is the worked example: full OS upgrades with a
snapshot, a reboot, and a report.

## Screenshots and files

An agent on a headless box can't see your clipboard, and pasting doesn't cross ssh. So my
screenshot tool saves into a folder that Syncthing mirrors to `~/drop` on every machine.
Screenshot, wait ~20 seconds, and tell the agent `look at ~/drop/Shot-0412.png`. Anything the
worker writes to `~/drop` (reports, captures, alerts) comes back the same way.

When the next step can't wait: `fleet send worker file.png`. When a human has to click something
on the worker (a login, 2FA, a captcha): `screenshare` opens the worker's browser on the
controller over the tailnet. When an agent must drive the controller's own screen: the
`control-computer` skill, with [Peekaboo](packages/peekaboo/) as a vendor-neutral option.

## Multiple harnesses, multiple models

I use Claude Code day to day, Codex for OpenAI models and for computer use, opencode for cheap
open-weight models through OpenRouter, and Cursor when I am in an editor. They all read the same
rules. The [`subagents`](skills/subagents/SKILL.md) skill holds a table ranking every model I can
reach by cost, intelligence and taste, and routes work by it: cheap models for mechanical work,
taste for anything a user sees, and a "council" of models from different vendors to review a diff
independently. [`codex-implementation`](skills/codex-implementation/SKILL.md) hands a scoped
change to Codex and has Claude review the patch.

## What's here

| path | what |
| --- | --- |
| [`quicksetupprompt.md`](quicksetupprompt.md) | the prompt that builds your fleet |
| [`bin/`](bin/) | `fleet`, `fleet send`, `fleet alert`, `fleet health`, `fleet sync`, `fleet link`, `fleet workorder`, `fleet secrets`. Portable bash |
| [`packages/`](packages/) | opt-in capabilities, each a spec plus reference scripts and a health check |
| [`skills/`](skills/), [`skills-controller/`](skills-controller/), [`skills-worker/`](skills-worker/) | agent skills, linked by role |
| [`templates/`](templates/) | your `computers.md`, rules, machine READMEs, automations registry, incident format |
| [`units/`](units/) | systemd and launchd units for the worker loop |
| [`docs/`](docs/) | skills and symlinks, cross-machine cookbook, harness wiring, porting to other OSes |
| [`examples/author/`](examples/author/) | my own fleet, anonymized, as a reference |

### Packages

| package | what |
| --- | --- |
| [tailscale](packages/tailscale/) | private network and ssh from anywhere |
| [drop-folder](packages/drop-folder/) | `~/drop` synced everywhere |
| [always-on](packages/always-on/) | never sleep, survive power loss, run headless |
| [accounts](packages/accounts/) | every login and API key you need, and `fleet secrets push` for keys |
| [agent-clis](packages/agent-clis/) | catch expired agent logins before an agent fails |
| [t3-remote](packages/t3-remote/) | install T3 Code, stable or nightly, and drive agents from your phone |
| [postdraft](packages/postdraft/) | agents publish plans and files as links on your own server ([npm](https://www.npmjs.com/package/postdraft)) |
| [screenshare](packages/screenshare/) | see and click a browser on a headless box ([npm](https://www.npmjs.com/package/screenshare-tunnel)) |
| [worker-chrome](packages/worker-chrome/) | one real, logged-in Chrome on each worker that agents drive ([npm](https://www.npmjs.com/package/worker-chrome)) |
| [peekaboo](packages/peekaboo/) | let an agent drive a Mac's screen |
| [vorssaint](packages/vorssaint/) | the free menu bar toolkit I run all day, from the release or your own fork |
| [mcp](packages/mcp/) | MCP servers on every machine without per-machine logins |
| [os-update](packages/os-update/) | OS upgrades as reboot-safe work orders |

### Skills

| skill | where | origin | what |
| --- | --- | --- | --- |
| fleet | everywhere | agent-built | answer questions about the machines from the docs, not from guesses |
| worker | everywhere | agent-built | operate a worker: connect, tmux, files, services, agents across machines |
| automation | everywhere | agent-built | add a scheduled job the native way, versioned and verified |
| edit-md-files | everywhere | agent-built | where a new rule or skill belongs, and how it ships |
| subagents | everywhere, Claude, Codex, opencode | agent-built | model routing, other harnesses, the review council |
| codex-implementation | everywhere, Claude | hand-crafted | delegate a scoped change to Codex, review the diff |
| file-pr | everywhere | hand-crafted | PRs with a plain-language problem statement first |
| unslop, technical-writing | everywhere | hand-crafted | writing rules that cut AI tells |
| fleet-update | controller | agent-built | update every machine from its enabled packages, safely |
| fleet-add-device | controller | agent-built | onboard a machine, verified by running |
| control-computer | controller, Claude, macOS | hand-crafted | cheapest-first routing for GUI work, Codex Computer Use and Peekaboo |
| screenshare-tunnel | with `screenshare` | hand-crafted | get a human onto a worker's browser. Ships in the npm package |
| html-communication, file-upload, send-file-link, request-upload-link | with `postdraft` | hand-crafted | publish docs, screenshots and files as links. Ship in the npm package |
| worker-chrome | with `worker-chrome` | hand-crafted | drive the worker's always-on, logged-in Chrome. Ships in the npm package |
| capture | worker, Linux | hand-crafted | screenshots and video with no display |

## Any OS

The reference scripts target what I run: a macOS controller and an Arch Linux worker. The
contracts are the point: command names, the health check interface, the work order phases, the
drop folder conventions. [`docs/porting.md`](docs/porting.md) maps each piece to macOS, Linux and
Windows, and the setup prompt tells your agent to port anything your machines need.

## Security

- Your fleet repo is **private**. It holds hostnames and your rules.
- Secrets never enter it. They live in `~/.config/fleet/machine.env` and
  `~/.config/agent-secrets.env` on each machine, mode 600.
- Logins are per machine: agent CLIs, `gh` and T3 are logged in by hand on each box and never
  copied. Static API keys are edited on the controller and sent to workers over ssh with
  `fleet secrets push`. See [`packages/accounts`](packages/accounts/).
- Nothing listens on a public port. Tailscale carries everything; `screenshare` firewalls its
  port to the tailnet; a random password per worker never leaves your machines.

## How this was built

This repo was built by AI agents, which is the point of it: the same fleet it describes did the
work. Agents extracted it from my private setup, generalized every machine-specific value into
roles and templates, wrote the portable commands and packages, scrubbed it, and ran secret scans
over it.

Some skills are **hand-crafted**: I wrote and tuned them over months of daily use, and they ship
here close to how I run them. Others are **agent-built**: generalized or written fresh by agents
for this repo, from my private versions. The skills table marks which is which. Treat the
agent-built ones as solid starting points and expect to tune them, the same way I tuned mine.

## Credits

Ideas and tools this setup leans on, and the people behind them:

- **[Theo Browne](https://github.com/t3dotgg)** ([t3.gg](https://t3.gg)), for
  [T3 Code](https://github.com/pingdotgg/t3code) and T3 Connect, which is how my phone drives the
  fleet.
- **[Matt Pocock](https://github.com/mattpocock)**, for how I think about TypeScript and about
  writing [skills for agents](https://github.com/mattpocock/skills).
- **[Ben Davis](https://github.com/bmdavis419)** ([davis7.sh](https://www.davis7.sh)), for ideas
  and inspiration.
- **Lauren ([poteto](https://x.com/poteto))** ([GitHub](https://github.com/poteto)), for ideas
  and inspiration.

## License

[MIT](LICENSE). Built by [Aryan Saini](https://github.com/Aryan-Saini).
