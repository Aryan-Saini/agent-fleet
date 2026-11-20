# settings-sync

How the settings of Claude Code, Codex and T3 Code stay in step across machines, and how a few
repos that never take PRs stay identical everywhere. Rules and skills are a separate path:
`fleet link` and `fleet sync` (see [docs/skills.md](../../docs/skills.md)).

## The rule: one author

Config flows one way. You change settings on the controller, they are captured into your fleet
repo, and workers apply them. A worker never captures. That one rule is what keeps a sparsely
configured worker (two keys set) from overwriting the fleet's shared settings (eleven keys) on its
first sync.

| what | source of truth | how it reaches other machines |
| --- | --- | --- |
| rules (`CLAUDE.md`, `AGENTS.md`) | `rules/` in your fleet repo | `fleet link`; Cursor gets a generated `.mdc` |
| skills | `skills*/` in your fleet repo | `fleet link`, by role, harness and OS |
| Claude Code settings | `settings/claude/shared.json` + `settings/claude/<machine>.json` | `settings-sync apply` |
| Codex `config.toml` | each machine's own file | snapshot only, `settings/codex/<machine>.toml`, drift-checked |
| T3 Code | keybindings shared, settings per machine | `settings-sync apply` |
| notes repos and the like | the repo's `main` | `repo-sync` |

## Shared keys and machine overlays

`settings.json` mixes keys that should match everywhere with keys that must not:

| shared (`shared.json`) | per machine (`<machine>.json`) |
| --- | --- |
| `model`, `effortLevel`, `theme`, `hooks`, `includeCoAuthoredBy`, `autoMemoryEnabled`, MCP server allow and deny lists | `permissions` (looser on the controller you watch, an explicit allow-list on an unattended worker), plugin sets, absolute paths such as a status line script, anything the OS decides |

`apply` writes `deep_merge(<machine>.json, shared.json)`: the machine's own file with shared keys
on top, after backing the live file up to `settings.json.bak`. A worker's overlay is a normal
tracked file you edit on the controller. That is how a one-way sync avoids handing a worker the
controller's `bypassPermissions` or a path under the controller's home.

Codex is captured but never regenerated. Its `config.toml` holds the trusted project list and MCP
wiring, and stdlib Python can't write TOML. Snapshots give you diff and restore, and `check`
reports when `model` or `model_reasoning_effort` differ between machines. Credential-looking
values are redacted in the snapshot.

```bash
settings-sync capture   # controller: live -> settings/ (then commit and push)
settings-sync apply     # worker: settings/ -> live, after each fleet sync
settings-sync check     # anywhere: drift in keys that must match
```

[`bin/settings-sync`](bin/settings-sync) is the reference. Edit `CLAUDE_SHARED` at its top to
choose which keys travel. It reads the machine name and role from `machine.env`.

Wire it in: on the controller, run `capture` from the same job that commits your fleet repo (a
nightly [mac-automations](../mac-automations/) tool, or by hand after a settings change). On
workers, run `apply` after `fleet sync` pulls.

## Instructions for every harness

One rules file per harness family, generated, never hand-edited in two places:

- `~/.claude/CLAUDE.md` for Claude Code, which imports `AGENTS.md` and adds Claude-only notes.
- `~/.codex/AGENTS.md` for Codex, read directly; opencode points at it with `instructions` in
  `opencode.jsonc`.
- Cursor wants `.mdc` files with frontmatter under `~/.cursor/rules`, so it gets a generated copy
  with `alwaysApply: true` (without it Cursor only fetches the rule when it guesses it matches)
  and a "generated, edit AGENTS.md" banner. `fleet link` writes it as `fleet-global.mdc`.

opencode's global `opencode.jsonc` lives outside any dot-repo; keep a copy in your fleet repo and
copy it into place on sync.

## repo-sync: repos without PRs

Some repos are just shared state: a notes vault, a study folder, a personal wiki. PRs there are
ceremony. [`bin/repo-sync`](bin/repo-sync) keeps them identical:

```bash
# ~/.config/fleet/repo-sync.list, per machine, since checkout paths differ
full ~/notes          # commit everything, rebase on origin/main, push
pull ~/dev/site       # fast-forward a clean main only; never commits
```

- **Order matters.** With `REPO_SYNC_PEER=<controller>` in the worker's `machine.env`, each run
  first does the controller's half over ssh (so its edits are pushed), then the worker rebases
  onto them. Run it on the worker every 15 minutes with a systemd timer
  ([linux-automations](../linux-automations/)) and both sides stay current; a sleeping laptop is
  reported and skipped. A daily run on the controller is a cheap safety net.
- **`pull` mode is for repos that deploy from `main`.** Auto-committing there would ship
  half-done work, so it only fast-forwards, and leaves a checkout on another branch, or with
  local commits, alone.
- **Big files stay out.** Untracked files over 5 MB go to `.git/info/exclude` instead of history.
- **Conflicts stop.** A failed rebase is aborted and reported; nothing is force-pushed.
- The peer must find `repo-sync` on its non-interactive ssh PATH (`~/.local/bin` in `.zshenv`).

Your fleet repo itself is not in the list: it is authored on the controller and workers
`reset --hard` onto it through `fleet sync`.

## Gotchas

- **A worker edit to synced config is discarded.** By design. Make the change on the controller.
- **Never capture on a worker**, even once. `settings-sync` refuses unless the role is
  `controller`.
- **Python 3.11+** for the Codex drift check (`tomllib`). launchd's `/usr/bin/python3` may be
  older; put Homebrew's first on PATH in the job that runs it.
- **`.bak` files are your undo.** `apply` keeps one; `repo-sync` never rewrites history.
