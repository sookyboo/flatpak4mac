#!/usr/bin/env bash
# Runs inside Ubuntu via cloud-init, and can be re-run manually after repairs.
set -Eeuo pipefail
exec > >(tee -a /var/log/flatpak4mac-provision.log) 2>&1
stamp=/var/lib/flatpak4mac/provisioned
policy_stamp=/var/lib/flatpak4mac/system-policy-v2
apply_system_policy(){
  # Flatpak4Mac manages system installations only. PackageKit's Discover backend
  # provides distro package management and is unnecessary for this purpose.
  if dpkg-query -W -f='${Status}' plasma-discover-backend-packagekit 2>/dev/null | grep -qx 'install ok installed'; then
    apt-get remove -y plasma-discover-backend-packagekit
    command -v plasma-discover >/dev/null || { echo 'Discover disappeared when removing PackageKit backend' >&2; exit 1; }
  fi
  flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # Safely remove only a duplicate, empty per-user Flathub remote. Never remove
  # existing user installations to make the system installation exclusive.
  if sudo -u flatpak flatpak --user remotes --columns=name 2>/dev/null | grep -qx flathub; then
    if [[ -z "$(sudo -u flatpak flatpak --user list --columns=application 2>/dev/null | sed '/^[[:space:]]*$/d')" ]]; then
      sudo -u flatpak flatpak --user remote-delete flathub
    else
      echo 'WARNING: user Flathub retained because user Flatpaks exist; migrate manually if desired.'
    fi
  fi
  mkdir -p /var/lib/flatpak4mac
  touch "$policy_stamp"
}
# The GSettings database can exist but contain an invalid GVDB header (as
# observed after an interrupted Ubuntu/Flatpak install). When that happens,
# unrelated user services crash and desktop startup may stall on D-Bus timeouts.
# Test lookup through the actual compiled database, not file existence or
# glib-compile-schemas --dry-run; those checks missed the corruption.
ensure_gsettings_schemas(){
  local schema_dir=/usr/share/glib-2.0/schemas
  local required_schema=org.gnome.desktop.interface
  local names
  [[ -d "$schema_dir" ]] || { echo "ERROR: Missing GSettings schema directory: $schema_dir" >&2; return 1; }
  names="$(gsettings --schemadir "$schema_dir" list-schemas 2>/dev/null || true)"
  if ! grep -Fxq "$required_schema" <<< "$names"; then
    echo 'GSettings database missing/corrupt; rebuilding compiled schemas.'
    command -v glib-compile-schemas >/dev/null || { echo 'ERROR: glib-compile-schemas unavailable' >&2; return 1; }
    glib-compile-schemas "$schema_dir"
    names="$(gsettings --schemadir "$schema_dir" list-schemas 2>/dev/null || true)"
  fi
  grep -Fxq "$required_schema" <<< "$names" || {
    echo "ERROR: GSettings schema database remains invalid at $schema_dir" >&2
    return 1
  }
  # Also confirm default lookup; this catches environment/search-path issues.
  names="$(gsettings list-schemas 2>/dev/null || true)"
  grep -Fxq "$required_schema" <<< "$names" || {
    echo 'ERROR: Default GSettings schema lookup failed; examine XDG_DATA_DIRS.' >&2
    return 1
  }
  echo 'GSettings schema database verified.'
}
# LightDM's Ubuntu unit refuses to start unless this Debian display-manager
# selection file identifies lightdm. Some cloud-image installs omit the file.
ensure_graphical_login(){
  install -d -m 755 /etc/X11
  if [[ "$(cat /etc/X11/default-display-manager 2>/dev/null || true)" != /usr/sbin/lightdm ]]; then
    printf '%s\n' /usr/sbin/lightdm > /etc/X11/default-display-manager
  fi
  # Preserve the operator-selected session. Never rewrite user-session here;
  # the session-mode helper maintains the authoritative 60-* LightDM file.
  systemctl set-default graphical.target
  # LightDM is an indirect unit; it is selected via display-manager.service.
  # Do not invoke `systemctl enable lightdm` (Ubuntu emits a static-unit warning).
  systemctl reset-failed lightdm.service || true
  systemctl start lightdm.service
  systemctl is-active --quiet lightdm.service || {
    echo 'ERROR: LightDM failed to start; inspect journalctl -u lightdm -b' >&2
    exit 1
  }
  [[ "$(systemctl get-default)" == graphical.target ]] || {
    echo 'ERROR: graphical.target was not selected' >&2
    exit 1
  }
}

