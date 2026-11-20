#!/usr/bin/env bash
# postdraft: the CLI is installed and has a server and a key. Report only; a key needs a human.
[ "${1:-}" = --heal ] && exit 1
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v postdraft >/dev/null || { echo "postdraft is not installed (npm i -g postdraft)"; exit 1; }
[ -s "$HOME/.postplan/config.json" ] || [ -n "${POSTPLAN_API_URL:-}" ] ||
  { echo "postdraft has no server configured (run SETUP.md once, then copy ~/.postplan here)"; exit 1; }
[ -s "$HOME/.postplan/credentials.json" ] || [ -n "${POSTPLAN_API_KEY:-}" ] ||
  { echo "postdraft has no API key (~/.postplan/credentials.json or POSTPLAN_API_KEY)"; exit 1; }
if [ "${FLEET_PROBE:-0}" = 1 ]; then
  postdraft whoami >/dev/null 2>&1 || { echo "postdraft whoami failed (key revoked or server down)"; exit 1; }
fi
exit 0
