#!/usr/bin/env bash
# arch.sh: a full Arch Linux upgrade as a fleet work order. Reference implementation.
#
#   fleet workorder start os-update ~/fleet/packages/os-update/arch.sh
#
# run:    preflight -> optional btrfs snapshot -> keyring -> pacman -Syu -> AUR (best effort)
#         -> flatpak -> agent CLIs -> verify /boot -> reboot only if the kernel changed
# resume: record what booted. fleet-workorder then runs health, proves the controller can reach
#         this machine, writes the report and alerts.
#
# Needs passwordless sudo (or a sudoers rule scoped to pacman, btrfs and reboot). Every fact
# goes into $FLEET_WO_STATE so it lands in the report.
set -uo pipefail
put() { printf '%s=%s\n' "$1" "${*:2}" >> "$FLEET_WO_STATE"; }
fail() { put ABORT "$*"; echo "ABORT: $*"; exit 1; }

case "${1:-}" in
run)
  # ---- preflight. Refuse anything that would make a reboot risky.
  [ -e /var/lib/pacman/db.lck ] && fail "pacman lock present, another package operation is running"
  boot_free=$(df -Pm /boot | awk 'NR==2{print $4}')
  [ "$boot_free" -lt 250 ] && fail "/boot has ${boot_free}M free, need 250M for kernel images"
  put BOOT_FREE_M "$boot_free"
  put KERNEL_BEFORE "$(uname -r)"

  # ---- rollback target, when / is btrfs and the @ subvolume layout is in use
  if [ "$(findmnt -no FSTYPE /)" = btrfs ] && [ "${FLEET_SNAPSHOT:-1}" = 1 ]; then
    top=/mnt/.btrfs-top; snap="@snapshot-update-$(date +%Y%m%d-%H%M%S)"
    sudo -n mkdir -p "$top"
    mountpoint -q "$top" || sudo -n mount -o subvolid=5 "$(findmnt -no SOURCE / | sed 's/\[.*\]//')" "$top" ||
      fail "could not mount the btrfs top level"
    sudo -n btrfs subvolume snapshot -r "$top/@" "$top/$snap" || fail "btrfs snapshot failed"
    put ROLLBACK "boot with rootflags=subvol=$snap"
  fi

  # ---- packages. Keyring first: a full upgrade on a stale keyring fails halfway.
  sudo -n pacman -Sy --noconfirm --needed archlinux-keyring || fail "keyring update failed"
  sudo -n pacman -Su --noconfirm || fail "pacman -Su failed; read the log before retrying"
  put OFFICIAL ok

  if command -v paru >/dev/null; then   # AUR: per package, best effort, never load-bearing
    ok=(); bad=()
    for p in $(paru -Qua 2>/dev/null | awk '{print $1}'); do
      if paru -S --noconfirm --needed --skipreview "$p"; then ok+=("$p"); else bad+=("$p"); fi
    done
    put AUR_OK "${ok[*]:-none}"; put AUR_FAILED "${bad[*]:-none}"
  fi
  command -v flatpak >/dev/null && { flatpak update -y && put FLATPAK ok || put FLATPAK failed; }
  command -v claude >/dev/null && { claude update && put CLAUDE ok || put CLAUDE failed; }
  command -v cursor-agent >/dev/null && { cursor-agent update && put CURSOR ok || put CURSOR failed; }
  put PACNEW "$(find /etc -name '*.pacnew' 2>/dev/null | tr '\n' ' ')"

  # ---- reboot only when the running kernel is no longer installed
  if [ -d "/usr/lib/modules/$(uname -r)" ]; then
    put REBOOT "not needed"; exit 0
  fi
  for k in /boot/vmlinuz-*; do [ -s "$k" ] || fail "$k is empty after the upgrade, refusing to reboot"; done
  for i in /boot/initramfs-*.img; do [ -s "$i" ] || fail "$i is empty after the upgrade, refusing to reboot"; done
  put REBOOT "kernel changed"
  exec fleet-workorder reboot
  ;;
resume)
  put KERNEL_AFTER "$(uname -r)"
  systemctl --failed --no-legend | grep -q . && put FAILED_UNITS "$(systemctl --failed --no-legend | awk '{print $2}' | tr '\n' ' ')"
  exit 0
  ;;
*) echo "usage: $0 run|resume (called by fleet workorder)" >&2; exit 2 ;;
esac
