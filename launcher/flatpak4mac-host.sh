#!/bin/bash
# Flatpak macOS Phase 5: per-application display modes (AppleScript UI + CLI).
set -Eeuo pipefail
[[ "$(uname -s)" == Darwin || "${FLATPAK_MACOS_TEST:-}" == 1 ]] || { echo 'ERROR: Run on macOS.' >&2; exit 1; }
BACKEND=utm
MODE=auto
REMEMBER=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) [[ $# -ge 2 ]] || exit 2; BACKEND="$2"; shift 2;;
    --mode) [[ $# -ge 2 ]] || exit 2; MODE="$2"; shift 2;;
    --remember) REMEMBER=1; shift;;
    *) break;;
  esac
done
ACTION="${1:-help}"; [[ $# -eq 0 ]] || shift
ROOT="$HOME/.local/share/flatpak-macos"
PROJECT_ROOT="${FLATPAK4MAC_HOME:-$HOME/flatpak4mac}"
CONFIG="$PROJECT_ROOT/config/phase5.env"
PREFS="$PROJECT_ROOT/config/app-modes.tsv"
if [[ -e "$CONFIG" ]]; then
  [[ -f "$CONFIG" && ! -L "$CONFIG" ]] || { echo 'Configuration must be a regular file.' >&2; exit 1; }
  # This is user-authored shell configuration (same as Phase 5).
  # shellcheck source=/dev/null
  source "$CONFIG"
fi
LIMA_VERSION="${LIMA_VERSION:-2.3.0}"
LIMACTL="${LIMACTL:-$ROOT/lima-$LIMA_VERSION/bin/limactl}"
LIMA_HOME="${LIMA_HOME:-$HOME/.lima}"
KRUNKIT_VM="${KRUNKIT_VM:-flatpak-gpu-krunkit}"
UTM_SSH_HOST="${UTM_SSH_HOST:-}"
UTM_SSH_PORT="${UTM_SSH_PORT:-22}"
UTM_SSH_USER="${UTM_SSH_USER:-}"
UTM_DISPLAY="${UTM_DISPLAY:-:0}"
export LIMA_HOME
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info(){ printf '==> %s\n' "$*"; }
usage(){ cat <<'HELP'
Usage: flatpak-macos-phase5-host.sh [--backend krunkit|utm] [--mode auto|macos|gpu] [--remember] ACTION [APP_ID]
Actions: setup discover list update launch APP_ID session xfce|retrodeck|plasma start stop check preference APP_ID help
Display modes: auto (saved preference, then usable XQuartz/UTM desktop fallback); macos (XQuartz); gpu (guest desktop)
Examples:
  ./flatpak-macos-phase5-host.sh --backend utm --mode macos --remember launch org.xfce.mousepad
  ./flatpak-macos-phase5-host.sh --backend utm --mode gpu discover
  ./flatpak-macos-phase5-host.sh --backend utm preference org.xfce.mousepad
Mode 'gpu' requires an accessible guest X11 desktop; it never guarantees acceleration.
Settings: ~/flatpak4mac/config/phase5.env
Preferences: ~/flatpak4mac/config/app-modes.tsv
HELP
}
[[ "$BACKEND" == krunkit || "$BACKEND" == utm ]] || fail "Unknown backend: $BACKEND"
[[ "$MODE" == auto || "$MODE" == macos || "$MODE" == gpu ]] || fail "Invalid display mode: $MODE"
case "$ACTION" in setup|discover|list|update|launch|session|start|stop|check|preference|help) ;; *) usage; exit 2;; esac
if [[ "$ACTION" == help ]]; then usage; exit 0; fi
if [[ "$ACTION" == launch || "$ACTION" == preference ]]; then
  [[ $# -eq 1 && "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail 'Provide a valid Flatpak application ID.'
  APP_ID="$1"
elif [[ "$ACTION" == session ]]; then
  [[ $# -eq 1 && ( "$1" == xfce || "$1" == retrodeck || "$1" == plasma ) ]] || fail 'Usage: session xfce|retrodeck|plasma'
  SESSION_MODE="$1"
elif [[ "$ACTION" == discover ]]; then
  APP_ID=org.kde.discover
elif [[ $# -ne 0 ]]; then
  fail "Unexpected arguments for $ACTION"
fi
read_preference(){
  [[ -f "$PREFS" && ! -L "$PREFS" ]] || return 0
  awk -F '\t' -v b="$BACKEND" -v a="$APP_ID" '$1==b && $2==a && ($3=="macos" || $3=="gpu") {p=$3} END {print p}' "$PREFS"
}
save_preference(){
  local tmp
  mkdir -p "$(dirname "$PREFS")"
  [[ ! -e "$PREFS" || ( -f "$PREFS" && ! -L "$PREFS" ) ]] || fail 'Preference file is not a regular file.'
  tmp="$(mktemp "${PREFS}.tmp.XXXXXXXX")"
  chmod 600 "$tmp"
  if [[ -f "$PREFS" ]]; then
    awk -F '\t' -v b="$BACKEND" -v a="$APP_ID" '!($1==b && $2==a)' "$PREFS" > "$tmp"
  fi
  printf '%s\t%s\t%s\n' "$BACKEND" "$APP_ID" "$MODE" >> "$tmp"
  mv -f "$tmp" "$PREFS"
}
if [[ "$ACTION" == preference ]]; then
  saved="$(read_preference)"
  printf '%s\n' "${saved:-auto}"
  exit 0
fi
# Keep Automatic distinct from an explicit request. A saved mode is only a
# preference for Automatic; it must not prevent recovery from a broken display.
if [[ "$ACTION" == discover || "$ACTION" == launch ]]; then
  if (( REMEMBER )); then
    [[ "$MODE" == macos || "$MODE" == gpu ]] || fail 'Only explicit display modes can be remembered'
    save_preference
  fi
fi
# Compose only fixed remote commands; app IDs have been validated above.
case "$ACTION" in
  setup)
    REMOTE='set -e; command -v apt-get >/dev/null || { echo Ubuntu/Debian required >&2; exit 1; }; sudo apt-get update; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y flatpak plasma-discover plasma-discover-backend-flatpak dbus-user-session xauth x11-utils x11-xserver-utils; sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; echo "Discover installed."';;
  discover) REMOTE='command -v plasma-discover >/dev/null || { echo "Install Discover first" >&2; exit 1; }; exec env QT_QPA_PLATFORM=xcb plasma-discover';;
  list) REMOTE='flatpak list --app --columns=application,name,version,installation';;
  update) REMOTE='sudo flatpak update --system -y';;
  launch) REMOTE="exec flatpak run --system '$APP_ID'";;
  check) REMOTE='printf "hostname: "; hostname; printf "flatpak: "; flatpak --version; command -v plasma-discover || true; printf "session display: %s\\n" "\${DISPLAY:-unset}"';;
  session) REMOTE="sudo /usr/local/sbin/flatpak4mac-session-mode '$SESSION_MODE'";;
  start|stop) REMOTE='';;
