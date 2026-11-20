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
              phone  (T3 Code app)
                |  T3 Connect relay / Tailscale
   +------------+-------------------------------------------------+
   |                         tailnet                               |
   |   controller (laptop, leader)        worker (always on)       |
   |   - you work here         ssh -->    - agents: tmux, T3       |
   |   - authors all config   <-- ssh     - CLIProxyAPI hub        |
   |   - nightly /fleet-update            - worker-chrome, Halo    |
   |   - signed automation runner         - dev servers over HTTPS |
   |   - Cua Driver computer use          - watchdog, backups      |
   |            \                          /                       |
   |             +-- git: controller pushes, worker resets /30m --+|
   |             +-- T3 environment links: threads either way ---+|
   +---------------------------------------------------------------+
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
./install.sh --role controller --packages "tailscale t3-remote mac-automations"
# then on each worker, after cloning your fleet repo there:
./install.sh --role worker --controller <laptop-ssh-alias> --packages "tailscale always-on agent-clis t3-remote linux-automations"
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

## Screens, browsers and files

An agent on a headless box can't see your clipboard, and pasting doesn't cross ssh. Files move
with `to-worker file.png` / `to-controller file.png` (thin wrappers over `fleet send`) or as T3
attachments. I used to mirror a Syncthing `~/drop` folder everywhere; it is still in
[`packages/drop-folder`](packages/drop-folder/) as an option, but I retired it.

- **A human has to click something on the worker** (a login, 2FA, a captcha):
  [`halo`](packages/halo/) brings up a screen, Chrome, a voxl browser viewer and a RustDesk
  fallback on the worker and opens it on the controller, firewalled to the tailnet.
- **Agents need a real browser on the worker:** [`worker-chrome`](packages/worker-chrome/) keeps
  one logged-in Chrome running; the `playwright` and `chrome-devtools` MCP servers attach to it.
- **An agent must drive the controller's own apps:** the `control-computer` skill, built on
  [Cua Driver](packages/cua-driver/) (background, accessibility-tree first), with
  [Peekaboo](packages/peekaboo/) as the fallback.
- **You want the Mac on your phone:** [Sill](packages/sill/). **An agent needs the phone itself:**
  [phoneuse](packages/phoneuse/).

## Multiple harnesses, multiple models

I use Claude Code day to day inside T3 Code, Codex for OpenAI models, opencode for cheap
open-weight models through OpenRouter, and Cursor when I am in an editor. They all read the same
rules. The [`subagents`](skills/subagents/SKILL.md) skill holds a table ranking every model I can
reach by cost, intelligence and taste, and routes work by it: cheap models for mechanical work,
taste for anything a user sees, and a "council" of models from different vendors to review a diff
independently. [`codex-implementation`](skills/codex-implementation/SKILL.md) hands a scoped
change to Codex and has Claude review the patch. Every Claude Code and Codex on the fleet routes
through one [CLIProxyAPI hub](packages/cliproxy/) on the worker, and the controller falls back to
its own logins within three minutes if the hub goes down.

[T3 Code](docs/t3-code.md) is the glue: the desktop app on the controller, a service on the
worker, the phone through T3 Connect, and environment links so a thread or a subagent on one
machine can run on the other.

## How it is wired

| doc | what |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | leader and worker, every channel between them, work orders, sudo on both sides |
| [`docs/sync.md`](docs/sync.md) | every sync path: global rules files, skills, the fleet repo, settings, secrets |
| [`docs/skills.md`](docs/skills.md) | one copy of each skill for every harness, and the metadata header that says who gets it |
| [`docs/automations.md`](docs/automations.md) | both scheduler designs and every automation I run, with why |
| [`docs/t3-code.md`](docs/t3-code.md) | T3 Code across controller, worker and phone |
| [`docs/storage.md`](docs/storage.md) | the worker's disks: btrfs system, XFS on LVM/VDO work volume, ext4 snapshots, a read-only vault |
| [`docs/communicate.md`](docs/communicate.md) | cross-machine cookbook: commands, agents, files, services |
| [`docs/harnesses.md`](docs/harnesses.md) | what Claude Code, Codex, Cursor and opencode each read |
| [`docs/porting.md`](docs/porting.md) | each piece on macOS, Linux and Windows |

## What's here

