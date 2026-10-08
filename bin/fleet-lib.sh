# shellcheck shell=bash
# fleet-lib.sh: shared setup for every fleet-* command. Source it, never run it.
#
# Load order, later wins:
#   1. defaults below
#   2. $FLEET_HOME/fleet.env            shared, committed, identical on every machine
#   3. ~/.config/fleet/machine.env      this machine only, never committed
#
# FLEET_HOME is the checkout this script lives in, so the commands work from any
# clone path without configuration.

_fleet_self="${BASH_SOURCE[0]}"
while [ -L "$_fleet_self" ]; do
  _fleet_link="$(readlink "$_fleet_self")"
  case "$_fleet_link" in /*) _fleet_self="$_fleet_link" ;; *) _fleet_self="$(dirname "$_fleet_self")/$_fleet_link" ;; esac
done
FLEET_HOME="$(cd "$(dirname "$_fleet_self")/.." && pwd -P)"
unset _fleet_self _fleet_link

FLEET_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fleet"
FLEET_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/fleet"

# shellcheck disable=SC1091
[ -f "$FLEET_HOME/fleet.env" ] && . "$FLEET_HOME/fleet.env"
# shellcheck disable=SC1091
[ -f "$FLEET_CONFIG_DIR/machine.env" ] && . "$FLEET_CONFIG_DIR/machine.env"

FLEET_NAME="${FLEET_NAME:-$(hostname -s 2>/dev/null || uname -n)}"
FLEET_ROLE="${FLEET_ROLE:-unset}"
FLEET_DROP="${FLEET_DROP:-$HOME/drop}"
FLEET_PACKAGES="${FLEET_PACKAGES:-}"
FLEET_LOGS="$FLEET_STATE/logs"
FLEET_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"   # darwin | linux

# Non-interactive shells (ssh 'cmd', systemd, launchd) get a stripped PATH. Add the usual
# per-user bin dirs so agent CLIs resolve the same way they do in a terminal.
PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH FLEET_HOME FLEET_NAME FLEET_ROLE FLEET_DROP FLEET_STATE FLEET_LOGS FLEET_OS

mkdir -p "$FLEET_LOGS" 2>/dev/null

# fleet_log FILE MSG... appends a timestamped line to $FLEET_LOGS/FILE.log
fleet_log() { local f="$1"; shift; printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$FLEET_LOGS/$f.log"; }

fleet_die() { echo "${0##*/}: $*" >&2; exit 1; }

# fleet_has_package NAME is true when NAME is listed in FLEET_PACKAGES
fleet_has_package() { case " $FLEET_PACKAGES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# fleet_timeout SECS CMD... runs CMD with a time limit where one is available. macOS ships no
# `timeout`, so fall back to coreutils' gtimeout, then to no limit at all.
fleet_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else shift; "$@"; fi
}
