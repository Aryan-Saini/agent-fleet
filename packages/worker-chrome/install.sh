#!/usr/bin/env bash
# worker-chrome install: systemd units and a running Chrome. Linux workers only. Idempotent.
set -uo pipefail
[ "$(uname -s)" = Linux ] || { echo "worker-chrome runs on Linux workers; skipped"; exit 0; }
command -v worker-chrome >/dev/null || { echo "worker-chrome not on PATH (npm i -g worker-chrome)" >&2; exit 1; }
worker-chrome setup
echo "you: log in to the sites agents need, once: 'screenshare https://site/login' from the controller"
