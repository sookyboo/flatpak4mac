#!/usr/bin/env bash
# Ubuntu 24.04 ARM64 dev profile. No removal of XFCE / RetroDECK packages.
set -Eeuo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Run as root' >&2; exit 1; }
[[ "$(dpkg --print-architecture)" == arm64 ]] || { echo 'Dev profile requires ARM64 Ubuntu' >&2; exit 1; }
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || { echo 'Expected Ubuntu 24.04' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
available_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
if (( available_kb < 6 * 1024 * 1024 )); then
  echo 'ERROR: Development profile needs at least 6 GiB free inside Ubuntu (and adequate free space on macOS for QCOW2 growth).' >&2
  exit 1
fi
apt-get update
# Ubuntu 24.04 ships SDL2 proper, not SDL3-backed sdl2-compat.
# Chromium is handled as a Flatpak (Ubuntu chromium-browser is a Snap bootstrap).
packages=(
  kde-plasma-desktop plasma-workspace konsole yakuake kate jq
  build-essential pkg-config libsdl2-dev ffmpeg libavcodec-dev libavformat-dev
  libavutil-dev libswscale-dev git
  krusader qdirstat filelight mc
  ark 7zip unzip zip kio-extras
  kde-spectacle
  plasma-discover plasma-discover-backend-flatpak flatpak flatpak-builder
  podman crun
  vulkan-tools mesa-utils
  curl libfuse2t64 ca-certificates
)
# Fail visibly if a mandatory package is unavailable; don't silently skip tools.
for package in "${packages[@]}"; do
  if ! apt-cache show "$package" >/dev/null 2>&1; then
    echo "ERROR: Required Ubuntu package not available: $package" >&2
    exit 1
  fi
done
apt-get install -y --no-install-recommends "${packages[@]}"
# Do not replace LightDM with SDDM when adding Plasma to an existing guest.
# Official SourceGit and GitHub CLI are installed by install-git-tools-guest.sh.
# Browser: official Ubuntu 'chromium-browser' is a Snap bootstrap. Offer the
# sandboxed Flatpak instead, but do not fail dev setup if ARM64 isn't published.
if ! flatpak info --system org.chromium.Chromium >/dev/null 2>&1; then
  if ! flatpak install --system -y --noninteractive flathub org.chromium.Chromium; then
    echo 'WARNING: Chromium Flatpak unavailable for this architecture/remote; install separately.' >&2
  fi
fi
# Verify GSettings after package installation. Recover broken schema caches
# so desktop services can start reliably.
if ! gsettings list-schemas 2>/dev/null | grep -Fxq org.gnome.desktop.interface; then
  glib-compile-schemas /usr/share/glib-2.0/schemas
fi
# Detect X11 Plasma desktop entry on Ubuntu noble (not Wayland for LightDM).
if [[ ! -f /usr/share/xsessions/plasma.desktop ]]; then
  echo 'WARNING: Plasma X11 session entry missing; check plasma-workspace package.' >&2
fi
mkdir -p /var/lib/flatpak4mac
touch /var/lib/flatpak4mac/dev-installed
printf 'Development profile ready. Plasma session is available via the Flatpak4Mac session switcher.\n'
