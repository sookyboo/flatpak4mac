#!/usr/bin/env bash
# RetroDECK workflow: bootstrap VM, configure VirtFS, then ask install/launch.
# macOS Bash 3.2 compatible; no Homebrew/Python required.
set -Eeuo pipefail
F4M_QUICK_RETRODECK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$F4M_QUICK_RETRODECK_ROOT/scripts/common.sh"
need_macos
DEV_MODE=0
case "${1:-}" in
  --dev) DEV_MODE=1 ;;
  -h|--help) printf 'Usage: %s [--dev]\n' "$0"; exit 0 ;;
  '') ;;
  *) fail "Unknown argument: $1" ;;
esac
[[ $# -le 1 ]] || fail 'Too many arguments'

ask_yn() {
  local question="$1" default="$2" reply
  if [[ ! -t 0 ]]; then
    printf '%s: noninteractive default %s\n' "$question" "$default" >&2
    [[ "$default" == yes ]]
    return
  fi
  while true; do
    if [[ "$default" == yes ]]; then
      printf '%s [Y/n] ' "$question"
    else
      printf '%s [y/N] ' "$question"
    fi
    IFS= read -r reply || reply=''
    case "$reply" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      '') [[ "$default" == yes ]]; return ;;
      *) echo 'Enter yes or no.' >&2 ;;
    esac
  done
}

# Both desktop choices are host-side preferences and apply to --dev and
# normal runs. The two files survive VM rebuilding and are never silently
# overwritten.
preference_dir="$F4M_QUICK_RETRODECK_ROOT/config"
load_choice() {
  local file="$1" valid1="$2" valid2="$3" default="$4" prompt="$5" choice="" result=""
  if [[ -e "$file" ]]; then
    [[ -f "$file" && ! -L "$file" ]] || fail "Unsafe preference file: $file"
    IFS= read -r result < "$file" || true
    case "$result" in
      "$valid1"|"$valid2") printf '%s\n' "$result"; return ;;
      *) fail "Invalid preference in $file: $result (expected $valid1 or $valid2)" ;;
    esac
  fi
  if [[ -t 0 ]]; then
    # Prompt on stderr because stdout carries the selected value.
    printf '%s' "$prompt" >&2
    IFS= read -r choice </dev/tty || choice=''
  else
    printf 'Noninteractive setup: using recommended %s\n' "$default" >&2
  fi
  case "$choice" in
    ''|1) result="$default" ;;
    2) if [[ "$default" == "$valid1" ]]; then result="$valid2"; else result="$valid1"; fi ;;
    *) fail "Invalid choice: $choice. Select 1 or 2." ;;
  esac
  mkdir -p "$preference_dir"
  local temp
  temp="$(mktemp "$preference_dir/.display-choice.XXXXXX")"
  printf '%s\n' "$result" > "$temp"
  mv -f "$temp" "$file"
  printf 'Saved preference in %s: %s\n' "$file" "$result" >&2
  printf '%s\n' "$result"
}

DESKTOP_ENV="$(load_choice "$preference_dir/desktop-environment.conf" kde xfce kde \
  'Desktop environment: [1] KDE Plasma (recommended), [2] XFCE [1]: ')"
PLASMA_PROTOCOL=''
# Ask about the Plasma protocol only when KDE is chosen. Retain the saved
# preference if the user switches from XFCE to KDE later.
if [[ "$DESKTOP_ENV" == kde ]]; then
  PLASMA_PROTOCOL="$(load_choice "$preference_dir/plasma-display.conf" x11 wayland x11 \
    'KDE Plasma protocol: [1] X11 (recommended), [2] Wayland [1]: ')"
fi
log "Using desktop environment: $DESKTOP_ENV${PLASMA_PROTOCOL:+ ($PLASMA_PROTOCOL)}"

