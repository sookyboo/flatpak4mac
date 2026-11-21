#!/bin/bash
# Phase 2: GUI Flatpaks via XQuartz + SSH X11 forwarding (no Homebrew).
# Designed for the VM and Lima layout created by install-lima.sh.
# Usage: ./configure-xquartz.sh [setup|xclock|launch|check]
set -Eeuo pipefail

VM_NAME="${VM_NAME:-flatpak}"
LIMA_VERSION="${LIMA_VERSION:-2.3.0}"
LIMA_HOME="${LIMA_HOME:-${HOME}/.lima}"
ROOT="${HOME}/.local/share/flatpak-macos"
LIMACTL="${ROOT}/lima-${LIMA_VERSION}/bin/limactl"
APP_ID="org.xfce.mousepad"
MODE="${1:-setup}"
export LIMA_HOME

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
[[ "$(uname -s)" == Darwin ]] || die "Run on macOS."
[[ "$(id -u)" -ne 0 ]] || die "Run as your macOS user, not with sudo."
case "$MODE" in setup|xclock|launch|check) ;; *) die 'Usage: script [setup|xclock|launch|check]' ;; esac
need ssh
need launchctl
need open
[[ -x "$LIMACTL" ]] || die "Lima not found at $LIMACTL. Run Phase 1 first (or set LIMA_VERSION)."
[[ -f "$LIMA_HOME/$VM_NAME/lima.yaml" ]] || die "Lima VM '$VM_NAME' does not exist. Run Phase 1 first."
SSH_CONFIG="$LIMA_HOME/$VM_NAME/ssh.config"
SSH_HOST="lima-${VM_NAME}"

check_xquartz() {
  if [[ ! -d /Applications/Utilities/XQuartz.app && ! -d /Applications/XQuartz.app ]]; then
    cat >&2 <<'MSG'
XQuartz is not installed in a standard location.
Install the current stable .pkg from https://www.xquartz.org/
Complete the installer and LOG OUT/LOG IN if requested, then rerun this script.
No Homebrew is required.
MSG
    exit 2
  fi
  [[ -x /opt/X11/bin/xauth ]] || die "XQuartz xauth not found at /opt/X11/bin/xauth; finish installation and relogin."
}

start_xquartz() {
  check_xquartz
  log 'Starting XQuartz'
  open -a XQuartz || die 'Unable to start XQuartz.'
  local disp="" n
  for ((n=0; n<15; n++)); do
    disp="$(launchctl getenv DISPLAY 2>/dev/null || true)"
    [[ -n "$disp" ]] && break
    sleep 1
  done
  if [[ -z "$disp" ]]; then
    # XQuartz may have a conventional display even when the shell has not
    # inherited the launchd variable, but forwarded SSH can require relogin.
    disp="${DISPLAY:-:0}"
    log 'launchctl DISPLAY is unset; trying default display. If forwarding fails, log out/in once after installing XQuartz.'
  fi
  export DISPLAY="$disp"
  export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
  # macOS ssh uses xauth to create per-connection cookies for X11 forwarding.
  # The XQuartz installer supplies the utility outside the default PATH.
  export PATH="/opt/X11/bin:$PATH"
  log "Host X11 display: $DISPLAY"
}

start_vm() {
  log "Starting or reusing VM '$VM_NAME'"
  "$LIMACTL" start "$VM_NAME"
  [[ -s "$SSH_CONFIG" ]] || die "Missing $SSH_CONFIG (Lima SSH config)."
}

# -Y trusted forwarding is needed by many GTK applications. SSH handles X11
# auth cookies; this does NOT expose an X server to the network or require xhost +.
run_ssh() {
  ssh -F "$SSH_CONFIG" \
    -o ForwardX11=yes -o ForwardX11Trusted=yes \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "$SSH_HOST" "$@"
}

guest_setup() {
  log 'Installing X11 diagnostics, X11 authentication and graphical Flatpak'
  local guest
  guest=$(cat <<'GUEST'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
command -v apt-get >/dev/null || { echo 'Ubuntu/Debian guest required' >&2; exit 1; }
sudo apt-get update
sudo apt-get install -y xauth x11-apps x11-utils dbus-user-session flatpak
sudo flatpak remote-add --system --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install --system --noninteractive -y flathub org.xfce.mousepad
flatpak info --system org.xfce.mousepad >/dev/null
printf 'PASS: Mousepad Flatpak installed in guest\n'
GUEST
)
  "$LIMACTL" shell --tty=false "$VM_NAME" bash -lc "$guest"
}

check_forwarding() {
  log 'Checking authenticated X11 forwarding over SSH'
  if ! run_ssh 'test -n "$DISPLAY" && command -v xset >/dev/null && xset q >/dev/null && printf "PASS: guest X11 forwarding available (DISPLAY=%s)\n" "$DISPLAY"'; then
    cat >&2 <<'MSG'
X11 forwarding failed.
- Ensure XQuartz is running (and log out/in after first installation).
- Verify macOS has a GUI session, rather than headless/SSH-only login.
- Check /opt/X11/bin/xauth on macOS and xauth in Ubuntu.
- Check that Ubuntu's sshd permits X11Forwarding (normally enabled).
MSG
    exit 1
  fi
}

check_xquartz
start_vm
case "$MODE" in
  setup)
    guest_setup
    start_xquartz
    check_forwarding
    log 'Phase 2 ready. Test a window, then launch the Flatpak:'
    printf '  %q xclock\n  %q launch\n' "$0" "$0"
    ;;
  check)
    start_xquartz
    check_forwarding
    ;;
  xclock)
    start_xquartz
    check_forwarding
    log 'Launching xclock (close its window or press Ctrl-C to finish)'
    run_ssh xclock
    ;;
  launch)
    start_xquartz
    check_forwarding
    log 'Launching Mousepad Flatpak (close its window to finish)'
    # Flatpak app uses X11 backend; do not pass host DISPLAY into guest.
    # SSH synthesizes guest DISPLAY and handles per-session authorization.
    run_ssh 'dbus-run-session -- env GDK_BACKEND=x11 flatpak run --system org.xfce.mousepad'
    ;;
esac
