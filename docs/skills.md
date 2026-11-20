# Skills: one copy, every harness, every machine

A skill is a folder with a `SKILL.md` in it: instructions an agent loads when a task matches the
skill's description. Every harness looks for skills in its own folder, so without a plan you end
up with five copies of the same skill on each machine, all slightly different. This page covers
how the fleet keeps exactly one copy and makes every harness on every machine read it.

## What a symlink is

A symlink is a tiny file that points at another path. Programs that open the symlink actually
read the file or folder it points to. It works like a shortcut, except no program can tell the
difference.

```bash
ln -s ~/fleet/skills/unslop ~/.claude/skills/unslop    # make one
readlink ~/.claude/skills/unslop                       # -> /Users/you/fleet/skills/unslop
ls -la ~/.claude/skills                                 # links show as "name -> target"
```

Delete the link and the real folder is untouched. Delete the real folder and the link breaks.

## Why we link instead of copy

- **Every harness has its own folder.** Claude Code reads `~/.claude/skills/`, Codex reads
  `~/.codex/skills/`, opencode and Cursor read `~/.agents/skills/`. Same skill, three places.
- **Copies drift.** You fix a skill in Claude's folder, and Codex keeps running the old version
  for months without anyone noticing. Links leave nothing to fall out of sync, because there is
  only one file.
- **The one copy lives in git.** The real folder is in your fleet repo, so every change is
  committed, reviewable and revertible, and git carries it to every other machine.
- **Edit once, everyone gets it.** Change `skills/unslop/SKILL.md` on the controller, push, and
  every harness on every worker reads the new version after the next sync.

## The layout

```
~/fleet/                          the repo, the only real copy
  skills/<name>/                  every machine
  skills-controller/<name>/       controllers only
  skills-worker/<name>/           workers only
  skills-local/<name>/            yours; overrides a kit skill of the same name

~/.claude/skills/<name>   -> ~/fleet/skills/<name>     Claude Code
~/.codex/skills/<name>    -> ~/fleet/skills/<name>     Codex
~/.agents/skills/<name>   -> ~/fleet/skills/<name>     opencode, Cursor
```

When the same skill name exists in several places, the most specific copy wins:
`skills-local/`, then `skills-<role>/`, then `skills/`, then the `skills/` folder of an npm
package an enabled kit package ships as. Kit upgrades never touch `skills-local/`, so personalize
a kit skill by copying it there. A few kit skills (`halo`, `cua-driver`) are short pointers to a
skill that ships with the tool itself; they tell the agent where to read the real one.

Each `SKILL.md`'s frontmatter says who can use it. See the next section.

## The metadata block

Every skill in this kit opens with the same four keys under `metadata`:

```yaml
---
name: dev-server
description: Run a web app's dev server on a worker and hand the user a tailnet HTTPS link...
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "worker-expose on the worker, Tailscale with HTTPS certificates enabled, jq"
---
```

| key | means | allowed values | who reads it |
| --- | --- | --- | --- |
| `harness` | which agent harnesses get the skill | any of `claude`, `codex`, `cursor`, `opencode`. Omit for all four | `fleet link` |
| `platform` | which operating systems it works on | any of `darwin`, `linux` (add `windows` if you port one). Omit for any | `fleet link` |
| `scope` | which machine role it belongs to | exactly one of `fleet`, `controller`, `worker` | you and agents; it must match the folder |
| `requires` | what has to be installed or set up on the machine for the skill to work | free text, one line | you and agents |

**`harness` and `platform`.** `fleet link` reads both lists. A skill whose `platform` doesn't
include this machine's OS is not linked at all. Otherwise it is linked into each listed harness's
folder: `claude` into `~/.claude/skills/`, `codex` into `~/.codex/skills/`, and `cursor` or
`opencode` into `~/.agents/skills/` (both read that one folder). Harnesses never see these keys;
a skill stays out of a harness by never being linked there. That is how `control-computer`
(`harness: [claude]`, `platform: [darwin]`) exists only for Claude Code on a Mac.

**`scope`.** The folder is what enforces role, and `scope` names it:

| `scope` | folder | linked on |
| --- | --- | --- |
| `fleet` | `skills/` | every machine |
| `controller` | `skills-controller/` | controllers only |
| `worker` | `skills-worker/` | workers only |

`fleet link` picks folders by the machine's role (`skills/` plus `skills-<role>/`), so a
controller skill is not merely switched off on a worker, it is absent. Keep `scope` and the folder
in agreement: the key is how a skill read out of context (in a PR, on GitHub, pasted into a chat)
says where it belongs. A skill in `skills-local/` uses whichever scope it really has.

**`requires`.** Documentation, not enforcement. It tells a human installing the skill, and an
agent about to use it, what must already exist on the machine: a CLI on PATH, a login, an ssh
alias, a permission grant, a file such as `~/.npmrc` (never its contents). When a skill fails, this
line is the first thing to check. Write it so someone can turn it into a checklist.