# Validate the set of bundled session scripts before doing any guest work.
F4M_SESSION_SELECTOR="$F4M_QUICK_RETRODECK_ROOT/scripts/flatpak4mac-session-mode"
F4M_SESSION_WORKER="$F4M_QUICK_RETRODECK_ROOT/scripts/flatpak4mac-session-switch-worker"
F4M_SESSION_INSTALLER="$F4M_QUICK_RETRODECK_ROOT/scripts/ensure-session-helper.sh"
for required in "$F4M_SESSION_SELECTOR" "$F4M_SESSION_WORKER" "$F4M_SESSION_INSTALLER" \
  "$F4M_QUICK_RETRODECK_ROOT/scripts/configure-retrodeck-share.sh" \
  "$F4M_QUICK_RETRODECK_ROOT/scripts/ensure-retrodeck-share.sh" \
  "$F4M_QUICK_RETRODECK_ROOT/scripts/configure-unlock-guest.sh" \
  "$F4M_QUICK_RETRODECK_ROOT/scripts/install-flatpaks.sh" \
  "$F4M_QUICK_RETRODECK_ROOT/scripts/install-retrodeck-session.sh"; do
  [[ -f "$required" && ! -L "$required" ]] || fail "Missing session component: $required; reinstall the complete Flatpak4Mac package."
  bash -n "$required" || fail "Invalid session script: $required"
done
if ! grep -Fq 'plasma-wayland' "$F4M_SESSION_SELECTOR" ||
   ! grep -Fq 'flatpak4mac-session-switch-worker' "$F4M_SESSION_SELECTOR"; then
  fail 'Incompatible session selector. Reinstall the complete Flatpak4Mac package.'
fi
if (( DEV_MODE )); then
  [[ -f "$F4M_QUICK_RETRODECK_ROOT/scripts/install-dev-environment.sh" && ! -L "$F4M_QUICK_RETRODECK_ROOT/scripts/install-dev-environment.sh" ]] || fail 'Missing development installer.'
  bash -n "$F4M_QUICK_RETRODECK_ROOT/scripts/install-dev-environment.sh" || fail 'Invalid development installer.'
fi

# Important: bring up Ubuntu and configure/mount the UTM host share BEFORE
# presenting the RetroDECK installation question. Even if installation is
# declined, the share remains useful for KDE/other development workflows.
# Bundle installation is a separate, explicit action after the user's choice.
log 'Preparing Ubuntu guest and the RetroDECK VirtFS share before installation choices.'
"$F4M_QUICK_RETRODECK_ROOT/quick-start.sh"
# Reload refreshed guest address after Quick Start.
source "$F4M_QUICK_RETRODECK_ROOT/scripts/common.sh"
validate_guest_env
"$F4M_QUICK_RETRODECK_ROOT/scripts/configure-retrodeck-share.sh"
"$F4M_QUICK_RETRODECK_ROOT/scripts/ensure-retrodeck-share.sh"
log 'RetroDECK share is ready at /home/flatpak/retrodeck (also available in KDE).'

# Configure local login once, before any desktop is activated. Re-running is
# safe: an existing password is never reset, and desktop settings stay unlocked.
log 'Ensuring flatpak initial password and disabling idle desktop locking.'
scp -q -i "$F4M_KEY" -P "$F4M_PORT" -o BatchMode=yes \
  -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  "$F4M_QUICK_RETRODECK_ROOT/scripts/configure-unlock-guest.sh" \
  "flatpak@$F4M_HOST:/tmp/flatpak4mac-configure-unlock-guest.sh"
ssh_guest 'sudo install -m 755 /tmp/flatpak4mac-configure-unlock-guest.sh /usr/local/sbin/flatpak4mac-configure-unlock && sudo /usr/local/sbin/flatpak4mac-configure-unlock && rm -f /tmp/flatpak4mac-configure-unlock-guest.sh'

# Respect the input method configured by the OS or by the desktop session.
# Do not run `im-config -n none` during provisioning: it writes ~/.xinputrc,
# alters existing users' sessions, and is not necessary for ordinary Wayland
# keyboard input. Users can opt into IBus/Fcitx5 in their desktop settings.
# In particular, this script must never rewrite an existing ~/.xinputrc.

