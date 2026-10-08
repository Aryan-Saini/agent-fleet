# agent-clis

The agent CLIs a worker runs: Claude Code, Codex, Cursor's `cursor-agent`, opencode, and `gh`.
Their logins expire, get revoked, or get consumed by another machine, and nothing tells you until
an agent you started from your phone fails. This package catches that.

## Install

Install whichever you use. Each one is logged in by hand, once, on each machine.
**Credentials are per machine and never sync.**

| tool | install | log in |
| --- | --- | --- |
| Claude Code | `curl -fsSL https://claude.ai/install.sh \| bash` | `claude`, then `/login` |
| Codex | `npm i -g @openai/codex` | `codex login` (`--device-auth` on a headless box) |
| Cursor | `curl https://cursor.com/install -fsS \| bash` | `cursor-agent login` |
| opencode | `curl -fsSL https://opencode.ai/install \| bash` | `opencode auth login` |
| GitHub CLI | your package manager | `gh auth login` |

## Running an agent on another machine

Headless agents take a prompt and print the result, so they compose with ssh:

```bash
ssh worker '~/.local/bin/claude -p "summarize ~/drop/report.md" '
ssh worker 'cd ~ && codex exec -s read-only --skip-git-repo-check "audit ~/drop/x.py" < /dev/null'
ssh worker 'tmux new -d -s job "claude -p \"run the tests and fix failures\" > ~/drop/job.md 2>&1; fleet-alert job done"'
```

Use absolute paths or put `~/.local/bin` on PATH in `~/.zshenv` (zsh) or `~/.profile`: a
non-interactive ssh does not read `.zshrc`.

## Health

Cheap checks every run: each installed CLI has its credential file. With `FLEET_PROBE=1` (daily,
or `fleet health --probe`) it sends each one a live prompt and expects `OK` back. No heal:
logging in needs a human.

## Gotchas

- **Claude Code on macOS keeps credentials in the Keychain**, which a non-interactive ssh session
  cannot unlock. So `ssh mac 'claude -p ...'` fails with "Not logged in" while the same command
  works on Linux, where credentials are a file. Drive Claude on a Mac from that Mac, or use Codex.
- **Codex refresh tokens are single use.** Copying `~/.codex/auth.json` to two machines works
  until one refreshes, then the other fails with "refresh token was already used". Log in on each
  machine, or re-copy after every refresh.
- **Codex needs `< /dev/null`** without a TTY, or it waits on stdin forever, and
  `--skip-git-repo-check` outside a repo.
- Services started by systemd or launchd do not read your shell profile, so they get none of the
  environment variables your MCP keys live in. See `packages/mcp`.