## Set it up

`./install.sh` runs this for you. To do it by hand, or to repair a machine:

```bash
cd ~/fleet
fleet link          # creates every link, removes stale ones, prints what changed
ls -la ~/.claude/skills ~/.codex/skills ~/.agents/skills
```

If a real folder is already sitting where a link should go (a skill you installed by hand),
`fleet link` moves it to `<name>.pre-fleet` instead of deleting it. Move anything worth keeping
into `skills-local/`, then delete the `.pre-fleet` copy.

## Add or change a skill

Always on the controller:

```bash
mkdir -p ~/fleet/skills-local/my-skill
$EDITOR ~/fleet/skills-local/my-skill/SKILL.md    # name, description, metadata, then the instructions
fleet link                                        # links it on this machine
git -C ~/fleet add -A && git -C ~/fleet commit -m "feat(skills): my-skill" && git -C ~/fleet push
```

Restart the agent afterwards. No harness hot-reloads skills.

The `description` is the most important line. It is what the agent reads when deciding whether
to load the skill, so write down the situations and phrases that should trigger it, not a
summary of what the skill contains.

## Keep every worker in sync

Config flows one way: the controller authors, workers receive.

1. You edit and push on the controller.
2. Every 30 minutes, each worker's `fleet sync` timer resets its `~/fleet` to `origin/main` and
   runs `fleet link --quiet`. New skills get linked, deleted ones get unlinked.
3. To push a change out right away: `ssh <worker> fleet sync`.

A skill edited directly on a worker is wiped out by the next sync, so make edits on the
controller. The worker's edit isn't lost: `fleet sync` saves it to `refs/fleet-local/*` first,
so you can recover it from there.

This scales without extra work. Ten workers or one, each one pulls the same commit and links the
same skills for its role and OS. Adding a worker means cloning the repo and running
`./install.sh --role worker`.

## How the author actually syncs

The kit above keeps skills in the fleet repo. The author's private setup predates it and works the
same way with different plumbing. It is worth knowing because every rule carries over.

- **One copy.** A private git repo (`dotagents`) is checked out directly at `~/.agents`. Its
  `skills/` folder is the only real copy of every shared skill, and `skills-worker/` holds the
  worker-only ones.
- **Symlinks everywhere else.** `~/.claude/skills/<name>` is a symlink
  (`../../.agents/skills/<name>`), tracked in its own small config repo checked out at `~/.claude`.
  Codex and Cursor do the same. opencode and Cursor read `~/.agents/skills/` directly. Each config
  repo uses an allowlist `.gitignore` (ignore `*`, re-include only config), so a checkout can sit
  on top of a folder full of credentials.
- **Workers reset onto origin every 30 minutes.** A timer on each worker fetches every config repo
  and runs `git reset --hard origin/main`, after saving any local edit to a `refs/<worker>-local/*`
  ref. Workers never push. A skill edited on a worker survives until the next sync, then it's gone.
- **Scope is enforced at sync time.** The sync reads each skill's `scope` and `platform` and turns
  them into Claude Code `skillOverrides`, switching off a controller skill on a worker. Worker-only
  skills are linked in from `skills-worker/` on workers only.
- **Edit only on the controller, and commit and push in the same pass.** An unpushed commit is
  invisible to every worker. A shell helper (`dotpush "<message>"`) commits and pushes every dirty
  config repo at once, and `dotstatus` shows what is dirty. After a change a worker needs now,
  trigger its sync over ssh instead of waiting.

The `edit-md-files` skill carries these rules for agents.

## Verify

```bash
fleet link                               # "linked ..." lines mean something was missing
readlink ~/.codex/skills/unslop          # points into ~/fleet
ssh <worker> fleet sync --status         # the worker's repo matches origin/main
opencode debug skill                     # every skill opencode can see
```

The real test is asking an agent in each harness something only a skill knows.

## Starter skills

These three are the ones I use most. They ship in `skills/`, so every machine gets them as soon as
`fleet link` runs.

| skill | what it does | why start here |
| --- | --- | --- |
| [subagents](../skills/subagents/SKILL.md) | ranks your models, routes each job to the right one, and runs a council of models from different vendors to review a diff | stops every subtask from going to your most expensive model, and gets you reviews that don't share the author's blind spots |
| [file-pr](../skills/file-pr/SKILL.md) | PRs that open with the problem in plain language, then the fix | reviewers, human or bot, understand the change in ten seconds |
| [unslop](../skills/unslop/SKILL.md) | writing rules that cut AI tells: filler, hedging, em dashes, empty summaries | every agent-written message, doc and commit reads like a person wrote it |

Personalize `subagents` first: copy it to `skills-local/subagents` and put your own models and
subscriptions in its table.
