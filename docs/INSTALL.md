# Installing Flatpak4Mac (Ubuntu 24.04 ARM64)

> **Experimental / not yet fully tested:** Do not store anything important only
> inside a Flatpak4Mac VM. Keep independent backups outside the VM before
> installing, developing, resetting or testing applications. Rebuilding a VM
> can permanently erase its virtual disk.

## Fresh installation

1. On an Apple Silicon Mac, install UTM or let Quick Start assist with its installation.
2. Extract the project to `~/flatpak4mac/`, with `quick-start.sh` directly
   inside that directory (not nested inside a second `flatpak4mac/`).
3. Open Terminal and run `cd ~/flatpak4mac && ./quick-start.sh` to prepare a
   general Flatpak VM, or `./quick-retrodeck.sh` for shared-folder and
   RetroDECK integration.
4. Before the first VM boot, complete the UTM drive and display checks below.

**Recommended:** Select KDE Plasma **X11** if running Quick RetroDECK. On the
tested UTM VirGL setup, X11 applications including `xeyes` and SourceGit showed
black windows under Plasma Wayland/XWayland. This needs further investigation.
The scripts do not install XQuartz.

Quick Start provisions the VM without automatically installing local bundles.
To install files in `autoinstall/` explicitly, use `./quick-start.sh --install-bundles`.
Quick RetroDECK runs Quick Start for provisioning, prepares VirtFS sharing, and
then invokes the bundle installer only if installation was accepted. If a VM
restart is required to enable sharing, the setup helper reruns Quick Start to
rediscover SSH safely; it does not install bundles again.

## First-time UTM configuration (required)

Quick Start downloads/checksums the Ubuntu cloud image and generates a NoCloud `cidata` ISO and SSH key. UTM VM creation is best effort. If auto-creation succeeds, **DO NOT BOOT yet**:

- In UTM **Edit > Drives > Ubuntu boot disk**, use **Resize** to grow the **primary virtual disk** to **64 GiB** (at least **40 GiB**). This is not the seed disk or an extra disk. The Ubuntu cloud image starts with ~2.4 GiB root capacity, too small for the desktop.
- Attach `vm/ubuntu-24.04/flatpak-seed.iso` as a **separate non-removable VirtIO disk** rather than an IDE or VirtIO CD-ROM. ARM64 UTM's CD-ROM options can fail. `cidata` should become `/dev/vdb`.
- Choose QEMU backend, ARM64 on Apple Silicon, Shared Network, UEFI, VirtIO GPU (GPU Supported), and UTM Preferences > macOS > QEMU Graphics Acceleration > **Apple Core OpenGL**.
- Save settings and rerun Quick Start. When it asks, enter `RESIZED` **only after making those changes**. It will then start the VM.

If you need to create the VM manually: import `vm/ubuntu-24.04/noble-server-cloudimg-arm64.img` as main disk, enlarge it, attach the ISO as non-removable VirtIO disk, then start. If Cloud-init was already attempted with a too-small disk, the guest provisioner can be rerun manually after disk expansion.

## Provisioning and SSH

The seed creates the `flatpak` account with SSH-key authentication and initially
no usable local password. Quick RetroDECK later sets an initial local password
(`flatpak`) only if the account has no usable password; it preserves any
existing password. The base guest installs XFCE, Discover, Flatpak and graphics
tools **only after** verifying the root disk has sufficient capacity. The
success marker is `/var/lib/flatpak4mac/provisioned` and is written only after
package setup succeeds. This is a development VM, not a hardened production host.

If automatic IP detection fails (QEMU guest agent is not yet installed), Quick Start will ask for the guest IP. Find it using `hostname -I` in Ubuntu or `arp -an -i bridge100` on macOS, matching the UTM network MAC. On successful SSH the script writes `~/flatpak4mac/config/phase5.env`.

Diagnostics in the guest:

```sh
sudo cat /var/log/flatpak4mac-provision.log
cloud-init status --long
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
df -h /
test -f /var/lib/flatpak4mac/provisioned && echo READY
```

If provisioning failed due to small disk, power off VM, resize *existing boot disk* in UTM, reboot and run:

```sh
sudo /usr/local/sbin/flatpak4mac-provision
```

Then rerun `./quick-start.sh` on macOS. Provisioning verifies its current
completion marker and required services before reporting success.

## RetroDECK

Place a native ARM64 RetroDECK `.flatpak` in `autoinstall/`, then run
`./quick-retrodeck.sh`. It calls Quick Start, checks the UTM VirtFS share,
and asks separately whether to install/retain RetroDECK and whether to launch
it (both choices default to Yes). When launch is declined it selects the
chosen desktop, KDE Plasma X11 by default. Only the top-level `retrodeck/`
directory is created on macOS; it is mounted at `/home/flatpak/retrodeck` in
Ubuntu. RetroDECK creates its own subdirectories. See [RetroDECK](RETRODECK.md)
for the current **hard-coded `arm-0.11.0` launch branch limitation**.

**Preservation:** The reset only concerns the old disposable VM and generated Ubuntu resources. Do not remove existing RetroDECK data or autoinstall bundles.


