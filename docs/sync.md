# Sync: every path config takes between machines

Almost everything moves one way: the controller authors, the worker receives. The exceptions
are repos that are meant to be edited on both machines, and logins, which never move at all.
This page lists every path in one table, then explains the global instruction files, which are
the ones people get wrong.

## The table

| what | mechanism | direction | cadence | conflict rule |
| --- | --- | --- | --- | --- |
| harness config and skills (`~/.claude`, `~/.codex`, `~/.cursor`, `~/.agents`) | dot-repos: each harness home is its own private git repo | controller to worker | controller pushes on every edit; worker resets every 30 min and after every resume | controller wins. The worker saves local edits to `refs/<worker>-local/*`, then `reset --hard origin/main` |
| fleet repo (`~/fleet`): docs, scripts, units, settings overlays | git | controller to worker | same as the dot-repos | same: controller wins |
| agent settings (Claude `settings.json`, Codex `config.toml`, T3 settings and keybindings) | `settings-sync`: shared file plus per-machine overlay in the fleet repo | controller to worker | captured on the controller daily and on demand; applied on the worker after each config sync | the repo wins on apply, with a backup first. Capture refuses to run anywhere but the controller |
| Cursor's global rules | `mirror-instructions` generates `~/.cursor/rules/<name>.mdc` from `AGENTS.md` | controller, then rides the Cursor dot-repo | at settings capture, or by hand after editing `AGENTS.md` | generated; a hand edit is overwritten |
| opencode config (`~/.config/opencode/opencode.jsonc`) | a copy in the fleet repo, copied into place | controller to worker | at settings capture and config sync | the repo copy wins |
| skill scope (which skills a machine loads) | derived from each `SKILL.md`'s `scope:` and `platform:` at apply time | n/a | every apply | never stored, so a new skill disables itself on the wrong machines |
| no-PR repos (notes vault, coursework, a deploy-from-main app) | `repo-sync`, per repo `full` or `pull` mode | both ways | every 15 min from the worker, daily safety net on the controller | `full`: commit, rebase on `origin/main`, push; a rebase conflict aborts and is reported, never forced. `pull`: fast-forward only, never commits |
| static API keys | `fleet secrets push <machine>` over ssh | controller to worker | on demand, after you change a key | the pushed file replaces the remote one, mode 600 |
| keys for GUI apps and services | login-time loader: `launchctl setenv` on macOS, `systemctl --user set-environment` before T3 on Linux | local | at login or boot | reads the local secrets file; restart an app to pick up a change |
| logins (Claude Code, Codex, `gh`, T3, cloud CLIs) | none | never synced | n/a | log in on each machine. Shared OAuth tokens rotate and two machines log each other out: copying one Codex `auth.json` gives "refresh token was already used" |
| files | `to-worker` / `to-controller`, T3 attachments | both ways | on demand | n/a. See [communicate.md](communicate.md) |

Why one way: a config the worker could edit would eventually fork from the controller's, and
every agent on the worker would quietly follow different rules. Making the worker's edits
disappear within 30 minutes is blunt, but you find out fast, and the ref keeps the edit in case
it mattered.

To push a change to the worker now instead of waiting:
`ssh <worker> 'systemctl --user start <sync-unit>'` (`fleet sync` in the kit).

## Global instruction files, skills and the fleet repo

Three kinds of thing get confused here: the outermost rules files every agent loads, skills,
and the fleet repo. They live in different repos and travel the same way.

```
controller                                   worker
~/.claude   (dot-repo)  CLAUDE.md, skills/ links  --push-->  GitHub  --reset 30m-->  ~/.claude
~/.codex    (dot-repo)  AGENTS.md                 --push-->  GitHub  --reset 30m-->  ~/.codex
~/.agents   (dot-repo)  skills/<name>/  (real)    --push-->  GitHub  --reset 30m-->  ~/.agents
~/.cursor   (dot-repo)  rules/<name>.mdc  (generated from AGENTS.md by mirror-instructions)
~/fleet     (repo)      CLAUDE.md (+ AGENTS.md symlink), docs, scripts, settings/
```