if [[ -f "$stamp" ]]; then
  if command -v flatpak >/dev/null && command -v plasma-discover >/dev/null \
      && dpkg-query -W -f='${Status}' xfce4 2>/dev/null | grep -qx 'install ok installed'; then
    if [[ ! -f "$policy_stamp" ]]; then
      export DEBIAN_FRONTEND=noninteractive
      apply_system_policy
    fi
    ensure_gsettings_schemas
    ensure_graphical_login
    echo 'Already provisioned and graphical login verified.'
    exit 0
  fi
  echo 'Stale provisioning marker detected; rechecking packages.'
  rm -f "$stamp"
fi
mkdir -p /var/lib/flatpak4mac
# Must validate the entire block device before APT starts. A cloud image may
# contain a 2-3GiB root disk even when cloud-init itself works.
root_dev="$(findmnt -n -o SOURCE /)"
root_disk="$(lsblk -ndo PKNAME "$root_dev" | head -n1)"
[[ -n "$root_disk" ]] || { echo "Could not locate root disk for $root_dev" >&2; exit 1; }
dev="/dev/$root_disk"
bytes="$(blockdev --getsize64 "$dev")"
min_bytes=$((40 * 1024 * 1024 * 1024))
if (( bytes < min_bytes )); then
  echo "FATAL: root disk $dev is only $((bytes/1024/1024/1024)) GiB; expand to >=40 GiB in UTM before provisioning." >&2
  echo 'After resizing the UTM boot disk, run: sudo /usr/local/sbin/flatpak4mac-provision' >&2
  exit 1
fi
# If the root filesystem already has sufficient free space, avoid touching
# partition metadata. In particular, cloud-init may already have expanded it.
root_free="$(df -B1 --output=avail / | tail -n 1 | tr -d '[:space:]')"
min_free=$((15 * 1024 * 1024 * 1024))
if (( root_free >= min_free )); then
  echo "Root filesystem already has $((root_free/1024/1024/1024)) GiB available; no resize required."
else
  # Derive a root partition number robustly from the Linux device name,
  # falling back to sysfs/lsblk for less usual partition naming schemes.
  root_part_name="$(basename "$root_dev")"
  root_part=''
  case "$root_dev" in
    /dev/[hsv]d*[0-9]|/dev/xvd*[0-9]|/dev/vd*[0-9])
      root_part="${root_dev##*[!0-9]}" ;;
    /dev/nvme*n*p[0-9]*|/dev/mmcblk*p[0-9]*)
      root_part="${root_dev##*p}" ;;
  esac
  if [[ ! "$root_part" =~ ^[1-9][0-9]*$ ]]; then
    root_part_file="/sys/class/block/$root_part_name/partition"
    if [[ -r "$root_part_file" ]]; then
      root_part="$(tr -d '[:space:]' < "$root_part_file")"
    else
      root_part="$(lsblk -n -o PARTN "$root_dev" 2>/dev/null | head -n1 | tr -d '[:space:]')"
    fi
  fi
  [[ "$root_part" =~ ^[1-9][0-9]*$ ]] || {
    echo "Cannot determine root partition for growth: $root_dev" >&2
    exit 1
  }
  echo "Growing root partition $root_part on $dev and filesystem $root_dev"
  if ! command -v growpart >/dev/null; then
    echo 'growpart not installed; cannot expand the root partition.' >&2
    exit 1
  fi
  growpart "$dev" "$root_part" || echo 'growpart returned nonzero; checking filesystem after resize'
  resize2fs "$root_dev"
  root_free="$(df -B1 --output=avail / | tail -n 1 | tr -d '[:space:]')"
  if (( root_free < min_free )); then
    echo "FATAL: only $((root_free/1024/1024/1024)) GiB free on root after resize." >&2
    exit 1
  fi
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
# Ensure 'universe' is enabled for KDE Discover/XFCE on Ubuntu Server.
if ! apt-cache show plasma-discover-backend-flatpak >/dev/null 2>&1; then
  apt-get install -y software-properties-common
  add-apt-repository -y universe
  apt-get update
fi
apt-get install -y \
  openssh-server xauth x11-utils x11-xserver-utils x11-apps \
  xfce4 xfce4-terminal xorg lightdm dbus-x11 dbus-user-session \
  flatpak plasma-discover plasma-discover-backend-flatpak \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  spice-vdagent qemu-guest-agent mesa-utils vulkan-tools \
  libgl1-mesa-dri mesa-vulkan-drivers git curl
systemctl enable --now ssh
ensure_gsettings_schemas
ensure_graphical_login
apply_system_policy
# Independent checks. Never write a success marker based on cloud-init alone.
command -v flatpak
command -v plasma-discover
dpkg-query -W -f='${Status}' xfce4 | grep -qx 'install ok installed'
flatpak remotes --system | grep -q flathub
touch "$stamp"
echo 'SUCCESS: Flatpak4Mac provisioning complete.'
