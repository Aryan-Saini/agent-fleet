# Harnesses: who reads what

Four agent harnesses run on the fleet: Claude Code, Codex, Cursor and opencode. They all get the
same rules and the same skills from one place, the fleet repo, through `fleet link`.

## The split

**One shared rules file, one Claude addition.** `rules/AGENTS.md` is harness-neutral and is what
every agents.md harness reads. `rules/CLAUDE.md` imports it with `@~/.codex/AGENTS.md` and adds
only Claude-specific guidance (how to use subagents, how to drive the screen), which would be
noise anywhere else. Change the rules for everyone in AGENTS.md; change Claude alone in CLAUDE.md.

| harness | global rules | skills | global MCP |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` -> `rules/CLAUDE.md` | `~/.claude/skills/` | `~/.claude.json` |
| Codex | `~/.codex/AGENTS.md` -> `rules/AGENTS.md` | `~/.codex/skills/` | `~/.codex/config.toml` |
| Cursor | `~/.cursor/rules/fleet-global.mdc`, generated | auto-discovers `~/.cursor`, `~/.codex`, `~/.agents`, `~/.claude` skill dirs | `~/.cursor/mcp.json` |
| opencode | `instructions` -> `~/.codex/AGENTS.md` | `~/.agents/skills/` | `mcp` block in `opencode.jsonc` |

`fleet link` makes the symlinks and generates the Cursor file. Each skill's `harness:`
frontmatter decides which skill dirs get a link. **Where a skill physically is decides who loads
it**: frontmatter is only read by `fleet link`, the harnesses don't gate on it.

## opencode

Global config is `~/.config/opencode/opencode.jsonc`. Getting it to Codex parity takes:

| setting | where | why |
| --- | --- | --- |
| `"instructions": ["~/.codex/AGENTS.md"]` | opencode.jsonc | the shared rules, by reference |
| `OPENCODE_DISABLE_CLAUDE_CODE=1` | `~/.zshenv` | otherwise its Claude compatibility loads `~/.claude/CLAUDE.md` **on top of** `instructions`, and `debug config` won't show it |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` | `~/.zshenv` | keeps Claude-only skills out |

An unknown top-level key in opencode.jsonc is a hard `ConfigInvalidError`. Run
`opencode debug config` after editing.

## Cursor

User-level rules must be `.mdc` with frontmatter, so Cursor gets a generated copy with
`alwaysApply: true`. Never edit it by hand. Cursor resolves `~/.cursor/rules` by walking up from
the workspace, so a workspace outside `$HOME` (like `/tmp`) gets no global rules. Test in a real
project under `~`, or you will wrongly conclude the setup is broken.

## Verify

Config files alone don't prove the rules loaded. Ask each harness two questions:

1. Something only your rules contain (your name, your work email). Proves rules loaded at all.
2. Something only CLAUDE.md contains. Claude should say yes; every other harness should say no.
   A yes elsewhere means Claude config is leaking in.

```bash
opencode debug skill        # every skill opencode can see
opencode debug config       # instructions, mcp, skills paths
claude mcp list             # in an opted-in repo
```

None of the harnesses hot-reload. Restart the agent after `fleet link` or `fleet sync`.

## Models

Different harnesses are how you reach different model vendors from one workflow: Claude Code
for Claude models, Codex for OpenAI's, opencode for open-weight models through OpenRouter. The
`subagents` skill covers ranking them and routing work; `codex-implementation` covers handing a
scoped change to Codex and reviewing its diff.
