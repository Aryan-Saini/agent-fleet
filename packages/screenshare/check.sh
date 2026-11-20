#!/usr/bin/env bash
# screenshare: on a Mac with Sill installed, Sill is running so the phone can reach this screen.
# Heals by clearing quarantine and relaunching it. Nothing to check elsewhere.
APP=/Applications/Sill.app
[ "$(uname -s)" = Darwin ] && [ -d "$APP" ] || exit 0
if [ "${1:-}" = --heal ]; then
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null
  open -g "$APP"
  sleep 5; exit 0
fi
pgrep -x Sill >/dev/null || { echo "Sill is not running"; exit 1; }
