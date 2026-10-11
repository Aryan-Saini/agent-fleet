#!/usr/bin/env bash
# worker-chrome: the always-on Chrome is running and DevTools answers. Heals by restarting it.
[ "$(uname -s)" = Linux ] || exit 0
PORT="${WORKER_CHROME_PORT:-9230}"
if [ "${1:-}" = --heal ]; then
  systemctl --user restart worker-chrome.service && sleep 5
  exit 0
fi
systemctl --user is-active --quiet worker-chrome.service || { echo "worker-chrome.service is not active"; exit 1; }
curl -sfm3 "http://127.0.0.1:$PORT/json/version" >/dev/null || { echo "worker-chrome DevTools on :$PORT is not answering"; exit 1; }
exit 0
