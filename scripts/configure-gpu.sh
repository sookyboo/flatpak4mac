#!/bin/bash
# Phase 3 host coordinator for UTM and Lima/krunkit (no Homebrew installation).
# Keeps the Phase 1 VZ VM untouched; creates a separate krunkit VM.
set -Eeuo pipefail
ROOT="${HOME}/.local/share/flatpak-macos"
LIMA_VERSION="${LIMA_VERSION:-2.3.0}"
LIMACTL="${LIMACTL:-${ROOT}/lima-${LIMA_VERSION}/bin/limactl}"
LIMA_HOME="${LIMA_HOME:-${HOME}/.lima}"
KRUNKIT_VM="${KRUNKIT_VM:-flatpak-gpu-krunkit}"
UTM_GUEST_SCRIPT='configure-gpu-guest.sh'
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export LIMA_HOME
log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
Usage: configure-gpu.sh <command>
  utm             Show supported UTM VM setup and copy/guest install instructions
  utm-open        Open UTM if installed (otherwise show official download URL)
  krunkit-check   Check Apple Silicon, Lima driver, krunkit/libkrun prerequisites
  krunkit-setup   Create/reuse a SEPARATE Lima krunkit VM; install Flatpak/tests
  krunkit-check-gpu  Run GPU diagnostics in existing krunkit VM
  krunkit-shell   Open a shell in the krunkit VM
  help            Print this help
Notes:
  * No Homebrew is installed or invoked.
  * UTM guests run GPU checks locally inside the guest desktop or its terminal.
  * Krunkit requires a separately installed krunkit + libkrun stack.
  * Neither mode modifies your original Lima 'flatpak' VZ VM.
HELP
}
[[ "$(uname -s)" == Darwin ]] || die 'Run this coordinator on macOS.'
[[ "$(id -u)" -ne 0 ]] || die 'Run as your normal macOS account.'

