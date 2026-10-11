#!/usr/bin/env bash
# accounts: the key file exists, is private, and every key you asked for has a value.
[ "${1:-}" = --heal ] && exit 1
f="$HOME/.config/agent-secrets.env"
[ -f "$f" ] || { echo "no $f (copy templates/agent-secrets.env, chmod 600)"; exit 1; }
perm="$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")"
[ "$perm" = 600 ] || { echo "$f is mode $perm, not 600"; exit 1; }
missing="$(awk '/^[[:space:]]*(export[[:space:]]+)?[A-Z][A-Z0-9_]*=/ {
  v = substr($0, index($0, "=") + 1); gsub(/["\047[:space:]]/, "", v)
  k = $0; sub(/=.*/, "", k); sub(/^[[:space:]]*(export[[:space:]]+)?/, "", k)
  if (v == "") printf "%s ", k }' "$f")"
[ -z "$missing" ] || { echo "keys wanted but not set: ${missing% }"; exit 1; }
exit 0
