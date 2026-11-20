---
name: edit-md-files
description: The user's agent instruction files (CLAUDE.md, AGENTS.md) and skills. Use when editing, adding to, or reasoning about global rules or memory; when deciding WHERE a new rule or skill should go so it applies to the right harness at the right scope; when they say "editmd", "add this to my rules", "make this global", "why is this applied everywhere"; and IMMEDIATELY after editing anything in the fleet repo's rules/ or skills folders, or under ~/.claude, ~/.codex, ~/.agents or ~/.cursor, since it must be committed and pushed.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "the fleet repo checkout (or the config repos, in the dot-repo layout)"
---

# Rules and skills

## Which file applies where

Every harness walks up from its working directory to `$HOME` collecting its own rules file, so a
file's **location is its scope**.

| file | read by | applies |
| --- | --- | --- |
| `~/.claude/CLAUDE.md` -> `rules/CLAUDE.md` | Claude Code | every session |
| `~/.codex/AGENTS.md` -> `rules/AGENTS.md` | Codex; opencode via `instructions` | every session |
| `~/.cursor/rules/fleet-global.mdc` | Cursor | every session. Generated from AGENTS.md by `fleet link`; never edit it |
| `<repo>/AGENTS.md`, `<repo>/CLAUDE.md` | each harness | that project only |

`rules/CLAUDE.md` imports `rules/AGENTS.md`, so shared rules live once. Claude-only guidance goes
below the import in CLAUDE.md; everything else goes in AGENTS.md. Full map and verification:
`docs/harnesses.md`.

## Where to put a new rule

Global rules load into every session, so anything narrow there is context tax on unrelated work.
Decide in this order:

1. Applies to one directory? That directory's `AGENTS.md` / `CLAUDE.md`.
2. Applies to one kind of task? A **skill**, so it loads only when relevant.
3. Genuinely applies to everything? Only then, `rules/AGENTS.md` (or `rules/CLAUDE.md` if it is
   Claude-specific).

Never write the same prose in two files. Pick one home and point at it from the other.

## Where to put a new skill

| folder | linked on |
| --- | --- |
| `skills/` | every machine |
| `skills-controller/` | the controller only |
| `skills-worker/` | workers only |
| `skills-local/` | every machine; yours, untouched by kit upgrades. Overrides a kit skill with the same name |

The frontmatter `metadata` block decides the rest: `harness` (which harness folders get a link),
`platform` (which OSes), `scope` (`fleet`, `controller` or `worker`, matching the folder) and
`requires` (what must be installed for it to work, for humans and agents to read). A skill stays
out of a harness by never being linked there. A skill that refers to its own files uses its path
in the fleet repo, not a harness's link to it. Full reference: `docs/skills.md`.

## After editing: commit and push, from the controller

Edit on the controller only. Workers `reset --hard` onto the remote every 30 minutes, so an edit
made on a worker is discarded.

Once the change is complete (not mid-task), one commit per logical change:

```bash
cd <fleet repo> && fleet link && git add -A && git commit -m "docs(rules): <what changed>" && git push
```

`fleet link` makes a new or renamed skill appear immediately on this machine; workers pick it up
on their next sync. Restart running agents: none of the harnesses hot-reload rules.

## The dot-repo layout

Some people (the author included) keep config in several small private repos checked out
directly over the live config folders instead of one fleet repo: `~/.claude`, `~/.codex`,
`~/.agents`, `~/.cursor`. Shared skills live once in the `~/.agents` repo and every other
harness folder holds a symlink into it:

```bash
ln -s ../../.agents/skills/<name> ~/.claude/skills/<name>   # the link is tracked in that repo
```

Each repo uses an **allowlist** `.gitignore` (ignore `*`, re-include only config), which is why a
checkout can sit on top of a folder holding credentials. If `git add -A` skips a file you
expected, that is the allowlist working. Read the `.gitignore` before calling it a bug, and never
force-add anything ignored. A small shell helper that commits and pushes every dirty config repo
in one go (`dotpush "<message>"`) and one that shows what is dirty (`dotstatus`) save a lot of
missed pushes. The same rules apply: edit on the controller, commit and push in the same pass.

## Secrets

Never commit one. Before every commit in the fleet repo, check what you are adding:
`git diff --cached --stat`, and look at anything that is not prose or code. Tokens belong in
`~/.config/fleet/machine.env` or `~/.config/agent-secrets.env`, which live outside the repo.
