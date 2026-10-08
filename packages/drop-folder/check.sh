#!/usr/bin/env bash
# drop-folder: Syncthing answering and ~/drop present. Heals by restarting Syncthing.
drop="${FLEET_DROP:-$HOME/drop}"
if [ "${1:-}" = --heal ]; then
  mkdir -p "$drop"
  case "$(uname -s)" in
    Darwin) brew services restart syncthing >/dev/null 2>&1 ;;
    *) systemctl --user restart syncthing >/dev/null 2>&1 ;;
  esac
  sleep 10; exit 0
fi
[ -d "$drop" ] || { echo "$drop is missing"; exit 1; }
curl -fsS --max-time 5 http://127.0.0.1:8384/rest/noauth/health 2>/dev/null | grep -q OK ||
  { echo "syncthing is not answering on :8384"; exit 1; }
