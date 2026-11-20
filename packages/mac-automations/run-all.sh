#!/bin/bash
# run-all.sh: the macOS automations dispatcher (packages/mac-automations).
#
# Runs every tool through the signed runner, a private copy of bash that holds the Full Disk
# Access grant. macOS attributes access to the responsible process, so every tool inherits the
# grant and a new tool never needs a new permission.
#
# Layout, next to this script:
#   tools/<name>/<name>.sh   the tool. Must match its folder name and be executable
#   tools/<name>/cadence     optional: "hourly" or "every <N>m" (e.g. "every 5m"). Absent = daily
#   tools/<name>/logs/       that tool's own log, created on first run
#   manual/<name>/           tools kept for running by hand. Never scanned
#
# Two LaunchAgents fire it, two lanes, so a long daily pass never delays a frequent tool:
#   --scheduled  hourly at :30. Hourly tools run every fire; daily tools run on the first fire
#                at or after DAILY_AT, so a pass missed while the Mac slept runs on wake.
#                Skips "every" tools.
#   --frequent   every minute. Runs only "every <N>m" tools, each once N minutes have passed.
#                Prints only failures and trims those tools' logs past 1 MB.
#
# By hand:  ./run-all.sh           every tool now, ignoring cadence
#           ./run-all.sh <name>    one tool
# A manual run starts from your shell, not launchd, so protected paths can still be denied.
# Test those through launchd (see the package README).
set -uo pipefail

BASE="$(cd "$(dirname "$0")" && pwd -P)"
TOOLS="$BASE/tools"
RUNNER="${AUTOMATIONS_RUNNER:-$HOME/Library/Application Support/automations/Automations}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/automations"
LAST_DAILY="$STATE/last-daily"
DAILY_AT="${AUTOMATIONS_DAILY_AT:-23:30:00}"

# launchd gives only /usr/bin:/bin:/usr/sbin:/sbin. Every tool inherits this one PATH, so tools
# call node, aws, uv and friends by name instead of pinning install paths that move on upgrade.
# node comes from nvm's newest installed version, if nvm is there.
NVM_NODE=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1)
export PATH="$HOME/.local/bin:$HOME/bin${NVM_NODE:+:$NVM_NODE}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ ! -x "$RUNNER" ]; then
  echo "[automations] runner missing at $RUNNER, using /bin/bash (no Full Disk Access). Run packages/mac-automations/install.sh"
  RUNNER=/bin/bash
fi

stamp=$(date '+%Y-%m-%d %H:%M:%S')
scheduled=0 frequent=0
[ "${1:-}" = "--scheduled" ] && { scheduled=1; shift; }
[ "${1:-}" = "--frequent" ] && { frequent=1; shift; }
only="${1:-}"
mkdir -p "$STATE"

# Daily tools are due when the last daily pass predates the most recent DAILY_AT.
daily_due=1
if [ "$scheduled" -eq 1 ]; then
  now=$(date +%s)
  boundary=$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date +%Y-%m-%d) $DAILY_AT" +%s)
  [ "$now" -lt "$boundary" ] && boundary=$((boundary - 86400))
  last=$(cat "$LAST_DAILY" 2>/dev/null || echo 0)
  [ "$last" -ge "$boundary" ] && daily_due=0
fi

ran=0
for dir in "$TOOLS"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  [ -n "$only" ] && [ "$only" != "$name" ] && continue
  script="$dir$name.sh"
  [ -x "$script" ] || { echo "[automations] $name: $script missing or not executable"; continue; }

  cadence=$(tr -d '[:space:]' 2>/dev/null < "${dir}cadence" || true)
  every=""
  [[ "$cadence" =~ ^every([0-9]+)m$ ]] && every=${BASH_REMATCH[1]}
  if [ "$frequent" -eq 1 ]; then
    [ -n "$every" ] || continue
    last=$(cat "$STATE/$name.last" 2>/dev/null || echo 0)
    # 5 s of slack: launchd's 60 s interval drifts a little either way.
    [ $(( $(date +%s) - last )) -ge $(( every * 60 - 5 )) ] || continue
    date +%s > "$STATE/$name.last"
  elif [ "$scheduled" -eq 1 ]; then
    [ -n "$every" ] && continue
    [ "$cadence" != hourly ] && [ "$daily_due" -eq 0 ] && continue
  fi

  mkdir -p "${dir}logs"
  log="${dir}logs/$name.log"
  echo "===== run $stamp =====" >> "$log"
  "$RUNNER" "$script" >> "$log" 2>&1
  code=$?
  if [ -n "$every" ] && [ "$(stat -f %z "$log")" -gt 1048576 ]; then
    tail -n 2000 "$log" > "$log.trim" && mv -f "$log.trim" "$log"
  fi
  if [ "$frequent" -eq 0 ] || [ "$code" -ne 0 ]; then
    echo "[automations] $name -> exit=$code (log: $log)"
  fi
  ran=$((ran + 1))
done

if [ "$scheduled" -eq 1 ] && [ "$daily_due" -eq 1 ] && [ -z "$only" ]; then
  date +%s > "$LAST_DAILY"
fi

[ "$frequent" -eq 1 ] && exit 0
[ "$ran" -eq 0 ] && echo "[automations] no matching tools in $TOOLS"
pass=manual; [ "$scheduled" -eq 1 ] && { [ "$daily_due" -eq 1 ] && pass=daily || pass=hourly; }
echo "[automations] finished $stamp ($ran tool(s), $pass)"
