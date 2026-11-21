#!/usr/bin/env bash
set -Eeuo pipefail
F4M_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
F4M_IMAGE_DIR="${F4M_IMAGE_DIR:-$F4M_DIR/vm/ubuntu-24.04}"
F4M_VM_NAME="${F4M_VM_NAME:-Flatpak4Mac}"
F4M_DISK_GB="${F4M_DISK_GB:-64}"
F4M_CONFIG_DIR="$F4M_DIR/config"
F4M_ENV="$F4M_CONFIG_DIR/phase5.env"
F4M_SHARE="$F4M_DIR/retrodeck"
F4M_KEY="$F4M_IMAGE_DIR/flatpak-utm-ed25519"
F4M_HOST="${F4M_HOST:-}"
F4M_PORT="${F4M_PORT:-22}"
log(){ printf '\n==> %s\n' "$*"; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_macos(){ [[ "$(uname -s)" == Darwin ]] || fail 'Run this script on macOS.'; [[ "$(id -u)" != 0 ]] || fail 'Do not run as root.'; }
validate_guest_env(){
  if [[ -f "$F4M_ENV" ]]; then
    # This file belongs to the user; read the exact keys needed, without executing it.
    local line k v
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^(UTM_SSH_HOST|UTM_SSH_PORT|UTM_SSH_USER|UTM_SSH_KEY|UTM_DISPLAY)= ]] || continue
      k="${line%%=*}"; v="${line#*=}"; v="${v#\"}"; v="${v%\"}"
      case "$k" in
        UTM_SSH_HOST) F4M_HOST="$v";;
        UTM_SSH_PORT) F4M_PORT="$v";;
      esac
    done < "$F4M_ENV"
  fi
}
resolve_utm(){
  if [[ -d /Applications/UTM.app ]]; then UTM_APP=/Applications/UTM.app
  elif [[ -d "$HOME/Applications/UTM.app" ]]; then UTM_APP="$HOME/Applications/UTM.app"
  else UTM_APP=''; fi
}
ssh_guest(){
  [[ -f "$F4M_KEY" ]] || fail "Missing SSH key: $F4M_KEY"
  validate_guest_env
  [[ -n "$F4M_HOST" ]] || fail 'UTM guest address unknown; configure UTM_SSH_HOST in $F4M_DIR/config/phase5.env (see docs).'
  [[ "$F4M_PORT" =~ ^[0-9]{1,5}$ ]] || fail 'Invalid SSH port'
  ssh -i "$F4M_KEY" -p "$F4M_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "flatpak@$F4M_HOST" "$@"
}
get_guest_ip(){
  resolve_utm
  [[ -n "$UTM_APP" ]] || return 1
  osascript - "$F4M_VM_NAME" <<'APPLESCRIPT' 2>/dev/null
on run argv
  tell application "UTM"
    set vm to virtual machine named (item 1 of argv)
    set ips to query ip of vm
    repeat with ip in ips
      set t to ip as text
      if t contains "." and t is not "127.0.0.1" then return t
    end repeat
  end tell
end run
APPLESCRIPT
}
write_config(){
  local host="$1" port="${2:-22}" key="$F4M_KEY" tmp
  [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid IPv4 address'
  mkdir -p "$F4M_CONFIG_DIR"
  tmp="$(mktemp "$F4M_CONFIG_DIR/.phase5.env.XXXXXX")"
  chmod 600 "$tmp"
  # Update only SSH connection fields, preserving display preferences.
  if [[ -f "$F4M_ENV" ]]; then
    awk -F= '!($1=="UTM_SSH_HOST" || $1=="UTM_SSH_PORT" || $1=="UTM_SSH_USER" || $1=="UTM_SSH_KEY") {print}' "$F4M_ENV" > "$tmp"
  else
    printf 'UTM_DISPLAY=:0\n' > "$tmp"
  fi
  printf 'UTM_SSH_HOST=%s\nUTM_SSH_PORT=%s\nUTM_SSH_USER=flatpak\nUTM_SSH_KEY=%s\n' "$host" "$port" "$key" >> "$tmp"
  mv -f "$tmp" "$F4M_ENV"
  F4M_HOST="$host"
  F4M_PORT="$port"
  log "Updated guest SSH connection: $host:$port"
}
