#!/bin/bash
# Phase 4 host coordinator: UTM instructions and Lima/krunkit guest provisioning.
# Does not install Homebrew, alter VM backend or silently change VM settings.
set -Eeuo pipefail
MODE="${1:-help}"
LIMA_VERSION="${LIMA_VERSION:-2.3.0}"
ROOT="${HOME}/.local/share/flatpak-macos"
LIMACTL="${LIMACTL:-${ROOT}/lima-${LIMA_VERSION}/bin/limactl}"
LIMA_HOME="${LIMA_HOME:-$HOME/.lima}"
KRUNKIT_VM="${KRUNKIT_VM:-flatpak-gpu-krunkit}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
GUEST="$SELF_DIR/configure-desktop-guest.sh"
export LIMA_HOME
log(){ printf '\n==> %s\n' "$*"; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage(){ cat <<'HELP'
Usage: configure-desktop.sh <command>
  utm                  Explain UTM GUI settings and guest installation
  utm-open             Open UTM.app (if installed)
  krunkit-setup        Install guest integration in EXISTING krunkit Lima VM
  krunkit-check        Inspect guest integration in existing krunkit VM
  krunkit-audio-test   Test audio in the existing krunkit guest
  help                 Show this message
For UTM guests: copy configure-desktop-guest.sh into Ubuntu and run
  ./configure-desktop-guest.sh setup
  ./configure-desktop-guest.sh mount-utm
  ./configure-desktop-guest.sh check
No Homebrew; existing Lima VZ VM is not modified.
HELP
}
[[ "$(uname -s)" == Darwin ]] || die 'Run host coordinator on macOS.'
[[ "$(id -u)" -ne 0 ]] || die 'Do not run as root.'
utm(){ cat <<'HELP'
UTM PHASE 4 (QEMU backend, not Apple VZ):
1. Shut down the UTM Ubuntu VM before changing its settings.
2. In UTM settings, enable clipboard sharing and SPICE display support.
3. Configure QEMU audio output hardware (and a working guest sound session).
4. Choose a host Shared Directory and select the VirtFS (9p) sharing mode.
   Do not choose SPICE WebDAV if using the mount-utm command below.
5. For controllers, explicitly configure USB device passthrough in UTM and
   attach a controller after starting the VM. Not all controllers support it.
6. Start Ubuntu's graphical desktop, open Terminal and transfer the adjacent
   configure-desktop-guest.sh file into the guest.
7. In the Ubuntu guest:
      chmod +x configure-desktop-guest.sh
      ./configure-desktop-guest.sh setup
      ./configure-desktop-guest.sh mount-utm
      ./configure-desktop-guest.sh check
      ./configure-desktop-guest.sh audio-test
8. For access by an individual Flatpak (example; after installing Mousepad):
      ./configure-desktop-guest.sh grant-share org.xfce.mousepad /mnt/utm

To persist the UTM mount across reboots (optional), add exactly this line ONCE
in the guest's /etc/fstab (after confirming a working manual mount):
  share /mnt/utm 9p trans=virtio,version=9p2000.L,rw,_netdev,nofail 0 0

Documentation: https://docs.getutm.app/guest-support/linux/
               https://docs.getutm.app/settings-qemu/sharing/
HELP
}
krunkit_run(){
  local action="$1"
  [[ -x "$LIMACTL" ]] || die "Cannot find Lima at $LIMACTL. Run Phase 1 or set LIMACTL."
  [[ -f "$LIMA_HOME/$KRUNKIT_VM/lima.yaml" ]] || die "Missing VM $KRUNKIT_VM. Run Phase 3 krunkit-setup first."
  grep -Eq '^[[:space:]]*vmType:[[:space:]]*krunkit([[:space:]#]|$)' "$LIMA_HOME/$KRUNKIT_VM/lima.yaml" || \
    die "VM $KRUNKIT_VM is not configured for krunkit; refusing to run."
  [[ -r "$GUEST" ]] || die "Missing guest script $GUEST"
  "$LIMACTL" start "$KRUNKIT_VM"
  # Copy guest script via Lima's existing filesystem mounting (or direct stdin
  # on an SSH command); no guest-side host path assumptions and no root SSH.
  # Quote script contents into positional Bash command via base64 to avoid
  # shell word-splitting. macOS has base64 and guest has base64 (coreutils).
  local payload
  payload="$(base64 < "$GUEST" | tr -d '\n')"
  "$LIMACTL" shell --tty=false "$KRUNKIT_VM" bash -lc \
    "export PHASE4_BACKEND=krunkit; printf %s '$payload' | base64 -d | bash -s -- '$action'"
}
case "$MODE" in
  utm) utm;;
  utm-open) if [[ -d /Applications/UTM.app ]]; then open -a /Applications/UTM.app; else utm; fi;;
  krunkit-setup) krunkit_run setup;;
  krunkit-check) krunkit_run check;;
  krunkit-audio-test) krunkit_run audio-test;;
  help|-h|--help) usage;;
  *) usage >&2; exit 2;;
esac
