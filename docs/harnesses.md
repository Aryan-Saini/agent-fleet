# Harnesses: who reads what

Four agent harnesses run on the fleet: Claude Code, Codex, Cursor and opencode. They all get
their rules and skills from one place. In the kit that is your fleet repo, wired up by
`fleet link`. The author's own setup splits the same files across one git repo per harness home;
[sync.md](sync.md#global-instruction-files-skills-and-the-fleet-repo) compares the two. For MCP
see [`packages/mcp`](../packages/mcp/).

## The split

**Claude is its own thing; everything else mirrors Codex.** `AGENTS.md` is harness-neutral and is
what every agents.md harness reads: Codex directly, opencode by reference, Cursor through a
generated copy. `CLAUDE.md` carries the shared rules plus Claude-only guidance (how to use
subagents, how to drive the screen), which would be noise anywhere else. In the kit, `CLAUDE.md`
imports `AGENTS.md` with `@~/.codex/AGENTS.md`, so shared rules live once.

Change the rules for everyone in `AGENTS.md`. Change Claude alone in `CLAUDE.md`.

| harness | global rules | skills | global MCP |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/` | `~/.claude.json` |
| Codex | `~/.codex/AGENTS.md` | `~/.codex/skills/` and `~/.agents/skills/` | `~/.codex/config.toml` |
| Cursor | `~/.cursor/rules/<name>.mdc`, generated | auto-discovers `.cursor`, `.codex`, `.agents` and `.claude` skill dirs | `~/.cursor/mcp.json` |
| opencode | `instructions` -> `~/.codex/AGENTS.md` | `~/.agents/skills/` plus `skills.paths` | `mcp` block in `opencode.jsonc` |

Shared skills live once, in `~/.agents/skills` (or your fleet repo's `skills/`), and are
symlinked into each harness's skill directory. Codex may add a few of its own on top.

## Where a skill lives decides who loads it

The `harness:` key in a skill's frontmatter is read by `fleet link` to decide which folders get a
link. The harnesses themselves gate on nothing: if a skill folder is in a directory a harness
scans, it loads. So a few skills are kept out of some harnesses by where they physically live:

| skill | lives in | seen by | why |
| --- | --- | --- | --- |
| `codex-implementation` | `~/.claude/skills` | Claude | delegates *to* Codex. Meaningless inside Codex, noise in the rest |
| an image generation skill that calls a proxy's image route | `~/.agents/skills`, linked into Claude and Cursor but not Codex | Claude, Cursor, opencode | Codex has the tool natively |
| `control-computer` | `~/.claude/skills` | Claude | routes GUI work and names Claude's own tools |

That last row is the trap: **anything in `~/.agents/skills` is loaded by opencode**, symlinks or
not. To make a skill Claude-only, move the folder into `~/.claude/skills`. Removing symlinks is
not enough.

Two rules follow, and both have been broken before:

- **A shared skill refers to its own files as `~/.agents/skills/<name>/...`**, never
  `~/.claude/skills/<name>/...`. The Claude path only resolves through a symlink, so it breaks
  the moment that link is missing.
- **A shared skill must not hard-depend on a Claude-only one.** Where it needs
  `control-computer`, gate it ("if you are Claude, use ...") and give the other harnesses a path
  that ends in handing the GUI step back to the human.

Per-machine scope is a separate layer: `settings-sync` turns each skill's `scope:` and
`platform:` into Claude `skillOverrides`, so the controller does not load worker-only skills and
the reverse. See [skills.md](skills.md) and [sync.md](sync.md).

## opencode

Global config is `~/.config/opencode/opencode.jsonc`, not `~/.opencode` (which holds the binary).
Codex parity takes four settings, because opencode reaches for Claude config in two places on its
own:

| setting | where | why |
| --- | --- | --- |
| `"instructions": ["~/.codex/AGENTS.md"]` | opencode.jsonc | the shared rules, by reference. `~` expands per machine |
| `"skills": { "paths": ["~/.codex/skills"] }` | opencode.jsonc | it auto-loads `~/.agents/skills` but not Codex's own |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` | `~/.zshenv` | drops `~/.claude/skills` |
| `OPENCODE_DISABLE_CLAUDE_CODE=1` | `~/.zshenv` | drops Claude Code compatibility, which otherwise loads `~/.claude/CLAUDE.md` **on top of** `instructions` |

That last one is the non-obvious one. Without it the config looks right and `debug config`
reports the right `instructions`, but the model still gets `CLAUDE.md` as well. Set the flags in
`~/.zshenv` (or the worker's shared env file), not `~/.zshrc`, so non-interactive ssh and
services get them too.

`~/.config/opencode` is not a git checkout, so the fleet repo carries a copy of `opencode.jsonc`
and copies it into place. An unknown top-level key is a hard `ConfigInvalidError`; run
`opencode debug config` after editing.

## Cursor

User-level rules must be `.mdc` with frontmatter, so Cursor cannot reference a plain markdown
file the way opencode does. `mirror-instructions` (or `fleet link` in the kit) writes a copy of
`AGENTS.md` with `alwaysApply: true`. Never edit it by hand; the next run overwrites it.

Two gotchas:

- **Cursor still sees `~/.claude/skills`.** It gates `.claude`, `.codex` and other third-party
  skill dirs behind a single flag. Turning it off to hide Claude's skills would hide Codex's too,
  so Cursor ends up with a couple of redundant Claude-only skills. Harmless.
- **Cursor only finds global rules under `$HOME`.** It resolves `~/.cursor/rules` by walking up
  from the workspace, so a workspace in `/tmp` gets no global rules and no personal skills.
  Test in a real project under `~`, or you will wrongly conclude the setup is broken.

## Verify

Config files alone don't prove the rules loaded. Ask each harness two questions:

1. Something only your rules contain (your name, your work email). Proves rules loaded at all.
2. Something only `CLAUDE.md` contains. Claude should say yes; every other harness should say
   no. A yes elsewhere means Claude config is leaking in.

```bash
opencode debug skill        # every skill opencode can see
opencode debug config       # instructions, mcp, skills paths
opencode mcp list
claude mcp list             # in an opted-in repo
```

None of the harnesses hot-reload. Restart the agent after `fleet link` or a config sync.

## Models

Different harnesses are how you reach different model vendors from one workflow: Claude Code for
Claude models, Codex for OpenAI's, opencode for open-weight models. In the author's fleet every
Claude Code and Codex session routes through one CLIProxyAPI hub with an account pool
([`packages/cliproxy`](../packages/cliproxy/)). The `subagents` skill covers ranking models and
routing work; `codex-implementation` covers handing a scoped change to Codex and reviewing its
diff.
