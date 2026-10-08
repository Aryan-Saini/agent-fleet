#!/usr/bin/env bash
# install.sh: make this machine part of the fleet. Safe to re-run; it converges.
#
#   ./install.sh --role controller                      the machine you author config on
#   ./install.sh --role worker --controller laptop      an always-on box that runs agents
#
# Options:
#   --name NAME            this machine's fleet name (default: short hostname)
#   --controller ALIAS     ssh alias of the controller (workers: needed for alerts and rejoin)
#   --packages "a b c"     packages to enable, from packages/ (default: tailscale drop-folder)
#
# What it does:
#   1. writes ~/.config/fleet/machine.env if missing (never overwrites; edit it by hand after)
#   2. creates fleet.env, rules/ and computers.md from templates/ if this checkout has none yet
#   3. links bin/ and each enabled package's bin/ into ~/.local/bin
#   4. creates ~/drop and runs `fleet link` (rules + skills into every harness)
#   5. workers only: installs the health timer, the sync timer and boot continuation
set -euo pipefail
cd "$(dirname "$0")"
FLEET_HOME="$(pwd -P)"

ROLE=""; NAME="$(hostname -s 2>/dev/null || uname -n)"; CONTROLLER=""; PACKAGES="tailscale drop-folder"
while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --controller) CONTROLLER="$2"; shift 2 ;;
    --packages) PACKAGES="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$ROLE" in controller|worker) ;; *) echo "--role controller|worker is required" >&2; exit 2 ;; esac
for p in $PACKAGES; do [ -d "packages/$p" ] || { echo "no such package: $p (see packages/)" >&2; exit 2; }; done
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

# 1. machine identity, local only
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/fleet"
mkdir -p "$CFG/checks.d"
if [ ! -f "$CFG/machine.env" ]; then
  sed -e "s|^FLEET_NAME=.*|FLEET_NAME=$NAME|" -e "s|^FLEET_ROLE=.*|FLEET_ROLE=$ROLE|" \
      -e "s|^FLEET_PACKAGES=.*|FLEET_PACKAGES=\"$PACKAGES\"|" \
      -e "s|^FLEET_CONTROLLER=.*|FLEET_CONTROLLER=$CONTROLLER|" templates/machine.env > "$CFG/machine.env"
  chmod 600 "$CFG/machine.env"
  echo "wrote $CFG/machine.env"
else
  echo "kept existing $CFG/machine.env (edit it to change role, packages or controller)"
fi

# 2. your fleet's own files, created once from the templates
[ -f fleet.env ] || { cp templates/fleet.env fleet.env; echo "created fleet.env"; }
[ -f computers.md ] || { cp templates/computers.md computers.md; echo "created computers.md (fill it in)"; }
mkdir -p rules skills-local machines
[ -f rules/AGENTS.md ] || { cp templates/AGENTS.md rules/AGENTS.md; echo "created rules/AGENTS.md"; }
[ -f rules/CLAUDE.md ] || { cp templates/CLAUDE.md rules/CLAUDE.md; echo "created rules/CLAUDE.md"; }

# 3. commands on PATH
mkdir -p "$HOME/.local/bin"
for f in bin/fleet bin/fleet-* ; do
  [ "$f" = bin/fleet-lib.sh ] && continue
  ln -sfn "$FLEET_HOME/$f" "$HOME/.local/bin/$(basename "$f")"
done
for p in $PACKAGES; do
  for f in packages/"$p"/bin/*; do [ -f "$f" ] && ln -sfn "$FLEET_HOME/$f" "$HOME/.local/bin/$(basename "$f")"; done
done
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "NOTE: add ~/.local/bin to PATH in ~/.zshenv or ~/.profile (zshenv: non-interactive ssh reads it too)";; esac

# 4. drop folder + harness wiring
mkdir -p "$HOME/drop"
"$FLEET_HOME/bin/fleet-link"

# 5. the worker loop
if [ "$ROLE" = worker ]; then
  if [ "$OS" = linux ]; then
    U="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; mkdir -p "$U"
    cp units/systemd/fleet-* "$U/"
    systemctl --user daemon-reload
    systemctl --user enable --now fleet-health.timer fleet-sync.timer
    systemctl --user enable fleet-resume.service
    # Lingering starts user units at boot without a login. Without it nothing here runs after
    # a reboot, which is exactly when it matters.
    loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes' ||
      sudo loginctl enable-linger "$USER" || echo "WARNING: enable lingering: sudo loginctl enable-linger $USER"
    echo "installed systemd user units: fleet-health.timer, fleet-sync.timer, fleet-resume.service"
  elif [ "$OS" = darwin ]; then
    LA="$HOME/Library/LaunchAgents"; mkdir -p "$LA"
    for p in units/launchd/*.plist; do
      dest="$LA/$(basename "$p")"
      sed "s|__HOME__|$HOME|g" "$p" > "$dest"
      launchctl bootout "gui/$(id -u)" "$dest" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$dest"
    done
    echo "installed LaunchAgents: fleet.health, fleet.sync, fleet.resume"
    echo "NOTE: a headless Mac worker needs auto-login, or LaunchAgents never start after a reboot"
  else
    echo "No scheduler template for $OS yet. Port units/systemd to it (see docs/porting.md)."
  fi
fi

echo
"$FLEET_HOME/bin/fleet"
echo
echo "next: fill in computers.md, then run 'fleet health'"
