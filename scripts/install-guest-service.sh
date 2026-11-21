#!/usr/bin/env bash
# Configure or repair the guest provisioning service over the SSH connection.
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
[[ -n "$F4M_HOST" ]] || validate_guest_env
[[ -n "$F4M_HOST" ]] || fail 'SSH address not configured'
log 'Installing/updating guest provisioning service over SSH.'
ssh_guest 'mkdir -p /tmp/flatpak4mac-bootstrap'
scp -q -i "$F4M_KEY" -P "$F4M_PORT" -o BatchMode=yes \
  -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
  "$F4M_DIR/scripts/provision-ubuntu-guest.sh" "$F4M_DIR/scripts/flatpak4mac-provision.service" \
  "flatpak@$F4M_HOST:/tmp/flatpak4mac-bootstrap/"
ssh_guest 'sudo install -m 755 /tmp/flatpak4mac-bootstrap/provision-ubuntu-guest.sh /usr/local/sbin/flatpak4mac-provision && sudo install -m 644 /tmp/flatpak4mac-bootstrap/flatpak4mac-provision.service /etc/systemd/system/flatpak4mac-provision.service && sudo systemctl daemon-reload && sudo systemctl enable flatpak4mac-provision.service && if sudo systemctl is-active --quiet flatpak4mac-provision.service; then echo "Provisioning already running"; else sudo systemctl reset-failed flatpak4mac-provision.service && sudo systemctl start --no-block flatpak4mac-provision.service; fi && rm -rf /tmp/flatpak4mac-bootstrap'
log 'Guest provisioning service installed; installation proceeds independently of SSH.'
