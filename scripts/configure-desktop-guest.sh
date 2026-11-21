#!/usr/bin/env bash
# Phase 4 guest integration for Ubuntu/Debian in UTM (QEMU) or Lima/krunkit.
# No macOS package manager. Does not widen Flatpak sandbox permissions globally.
set -Eeuo pipefail
MODE="${1:-setup}"
BACKEND="${PHASE4_BACKEND:-auto}"   # utm | krunkit | auto
UTM_MOUNT="${UTM_MOUNT:-/mnt/utm}"
log(){ printf '\n==> %s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage(){ cat <<'HELP'
Usage: configure-desktop-guest.sh [setup|check|mount-utm|audio-test|grant-share APP_ID PATH]
  setup                Install Linux integration packages (repeatable; no VM config changes)
  check                Report clipboard, guest agent, sharing, audio, portals, controllers
  mount-utm            Mount configured UTM QEMU VirtFS share at /mnt/utm
  audio-test           Play a short local test tone (if audio device/session works)
  grant-share APP PATH Give ONE Flatpak app access to an EXISTING shared directory
Environment:
  PHASE4_BACKEND=utm|krunkit|auto (default auto)
  UTM_MOUNT=/mnt/utm
Requirements:
  Ubuntu/Debian VM; sudo for setup/mount. UTM sharing, SPICE clipboard, audio
  and USB options must also be enabled in UTM's VM settings. UTM QEMU sharing
  uses VirtFS/9p tag 'share', NOT the VZ/Apple VirtioFS configuration.
HELP
}
[[ "$(uname -s)" == Linux ]] || die 'Run inside a Linux VM.'
case "$MODE" in setup|check|mount-utm|audio-test|grant-share|-h|--help) ;; *) usage >&2; exit 2;; esac
case "$BACKEND" in auto|utm|krunkit) ;; *) die "Invalid PHASE4_BACKEND: $BACKEND";; esac
if [[ "$MODE" == -h || "$MODE" == --help ]]; then usage; exit 0; fi

setup(){
  command -v apt-get >/dev/null || die 'Only apt-based Ubuntu/Debian guests are supported.'
  command -v sudo >/dev/null || die 'sudo is required.'
  log 'Installing guest integration packages'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    spice-vdagent qemu-guest-agent \
    xdg-desktop-portal xdg-desktop-portal-gtk \
    pipewire pipewire-pulse wireplumber alsa-utils \
    dbus-user-session flatpak x11-utils pciutils usbutils
  # SPICE guest agent only helps where UTM provides the corresponding channel.
  # Do not force-enable pipewire or override the guest desktop's own audio setup.
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    sudo systemctl enable --now qemu-guest-agent.service 2>/dev/null || \
      warn 'qemu-guest-agent service not running (VM may lack virtio serial channel).'
    sudo systemctl enable --now spice-vdagentd.service 2>/dev/null || \
      warn 'spice-vdagentd service not running (SPICE channel may be absent).'
  fi
  log 'Package installation complete. Clipboard needs a graphical desktop session with spice-vdagent.'
  check
}

mount_utm(){
  [[ "$BACKEND" != krunkit ]] || die 'UTM VirtFS is not applicable to krunkit; use Lima mounts.'
  command -v sudo >/dev/null || die 'sudo is required.'
  sudo mkdir -p -- "$UTM_MOUNT"
  if mountpoint -q -- "$UTM_MOUNT"; then
    log "$UTM_MOUNT is already mounted"
  else
    log "Mounting UTM VirtFS share (tag: share) at $UTM_MOUNT"
    sudo mount -t 9p -o trans=virtio,version=9p2000.L share "$UTM_MOUNT" || \
      die 'Mount failed: first power off the UTM VM and enable QEMU Shared Directory → VirtFS (not SPICE WebDAV).'
  fi
  # Do not auto-add to fstab; users can opt into a persistent mount explicitly.
  ls -ld "$UTM_MOUNT"
  log 'This mount lasts until VM reboot. See script README for persistent /etc/fstab entry.'
}

