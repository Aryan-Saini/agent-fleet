# Quick setup prompt

Paste everything below the line into Claude Code, Codex, Cursor or opencode, on the machine you
work on. It builds **your** fleet: your machines, your OSes, your tools. Run it again any time
you add a machine or want a new tool. It updates what is there instead of starting over.

---

You are setting up my personal agent fleet using the agent-fleet kit
(https://github.com/Aryan-Saini/agent-fleet). Read its `README.md`, `packages/README.md`,
`docs/porting.md` and the `fleet`, `fleet-add-device` and `edit-md-files` skills before doing
anything. The kit describes one person's fleet as an example. Build mine, which will differ.

## Ground rules

- Never copy anyone else's values. Every account, hostname, key and login is mine and is created
  or entered by me.
- **No secret ever goes in a repo.** Tokens and passwords live in `~/.config/fleet/machine.env`
  or `~/.config/agent-secrets.env` (mode 600) on each machine. Before every commit, check
  `git diff --cached` for anything that looks like a credential.
- My fleet repo is **private**. It will hold hostnames and my rules.
- Stop and hand over to me for: account sign-ins, 2FA, agent CLI logins, BIOS settings, anything
  needing a password, and anything on a machine you cannot reach yet. Tell me exactly what to do,
  then wait and verify.
- Work one phase at a time. Verify each phase by running something, not by reading config.
- No em dashes in anything you write for me.

## Phase 0: is this a first run or an update?

Look for my fleet repo: `~/fleet` with a `computers.md`, or ask me where it is.

- **Found:** this is an update. Read `computers.md`, every `machines/*/README.md`, and
  `~/.config/fleet/machine.env` on each reachable machine. Pull the kit's latest changes
  (`git fetch upstream && git merge upstream/main`, adding the `upstream` remote if missing), then
  ask me what I want to change: a new machine, a new tool, a role change, or just "update
  everything". Skip to the phase that covers it. For "update everything", run `/fleet-update`.
- **Not found:** first run. Continue with phase 1.

## Phase 1: interview me

Ask these in one message, with sensible defaults I can accept by saying "defaults":

1. **Machines.** For each: a short name, the OS, its role (controller: where I work and author
   config; worker: always on, runs agents; remote: a phone or tablet), and whether you can reach
   it from here right now. At least one controller. A worker is strongly recommended.
2. **Agent harnesses** I use or want: Claude Code, Codex, Cursor, opencode, others.
3. **Models.** Which I pay for and how (subscriptions, per token). This feeds the model ranking
   in the `subagents` skill.
4. **Tools.** Offer every package in `packages/` with one line each, and recommend a set per
   machine from its role and OS. Ask what else I want available (apps, CLIs, services) so the
   fleet can install, health-check and update them.
5. **Phone access.** T3 Code with T3 Connect, an ssh app, both, or none.
6. **Alerts.** Desktop notifications only, or also phone push through ntfy.
7. **Screenshots.** Where my screenshot tool saves, so it can become the drop folder.
8. **About me**, for my rules: name, what I build, work and personal email, default stack, and
   any rules I already give agents. Offer to read my existing `CLAUDE.md` / `AGENTS.md` and fold
   them in.

Show me the plan back as a table (machine, role, OS, packages, harnesses) and wait for my yes.

## Phase 2: create my fleet repo

1. Create my private repo from the template:
   `gh repo create <me>/fleet --private --template Aryan-Saini/agent-fleet --clone` in `~`,
   or clone the kit and push it to a new private repo if template creation is unavailable.
   Add the kit as `upstream` so I can pull improvements later.
2. Run `./install.sh --role controller --name <name> --packages "<list>"` on this machine. It
   creates `fleet.env`, `computers.md`, `rules/`, `skills-local/` and `machines/` from
   `templates/`, puts the `fleet` commands on PATH, and links rules and skills into every
   harness.
3. Fill `computers.md` from the interview: every machine, role, OS, how they reach each other,
   the drop folder paths, enabled packages. Delete placeholder rows.
4. Create `machines/<name>/README.md` for every machine from `templates/machine-README.md`.
   Record hardware, storage rules (what must never be written to, where big data goes), the LAN
   fallback address, and the package manager.
5. Create `automations/README.md` from `templates/automations-README.md` and `incidents/` with
   `templates/incident.md` in it as the format.
6. Write `rules/AGENTS.md` from the template and the "about me" answers. Keep it
   harness-neutral. Put Claude-only guidance in `rules/CLAUDE.md` below the import. Remove every
   `<placeholder>`. Show me both files before committing.
7. Copy `skills/subagents` to `skills-local/subagents` and fill its model table from my answers.
   A skill in `skills-local/` overrides the kit's skill of the same name, and kit upgrades never
   touch `skills-local/`. Do the same for any other kit skill you personalize.
8. Commit with conventional commits (`feat: initial fleet`) and push.

## Phase 3: set up each package

For each machine, walk each enabled package's README: install, configure, verify. Order:
`tailscale`, then ssh aliases on every machine (each machine needs an alias for every other),
then `drop-folder`, then the rest.

- If a package doesn't cover a machine's OS, port it following `docs/porting.md`: same command
  names, same check contract. Put the port in the package folder and note it in that
  `machines/<name>/README.md`.
- For a tool I asked for that has no package, create one in `packages/<name>/` following
  `packages/README.md`: a README with install, verify and update steps, and a `check.sh` if it
  can silently die. Add it to that machine's `FLEET_PACKAGES`.

## Phase 4: bring up each worker

For each worker, following the `fleet-add-device` skill:

1. Clone my fleet repo to `~/fleet` on it.
2. `./install.sh --role worker --name <name> --controller <controller alias> --packages "<list>"`.
3. Apply `packages/always-on` and confirm lingering (Linux) or auto-login (macOS).
4. List the logins only I can do (agent CLIs, `gh`, T3 Connect), wait for me, then verify.
5. If I want phone push, generate a random ntfy topic, put it in that machine's `machine.env`,
   and tell me to subscribe to it in the ntfy app.

## Phase 5: prove it works

Run each and show me the output:

- `fleet` on every machine: right name, role, packages.
- `fleet health --probe` on every worker: healthy, or every failure is something waiting on me.
- `fleet send <worker> <file>` from the controller, and back.
- A file dropped in `~/drop` arrives on the other side within 30 seconds.
- `ssh <worker> 'fleet alert test "hello from the worker"'` reaches me on every channel I chose.
- `ssh <worker> fleet sync` after a test commit on the controller: the change arrives.
- A test work order: write a one-line script that prints the date and exits, run
  `fleet workorder start smoke ./that-script` on the worker, and show me the report in `~/drop`.
- Ask one agent per harness on the worker what my work email is. It should know.

Record what you verified and the date in each `machines/<name>/README.md`, commit, push.

## Phase 6: hand over

Tell me, briefly:

- how to start an agent on the worker from my phone,
- how to drop a screenshot for it,
- that `/fleet-update` updates everything and `/fleet-add-device` adds a machine,
- that rules and skills are edited only on the controller, then committed and pushed,
- that I can paste this prompt again any time to change the fleet.