| path | what |
| --- | --- |
| [`quicksetupprompt.md`](quicksetupprompt.md) | the prompt that builds your fleet |
| [`bin/`](bin/) | `fleet`, `fleet send`, `fleet alert`, `fleet health`, `fleet sync`, `fleet link`, `fleet workorder`, `fleet secrets`. Portable bash |
| [`packages/`](packages/) | opt-in capabilities, each a spec plus reference scripts and a health check |
| [`skills/`](skills/), [`skills-controller/`](skills-controller/), [`skills-worker/`](skills-worker/) | agent skills, linked by role |
| [`templates/`](templates/) | your `computers.md`, rules, machine READMEs, automations registry, incident format |
| [`units/`](units/) | systemd and launchd units for the worker loop |
| [`docs/`](docs/) | how it is wired, see the table above |
| [`examples/author/`](examples/author/) | my own fleet, anonymized, as a reference |

### Packages

| package | for | what |
| --- | --- | --- |
| [tailscale](packages/tailscale/) | every machine | the private network, ssh from anywhere, `serve` for HTTPS, sharing across tailnets |
| [drop-folder](packages/drop-folder/) | every machine | `~/drop` on every machine; `to-worker` / `to-controller` push files, Syncthing optional |
| [always-on](packages/always-on/) | workers | never sleep, come back after power loss, run headless |
| [agent-clis](packages/agent-clis/) | workers | catch expired Claude, Codex, Cursor, opencode and gh logins |
| [accounts](packages/accounts/) | every machine | which logins and API keys you need, and how keys reach every machine |
| [settings-sync](packages/settings-sync/) | every machine | Claude, Codex and T3 settings shared one way with per-machine overlays; `repo-sync` for no-PR repos |
| [mcp](packages/mcp/) | every machine | MCP servers without per-machine logins: keys global, definitions per project, trust per machine |
| [t3-remote](packages/t3-remote/) | workers, controllers | T3 Code as a service, phone access, controller and worker linked to each other |
| [cliproxy](packages/cliproxy/) | worker + controller | one CLIProxyAPI hub for every Claude and Codex account, failover, request log archive |
| [mac-automations](packages/mac-automations/) | macOS | every scheduled job through one signed runner granted Full Disk Access once |
| [linux-automations](packages/linux-automations/) | Linux workers | one systemd user timer per job, `Persistent=true` where downtime matters |
| [agent-history-backup](packages/agent-history-backup/) | every machine | every agent conversation kept forever in restic on S3, with a restore helper |
| [dev-server](packages/dev-server/) | workers | run a web app on the worker, open it over tailnet HTTPS from anywhere, reaped after 24h |
| [postdraft](packages/postdraft/) | every machine | agents publish plans, reports and files as links, on your own Convex server (npm) |
| [halo](packages/halo/) | controller + headless worker | see and click a worker's screen from the controller: Xvfb, voxl, RustDesk, a screen pool (npm) |
| [sill](packages/sill/) | macOS + phone | any window on your Mac on your iPhone or iPad, over Tailscale, kept running |
| [worker-chrome](packages/worker-chrome/) | workers | one real, logged-in Chrome that agents drive instead of headless Chromium (npm) |
| [cua-driver](packages/cua-driver/) | macOS controllers | agents drive native apps in the background, CLI and MCP (trycua) |
| [peekaboo](packages/peekaboo/) | macOS | let an agent see and click the real screen, fallback for cua-driver |
| [phoneuse](packages/phoneuse/) | headless worker + phone | agents see and tap a real iPhone over AirPlay and Bluetooth (spec) |
| [vorssaint](packages/vorssaint/) | macOS controllers | free menu bar toolkit, from the release or your own fork's build |
| [os-update](packages/os-update/) | workers | OS upgrades as reboot-safe work orders |

### Skills

