#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
resolve_utm
printf 'UTM: %s\nImage: %s\nMac share: %s\nSSH config: %s\n' "${UTM_APP:-missing}" "$F4M_IMAGE_DIR" "$F4M_SHARE" "$F4M_ENV"
validate_guest_env
if [[ -n "$F4M_HOST" && -f "$F4M_KEY" ]]; then
  ssh_guest 'printf "\nGuest: "; uname -m; cloud-init status || true; df -h /; test -f /var/lib/flatpak4mac/provisioned && echo PROVISIONED || echo NOT_PROVISIONED; flatpak --version || true; glxinfo -B 2>/dev/null | grep -E "OpenGL renderer|OpenGL version" || true; mount | grep /home/flatpak/retrodeck || true' || true
fi
