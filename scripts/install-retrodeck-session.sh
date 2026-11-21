#!/usr/bin/env bash
# Host-side installer for dedicated RetroDECK and XFCE LightDM sessions.
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
[[ -n "$F4M_HOST" ]] || validate_guest_env
[[ -n "$F4M_HOST" ]] || fail 'SSH host not configured.'
ssh_guest 'mkdir -p /tmp/flatpak4mac-session-setup'
scp -q -i "$F4M_KEY" -P "$F4M_PORT" -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  "$F4M_DIR/scripts/flatpak4mac-session-mode" \
  "$F4M_DIR/scripts/flatpak4mac-retrodeck-session" \
  "flatpak@$F4M_HOST:/tmp/flatpak4mac-session-setup/"
ssh_guest 'sudo install -m 755 /tmp/flatpak4mac-session-setup/flatpak4mac-session-mode /usr/local/sbin/flatpak4mac-session-mode && sudo install -m 755 /tmp/flatpak4mac-session-setup/flatpak4mac-retrodeck-session /usr/local/bin/flatpak4mac-retrodeck-session && sudo install -d -m 755 /usr/share/xsessions && printf "[Desktop Entry]\nName=RetroDECK (dedicated)\nComment=Fullscreen RetroDECK without XFCE\nExec=/usr/local/bin/flatpak4mac-retrodeck-session\nType=Application\nDesktopNames=RetroDECK\n" | sudo tee /usr/share/xsessions/flatpak4mac-retrodeck.desktop >/dev/null && sudo chmod 644 /usr/share/xsessions/flatpak4mac-retrodeck.desktop && rm -rf /tmp/flatpak4mac-session-setup'
log 'Dedicated RetroDECK X11 session installed; XFCE remains available. Session choice is preserved.'
