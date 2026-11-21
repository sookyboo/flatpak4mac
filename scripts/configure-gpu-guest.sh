#!/usr/bin/env bash
# Phase 3 guest-side Flatpak + graphics diagnostics (Ubuntu/Debian).
# Run inside either a UTM Linux guest or Lima/krunkit Linux guest.
set -Eeuo pipefail

usage() {
  cat <<'HELP'
Usage: configure-gpu-guest.sh [setup|check|flatpak-test]
  setup        Install diagnostics and Flatpak runtime; perform a non-fatal GPU check
  check        Diagnose the guest GPU stack (does not claim acceleration without proof)
  flatpak-test Execute a sandboxed Flatpak runtime command
Environment:
  FLATPAK_RUNTIME  Runtime branch (default org.freedesktop.Platform//25.08)
HELP
}
MODE="${1:-setup}"
RUNTIME="${FLATPAK_RUNTIME:-org.freedesktop.Platform//25.08}"
log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
case "$MODE" in setup|check|flatpak-test) ;; -h|--help) usage; exit 0;; *) usage >&2; exit 2;; esac
[[ "$(uname -s)" == Linux ]] || die 'This script must run inside a Linux VM.'

setup() {
  command -v apt-get >/dev/null || die 'Only Ubuntu/Debian apt guests are supported.'
  command -v sudo >/dev/null || die 'sudo is required in the guest.'
  log 'Installing Flatpak and 3D diagnostics (idempotent apt operation)'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    flatpak dbus-user-session dbus-bin mesa-utils mesa-vulkan-drivers \
    vulkan-tools libgl1-mesa-dri libegl1 pciutils
  sudo flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  sudo flatpak install --system -y --noninteractive flathub "$RUNTIME"
  flatpak_test
}
flatpak_test() {
  log 'Verifying sandbox execution'
  command -v dbus-run-session >/dev/null || die 'Missing dbus-run-session.'
  dbus-run-session -- flatpak run --system --command=sh "$RUNTIME" \
    -c 'test -f /.flatpak-info && printf "PASS: Flatpak sandbox (%s)\n" "$(uname -m)"'
}
check() {
  log 'Guest kernel and DRM devices'
  uname -a
  ls -la /dev/dri 2>/dev/null || true
  if command -v lspci >/dev/null; then lspci -nn | grep -Ei 'vga|3d|display|virtio' || true; fi
  log 'Renderer diagnostics'
  if [[ -n "${DISPLAY:-}" ]] && command -v glxinfo >/dev/null; then
    glxinfo -B 2>&1 || true
  else
    printf 'GLX: No DISPLAY or glxinfo; GLX acceleration cannot be evaluated in this session.\n'
  fi
  if command -v eglinfo >/dev/null; then
    eglinfo -B 2>&1 | sed -n '1,110p' || true
  fi
  if command -v vulkaninfo >/dev/null; then
    vulkaninfo --summary 2>&1 | sed -n '1,130p' || true
  else
    printf 'Vulkan: vulkaninfo is not installed.\n'
  fi
  log 'Interpretation'
  printf '%s\n' \
    'GPU acceleration is NOT established solely by /dev/dri or Mesa being installed.' \
    'VirGL/Virgl in the actual OpenGL renderer indicates virtual GPU rendering.' \
    'Venus in the selected Vulkan driver/device indicates a guest Venus path.' \
    'llvmpipe/softpipe/lavapipe indicate SOFTWARE rendering for that API.' \
    'A GPU backend must be enabled in the host VM settings; test a real app too.' \
    'Note: when forwarding via XQuartz SSH X11, GLX typically does NOT use the guest 3D GPU.'
}
case "$MODE" in
  setup) setup; check;;
  check) check;;
  flatpak-test) flatpak_test;;
esac
