#!/usr/bin/env bash
# Remove the Flatpak4Mac installation while offering to retain ROMs and image cache.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Run on macOS.' >&2; exit 1; }
[[ "$(id -u)" != 0 ]] || { echo 'Do not run as root.' >&2; exit 1; }
[[ "$ROOT" == "$HOME/flatpak4mac" && ! -L "$ROOT" ]] || {
  echo "Refusing uninstall outside the expected project directory: $ROOT" >&2; exit 1;
}
[[ -t 0 ]] || { echo 'Interactive uninstall required; no changes made.' >&2; exit 1; }
log(){ printf '==> %s\n' "$*"; }
ask_yes_default(){
  local answer
  read -r -p "$1 [Y/n] " answer || return 1
  case "$answer" in ''|y|Y|yes|YES|Yes) return 0;; n|N|no|NO|No) return 1;;
    *) echo 'Please answer yes or no.' >&2; ask_yes_default "$1";; esac
}
ask_no_default(){
  local answer
  read -r -p "$1 [y/N] " answer || return 1
  case "$answer" in y|Y|yes|YES|Yes) return 0;; ''|n|N|no|NO|No) return 1;;
    *) echo 'Please answer yes or no.' >&2; ask_no_default "$1";; esac
}
RETRO="$ROOT/retrodeck"
CACHE="$ROOT/cache"
VM_MARKER="$ROOT/vm/ubuntu-24.04/.vm-created-by-v2"
APP="$HOME/Applications/Flatpak Manager.app"
APP_MARKER="$APP/Contents/Resources/.flatpak-macos-phase5"
UTM_APP=''
if [[ -d /Applications/UTM.app ]]; then UTM_APP=/Applications/UTM.app
elif [[ -d "$HOME/Applications/UTM.app" ]]; then UTM_APP="$HOME/Applications/UTM.app"; fi
printf '\nFlatpak4Mac uninstall from %s\n' "$ROOT"
if ask_yes_default 'Keep retrodeck/ (ROMs, ports, saves and configuration)?'; then KEEP_RETRO=1; else KEEP_RETRO=0; fi
if ask_yes_default 'Keep cached downloaded Ubuntu cloud image (cache/)?'; then KEEP_CACHE=1; else KEEP_CACHE=0; fi

# External targets must be confirmed separately and positively identified.
DELETE_VM=0
if [[ -f "$VM_MARKER" ]]; then
  vm_uuid="$(tr -d '\r\n' < "$VM_MARKER")"
  if [[ ! "$vm_uuid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    echo 'Invalid VM identity marker; refusing to delete any UTM VM.' >&2
  elif [[ -n "$UTM_APP" && -x "$UTM_APP/Contents/MacOS/utmctl" ]]; then
    UTMCTL="$UTM_APP/Contents/MacOS/utmctl"
    vm_line="$("$UTMCTL" list 2>/dev/null | awk -v id="$vm_uuid" 'NR>1 && $1==id {print}')" || vm_line=''
    if [[ -n "$vm_line" ]]; then
      read -r id state name_rest <<< "$vm_line"
      if [[ "$name_rest" == Flatpak4Mac && "$state" == stopped ]]; then
        if ask_no_default "Delete EXTERNAL UTM VM 'Flatpak4Mac' ($vm_uuid) permanently?"; then DELETE_VM=1; fi
      else
        printf 'Leaving UTM VM untouched (name/status mismatch: %s).\n' "$vm_line"
      fi
    else
      echo 'Recorded VM not found in UTM; no external VM deletion.'
    fi
  else
    echo 'UTM command-line tool unavailable; no external VM deletion.'
  fi
fi
DELETE_APP=0
if [[ -e "$APP" || -L "$APP" ]]; then
  if [[ -d "$APP" && ! -L "$APP" && -f "$APP_MARKER" ]]; then
    if ask_no_default "Delete EXTERNAL managed application '$APP'?"; then DELETE_APP=1; fi
  else
    echo "Unmanaged or symlink application left untouched: $APP"
  fi
fi

printf '\nCleanup plan:\n'
printf '  retrodeck/: %s\n' "$([[ "$KEEP_RETRO" == 1 ]] && echo KEEP || echo DELETE)"
printf '  cache/:     %s\n' "$([[ "$KEEP_CACHE" == 1 ]] && echo KEEP || echo DELETE)"
printf '  Other project entries: DELETE (including autoinstall bundles, config, VM working files)\n'
printf '  External UTM VM: %s\n' "$([[ "$DELETE_VM" == 1 ]] && echo DELETE || echo KEEP)"
printf '  External launcher: %s\n' "$([[ "$DELETE_APP" == 1 ]] && echo DELETE || echo KEEP)"
if (( DELETE_VM )); then
  log "Deleting UTM VM $vm_uuid"
  "$UTMCTL" delete "$vm_uuid" || { echo 'UTM delete failed: project cleanup aborted.' >&2; exit 1; }
fi
if (( DELETE_APP )); then
  log "Removing managed launcher $APP"
  rm -rf -- "$APP"
fi
# Verbose deletion only within the exact project root. Never follow top-level symlinks.
shopt -s nullglob dotglob
for entry in "$ROOT"/*; do
  basename="${entry##*/}"
  case "$basename" in
    retrodeck) if (( KEEP_RETRO )); then log "Preserving $entry"; continue; fi;;
    cache) if (( KEEP_CACHE )); then log "Preserving $entry"; continue; fi;;
    uninstall.sh) continue;;
  esac
  log "Removing $entry"
  rm -rf -- "$entry"
done
printf '\nUninstall finished. Remaining project data:\n'
for p in "$RETRO" "$CACHE"; do [[ -e "$p" ]] && printf '  %s\n' "$p"; done
printf '  %s/uninstall.sh\n' "$ROOT"
if (( ! DELETE_VM )); then echo 'Note: Any retained UTM VM is not managed after project files are removed.'; fi
