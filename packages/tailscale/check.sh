#!/usr/bin/env bash
# tailscale: connected to the tailnet. Heals by bringing it up.
if [ "${1:-}" = --heal ]; then
  case "$(uname -s)" in
    Darwin) open -ga Tailscale ;;
    *) sudo -n tailscale up ;;
  esac
  sleep 5; exit 0
fi
command -v tailscale >/dev/null || { echo "tailscale is not installed"; exit 1; }
tailscale status >/dev/null 2>&1 || { echo "tailscale is down"; exit 1; }
