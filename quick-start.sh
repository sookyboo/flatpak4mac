#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
source "$ROOT/scripts/common.sh"
source "$ROOT/scripts/discover-guest-ip.sh"
need_macos
INSTALL_BUNDLES=0
case "${1:-}" in
  --help|-h) echo 'Usage: ./quick-start.sh [--check|--install-bundles]'; exit 0 ;;
  --check) resolve_utm; printf 'UTM: %s\nImage: %s\nVM: %s\nSSH host: %s\n' "${UTM_APP:-missing}" "$F4M_IMAGE_DIR" "$F4M_VM_NAME" "${F4M_HOST:-not configured}"; exit 0 ;;
  --install-bundles) INSTALL_BUNDLES=1 ;;
  '') ;;
  *) fail 'Unknown argument' ;;
esac
[[ $# -le 1 ]] || fail 'Too many arguments'
for helper in install-utm.sh prepare-ubuntu-image.sh configure-utm-vm.sh \
  install-guest-service.sh install-launcher.sh discover-guest-ip.sh; do
  [[ -f "$ROOT/scripts/$helper" && ! -L "$ROOT/scripts/$helper" ]] || fail "Missing setup component: scripts/$helper"
  bash -n "$ROOT/scripts/$helper" || fail "Invalid setup component: scripts/$helper"
done
if (( INSTALL_BUNDLES )); then
  [[ -d "$ROOT/autoinstall" && -f "$ROOT/scripts/install-flatpaks.sh" && ! -L "$ROOT/scripts/install-flatpaks.sh" ]] || fail 'Missing autoinstall directory or bundle installer.'
  bash -n "$ROOT/scripts/install-flatpaks.sh" || fail 'Invalid bundle installer.'
fi
"$ROOT/scripts/install-utm.sh" || exit $?
"$ROOT/scripts/prepare-ubuntu-image.sh"
"$ROOT/scripts/configure-utm-vm.sh" || exit $?
if [[ -f "$F4M_IMAGE_DIR/.requires-first-boot-review" ]]; then
  cat <<EOF

Before first boot, verify in UTM:
  1. Boot disk is resized to ${F4M_DISK_GB} GiB (minimum 40 GiB).
  2. flatpak-seed.iso is attached as a SECOND, NON-REMOVABLE VirtIO DISK.
  3. VirtIO GPU is GPU Supported; Apple Core OpenGL renderer selected.
  4. Shared Network is configured.
Do NOT continue if you have not resized the boot disk.
EOF
  read -r -p 'Have you completed these settings? Type RESIZED to continue: ' answer
  [[ "$answer" == RESIZED ]] || fail 'No changes made. Resize/configure the VM, then rerun Quick Start.'
  rm -f "$F4M_IMAGE_DIR/.requires-first-boot-review"
fi
# Snapshot before VM startup; do not assume a new ARP entry uniquely identifies the VM.
arp_before="$(arp_pairs)"
# UTM uses global renderer preferences; we deliberately do not overwrite them.
printf '\nIMPORTANT: In UTM Preferences > macOS > QEMU Graphics Acceleration, set\n  Renderer Backend: Apple Core OpenGL\nAlso verify the VM display is GPU Supported.\n'
open -a UTM
osascript - "$F4M_VM_NAME" <<'APPLESCRIPT' || warn 'Start the Flatpak4Mac VM manually in UTM.'
on run argv
  tell application "UTM"
    set vm to virtual machine named (item 1 of argv)
    if (status of vm) is stopped then start vm
  end tell
end run
APPLESCRIPT
# A configured address is only a candidate: verify it belongs to this guest.
validate_guest_env
connected=0
if [[ -n "$F4M_HOST" ]] && probe_ip "$F4M_HOST"; then connected=1; fi
if (( ! connected )); then
  log 'Waiting for SSH; checking UTM guest agent, VM MAC and new bridge ARP entries.'
  for ((i=0;i<36;i++)); do
    host="$(get_guest_ip || true)"
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && probe_ip "$host"; then connected=1; break; fi
    host="$(discover_arp_ip "$arp_before" || true)"
    if [[ -n "$host" ]]; then connected=1; break; fi
    if (( i % 6 == 5 )); then warn 'Still awaiting authenticated SSH access (cloud-init user/key setup may be running).'; fi
    sleep 5
  done
  if (( connected )); then
    F4M_HOST="$host"
    write_config "$F4M_HOST" 22
  fi
fi
if (( ! connected )); then
  warn 'No authenticated SSH endpoint discovered. Check VM boot and UTM shared networking.'
  if [[ -t 0 ]]; then
    read -r -p 'Enter guest IP manually (Enter to exit): ' host
    if [[ -n "$host" ]] && probe_ip "$host"; then
      F4M_HOST="$host"; F4M_PORT=22; connected=1; write_config "$host" 22
    fi
  fi
fi
(( connected )) || fail 'SSH not ready; rerun Quick Start later. The VM remains intact.'
log "SSH_READY: flatpak-utm at $F4M_HOST"
"$ROOT/scripts/install-guest-service.sh"
# A cloud-init package installation no longer blocks SSH. Poll the independent unit
# and show its latest log lines; transient SSH failures do not abort it.
ready=0
for ((i=0;i<90;i++)); do
  if ssh_guest 'test -f /var/lib/flatpak4mac/provisioned && test -f /var/lib/flatpak4mac/system-policy-v2 && command -v flatpak && command -v plasma-discover && systemctl is-active --quiet lightdm.service && gsettings list-schemas | grep -Fxq org.gnome.desktop.interface && ! systemctl is-active --quiet flatpak4mac-provision.service' >/dev/null 2>&1; then ready=1; break; fi
  if (( i % 3 == 0 )); then
    log 'Desktop provisioning status (systemd service):'
    ssh_guest 'systemctl is-active flatpak4mac-provision.service || true; sudo tail -n 5 /var/log/flatpak4mac-provision.log 2>/dev/null || true' || warn 'Temporary SSH interruption; retrying.'
  fi
  if ssh_guest 'systemctl is-failed --quiet flatpak4mac-provision.service' >/dev/null 2>&1; then
    fail 'Guest provisioning service failed. Inspect: sudo journalctl -u flatpak4mac-provision.service -n 100 --no-pager'
  fi
  sleep 10
done
if (( ! ready )); then
  fail 'Provisioning incomplete. It may still be installing packages; inspect: sudo journalctl -u flatpak4mac-provision.service -f. Rerun Quick Start after it completes.'
fi
if (( INSTALL_BUNDLES )); then
  "$ROOT/scripts/install-flatpaks.sh"
fi
"$ROOT/scripts/install-launcher.sh"
log 'Quick Start complete. Launch Discover from Flatpak Manager.app (UTM / VM display).'
