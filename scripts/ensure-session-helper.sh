#!/usr/bin/env bash
# Ensure the host project's LightDM session selector is installed inside Ubuntu.
# Safe to rerun; only refreshes this one helper executable.
set -Eeuo pipefail
F4M_SESSION_HELPER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/common.sh
source "$F4M_SESSION_HELPER_ROOT/scripts/common.sh"
need_macos
# Load saved VM SSH configuration before checking host, port and key.
validate_guest_env
local_script="$F4M_SESSION_HELPER_ROOT/scripts/flatpak4mac-session-mode"
worker_script="$F4M_SESSION_HELPER_ROOT/scripts/flatpak4mac-session-switch-worker"
[[ -f "$local_script" && -f "$worker_script" ]] || fail 'Missing session selector or worker in scripts/'
[[ -n "${F4M_HOST:-}" && -n "${F4M_PORT:-}" && -f "${F4M_KEY:-/nonexistent}" ]] || fail 'VM SSH connection not configured; run ./quick-start.sh'
# Check the local helper supports Plasma before updating the VM.
grep -q 'plasma' "$local_script" || fail 'Local session helper is too old (no Plasma support). Update flatpak4mac/scripts/flatpak4mac-session-mode first.'
log 'Refreshing LightDM session selector in Ubuntu'
scp -q -i "$F4M_KEY" -P "$F4M_PORT" -o BatchMode=yes -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  "$local_script" "$worker_script" "flatpak@$F4M_HOST:/tmp/"
# Install worker first, then selector; interruption can't leave a selector
# pointing to a missing root service.
ssh_guest 'sudo install -m 755 /tmp/flatpak4mac-session-switch-worker /usr/local/sbin/flatpak4mac-session-switch-worker && sudo install -m 755 /tmp/flatpak4mac-session-mode /usr/local/sbin/flatpak4mac-session-mode && rm -f /tmp/flatpak4mac-session-mode /tmp/flatpak4mac-session-switch-worker && sudo test -x /usr/local/sbin/flatpak4mac-session-switch-worker'
