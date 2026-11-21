#!/bin/bash
# Prepare a bootable Ubuntu 24.04 cloud image and cloud-init seed for UTM.
# Requires macOS, curl, hdiutil, shasum, ssh-keygen. Does not require Homebrew.
set -euo pipefail
umask 077

if [[ "$(uname -s)" != Darwin ]]; then echo 'ERROR: Run on macOS.' >&2; exit 1; fi
for cmd in curl hdiutil shasum ssh-keygen awk; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done

case "$(uname -m)" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) echo 'Unsupported Mac CPU' >&2; exit 1 ;;
esac
RELEASE="${UBUNTU_IMAGE_RELEASE:-current}"
BASE="https://cloud-images.ubuntu.com/noble/${RELEASE}"
FILE="noble-server-cloudimg-${ARCH}.img"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DIR="${F4M_IMAGE_DIR:-$ROOT/vm/ubuntu-24.04}"
mkdir -p "$DIR/seed-files"
DIR="$(cd "$DIR" && pwd)"
IMAGE="$DIR/$FILE"
SEED="$DIR/flatpak-seed.iso"
KEY="$DIR/flatpak-utm-ed25519"

# Keep a persistent dedicated key; do not replace it on reruns.
if [[ ! -f "$KEY" ]]; then
  if [[ -e "${KEY}.pub" ]]; then echo 'Orphaned public key; refusing replacement' >&2; exit 1; fi
  ssh-keygen -q -t ed25519 -N '' -C 'flatpak-utm' -f "$KEY"
fi
PUBKEY="$(cat "${KEY}.pub")"
case "$PUBKEY" in ssh-ed25519\ *) ;; *) echo 'Unexpected SSH public key format' >&2; exit 1 ;; esac

# A pristine checksum-verified image can be retained separately from the VM disk.
# Never resize or mutate the cached image: only the working VM disk is imported into UTM.
CACHE_DIR="$ROOT/cache/ubuntu-24.04"
CHOICE_FILE="$ROOT/config/image-cache.conf"
mkdir -p "$ROOT/config"
if [[ -f "$CHOICE_FILE" ]]; then
  case "$(cat "$CHOICE_FILE")" in yes|no) CACHE_CHOICE="$(cat "$CHOICE_FILE")";;
    *) echo "Invalid cache preference: $CHOICE_FILE" >&2; exit 1;; esac
else
  CACHE_CHOICE=yes
  if [[ -t 0 ]]; then
    printf 'Keep a reusable pristine Ubuntu cloud-image cache? [Y/n] '
    read -r cache_answer || cache_answer=''
    case "$cache_answer" in ''|y|Y|yes|YES|Yes) CACHE_CHOICE=yes;; n|N|no|NO|No) CACHE_CHOICE=no;;
      *) echo 'Please answer yes or no; no files downloaded.' >&2; exit 1;; esac
  else
    echo 'Non-interactive mode: enabling cloud-image cache (default yes).'
  fi
  printf '%s\n' "$CACHE_CHOICE" > "$CHOICE_FILE"
fi

# The checksum document is pinned in the VM directory. A cached copy is also retained
# for a subsequent fresh VM (and can be used without downloading checksums again).
if [[ ! -f "$DIR/SHA256SUMS" ]]; then
  if [[ "$CACHE_CHOICE" == yes && -f "$CACHE_DIR/SHA256SUMS" ]]; then
    cp "$CACHE_DIR/SHA256SUMS" "$DIR/SHA256SUMS"
  else
    curl --fail --location --retry 3 --connect-timeout 20 \
      "$BASE/SHA256SUMS" -o "$DIR/SHA256SUMS.tmp"
    mv "$DIR/SHA256SUMS.tmp" "$DIR/SHA256SUMS"
  fi
fi
EXPECTED="$(awk -v f="$FILE" '$2 == "*" f || $2 == f {print $1}' "$DIR/SHA256SUMS")"
if [[ ! "$EXPECTED" =~ ^[0-9a-f]{64}$ ]]; then echo 'Image checksum entry missing' >&2; exit 1; fi
verify_image(){ [[ -f "$1" ]] && [[ "$(shasum -a 256 "$1" | awk '{print $1}')" == "$EXPECTED" ]]; }

if [[ "$CACHE_CHOICE" == yes ]]; then
  mkdir -p "$CACHE_DIR"
  if ! verify_image "$CACHE_DIR/$FILE"; then
    if [[ -e "$CACHE_DIR/$FILE" ]]; then
      echo "Existing cached image checksum mismatch; refusing to overwrite: $CACHE_DIR/$FILE" >&2
      exit 1
    fi
    # Reuse a pristine working image only if its checksum matches; it may have
    # already been imported/resized, in which case it must NOT seed the cache.
    if verify_image "$IMAGE"; then
      cp "$IMAGE" "$CACHE_DIR/$FILE.part"
    else
      echo "Downloading pristine Ubuntu cloud image into cache: $FILE"
      curl --fail --location --retry 3 --connect-timeout 20 \
        "$BASE/$FILE" -o "$CACHE_DIR/$FILE.part"
    fi
    verify_image "$CACHE_DIR/$FILE.part" || { rm -f "$CACHE_DIR/$FILE.part"; echo 'Cached image checksum mismatch' >&2; exit 1; }
    mv "$CACHE_DIR/$FILE.part" "$CACHE_DIR/$FILE"
  fi
  if [[ ! -e "$CACHE_DIR/SHA256SUMS" ]]; then cp "$DIR/SHA256SUMS" "$CACHE_DIR/SHA256SUMS"; fi
  if [[ ! -e "$IMAGE" ]]; then
    echo 'Creating a separate working copy from the verified cached image...'
    cp "$CACHE_DIR/$FILE" "$IMAGE.part"
    verify_image "$IMAGE.part" || { rm -f "$IMAGE.part"; echo 'Working copy verification failed' >&2; exit 1; }
    mv "$IMAGE.part" "$IMAGE"
  fi
