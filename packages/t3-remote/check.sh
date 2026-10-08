#!/usr/bin/env bash
# t3-remote: the T3 backend is up and reachable from the phone. Heals by restarting it.
PORT="${T3_PORT:-3773}"; UNIT="${T3_SERVICE:-t3code.service}"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
answers() { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://127.0.0.1:$PORT/")" = 200 ]; }

if [ "${1:-}" = --heal ]; then
  [ "$(uname -s)" = Linux ] || exit 1
  systemctl --user restart "$UNIT" && sleep 20
  if command -v tailscale >/dev/null && ! tailscale serve status 2>/dev/null | grep -q "127.0.0.1:$PORT"; then
    sudo -n tailscale serve --bg --https=443 "http://127.0.0.1:$PORT" >/dev/null 2>&1
  fi
  exit 0
fi

answers || { echo "T3 backend on :$PORT is not answering"; exit 1; }
[ "$(uname -s)" = Linux ] || exit 0
systemctl --user is-active --quiet "$UNIT" || { echo "$UNIT is not active"; exit 1; }
st="$(t3 connect status 2>/dev/null)"
grep -q 'Exposure: enabled' <<<"$st" || { echo "T3 Connect exposure is disabled (no phone access)"; exit 1; }
grep -q 'Environment link: provisioned' <<<"$st" || { echo "T3 Connect link missing (t3 connect link)"; exit 1; }
pgrep -f 'cloudflared tunnel .*run' >/dev/null || { echo "relay tunnel is down"; exit 1; }
