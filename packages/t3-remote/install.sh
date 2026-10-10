#!/usr/bin/env bash
# t3-remote install: T3 Code on this machine, on the channel you chose, running as a service on
# Linux. Idempotent. Signing in to T3 Connect needs you, so it prints that step instead.
#
# Channel: T3_CHANNEL=stable|nightly from the environment, else machine.env, else stable. The
# choice is recorded in machine.env so /fleet-update keeps following it.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
want="${T3_CHANNEL:-}"
# shellcheck disable=SC1091
. "$here/../../bin/fleet-lib.sh"
CHANNEL="${want:-${T3_CHANNEL:-stable}}"
case "$CHANNEL" in stable|nightly) ;; *) echo "T3_CHANNEL must be stable or nightly, got $CHANNEL" >&2; exit 2 ;; esac
env="$FLEET_CONFIG_DIR/machine.env"
if [ -f "$env" ]; then
  if grep -q '^T3_CHANNEL=' "$env"; then sed -i.bak "s/^T3_CHANNEL=.*/T3_CHANNEL=$CHANNEL/" "$env" && rm -f "$env.bak"
  else echo "T3_CHANNEL=$CHANNEL" >> "$env"; fi
fi

case "$FLEET_OS" in
darwin)
  # The desktop app runs its own backend and updates itself.
  if ls -d /Applications/T3\ Code*.app >/dev/null 2>&1; then
    echo "T3 Code app already installed"
  elif command -v brew >/dev/null; then
    cask=t3-code; [ "$CHANNEL" = nightly ] && cask=t3-code@nightly
    brew install --cask "$cask"
  else
    echo "install T3 Code ($CHANNEL) from https://t3.codes"
  fi
  echo "you: open T3 Code, sign in, and turn on T3 Connect in Settings so your phone can reach this Mac"
  ;;
linux)
  if ! command -v t3 >/dev/null; then
    tag=latest; [ "$CHANNEL" = nightly ] && tag=nightly
    npm i -g "t3@$tag" || { echo "npm i -g t3@$tag failed (Node 20+ needed)" >&2; exit 1; }
  fi
  t3 service status 2>/dev/null | grep -q 'Status: installed' || t3 service install
  if t3 connect status 2>/dev/null | grep -q 'Environment link: provisioned'; then
    echo "T3 Connect already linked"
  else
    echo "you: run 't3 connect link --headless' on this machine, open the link it prints, then"
    echo "     't3 service restart' and 't3 connect publish' for phone notifications"
  fi
  ;;
*) echo "no T3 install recipe for $FLEET_OS yet; see https://t3.codes and docs/porting.md" ;;
esac
