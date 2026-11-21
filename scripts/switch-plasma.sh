#!/usr/bin/env bash
# Switch Plasma display protocol without changing the saved default.
set -Eeuo pipefail
F4M_SWITCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$F4M_SWITCH_ROOT/scripts/common.sh"
need_macos
validate_guest_env
case "${1:-}" in
  wayland) mode=plasma-wayland ;;
  x11) mode=plasma-x11 ;;
  *) echo 'Usage: ./scripts/switch-plasma.sh wayland|x11' >&2; exit 2 ;;
esac
"$F4M_SWITCH_ROOT/scripts/ensure-session-helper.sh"
ssh_guest "sudo /usr/local/sbin/flatpak4mac-session-mode $mode"
