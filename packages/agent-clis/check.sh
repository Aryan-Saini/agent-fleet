#!/usr/bin/env bash
# agent-clis: every installed agent CLI is logged in. Report only; logins need a human.
[ "${1:-}" = --heal ] && exit 1
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
problems=()
has() { command -v "$1" >/dev/null 2>&1; }
to() { if has timeout; then timeout "$@"; elif has gtimeout; then gtimeout "$@"; else shift; "$@"; fi; }

if has claude && [ "$(uname -s)" = Linux ] && [ ! -s "$HOME/.claude/.credentials.json" ]; then
  problems+=("claude has no credentials (run: claude, then /login)")
fi
has codex && [ ! -s "$HOME/.codex/auth.json" ] && problems+=("codex is not logged in (codex login)")
has gh && ! gh auth status >/dev/null 2>&1 && problems+=("gh token is invalid (gh auth login)")

if [ "${FLEET_PROBE:-0}" = 1 ]; then
  if has claude; then
    out="$(cd /tmp && to 120 claude -p "reply with exactly: OK" </dev/null 2>/dev/null)"
    grep -q OK <<<"$out" || problems+=("claude did not answer a live prompt (login expired?)")
  fi
  if has codex; then
    out="$(cd /tmp && to 180 codex exec --skip-git-repo-check -s read-only "reply with exactly: OK" </dev/null 2>&1)"
    if ! grep -q OK <<<"$out"; then
      if grep -qi "refresh token was already used" <<<"$out"; then problems+=("codex refresh token was consumed by another machine (codex login)")
      else problems+=("codex did not answer a live prompt (codex login)"); fi
    fi
  fi
  if has cursor-agent; then
    to 60 cursor-agent status 2>&1 | grep -qi "logged in" || problems+=("cursor-agent is not logged in (cursor-agent login)")
  fi
fi

[ "${#problems[@]}" -eq 0 ] && exit 0
( IFS=';'; echo "${problems[*]}" ); exit 1
