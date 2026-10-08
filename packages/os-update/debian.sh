#!/usr/bin/env bash
# debian.sh: a full Debian or Ubuntu upgrade as a fleet work order. Reference implementation.
#
#   fleet workorder start os-update ~/fleet/packages/os-update/debian.sh
set -uo pipefail
put() { printf '%s=%s\n' "$1" "${*:2}" >> "$FLEET_WO_STATE"; }
fail() { put ABORT "$*"; echo "ABORT: $*"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

case "${1:-}" in
run)
  put KERNEL_BEFORE "$(uname -r)"
  sudo -n apt-get update || fail "apt-get update failed"
  sudo -n apt-get -y -o Dpkg::Options::=--force-confold full-upgrade || fail "full-upgrade failed"
  sudo -n apt-get -y autoremove
  command -v claude >/dev/null && { claude update && put CLAUDE ok || put CLAUDE failed; }
  if [ -f /var/run/reboot-required ]; then put REBOOT "required"; exec fleet-workorder reboot; fi
  put REBOOT "not needed"
  ;;
resume) put KERNEL_AFTER "$(uname -r)" ;;
*) echo "usage: $0 run|resume (called by fleet workorder)" >&2; exit 2 ;;
esac