## SSH-first provisioning

Cloud-init only configures the `flatpak` user, SSH key, LightDM autologin file, and
queues `flatpak4mac-provision.service`. The systemd service starts **after**
`cloud-final.service` and independently installs XFCE, Flatpak, Discover and drivers.
`SSH_READY` means the guest can be accessed; `PROVISIONED` requires the service
success marker at `/var/lib/flatpak4mac/provisioned`.

Quick Start takes a baseline of `arp -an -i bridge100` **before** starting the VM.
After startup it tries the UTM guest agent, finds entries matching the VM MAC,
then checks newly appeared ARP entries. Candidates must authenticate using the
project-specific SSH key and report `flatpak:flatpak-utm`; ARP alone is never proof.
Previously configured IPs are rechecked on every run. This uses macOS Shared
Network and does not need the router's DHCP leases.

Monitor provisioning over SSH:

```sh
sudo systemctl status flatpak4mac-provision.service --no-pager
sudo journalctl -u flatpak4mac-provision.service -f
sudo tail -f /var/log/flatpak4mac-provision.log
```

On reruns, the host can refresh the provisioning script and systemd unit after
SSH becomes available without replacing the seed attached to an existing VM.
The service waits for `cloud-final.service` to finish. These checks help recover
an interrupted installation without automatically recreating the guest.

If the service fails, inspect the logs and retry with:

```sh
sudo systemctl reset-failed flatpak4mac-provision.service
sudo systemctl restart flatpak4mac-provision.service
```

The latest seed is used when preparing a **fresh** image directory. Do not remove
an existing seed while a VM still depends on it.

## Configuration and removal

Launcher and SSH preferences live in `~/flatpak4mac/config/`. To uninstall
while preserving ROMs and saves in `retrodeck/`, run `./uninstall.sh` and
follow the confirmation prompt. See `docs/UNINSTALL.md`.

### Root partition validation and recovery

Provisioning validates that the boot disk is large enough before installing
packages. If filesystem growth is needed, it detects the root partition on
VirtIO (`/dev/vda1`), NVMe and MMC devices, then checks the available space.
With at least 15 GiB free, it does not alter partition metadata. A failed
provisioning service can be retried with `./quick-start.sh`; to diagnose it,
inspect `lsblk` and
`sudo journalctl -u flatpak4mac-provision.service -n 100 --no-pager` in the guest.

## Downloaded Ubuntu image cache

On the first fresh run, `quick-start.sh` / `quick-retrodeck.sh` asks whether to keep
an Ubuntu cloud-image cache (**default yes**). With caching enabled, a checksum-
verified pristine image is stored at `cache/ubuntu-24.04/` and a **separate copy**
is made at `vm/ubuntu-24.04/` for UTM. UTM disk resizing and guest writes must
never touch the cached copy. With caching disabled, only the VM working image
is downloaded. The choice is retained in `config/image-cache.conf` for reruns.
The cache is reused for future clean VM creation, so long as its checksum matches
its stored checksum manifest. `current` Ubuntu images can change over time;
remove an old cache and its manifest deliberately if you want a newer release.

## Flatpak installation policy

Flatpak4Mac installs local bundles and Flathub applications system-wide. If
there is a duplicate user-level Flathub remote and no user-level Flatpaks,
provisioning removes that empty duplicate. It never deletes installed user
Flatpaks. KDE Discover's PackageKit backend is removed when installed; the
Flatpak backend remains. Discover's graphics settings are **unchanged**.

For RetroDECK, `quick-retrodeck.sh` configures VirtFS sharing through UTM
AppleScript (VM restart may be required). The script checks the mount before
allowing the game frontend to launch.

### Graphical login and repeat installations

Flatpak4Mac repairs `/etc/X11/default-display-manager` to select LightDM,
sets the default to `graphical.target`, starts LightDM and verifies that it is
active before completing desktop provisioning. The provisioning service checks
this on existing VMs, too; no VM reset is necessary. If startup fails, inspect
`sudo journalctl -u lightdm -b --no-pager` inside Ubuntu.

Local ARM64 RetroDECK builds already installed at
`net.retrodeck.retrodeck/aarch64/arm-0.11.0` are skipped on subsequent runs.
Other bundles that Flatpak reports as already installed are treated as success
only after verifying the application's system installation. A different build
requires an explicit update or reinstall; an unrelated installation error is
not hidden.

## Recovery and rebuilding

If a first installation is interrupted, inspect the provisioning logs above
and rerun `./quick-start.sh`. If the VM is unusable and **you have backed up
everything you need**, stop it in UTM and use `./reset.sh` to remove only the
project-identified VM and its working image. This permanently discards data
stored solely inside that VM. The reset retains `cache/`, `retrodeck/`,
`autoinstall/` and `config/`; see [Reset](RESET.md) for the exact safeguards.

Never delete unrelated UTM VMs or assume that a host-shared folder is backed
up. For script sequencing and why a VirtFS restart may rerun bootstrap, see
[Architecture and script flow](ARCHITECTURE.md).