check(){
  log 'Backend and graphical environment'
  printf 'Backend setting: %s\nDisplay: %s\nWayland: %s\n' "$BACKEND" "${DISPLAY:-<none>}" "${WAYLAND_DISPLAY:-<none>}"
  printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-<none>}"
  log 'SPICE / QEMU agents'
  for cmd in spice-vdagent qemu-ga; do
    if command -v "$cmd" >/dev/null 2>&1; then printf '%s: installed\n' "$cmd"; else printf '%s: missing\n' "$cmd"; fi
  done
  if pgrep -x spice-vdagent >/dev/null 2>&1; then
    printf 'SPICE session clipboard agent: running\n'
  else
    printf 'SPICE session clipboard agent: not running (requires UTM graphical desktop + SPICE channel)\n'
  fi
  log 'Shared directories'
  if mountpoint -q -- "$UTM_MOUNT"; then
    findmnt -n -o SOURCE,FSTYPE,TARGET --target "$UTM_MOUNT" || true
  else
    printf 'UTM share not mounted at %s\n' "$UTM_MOUNT"
  fi
  for path in /Users /mnt/lima-data; do
    [[ ! -d "$path" ]] || { printf 'Possible Lima mount: %s\n' "$path"; findmnt -n -o SOURCE,FSTYPE,TARGET --target "$path" || true; }
  done
  log 'Audio'
  if command -v wpctl >/dev/null 2>&1; then wpctl status 2>&1 | sed -n '1,35p' || true; fi
  if command -v aplay >/dev/null 2>&1; then aplay -l 2>&1 || true; fi
  log 'Portals'
  if command -v busctl >/dev/null 2>&1 && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    busctl --user --list 2>/dev/null | grep -E 'org.freedesktop.portal.Desktop' || \
      printf 'Portal service not currently active; launch from a full desktop session.\n'
  else
    printf 'No active user D-Bus session detected.\n'
  fi
  log 'Input devices'
  ls /dev/input/js* /dev/input/event* 2>/dev/null | sed -n '1,30p' || true
  log 'Interpretation'
  cat <<'NOTES'
- UTM: enable SPICE clipboard, QEMU sound device, VirtFS shared folder, and USB
  passthrough (for controllers) in VM settings; guest packages alone cannot do it.
- A user session must start spice-vdagent; merely installing it is insufficient.
- Krunkit: Lima mounts can share files; SPICE clipboard and UTM USB/audio settings
  do NOT automatically apply. SSH/XQuartz clipboard may support X11 text selection.
- Linux xdg-desktop-portal-gtk supplies LINUX file pickers, not native macOS dialogs.
- Flatpaks still require explicit permission to access a host shared directory.
NOTES
}

audio_test(){
  command -v speaker-test >/dev/null 2>&1 || die 'Run setup first (alsa-utils missing).'
  log 'Playing 2-second speaker test; audible sound requires configured VM audio hardware and Linux session'
  speaker-test -t sine -f 440 -c 2 -l 1 -p 1000000 || die 'Audio test failed; inspect guest device and VM sound settings.'
}

grant_share(){
  local app="${2:-}" path="${3:-}"
  [[ -n "$app" && -n "$path" ]] || die 'Usage: grant-share APP_ID /absolute/mounted/path'
  [[ "$path" == /* && -d "$path" ]] || die "Directory does not exist or is not absolute: $path"
  command -v flatpak >/dev/null || die 'Flatpak not installed.'
  flatpak info "$app" >/dev/null || die "Flatpak app not installed: $app"
  # Restrict to an exact requested path; do not grant home/all-files to every app.
  sudo flatpak override --system --filesystem="$path" "$app"
  log "Granted $app access to $path for this user. Restart the app to apply."
}
case "$MODE" in
  setup) setup;; check) check;; mount-utm) mount_utm;; audio-test) audio_test;; grant-share) grant_share "$@";;
esac
