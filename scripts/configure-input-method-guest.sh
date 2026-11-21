#!/usr/bin/env bash
# Flatpak4Mac guest: let the desktop session manage input methods by default.
# Avoid Ubuntu im-config launching IBus separately inside Plasma Wayland.
# Never replace a pre-existing explicit input-method choice.
set -Eeuo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Run as root' >&2; exit 1; }
getent passwd flatpak >/dev/null || { echo 'Missing flatpak user' >&2; exit 1; }

config=/home/flatpak/.xinputrc
if [[ -e "$config" || -L "$config" ]]; then
  echo 'Existing input-method preference detected; leaving it unchanged.'
  exit 0
fi

if ! command -v im-config >/dev/null 2>&1; then
  echo 'No im-config installed; default desktop input handling is already active.'
  exit 0
fi

# Only the preconfigured VM user is affected. This corresponds to im-config's
# "none: do not activate any IM from im-config and use desktop default" mode.
# No packages are uninstalled, and KDE users can later configure IBus/Fcitx5.
if ! runuser -u flatpak -- env HOME=/home/flatpak im-config -n none; then
  echo 'ERROR: Failed to select desktop-managed input handling' >&2
  exit 1
fi
if [[ ! -f "$config" ]]; then
  echo 'ERROR: im-config did not write the user preference' >&2
  exit 1
fi
echo 'Input method: desktop-managed (im-config none).'
