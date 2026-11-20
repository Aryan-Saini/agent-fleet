#!/usr/bin/env bash
# dev-server install: the devserver@ template unit and the hourly reap timer. Linux workers only.
# Idempotent. worker-expose and devserver are linked into ~/.local/bin by ./install.sh.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
[ "$(uname -s)" = Linux ] || { echo "dev-server runs on Linux workers; skipped"; exit 0; }
for c in tailscale jq ss systemctl; do
  command -v "$c" >/dev/null || { echo "dev-server needs $c on PATH" >&2; exit 1; }
done
U="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; mkdir -p "$U"
cp "$here"/units/devserver@.service "$here"/units/devserver-reap.service "$here"/units/devserver-reap.timer "$U/"
systemctl --user daemon-reload
systemctl --user enable --now devserver-reap.timer >/dev/null 2>&1 && echo "devserver-reap.timer enabled"
# tailscale serve needs your user as the operator, or it exits non-zero without root.
if ! tailscale serve status >/dev/null 2>&1; then
  echo "you: let your user manage tailscale serve, once: sudo tailscale set --operator=$USER"
fi
