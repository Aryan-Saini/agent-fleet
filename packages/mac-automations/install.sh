#!/usr/bin/env bash
# mac-automations install: the signed runner, the dispatcher in your fleet repo, and the two
# LaunchAgents. macOS only. Idempotent. The Full Disk Access grant needs you, so it prints that
# step instead of attempting it.
#
#   AUTOMATIONS_DIR   where run-all.sh and tools/ live (default: <fleet>/automations/mac)
#   AUTOMATIONS_ID    code signing identifier for the runner (default: fleet.automations.runner)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
[ "$(uname -s)" = Darwin ] || { echo "mac-automations is macOS only; Linux uses packages/linux-automations"; exit 0; }
# shellcheck disable=SC1091
. "$here/../../bin/fleet-lib.sh"

RUNNER_DIR="$HOME/Library/Application Support/automations"
RUNNER="$RUNNER_DIR/Automations"
ID="${AUTOMATIONS_ID:-fleet.automations.runner}"
DIR="${AUTOMATIONS_DIR:-$FLEET_HOME/automations/mac}"

# 1. The runner: a private, ad-hoc signed copy of bash. Built once and never touched again,
#    because a changed binary loses its Full Disk Access grant without telling anyone.
#    It lives outside ~/Desktop and ~/Documents: launchd will not start a binary stored there.
if [ -x "$RUNNER" ] && codesign -v "$RUNNER" 2>/dev/null; then
  echo "runner present: $RUNNER"
  fresh=0
else
  mkdir -p "$RUNNER_DIR"
  cp /bin/bash "$RUNNER"
  codesign -s - -f --identifier "$ID" "$RUNNER" || { echo "codesign failed" >&2; exit 1; }
  echo "built runner: $RUNNER (identifier $ID)"
  fresh=1
fi

# 2. The dispatcher and an empty tools/ in your fleet repo, so tools are tracked with the rest.
#    An existing run-all.sh is yours; it is never overwritten.
mkdir -p "$DIR/tools" "$DIR/manual"
if [ -f "$DIR/run-all.sh" ]; then
  echo "kept existing $DIR/run-all.sh"
else
  cp "$here/run-all.sh" "$DIR/run-all.sh" && chmod +x "$DIR/run-all.sh"
  echo "installed $DIR/run-all.sh"
fi

# 3. Two triggers: hourly at :30 (--scheduled) and every minute (--frequent).
LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA"
for p in "$here"/fleet.automations.plist "$here"/fleet.automations-frequent.plist; do
  dest="$LA/$(basename "$p")"
  sed -e "s|__HOME__|$HOME|g" -e "s|__AUTOMATIONS__|$DIR|g" "$p" > "$dest.new"
  if cmp -s "$dest.new" "$dest"; then rm -f "$dest.new"; continue; fi
  mv -f "$dest.new" "$dest"
  launchctl bootout "gui/$(id -u)" "$dest" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$dest" && echo "loaded $(basename "$dest")"
done

if [ "$fresh" = 1 ]; then
  cat <<EOF
you: grant Full Disk Access to the runner, once:
     System Settings > Privacy & Security > Full Disk Access > + > Cmd+Shift+G >
     $RUNNER
     then turn its switch on. Every tool you add later inherits it.
EOF
fi
