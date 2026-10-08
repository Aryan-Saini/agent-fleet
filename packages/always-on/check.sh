#!/usr/bin/env bash
# always-on: nothing can put this machine to sleep. Report only; power policy is a human call.
[ "${1:-}" = --heal ] && exit 1
case "$(uname -s)" in
  Linux)
    for t in sleep.target suspend.target hibernate.target; do
      [ "$(systemctl is-enabled "$t" 2>/dev/null)" = masked ] || { echo "$t is not masked, the box can sleep"; exit 1; }
    done ;;
  Darwin)
    pmset -g | awk '$1=="sleep"{exit ($2==0)?0:1}' || { echo "pmset sleep is not 0, the Mac can sleep"; exit 1; } ;;
esac