utm_instructions() {
  cat <<'HELP'
UTM BACKEND (no package manager):
1. Install UTM v5.0.8 (or newer) from https://github.com/utmapp/UTM/releases
   Download UTM.dmg, drag UTM.app to /Applications, and open it.
2. Create a NEW Linux Ubuntu VM in UTM, using QEMU virtualisation (not Apple's
   Virtualization.framework backend). Use an ARM64 image on Apple Silicon.
3. In UTM VM settings, select a display device labelled '(GPU Supported)'
   (virtio-gpu-gl-pci or equivalent), and enable GPU acceleration.
4. For OpenGL VirGL: select the UTM host renderer 'Apple Core OpenGL' or a
   supported VirGL renderer. For Venus Vulkan: use 'Default' or 'ANGLE (Metal)',
   Vulkan Driver 'MoltenVK' (not Disabled). These are alternative configurations.
   UTM 5.0.x cannot render the Linux desktop through Venus in all cases.
5. Install Ubuntu. Open Terminal WITHIN the VM graphical session. Transfer the
   companion guest script to the Ubuntu guest, then run:
      chmod +x configure-gpu-guest.sh
      ./configure-gpu-guest.sh setup
   You can use SCP, an HTTP file transfer, or copy the script via shared folders.
6. Verify your actual GPU with:
      ./configure-gpu-guest.sh check
   Run glxinfo -B in the VM desktop terminal to verify VirGL (not llvmpipe).

IMPORTANT: This does NOT automatically migrate the Phase 1 Lima VM. UTM needs
its own Ubuntu VM with a GPU device; the old VZ VM remains unchanged.
For UTM documentation: https://docs.getutm.app/guest-support/linux/
HELP
}
find_krunkit() {
  if command -v krunkit >/dev/null 2>&1; then command -v krunkit; return 0; fi
  for p in /opt/homebrew/bin/krunkit /opt/local/bin/krunkit /usr/local/bin/krunkit "$HOME/.local/bin/krunkit"; do
    if [[ -x "$p" ]]; then printf '%s\n' "$p"; return 0; fi
  done
  return 1
}
check_krunkit() {
  [[ "$(uname -m)" == arm64 ]] || die 'Krunkit requires an Apple Silicon (arm64) Mac.'
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [[ "$major" =~ ^[0-9]+$ ]] && ((major >= 14)) || die 'Krunkit requires macOS 14+.'
  [[ -x "$LIMACTL" ]] || die "Lima missing: $LIMACTL. Run Phase 1 first."
  local binary
  binary="$(find_krunkit || true)"
  if [[ -z "$binary" ]]; then
    cat >&2 <<'HELP'
Krunkit executable not found. This script does not install Homebrew.
Krunkit depends on libkrun, libkrunfw, a Vulkan/graphics stack and build tooling.
Official build instructions: https://github.com/libkrun/krunkit
Lima backend instructions: https://lima-vm.io/docs/config/vmtype/krunkit/
Install krunkit + libkrun using a manually built stack or another installation
method you approve. Once krunkit is callable, rerun krunkit-check.
HELP
    exit 2
  fi
  export PATH="$(dirname "$binary"):$PATH"
  log "Detected krunkit: $binary"
  log 'Checking Lima supported drivers'
  "$LIMACTL" info | grep -i -C 3 krunkit || die 'Lima did not list the krunkit external driver. Install it for this Lima release.'
  log 'Krunkit prerequisites found (VM start is the functional test)'
}
vm_exists() { [[ -f "$LIMA_HOME/$KRUNKIT_VM/lima.yaml" ]]; }
krunkit_setup() {
  check_krunkit
  # A separate VM prevents Lima from attempting to change the VM backend in place.
  if vm_exists; then
    log "Reusing VM $KRUNKIT_VM"
    grep -Eq '^[[:space:]]*vmType:[[:space:]]*krunkit([[:space:]#]|$)' "$LIMA_HOME/$KRUNKIT_VM/lima.yaml" || \
      die "Existing $KRUNKIT_VM is not declared vmType: krunkit. Refusing to change it."
    "$LIMACTL" start "$KRUNKIT_VM"
  else
    [[ ! -e "$LIMA_HOME/$KRUNKIT_VM" ]] || die 'VM directory already exists but lacks lima.yaml; inspect manually.'
    log "Creating new krunkit Ubuntu VM: $KRUNKIT_VM"
    "$LIMACTL" start --name="$KRUNKIT_VM" --vm-type=krunkit --tty=false template:ubuntu
  fi
  local guest_script
  guest_script="$(cat "${SELF_DIR}/${UTM_GUEST_SCRIPT}" 2>/dev/null)" || die "Companion guest script missing at ${SELF_DIR}/${UTM_GUEST_SCRIPT}"
  log 'Installing guest graphics tooling + Flatpak and running sandbox test'
  # Passing the script as an argv string keeps the Lima shell SSH channel free.
  "$LIMACTL" shell --tty=false "$KRUNKIT_VM" bash -lc "$guest_script"
  log 'Phase 3 krunkit VM provisioned; check output for actual GPU driver evidence.'
  log "Inspect guest: $LIMACTL shell $KRUNKIT_VM"
}
case "${1:-help}" in
  help|-h|--help) usage;;
  utm) utm_instructions;;
  utm-open)
    if [[ -d /Applications/UTM.app ]]; then open -a /Applications/UTM.app
    elif [[ -d "$HOME/Applications/UTM.app" ]]; then open -a "$HOME/Applications/UTM.app"
    else utm_instructions; fi;;
  krunkit-check) check_krunkit;;
  krunkit-setup) krunkit_setup;;
  krunkit-check-gpu)
    check_krunkit
    vm_exists || die "VM $KRUNKIT_VM does not exist. Run krunkit-setup first."
    "$LIMACTL" start "$KRUNKIT_VM"
    "$LIMACTL" shell --tty=false "$KRUNKIT_VM" bash -lc "$(cat "${SELF_DIR}/${UTM_GUEST_SCRIPT}" | sed 's/MODE="${1:-setup}"/MODE="check"/')";;
  krunkit-shell)
    check_krunkit
    vm_exists || die "VM $KRUNKIT_VM does not exist."
    "$LIMACTL" shell "$KRUNKIT_VM";;
  *) usage >&2; exit 2;;
esac