else
  # No cache requested: download directly into the working VM directory.
  if [[ ! -f "$IMAGE" ]]; then
    echo "Downloading Ubuntu cloud image directly for the VM: $FILE"
    curl --fail --location --retry 3 --connect-timeout 20 \
      "$BASE/$FILE" -o "$IMAGE.part"
    verify_image "$IMAGE.part" || { rm -f "$IMAGE.part"; echo 'Image checksum mismatch' >&2; exit 1; }
    mv "$IMAGE.part" "$IMAGE"
  fi
fi
[[ -f "$IMAGE" ]] || { echo 'Working Ubuntu image missing' >&2; exit 1; }
printf 'Ubuntu VM image ready: %s\n' "$IMAGE"
printf 'Reusable cloud-image cache: %s\n' "$CACHE_CHOICE"

# Cloud-init creates the user/SSH key and installs an asynchronous systemd unit.
# Package installation runs after cloud-final.service rather than blocking cloud-init.
# SSH is key-based only; a locally accessible desktop is set to autologin.
cat > "$DIR/seed-files/meta-data" <<'EOF'
instance-id: flatpak-utm-ubuntu-2404-v1
local-hostname: flatpak-utm
EOF
cat > "$DIR/seed-files/user-data" <<EOF
#cloud-config
hostname: flatpak-utm
manage_etc_hosts: true
users:
  - name: flatpak
    gecos: Flatpak User
    groups: [adm, sudo, audio, video, render]
    shell: /bin/bash
    lock_passwd: true
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ${PUBKEY}
ssh_pwauth: false
package_update: false
package_upgrade: false
write_files:
  - path: /etc/lightdm/lightdm.conf.d/60-flatpak-autologin.conf
    permissions: '0644'
    content: |
      [Seat:*]
      autologin-user=flatpak
      autologin-user-timeout=0
      user-session=xfce
  - path: /usr/local/sbin/flatpak4mac-provision
    owner: root:root
    permissions: '0755'
    content: |
$(sed 's/^/      /' "$ROOT/scripts/provision-ubuntu-guest.sh")
  - path: /etc/systemd/system/flatpak4mac-provision.service
    owner: root:root
    permissions: '0644'
    content: |
$(sed 's/^/      /' "$ROOT/scripts/flatpak4mac-provision.service")
runcmd:
  - [ systemctl, enable, --now, ssh ]
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, flatpak4mac-provision.service ]
  - [ systemctl, start, --no-block, flatpak4mac-provision.service ]
final_message: 'SSH ready; Flatpak4Mac provisioning queued in systemd. Run systemctl status flatpak4mac-provision.service.'
EOF
# Make sure stale seed files don't survive a rerun.
cat > "$DIR/seed-files/network-config" <<'EOF'
version: 2
ethernets:
  default:
    match:
      name: "e*"
    dhcp4: true
EOF
# The seed used by a VM must never be silently replaced on a rerun.
# hdiutil includes metadata that can vary between builds, so compare source data,
# not the ISO's final byte digest.
seed_fingerprint="$DIR/.seed-config.sha256"
seed_digest="$(cat "$DIR/seed-files/user-data" "$DIR/seed-files/meta-data" "$DIR/seed-files/network-config" | shasum -a 256 | awk '{print $1}')"
if [[ -f "$SEED" ]]; then
  [[ -f "$seed_fingerprint" ]] || { echo 'Existing seed has no fingerprint; refusing to overwrite it. Review the VM/seed manually.' >&2; exit 1; }
  if [[ "$(cat "$seed_fingerprint")" != "$seed_digest" ]]; then
    echo 'NOTICE: Existing seed uses an older configuration. Preserving it for the existing VM.'
    echo 'Quick Start will install/update the provisioning service over SSH once connected.'
    echo 'For a NEW VM, use a fresh image directory so the updated seed is generated.'
  fi
else
  hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata \
    -o "$SEED" "$DIR/seed-files"
  printf '%s\n' "$seed_digest" > "$seed_fingerprint"
fi

cat <<EOF

Prepared:
  Ubuntu QCOW2: $IMAGE
  Cloud-init seed: $SEED
  SSH private key: $KEY

UTM (QEMU backend, NOT Apple Virtualization):
  1. Create an Ubuntu/Linux QEMU VM with UEFI firmware and $ARCH CPU.
  2. Import the QCOW2 file as its main VirtIO disk.
  3. Before first boot, enlarge the imported boot disk to at least 64 GiB in UTM.
  4. Attach flatpak-seed.iso as a separate non-removable VirtIO disk (NOT a CD-ROM).
  5. Use VirtIO GPU (GPU Supported), enabled acceleration and shared network.
  6. Boot with both disks attached. SSH starts first; a systemd service then installs packages.
  7. After provisioning completes, reboot to enter XFCE automatically.

Security: the local desktop automatically logs in as 'flatpak'; SSH requires
its generated key. Never publish or share the SSH private key or seed ISO.
The VM user has passwordless sudo (development VM only).

In the Linux guest, confirm setup with:
  cloud-init status --wait
  flatpak remotes
  systemctl status flatpak4mac-provision.service --no-pager
  test -f /var/lib/flatpak4mac/provisioned && echo READY
  glxinfo -B

If using SSH, configure UTM host port forwarding (e.g. 2222 to guest 22) and run:
  ssh -i '$KEY' -p 2222 flatpak@127.0.0.1
EOF
