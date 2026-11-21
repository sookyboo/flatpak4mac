#!/usr/bin/env bash
# Rebuild a Flatpak4Mac VM without losing the Ubuntu image cache or user data.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VM_DIR="$ROOT/vm"
VM_MARKER="$VM_DIR/ubuntu-24.04/.vm-created-by-v2"

[[ "$(uname -s)" == Darwin ]] || { echo 'ERROR: Run this on macOS.' >&2; exit 1; }
[[ "$(id -u)" != 0 ]] || { echo 'ERROR: Do not run as root.' >&2; exit 1; }
[[ "$ROOT" == "$HOME/flatpak4mac" && ! -L "$ROOT" ]] || {
  echo "ERROR: Unexpected project directory: $ROOT" >&2; exit 1;
}
[[ -t 0 ]] || { echo 'ERROR: Interactive confirmation required.' >&2; exit 1; }

log(){ printf '==> %s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
confirm_delete(){
  local answer
  printf '%s [y/N] ' "$1"
  IFS= read -r answer || return 1
  case "$answer" in y|Y|yes|Yes|YES) return 0;; *) return 1;; esac
}

utm_app=''
if [[ -d /Applications/UTM.app ]]; then utm_app=/Applications/UTM.app
elif [[ -d "$HOME/Applications/UTM.app" ]]; then utm_app="$HOME/Applications/UTM.app"
fi
utmctl=''
if [[ -n "$utm_app" && -x "$utm_app/Contents/MacOS/utmctl" ]]; then
  utmctl="$utm_app/Contents/MacOS/utmctl"
fi

printf '\nFlatpak4Mac VM reset\n'
printf '  Working VM directory: %s\n' "$VM_DIR"
printf '  Retained cache:        %s/cache/\n' "$ROOT"
printf '  Retained RetroDECK:    %s/retrodeck/\n' "$ROOT"
printf '  Retained config:       %s/config/\n\n' "$ROOT"

# If there is a registered UTM VM, only delete one positively identified by
# Flatpak4Mac's UUID marker, and never a running VM.
recorded_uuid=''
if [[ -e "$VM_MARKER" ]]; then
  [[ -f "$VM_MARKER" && ! -L "$VM_MARKER" ]] || fail 'VM marker is not a regular file.'
  recorded_uuid="$(tr -d '\r\n' < "$VM_MARKER")"
  [[ "$recorded_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || fail 'Invalid recorded UTM VM UUID; refusing reset.'
fi

vm_line=''
if [[ -n "$utmctl" ]]; then
  if ! vm_listing="$("$utmctl" list 2>&1)"; then
    fail "Cannot query UTM VM list; no files deleted: $vm_listing"
  fi
  if [[ -n "$recorded_uuid" ]]; then
    vm_line="$(printf '%s\n' "$vm_listing" | awk -v id="$recorded_uuid" 'NR>1 && toupper($1)==toupper(id) { print; exit }')"
  fi
  # Do not delete the working image directory while an untracked Flatpak4Mac
  # VM may still be referencing it.
  if [[ -z "$vm_line" ]] && printf '%s\n' "$vm_listing" | awk 'NR>1 && $3=="Flatpak4Mac" {found=1} END{exit !found}'; then
    fail 'A UTM VM called Flatpak4Mac exists but its UUID is not safely matched by the project marker. Delete or reconcile it manually first.'
  fi
else
  if [[ -n "$recorded_uuid" ]]; then
    fail 'UTM command-line tool unavailable; cannot verify whether the recorded VM still exists.'
  fi
  log 'UTM is not installed; no registered VM can be removed.'
fi

if [[ -n "$vm_line" ]]; then
  read -r actual_uuid state vm_name extra <<< "$vm_line"
  [[ "$vm_name" == Flatpak4Mac && -z "${extra:-}" ]] || fail "Recorded VM does not match expected name: $vm_line"
  [[ "$state" == stopped ]] || fail "VM is $state. Stop Flatpak4Mac completely in UTM before resetting."
  printf '  UTM VM: Flatpak4Mac (%s), stopped\n' "$actual_uuid"
  confirm_delete "PERMANENTLY delete this UTM VM, including its virtual disks?" || fail 'VM deletion declined; no changes made.'
  log "Deleting registered UTM VM $actual_uuid"
  "$utmctl" delete "$actual_uuid" || fail 'UTM deletion failed; project files have not been removed.'
  # Verify UTM no longer reports the VM before deleting local working image files.
  if ! remaining="$("$utmctl" list 2>&1)"; then
    fail 'Cannot verify VM deletion; leaving project VM directory untouched.'
  fi
  if printf '%s\n' "$remaining" | awk -v id="$actual_uuid" 'NR>1 && toupper($1)==toupper(id) {found=1} END{exit !found}'; then
    fail 'VM still appears in UTM; leaving project VM directory untouched.'
  fi
else
  log 'No matching registered UTM VM found.'
fi

if [[ -e "$VM_DIR" || -L "$VM_DIR" ]]; then
  [[ -d "$VM_DIR" && ! -L "$VM_DIR" ]] || fail 'VM directory is not a normal directory; refusing removal.'
  log "Removing working VM directory $VM_DIR"
  rm -rf -- "$VM_DIR"
else
  log 'Working VM directory already absent.'
fi

log 'VM reset complete.'
printf 'Kept: %s/cache/, %s/retrodeck/, %s/autoinstall/, %s/config/\n' "$ROOT" "$ROOT" "$ROOT" "$ROOT"
printf 'Create a new VM with: cd %q && ./quick-start.sh\n' "$ROOT"
