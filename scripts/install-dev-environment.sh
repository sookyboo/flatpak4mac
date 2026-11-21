#!/usr/bin/env bash
# Optional host-side ARM64 developer profile, never part of the normal installer.
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
[[ -n "$F4M_HOST" ]] || validate_guest_env
[[ -n "$F4M_HOST" ]] || fail 'Guest SSH not configured'
log 'Installing the optional Ubuntu ARM64 development environment.'
ssh_guest 'mkdir -p /tmp/flatpak4mac-dev'
scp -q -i "$F4M_KEY" -P "$F4M_PORT" -o BatchMode=yes -o ConnectTimeout=8 \
  -o StrictHostKeyChecking=accept-new \
  "$F4M_DIR/scripts/install-dev-guest.sh" \
  "$F4M_DIR/scripts/configure-bwrap-apparmor-guest.sh" \
  "$F4M_DIR/scripts/configure-input-method-guest.sh" \
  "$F4M_DIR/scripts/install-git-tools-guest.sh" \
  "flatpak@$F4M_HOST:/tmp/flatpak4mac-dev/"
# Always rerunnable; remote script checks package state and validates its download.
ssh_guest 'sudo bash /tmp/flatpak4mac-dev/install-dev-guest.sh && sudo bash /tmp/flatpak4mac-dev/configure-bwrap-apparmor-guest.sh && sudo bash /tmp/flatpak4mac-dev/configure-input-method-guest.sh && sudo bash /tmp/flatpak4mac-dev/install-git-tools-guest.sh && rm -f /tmp/flatpak4mac-dev/install-dev-guest.sh /tmp/flatpak4mac-dev/configure-bwrap-apparmor-guest.sh /tmp/flatpak4mac-dev/configure-input-method-guest.sh /tmp/flatpak4mac-dev/install-git-tools-guest.sh'
log 'Dev tools and Plasma installed; XFCE and RetroDECK sessions preserved.'
