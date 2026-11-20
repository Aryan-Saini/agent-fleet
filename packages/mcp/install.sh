#!/usr/bin/env bash
# mcp install: get agent keys to GUI apps and services at login, and keep the keyless servers
# fresh on workers. Idempotent. Installing the servers themselves is one npm line, in the README.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck disable=SC1091
. "$here/../../bin/fleet-lib.sh"

case "$FLEET_OS" in
darwin)
  LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA"
  dest="$LA/fleet.agent-secrets.plist"
  sed "s|__HOME__|$HOME|g" "$here/units/fleet.agent-secrets.plist" > "$dest.new"
  if cmp -s "$dest.new" "$dest"; then rm -f "$dest.new"
  else
    mv -f "$dest.new" "$dest"
    launchctl bootout "gui/$(id -u)" "$dest" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$dest" && echo "loaded fleet.agent-secrets (keys reach Dock-launched apps at login)"
  fi
  ;;
linux)
  U="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; mkdir -p "$U"
  cp "$here/units/agent-secrets.service" "$U/"
  units="agent-secrets.service"
  if [ "$FLEET_ROLE" = worker ]; then
    cp "$here/units/mcp-update.service" "$here/units/mcp-update.timer" "$U/"
    units="$units mcp-update.timer"
  fi
  systemctl --user daemon-reload
  # shellcheck disable=SC2086
  systemctl --user enable $units >/dev/null 2>&1 && echo "enabled $units"
  [ -r "$HOME/.config/agent-secrets.env" ] && systemctl --user start agent-secrets.service
  [ "$FLEET_ROLE" = worker ] && systemctl --user start mcp-update.timer
  ;;
esac
command -v mcp-server-launch >/dev/null || echo "NOTE: re-run ./install.sh so packages/mcp/bin lands on PATH"