# Development mode always starts the selected desktop and never installs or
# launches RetroDECK. The VirtFS share is prepared above for both modes.
# Only normal mode prompts for the RetroDECK installation/launch choices.
INSTALL_RETRO=0
LAUNCH_RETRO=0
if (( DEV_MODE )); then
  log 'Development mode: skipping all autoinstall bundles and RetroDECK launch (VirtFS share remains mounted).'
else
  if ask_yn 'Install RetroDECK (or retain an existing installation)?' yes; then INSTALL_RETRO=1; fi
  if ask_yn 'Launch RetroDECK when setup finishes?' yes; then LAUNCH_RETRO=1; fi
fi

if (( INSTALL_RETRO )); then
  # VM and SSH are already provisioned; avoid repeating the bootstrap flow.
  "$F4M_QUICK_RETRODECK_ROOT/scripts/install-flatpaks.sh"
fi

# The chosen desktop is independent of the developer packages.
# KDE must be available on both normal and --dev runs when preferred.
if (( DEV_MODE )); then
  "$F4M_QUICK_RETRODECK_ROOT/scripts/install-dev-environment.sh"
fi
if [[ "$DESKTOP_ENV" == kde ]]; then
  log 'Ensuring KDE Plasma X11, Wayland, XWayland, window manager and System Settings are installed.'
  ssh_guest 'sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y kde-plasma-desktop plasma-workspace plasma-workspace-wayland kwin-x11 xwayland systemsettings'
fi

INSTALLED_RETRO=0
if ssh_guest 'flatpak info --system net.retrodeck.retrodeck >/dev/null 2>&1'; then
  INSTALLED_RETRO=1
fi

if (( INSTALL_RETRO && ! INSTALLED_RETRO )); then
  guestarch="$(ssh_guest 'flatpak --default-arch' | tr -d '\r\n')"
  if [[ "$guestarch" == aarch64 ]]; then
    fail 'RetroDECK is not installed. Put an ARM64 bundle in autoinstall/ and rerun; check earlier autoinstall errors.'
  fi
  ssh_guest 'sudo flatpak install --system -y --noninteractive flathub net.retrodeck.retrodeck'
  INSTALLED_RETRO=1
fi

# A session entry is relevant only for installed RetroDECK. The share itself
# is deliberately independent and has already been mounted above.
if (( INSTALLED_RETRO && ! DEV_MODE )); then
  "$F4M_QUICK_RETRODECK_ROOT/scripts/install-retrodeck-session.sh"
fi

if (( LAUNCH_RETRO )) || [[ "$DESKTOP_ENV" == kde || "$DESKTOP_ENV" == xfce ]]; then
  # Install/update the session selector even if RetroDECK wasn't installed:
  # otherwise a clean --dev setup cannot switch to KDE.
  if [[ -x "$F4M_QUICK_RETRODECK_ROOT/scripts/ensure-session-helper.sh" ]]; then
    "$F4M_QUICK_RETRODECK_ROOT/scripts/ensure-session-helper.sh"
  else
    fail 'Missing scripts/ensure-session-helper.sh from the Flatpak4Mac project; update the project files.'
  fi
fi

if (( LAUNCH_RETRO )); then
  (( INSTALLED_RETRO )) || fail 'RetroDECK launch requested but no installation is present. Enable installation or supply an existing bundle.'
  log 'Switching LightDM to dedicated RetroDECK session.'
  ssh_guest 'sudo /usr/local/sbin/flatpak4mac-session-mode retrodeck'
elif [[ "$DESKTOP_ENV" == kde ]]; then
  log "Switching LightDM to KDE Plasma ($PLASMA_PROTOCOL)."
  if [[ "$PLASMA_PROTOCOL" == wayland ]]; then
    ssh_guest 'sudo /usr/local/sbin/flatpak4mac-session-mode plasma-wayland'
  else
    ssh_guest 'sudo /usr/local/sbin/flatpak4mac-session-mode plasma-x11'
  fi
else
  log 'Switching LightDM to XFCE desktop.'
  ssh_guest 'sudo /usr/local/sbin/flatpak4mac-session-mode xfce'
fi
log 'Quick RetroDECK setup finished.'
