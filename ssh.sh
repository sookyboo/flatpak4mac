#!/usr/bin/env bash
# Open an interactive SSH shell in the Flatpak4Mac UTM guest.
# Optional arguments are passed to ssh (e.g. ./ssh.sh -L 8080:localhost:8080).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
need_macos
[[ -f "$F4M_KEY" && ! -L "$F4M_KEY" ]] || fail "Missing VM SSH key: $F4M_KEY. Run ./quick-start.sh first."
validate_guest_env
[[ "$F4M_PORT" =~ ^[0-9]{1,5}$ ]] || fail 'Invalid UTM SSH port'

# The recorded address is fast on normal runs; IP discovery is only needed
# after DHCP changes. Verify the actual guest before opening an interactive shell.
probe_host() {
  local host="$1" port="$2" got
  [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  got="$(ssh -i "$F4M_KEY" -p "$port" -o BatchMode=yes \
    -o ConnectTimeout=3 -o ConnectionAttempts=1 \
    -o StrictHostKeyChecking=accept-new "flatpak@$host" \
    'printf "%s:%s" "$(id -un)" "$(hostname -s)"' 2>/dev/null)" || return 1
  [[ "$got" == 'flatpak:flatpak-utm' ]]
}

if [[ -z "$F4M_HOST" ]] || ! probe_host "$F4M_HOST" "$F4M_PORT"; then
  printf 'Finding Flatpak4Mac VM (saved SSH address unavailable)...\n' >&2
  candidate="$(get_guest_ip 2>/dev/null || true)"
  if [[ -n "$candidate" ]] && probe_host "$candidate" 22; then
    F4M_HOST="$candidate"
    F4M_PORT=22
  else
    # Use the same MAC-verified ARP discovery as quick-start, with no baseline.
    source "$ROOT/scripts/discover-guest-ip.sh"
    candidate="$(discover_arp_ip '' 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      F4M_HOST="$candidate"
      F4M_PORT=22
    else
      fail "Could not reach Flatpak4Mac over SSH. Start the VM in UTM, or run ./quick-start.sh to refresh its IP."
    fi
  fi
  write_config "$F4M_HOST" "$F4M_PORT" >&2
fi

printf 'Connecting to flatpak@%s:%s (Ctrl-D to disconnect)\n' "$F4M_HOST" "$F4M_PORT" >&2
exec ssh -t -i "$F4M_KEY" -p "$F4M_PORT" \
  -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  "$@" "flatpak@$F4M_HOST"