| skill | scope | what |
| --- | --- | --- |
| fleet, worker | everywhere | answer from the docs; operate the worker: connect, tmux, files, services |
| automation | everywhere | add a scheduled job the native way for that machine, versioned and verified |
| edit-md-files | everywhere | where a new rule or skill belongs, and how it ships |
| subagents | everywhere | model routing table, delegation inside and outside T3, the review council |
| codex-implementation | everywhere, Claude | delegate a scoped change to Codex, review the diff |
| t3-environment-handoff | everywhere, Claude | move a thread or worktree to the other machine's T3 |
| dev-server | everywhere | run a web app on the worker and hand back a tailnet HTTPS link |
| cliproxy-hub | everywhere | accounts, limits and resets on the shared CLIProxyAPI hub |
| create-project, remove-project | everywhere | register a repo in T3 on both machines; retire and archive one |
| npm-publish | everywhere | publish packages from any machine, handle EOTP |
| calendar | everywhere | Apple and Google calendars, a team availability mirror, week planning |
| messages | everywhere | read iMessage history from the controller; send only when told |
| file-pr | everywhere | PRs with a plain-language problem statement first |
| unslop, technical-writing | everywhere | writing rules that cut AI tells (from poteto's pstack) |
| codebase-design, improve-codebase-architecture, domain-modeling | everywhere | deep modules, seams, glossary and ADRs (from Matt Pocock) |
| grilling, grill-me, grill-with-docs, handoff | everywhere | stress-test a plan; hand a session to the next agent (from Matt Pocock) |
| recall, find-skills | everywhere | search past agent sessions; find installable skills |
| ui-craft, ui-stress-shots | everywhere | Emil Kowalski's UI and motion guides as a router; worst-case UI screenshots |
| content-principles | everywhere | pointer to aiwithremy's short-form content principles |
| audio-analyzer, video-downloader, spotify | everywhere | transcribe recordings; download video; play music anywhere |
| control-computer | controller, Claude, macOS | GUI work through Cua Driver, Peekaboo as fallback |
| codex-image-creation | controller | generate and edit images through Codex via the hub, or an OpenAI key |
| fleet-update, fleet-add-device | controller | update every machine safely; onboard a machine |
| phoneuse, reminders-mac | controller | drive a real iPhone; Apple Reminders |
| capture, reminders-worker | worker | screenshots and video with no display; Reminders via the controller |
| halo, worker-chrome, html-communication, file-upload, send-file-link, request-upload-link | with their npm package | ship inside `fleet-halo`, `worker-chrome` and `postdraft` |

Every `SKILL.md` opens with a `metadata` block (`harness`, `platform`, `scope`, `requires`) that
says which harnesses and OSes get it and what it needs on the machine. Most of these are
**skeletons** of the skills I run daily: the real structure, commands and lessons, with
`<placeholders>` where my values were. Copy the parts you want.

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
- Nothing listens on a public port. Tailscale carries everything; Funnel stays off; `halo`
  firewalls its ports to the tailnet; dev servers bind loopback and are reached only through
  `tailscale serve`.
- Unattended root: passwordless sudo on the worker only; the controller's password stays in the
  login Keychain behind a `SUDO_ASKPASS` helper. See [`docs/architecture.md`](docs/architecture.md).

## How this was built

This repo was built by AI agents, which is the point of it: the same fleet it describes did the
work. Agents extracted it from my private setup, generalized every machine-specific value into
roles and templates, wrote the portable commands and packages, scrubbed it, and ran secret scans
over it.

Some skills are **hand-crafted**: I wrote and tuned them over months of daily use, and they ship
here close to how I run them. Others are **agent-built**: generalized or written fresh by agents
for this repo, from my private versions, and most skills here are skeletons of mine with my
values swapped for placeholders. Treat them as solid starting points and expect to tune them,
the same way I tuned mine.

## Credits

Ideas and tools this setup leans on, and the people behind them:

- **[Theo Browne](https://github.com/t3dotgg)** ([t3.gg](https://t3.gg)), for
  [T3 Code](https://github.com/pingdotgg/t3code) and T3 Connect, which is how my phone drives the
  fleet.
- **[Matt Pocock](https://github.com/mattpocock)**, for how I think about TypeScript and about
  writing [skills for agents](https://github.com/mattpocock/skills); several skills here are his.
- **[Emil Kowalski](https://emilkowal.ski)**, for the UI and motion craft behind `ui-craft`.
- **[trycua](https://github.com/trycua/cua)**, for Cua Driver.
- **[router-for-me](https://github.com/router-for-me/CLIProxyAPI)**, for CLIProxyAPI.
- **[Ben Davis](https://github.com/bmdavis419)** ([davis7.sh](https://www.davis7.sh)), for ideas
  and inspiration.
- **Lauren ([poteto](https://x.com/poteto))** ([GitHub](https://github.com/poteto)), for ideas
  and inspiration, and the pstack skills behind `unslop`, `technical-writing` and `recall`.

## License

[MIT](LICENSE). Built by [Aryan Saini](https://github.com/Aryan-Saini).
