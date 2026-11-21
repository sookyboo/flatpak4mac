#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
resolve_utm
[[ -n "$UTM_APP" ]] || fail 'Install UTM first.'
IMAGE_ARCH="$(uname -m)"; [[ "$IMAGE_ARCH" == arm64 ]] && DISK_ARCH=arm64 || DISK_ARCH=amd64
IMAGE="$F4M_IMAGE_DIR/noble-server-cloudimg-$DISK_ARCH.img"
SEED="$F4M_IMAGE_DIR/flatpak-seed.iso"
[[ -f "$IMAGE" && -f "$SEED" ]] || fail 'Run prepare-ubuntu-image.sh first.'
# UTM AppleScript scripting suite supports VM creation, disk sources, and display.
# A failed API invocation falls back to the official wizard; existing VMs are never changed.
status="$(osascript - "$F4M_VM_NAME" <<'APPLESCRIPT'
on run argv
  tell application "UTM"
    try
      set vm to virtual machine named (item 1 of argv)
      return "exists"
    on error
      return "missing"
    end try
  end tell
end run
APPLESCRIPT
)"
if [[ "$status" == exists ]]; then
  [[ -f "$F4M_IMAGE_DIR/.vm-created-by-v2" ]] || fail "An older/unmanaged UTM VM named '$F4M_VM_NAME' already exists. Shut it down and delete ONLY that VM through UTM (if disposable), or set a different F4M_VM_NAME, then rerun. Your Mac retrodeck/ folder is untouched."
  log "Reusing existing VM $F4M_VM_NAME"
  exit 0
fi
printf 'Create UTM VM "%s" using documented UTM AppleScript interface? [Y/n] ' "$F4M_VM_NAME"
read -r answer
[[ "$answer" =~ ^([nN]|[nN][oO])$ ]] && { echo 'Create the VM in UTM manually; see docs/INSTALL.md.'; exit 4; }
if [[ "$IMAGE_ARCH" == arm64 ]]; then QEMU_ARCH=aarch64; else QEMU_ARCH=x86_64; fi
if created_uuid="$(osascript - "$F4M_VM_NAME" "$QEMU_ARCH" "$IMAGE" "$SEED" <<'APPLESCRIPT'
on run argv
  set vmName to item 1 of argv
  set archName to item 2 of argv
  set diskImage to POSIX file (item 3 of argv)
  set seedImage to POSIX file (item 4 of argv)
  tell application "UTM"
    set vm to make new virtual machine with properties {backend:qemu, configuration:{name:vmName, architecture:archName, uefi:true, hypervisor:true, memory:4096, cpu cores:4, drives:{{source:diskImage, interface:VirtIO}, {removable:false, source:seedImage, interface:VirtIO}}, displays:{{hardware:"virtio-gpu-gl-pci"}}}}
    return id of vm
  end tell
end run
APPLESCRIPT
)"; then
  [[ "$created_uuid" =~ ^[0-9A-Fa-f-]{36}$ ]] || fail "UTM returned unexpected UUID: $created_uuid"
  log 'UTM VM created; DO NOT BOOT until resizing the Ubuntu boot disk.'
  printf '%s\n' "$created_uuid" > "$F4M_IMAGE_DIR/.vm-created-by-v2"
  touch "$F4M_IMAGE_DIR/.requires-first-boot-review"
  cat <<EOF

ACTION REQUIRED BEFORE BOOT:
  - UTM > Flatpak4Mac > Edit > Drives > Ubuntu boot disk > Resize to ${F4M_DISK_GB} GiB (>=40 GiB).
  - Confirm the separate flatpak-seed.iso is a non-removable VirtIO disk, NOT CD-ROM.
  - Display: VirtIO GPU (GPU Supported); Preferences: Apple Core OpenGL.
  - Save settings, then rerun ./quick-start.sh to confirm these changes.
EOF
else
  warn 'Automated VM creation was not accepted by this UTM version. Create it manually with the prepared image and seed ISO (docs/INSTALL.md).'
  exit 4
fi
