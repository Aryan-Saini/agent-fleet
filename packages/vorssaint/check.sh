#!/usr/bin/env bash
# vorssaint: the menu bar app is running (the release, or a DEV build from a fork).
# Heals by relaunching whichever one is installed, DEV first.
[ "$(uname -s)" = Darwin ] || exit 0
if [ "${1:-}" = --heal ]; then
  open -ga "Vorssaint DEV" 2>/dev/null || open -ga Vorssaint
  sleep 5; exit 0
fi
pgrep -x Vorssaint >/dev/null || pgrep -x VorssaintDeveloper >/dev/null ||
  { echo "Vorssaint is not running"; exit 1; }
