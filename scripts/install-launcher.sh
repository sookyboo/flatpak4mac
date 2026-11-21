#!/bin/bash
# Phase 5: build a native AppleScript .app wrapper for Flatpak VM management.
# No Homebrew, no system-directory changes, no automatic overwrite of unrelated apps.
set -Eeuo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Run this installer on macOS.' >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || { echo 'Do not run as root.' >&2; exit 1; }
for program in osacompile ditto mktemp; do command -v "$program" >/dev/null || { echo "Missing $program" >&2; exit 1; }; done
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOST_SCRIPT="$SOURCE_DIR/../launcher/flatpak4mac-host.sh"
APPLESCRIPT="$SOURCE_DIR/../launcher/FlatpakManager.applescript"
[[ -r "$HOST_SCRIPT" && -r "$APPLESCRIPT" ]] || { echo 'Keep all Phase 5 files together.' >&2; exit 1; }
DEST_DIR="${PHASE5_APP_DIR:-$HOME/Applications}"
DEST="$DEST_DIR/Flatpak Manager.app"
MARKER="$DEST/Contents/Resources/.flatpak-macos-phase5"
mkdir -p "$DEST_DIR"
if [[ -e "$DEST" && ! -f "$MARKER" ]]; then
  echo "Refusing to replace unmanaged app: $DEST" >&2
  exit 1
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp/}flatpak-phase5.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
osacompile -o "$TMP/Flatpak Manager.app" "$APPLESCRIPT"
RES="$TMP/Flatpak Manager.app/Contents/Resources"
mkdir -p "$RES"
cp "$HOST_SCRIPT" "$RES/flatpak4mac-host.sh"
chmod 755 "$RES/flatpak4mac-host.sh"
: > "$RES/.flatpak-macos-phase5"
# Replace only an app from an earlier run of this installer.
if [[ -d "$DEST" ]]; then
  OLD="$TMP/previous.app"
  mv "$DEST" "$OLD"
  if ! ditto "$TMP/Flatpak Manager.app" "$DEST"; then
    rm -rf "$DEST"
    mv "$OLD" "$DEST"
    echo 'Installation failed, previous app restored.' >&2
    exit 1
  fi
else
  ditto "$TMP/Flatpak Manager.app" "$DEST"
fi
CONFIG_DIR="$(cd "$SOURCE_DIR/.." && pwd -P)/config"
mkdir -p "$CONFIG_DIR"
EXAMPLE="$CONFIG_DIR/phase5.env.example"
if [[ ! -e "$EXAMPLE" ]]; then
  cat > "$EXAMPLE" <<'CONFIG'
# Copy to phase5.env and edit if you use UTM.
# The UTM guest must have OpenSSH server installed and accessible from macOS.
UTM_SSH_HOST=192.168.64.2
UTM_SSH_PORT=22
UTM_SSH_USER=flatpak
# Optional SSH private key (leave unset for SSH agent/standard keys):
# UTM_SSH_KEY=/Users/you/.ssh/id_ed25519
# Optional: set if your guest desktop uses a different X11 display:
UTM_DISPLAY=:0
# For the Lima/krunkit backend:
KRUNKIT_VM=flatpak-gpu-krunkit
LIMA_VERSION=2.3.0
CONFIG
fi
printf 'Installed: %s\n' "$DEST"
printf 'UTM settings example: %s\n' "$EXAMPLE"
printf 'Open with: open %q\n' "$DEST"
