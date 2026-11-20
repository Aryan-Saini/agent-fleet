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
`skills-local/`, then `skills-<role>/`, then `skills/`. Kit upgrades never touch
`skills-local/`, so personalize a kit skill by copying it there.

Each `SKILL.md`'s frontmatter decides where it is linked:

```yaml
---
name: subagents
description: When delegating work to another agent or model. READ THIS before delegating.
metadata:
  harness: [claude, codex, opencode]   # which harness folders get a link; omit for all four
  platform: [darwin, linux]            # skipped on any other OS
---
```

Harnesses don't read these keys. `fleet link` does. A skill is kept out of a harness by never
linking it into that harness's folder.

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
$EDITOR ~/fleet/skills-local/my-skill/SKILL.md    # name, description, then the instructions
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