esac
# For ssh -Y, the guest DISPLAY is often localhost:10.0. Flatpak needs the
# loopback TCP socket reachable, plus the short-lived SSH xauth cookie.
# Permissions are per invocation, never persisted via 'flatpak override'.
if [[ "$ACTION" == launch && "$MODE" == macos ]]; then
  REMOTE="exec flatpak run --system --share=network --socket=x11 --filesystem=\"\$HOME/.Xauthority:ro\" --env=GDK_BACKEND=x11 --env=QT_QPA_PLATFORM=xcb '$APP_ID'"
fi
krunkit_start(){
  [[ -x "$LIMACTL" ]] || fail "Missing Lima binary $LIMACTL. Complete Phase 1."
  [[ -f "$LIMA_HOME/$KRUNKIT_VM/lima.yaml" ]] || fail "Missing Krunkit VM ($KRUNKIT_VM). Complete Phase 3."
  grep -Eq '^[[:space:]]*vmType:[[:space:]]*krunkit([[:space:]#]|$)' "$LIMA_HOME/$KRUNKIT_VM/lima.yaml" || fail 'Selected VM is not configured for Krunkit.'
  "$LIMACTL" start "$KRUNKIT_VM"
}
krunkit_ssh(){
  local config="$LIMA_HOME/$KRUNKIT_VM/ssh.config"
  [[ -s "$config" ]] || fail "Missing Lima SSH config: $config"
  ssh -F "$config" -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 "lima-$KRUNKIT_VM" "$@"
}
utm_ssh(){
  [[ -n "$UTM_SSH_HOST" && -n "$UTM_SSH_USER" ]] || fail "Configure UTM_SSH_HOST and UTM_SSH_USER in $CONFIG"
  [[ "$UTM_SSH_PORT" =~ ^[0-9]{1,5}$ ]] || fail 'Invalid UTM_SSH_PORT'
  local opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12 -o ServerAliveInterval=30 -p "$UTM_SSH_PORT")
  if [[ -n "${UTM_SSH_KEY:-}" ]]; then opts+=(-i "$UTM_SSH_KEY"); fi
  ssh "${opts[@]}" "$UTM_SSH_USER@$UTM_SSH_HOST" "$@"
}
# Prepare macOS X11 without disabling XQuartz authentication. This is used
# by the automatic preflight as well as the explicit window mode.
prepare_xquartz(){
  [[ -d /Applications/XQuartz.app || -d /Applications/Utilities/XQuartz.app || -d /opt/X11/XQuartz.app ]] || { echo 'XQuartz is not installed.' >&2; return 1; }
  [[ -x /opt/X11/bin/xauth ]] || { echo 'XQuartz xauth binary is missing.' >&2; return 1; }
  open -a XQuartz || { echo 'XQuartz could not be started.' >&2; return 1; }
  local d=""
  # launchctl provides the correct XQuartz socket when Terminal was opened
  # before XQuartz, so prefer it over a stale inherited DISPLAY.
  d="$(launchctl getenv DISPLAY 2>/dev/null || true)"
  [[ -n "$d" ]] || d="${DISPLAY:-}"
  [[ -n "$d" ]] || { echo 'macOS DISPLAY is unset; log out and back in after installing XQuartz.' >&2; return 1; }
  export DISPLAY="$d" PATH="/opt/X11/bin:$PATH" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
}
x11_ssh(){
  local guest_cmd="$1"
  if [[ "$BACKEND" == krunkit ]]; then
    local config="$LIMA_HOME/$KRUNKIT_VM/ssh.config"
    [[ -s "$config" ]] || { echo "Missing Lima SSH config: $config" >&2; return 1; }
    ssh -F "$config" -o ForwardX11=yes -o ForwardX11Trusted=yes -o XAuthLocation=/opt/X11/bin/xauth -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 "lima-$KRUNKIT_VM" "bash -lc $(printf '%q' "$guest_cmd")"
  else
    [[ -n "$UTM_SSH_HOST" && -n "$UTM_SSH_USER" ]] || { echo 'UTM SSH host/user are not configured.' >&2; return 1; }
    local opts=(-o ForwardX11=yes -o ForwardX11Trusted=yes -o XAuthLocation=/opt/X11/bin/xauth -o ExitOnForwardFailure=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=12 -p "$UTM_SSH_PORT")
    [[ -z "${UTM_SSH_KEY:-}" ]] || opts+=(-i "$UTM_SSH_KEY")
    ssh "${opts[@]}" "$UTM_SSH_USER@$UTM_SSH_HOST" "bash -lc $(printf '%q' "$guest_cmd")"
  fi
}
# Check the *real* forwarded display, not just the presence of XQuartz.app.
# This differentiates a working SSH X11 bridge from a broken/stale DISPLAY.
xquartz_usable(){
  prepare_xquartz || return 1
  x11_ssh 'test -n "$DISPLAY" && command -v xdpyinfo >/dev/null && xdpyinfo >/dev/null 2>&1'
}
macos_gui(){
  prepare_xquartz || fail 'XQuartz is unavailable. Install/configure XQuartz or choose Automatic/UTM VM display.'
  local guest_cmd
  guest_cmd="set -e; test -n \"\$DISPLAY\" && command -v xdpyinfo >/dev/null && xdpyinfo >/dev/null 2>&1 || { echo 'SSH X11 forwarding/display check failed' >&2; exit 1; }; $REMOTE"
  x11_ssh "$guest_cmd"
}
# Preflight a logged-in X11 guest desktop. The probe is synchronous, so
# Automatic never silently selects a nonexistent UTM desktop.
utm_guest_usable(){
  [[ "$BACKEND" == utm ]] || return 1
  [[ "$UTM_DISPLAY" =~ ^:[0-9]+(\.[0-9]+)?$ ]] || return 1
  local probe
  probe="export DISPLAY='$UTM_DISPLAY'; export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=\$XDG_RUNTIME_DIR/bus; command -v xset >/dev/null && xset q >/dev/null 2>&1"
  utm_ssh "bash -lc $(printf '%q' "$probe")"
}
# Existing guest X11 display; not XQuartz. A logged-in Linux session is needed.
guest_gui(){
  utm_guest_usable || fail 'No accessible UTM X11 desktop session. Log into the guest desktop first.'
  local guest_cmd
  guest_cmd="export DISPLAY='$UTM_DISPLAY'; export XDG_RUNTIME_DIR=/run/user/\$(id -u); export DBUS_SESSION_BUS_ADDRESS=unix:path=\$XDG_RUNTIME_DIR/bus; nohup bash -lc $(printf '%q' "$REMOTE") </dev/null >/tmp/flatpak-phase5-gui.log 2>&1 &"
  utm_ssh "bash -lc $(printf '%q' "$guest_cmd")"
  info 'Command submitted to the guest desktop. See /tmp/flatpak-phase5-gui.log inside the VM.'
}
# Automatic honours a saved preference when it is usable. Unavailable
# XQuartz (missing, won't start, forwarding broken) falls back to UTM's
# verified desktop. Explicit --mode macos / gpu never fall back.
resolve_auto_mode(){
  local preferred
  preferred="$(read_preference)"
  if [[ "$preferred" == gpu ]]; then
    if utm_guest_usable; then MODE=gpu; return 0; fi
    info 'Saved VM display is unavailable; trying XQuartz.'
    if xquartz_usable; then MODE=macos; return 0; fi
  else
    if xquartz_usable; then MODE=macos; return 0; fi
    info 'XQuartz is unavailable; checking for a UTM guest desktop.'
    if utm_guest_usable; then MODE=gpu; return 0; fi
  fi
  if [[ "$BACKEND" == krunkit ]]; then
    fail 'Automatic mode has no usable display: XQuartz forwarding failed and Krunkit VM desktop mode is not configured. Install/fix XQuartz or select a configured UTM backend.'
  fi
  fail 'Automatic mode has no usable display: XQuartz forwarding failed and UTM has no reachable logged-in X11 desktop. Configure either display path.'
}
case "$BACKEND:$ACTION" in
  krunkit:start) krunkit_start; exit;;
  krunkit:stop) [[ -x "$LIMACTL" ]] || fail 'Missing Lima'; "$LIMACTL" stop "$KRUNKIT_VM"; exit;;
  utm:start) open -a UTM || fail 'Install UTM.app'; osascript -e 'tell application "UTM" to start virtual machine named "Flatpak4Mac"' || warn 'Start the VM manually'; exit;;
  utm:stop) fail 'Stop the UTM VM manually inside UTM.';;
esac
if [[ "$BACKEND" == krunkit ]]; then
  krunkit_start
fi
if [[ "$ACTION" == discover || "$ACTION" == launch ]]; then
  if [[ "$MODE" == auto ]]; then resolve_auto_mode; fi
  info "Display mode for $APP_ID on $BACKEND: $MODE"
  if [[ "$MODE" == macos ]]; then
    macos_gui
  elif [[ "$BACKEND" == utm ]]; then
    guest_gui
  else
    fail 'Krunkit GPU display requires a configured guest graphical desktop; this launcher does not create one. Use --mode macos or UTM --mode gpu.'
  fi
elif [[ "$BACKEND" == krunkit ]]; then
  krunkit_ssh "bash -lc $(printf '%q' "$REMOTE")"
else
  utm_ssh "bash -lc $(printf '%q' "$REMOTE")"
fi
