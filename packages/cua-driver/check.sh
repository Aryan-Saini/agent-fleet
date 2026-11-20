#!/usr/bin/env bash
# cua-driver: on a Mac with Cua Driver installed, the daemon runs and holds Accessibility and
# Screen Recording. Report only: the daemon must start under its own signed identity (not a shell's)
# to keep its grants, and a missing permission needs a human.
command -v cua-driver >/dev/null || exit 0
[ "$(uname -s)" = Darwin ] || exit 0
[ "${1:-}" = --heal ] && exit 1
st="$(cua-driver permissions status --json 2>/dev/null)" || { echo "cua-driver permissions status failed"; exit 1; }
grep -q '"daemon_running": true' <<<"$st" || { echo "Cua Driver daemon is not running"; exit 1; }
grep -q '"accessibility": true' <<<"$st" || { echo "Cua Driver lacks Accessibility (cua-driver permissions grant)"; exit 1; }
grep -q '"screen_recording": true' <<<"$st" || { echo "Cua Driver lacks Screen Recording (cua-driver permissions grant)"; exit 1; }
exit 0
