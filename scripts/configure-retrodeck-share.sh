#!/usr/bin/env bash
# Flatpak4Mac: configure the QEMU VirtFS host folder independently of RetroDECK.
# macOS Bash 3.2 compatible. Never reads the broken UTM AppleScript
# `directory share mode of configuration of virtual machine ...` expression.
set -Eeuo pipefail
F4M_SHARE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
F4M_SHARE_ROOT="$(cd "$F4M_SHARE_SCRIPT_DIR/.." && pwd -P)"
# shellcheck source=common.sh
source "$F4M_SHARE_ROOT/scripts/common.sh"
need_macos
validate_guest_env

share_path="$F4M_SHARE_ROOT/retrodeck"
mkdir -p "$share_path"
share_path="$(cd "$share_path" && pwd -P)"
marker="$F4M_SHARE_ROOT/vm/ubuntu-24.04/.vm-created-by-v2"
[[ -s "$marker" ]] || fail "VM marker missing: $marker; run ./quick-start.sh first."
vm_id="$(tr -d '\r\n' < "$marker")"
[[ "$vm_id" =~ ^[[:xdigit:]]{8}-([[:xdigit:]]{4}-){3}[[:xdigit:]]{12}$ ]] || fail 'Invalid Flatpak4Mac VM marker; refusing to change another VM.'

get_utm_state() {
  /usr/bin/osascript - "$vm_id" <<'APPLESCRIPT'
on run argv
  tell application "UTM"
    set vm to virtual machine id (item 1 of argv)
    if (name of vm) is not "Flatpak4Mac" then error "Flatpak4Mac VM marker does not match expected VM name"
    return status of vm as text
  end tell
end run
APPLESCRIPT
}

# Reuse a working share without modifying the UTM VM configuration.
# Guest is already running at this point on the usual quick-retrodeck path.
state="$(get_utm_state)" || fail 'Could not read UTM VM state.'
if [[ "$state" == started || "$state" == running ]]; then
  if ssh_guest 'findmnt -rn -T /home/flatpak/retrodeck -t 9p >/dev/null 2>&1'; then
    log 'VirtFS shared folder is already mounted in Ubuntu.'
    exit 0
  fi
  # Existing UTM sharing can be active even if the mount was lost. Try
  # mounting before requesting a disruptive VM restart.
  if ssh_guest 'sudo mkdir -p /home/flatpak/retrodeck && sudo mount -t 9p -o trans=virtio,version=9p2000.L,rw share /home/flatpak/retrodeck' >/dev/null 2>&1; then
    log 'Existing UTM VirtFS share mounted successfully; restart unnecessary.'
    exit 0
  fi
  if [[ -t 0 ]]; then
    printf 'UTM must restart Flatpak4Mac to enable RetroDECK sharing. Restart now? [Y/n] '
    IFS= read -r reply || reply=''
    case "$reply" in n|N|no|NO|No) fail 'Cancelled; VM was not stopped.' ;; esac
  else
    fail 'VirtFS configuration requires stopping the running VM. Rerun interactively or shut down Flatpak4Mac in UTM first.'
  fi
  log 'Shutting down Flatpak4Mac guest gracefully.'
  ssh_guest 'sudo shutdown -h now' >/dev/null 2>&1 || true
  for ((i=0; i<90; i++)); do
    state="$(get_utm_state 2>/dev/null || true)"
    [[ "$state" == stopped ]] && break
    sleep 2
  done
  [[ "$state" == stopped ]] || fail 'VM did not shut down; no UTM configuration was changed. Stop it in UTM and rerun.'
fi
[[ "$state" == stopped ]] || fail "VM status is '$state' rather than stopped; refusing to edit sharing configuration."

log "Configuring UTM VirtFS share: $share_path"
# IMPORTANT: Use UTM's *update* commands with a partial configuration record.
# Accessing `directory share mode of (configuration of vm)` raises -1700 in
# some UTM releases. The registry controls the host folder path; configuring
# the directory share mode controls 9p/VirtFS exposure in QEMU.
/usr/bin/osascript - "$vm_id" "$share_path" <<'APPLESCRIPT'
on run argv
  set vmID to item 1 of argv
  set sharePath to item 2 of argv
  tell application "UTM"
    set vm to virtual machine id vmID
    if (name of vm) is not "Flatpak4Mac" then error "VM identity mismatch"
    if (backend of vm as text) is not "qemu" then error "Expected QEMU backend for 9p VirtFS"
    if (status of vm) is not stopped then error "VM must be fully stopped to update VirtFS"
    update configuration vm with {directory share mode:VirtFS}
    -- Registry contains one host share for this dedicated Flatpak4Mac VM.
    -- Do not use directory share mode as a getter; it triggers error -1700.
    update registry vm with {POSIX file sharePath}
  end tell
  return "VirtFS host directory registered"
end run
APPLESCRIPT

log 'Starting Flatpak4Mac after VirtFS configuration.'
# Use the project's existing startup/IP-discovery path. No RetroDECK install.
# Quick Start can re-use the VM and refresh stale SSH addresses after restart.
"$F4M_SHARE_ROOT/quick-start.sh"
log 'VirtFS configuration complete; mounting will be verified by ensure-retrodeck-share.sh.'
