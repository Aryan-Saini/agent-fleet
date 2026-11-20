#!/usr/bin/env bash
# cliproxy: on the worker, the hub service is up and /v1/models answers with the client key.
# Heals by restarting the service. On the controller, `hub status` is the check; nothing here.
[ "$(uname -s)" = Linux ] || exit 0
UNIT="${CLIPROXY_UNIT:-cliproxyapi.service}"
PORT="${CLIPROXY_PORT:-8317}"
KEY_FILE="${CLIPROXY_KEY_FILE:-$HOME/.config/cliproxy/access-key}"
systemctl --user cat "$UNIT" >/dev/null 2>&1 || exit 0   # no hub on this machine
if [ "${1:-}" = --heal ]; then
  systemctl --user restart "$UNIT" && sleep 5
  exit 0
fi
systemctl --user is-active --quiet "$UNIT" || { echo "$UNIT is not active"; exit 1; }
[ -r "$KEY_FILE" ] || { echo "no client key at $KEY_FILE"; exit 1; }
# The key goes to curl on stdin, never in argv.
code=$(printf 'Authorization: Bearer %s\n' "$(cat "$KEY_FILE")" |
  curl -s -o /dev/null -w '%{http_code}' -m 5 -H @- "http://127.0.0.1:$PORT/v1/models")
[ "$code" = 200 ] || { echo "hub /v1/models answered $code"; exit 1; }
exit 0