| file | who reads it | real copy | how other harnesses get it | how it reaches the worker |
| --- | --- | --- | --- | --- |
| `~/.claude/CLAUDE.md` | Claude Code | the Claude dot-repo | they don't. It holds the shared rules plus Claude-only tooling guidance that would be noise elsewhere | dot-repo push, worker reset |
| `~/.codex/AGENTS.md` | Codex directly; opencode via `"instructions": ["~/.codex/AGENTS.md"]` in `opencode.jsonc` | the Codex dot-repo | by reference, so an edit needs no copy step. Harness-neutral on purpose | dot-repo push, worker reset |
| `~/.cursor/rules/<name>.mdc` | Cursor | generated, never hand-edited | `mirror-instructions` writes it from `AGENTS.md` with `alwaysApply: true` frontmatter, because Cursor's user rules must be `.mdc` | rides the Cursor dot-repo |
| skills | every harness | `~/.agents/skills/<name>/`, in the agents dot-repo | `~/.claude/skills/<name>` is a relative symlink into it (`../../.agents/skills/<name>`); Codex, Cursor and opencode read `~/.agents/skills` directly. A few Claude-only skills are real folders in `~/.claude/skills` | the agents dot-repo carries the content; each consuming repo tracks its own symlinks |
| `~/fleet/CLAUDE.md` | any agent working in the fleet repo | the fleet repo | `AGENTS.md` beside it is a symlink to it, so Claude and Codex read the same project rules | fleet push, worker reset |

Rules that fall out of this:

- **Change the rules for every harness in `~/.codex/AGENTS.md`. Change Claude alone in
  `~/.claude/CLAUDE.md`.** Then rerun `mirror-instructions` for Cursor.
- **A shared skill refers to its own files as `~/.agents/skills/<name>/...`**, never through
  the Claude path, which only resolves through a symlink.
- **Anything in `~/.agents/skills` is loaded by opencode**, symlinks or not. To make a skill
  Claude-only, move the folder into `~/.claude/skills`. See [harnesses.md](harnesses.md).
- **Commit and push in the same pass as the edit.** An unpushed commit is invisible to the
  worker. Three small shell functions on the controller make that cheap: `editmd` opens every
  rules file that applies to the current directory, `dotstatus` lists dirty dot-repos, and
  `dotpush` commits and pushes all of them.

Each dot-repo uses an **allowlist** `.gitignore`: ignore `/*`, then re-include only rules files,
`skills/`, `rules/`, hooks and commands, with explicit excludes for `*token*.json`, `*.key`,
`*.pem` and `.env`. That is what makes it safe to check a repo out on top of a live harness
directory full of credentials, sessions and caches. Bootstrap on a populated directory is
`git init`, `remote add`, `fetch`, `reset --hard origin/main`: tracked config is written,
untracked local state is left alone.

### The kit's simpler version

This repo collapses the four dot-repos into one: your fleet repo holds `rules/AGENTS.md`,
`rules/CLAUDE.md` and `skills/`, and `fleet link` symlinks them into each harness's place and
generates the Cursor `.mdc`. One repo, one push, one sync. See [skills.md](skills.md).

Pick by how you work. One repo is easier to start with and to reason about. Separate dot-repos
fit if you already version `~/.claude` and friends, want each harness home to stand alone, or
share one harness's config without the others. The direction and the conflict rule are the same
either way.

## settings-sync in detail

Each harness's settings split three ways:

| class | example | where it lives |
| --- | --- | --- |
| shared | model, effort, hooks, behavior flags | `settings/<harness>/shared.json` |
| per machine | permissions, plugin sets, absolute paths | `settings/<harness>/<machine>.json` |
| ignored | tokens, caches, window geometry | nowhere |

`apply` merges shared over the machine's own file into the live settings, after a backup. That
per-machine overlay is what stops a one-way sync from handing the worker the controller's
`bypassPermissions` and its macOS-only statusline path. Per-machine files are edited on the
controller like any other tracked file.

- **Claude**: shared plus overlay merged into `settings.json`. `skillOverrides` is derived on
  every apply from each skill's `scope:` and `platform:`, so the controller does not load
  worker-only or Linux-only skills and the worker does not load controller-only or macOS-only
  ones.
- **Codex**: captured for diff and restore, and a few keys (`model`, `model_reasoning_effort`,
  `service_tier`) are checked for drift, but `config.toml` is never regenerated. It carries the
  trusted project list and MCP wiring, and a bad rewrite breaks every Codex session.
- **T3**: keybindings shared; `settings.json` and client settings per machine. The headless
  worker has no desktop client to configure.

`settings-sync check` reports drift in keys that are supposed to match everywhere.

## Secrets

Static keys live in `~/.config/agent-secrets.env` on each machine, mode 600, never in git.
Shells read it through `~/.zshenv` (or the worker's shared env file), so non-interactive ssh gets
the keys too. Config files reference `${KEY_NAME}`, never the value, so they are safe to commit.

Two consumers do not read your shell profile and need the login-time loader: apps launched from
the Dock (launchd's environment) and systemd user services such as T3. The tell that the loader
did not run: every keyed MCP server across unrelated providers fails at the same moment with
`invalid_token`, which real expiry never does. See [`packages/settings-sync`](../packages/settings-sync/)
and [`packages/mcp`](../packages/mcp/).
