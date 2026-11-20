#!/usr/bin/env bash
# drop-folder: ~/drop present, and Syncthing answering where it is installed. Heals by creating
# the folder and restarting Syncthing. Without Syncthing (push-only drop folders) only the folder
# is checked.
drop="${FLEET_DROP:-$HOME/drop}"
has_syncthing() { command -v syncthing >/dev/null; }
if [ "${1:-}" = --heal ]; then
  mkdir -p "$drop"
  if has_syncthing; then
    case "$(uname -s)" in
      Darwin) brew services restart syncthing >/dev/null 2>&1 ;;
      *) systemctl --user restart syncthing >/dev/null 2>&1 ;;
    esac
    sleep 10
  fi
  exit 0
fi
[ -d "$drop" ] || { echo "$drop is missing"; exit 1; }
has_syncthing || exit 0
curl -fsS --max-time 5 http://127.0.0.1:8384/rest/noauth/health 2>/dev/null | grep -q OK ||
  { echo "syncthing is not answering on :8384"; exit 1; }
