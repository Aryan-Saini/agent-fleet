#!/usr/bin/env bash
# postdraft: the CLI is installed and pointed at your server. Report only; a key needs a human.
[ "${1:-}" = --heal ] && exit 1
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v postdraft >/dev/null || { echo "postdraft is not installed (npm i -g postdraft)"; exit 1; }
[ -s "$HOME/.postplan/config.json" ] || [ -n "${POSTPLAN_API_URL:-}" ] ||
  { echo "postdraft has no server configured (run SETUP.md once, then fleet secrets push)"; exit 1; }
if [ "${FLEET_PROBE:-0}" = 1 ]; then
  postdraft whoami >/dev/null 2>&1 || { echo "postdraft whoami failed (key revoked or server down)"; exit 1; }
fi
exit 0
