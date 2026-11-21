# Architecture and script flow

Flatpak4Mac is a macOS host-side orchestration project for an Ubuntu 24.04
ARM64 guest running in UTM's **QEMU** backend. It was originally built to
build and test **RetroDECK for ARM devices** and also supports ordinary
Flatpak and development workflows.

> **Experimental software:** Installation, recovery and desktop/graphics
> integration still need further real-device testing. Do not store important
> data only inside the generated VM. Keep independent backups outside its
> virtual disk, including for any host-shared data.

## Components and responsibilities

| Component | Runs on | Responsibility |
| --- | --- | --- |
| `quick-start.sh` | macOS | Prepare/start the VM; discover authenticated SSH; provision Ubuntu; install the macOS launcher. Optional `--install-bundles` installs local Flatpak inputs. |
| `quick-retrodeck.sh` | macOS | Choose desktop/protocol, call Quick Start, configure VirtFS, optionally install and launch RetroDECK, or prepare the development environment with `--dev`. |
| `scripts/common.sh` | macOS | Shared paths, settings, SSH and validation helpers. |
| `scripts/prepare-ubuntu-image.sh` | macOS | Download/check cached Ubuntu image; generate working disk, cloud-init seed and SSH key. |
| `scripts/configure-utm-vm.sh` | macOS | Safely create or identify the UTM QEMU VM. UTM's boot-disk resize still requires user confirmation. |
| `scripts/discover-guest-ip.sh` | macOS | Match guest-agent/MAC/ARP candidates and verify identity using the project SSH key. |
| `scripts/install-guest-service.sh` | macOS | Refresh provisioning files and the systemd service over SSH. |
| `scripts/provision-ubuntu-guest.sh` | Ubuntu | Validate disk space, install XFCE/Flatpak/Discover, ensure LightDM and system policy; write completion markers. |
| `scripts/install-flatpaks.sh` | macOS + SSH | Transfer approved `.flatpak` / `.flatpakref` files from `autoinstall/`, then install them system-wide. |
| `scripts/configure-retrodeck-share.sh` | macOS | Configure UTM VirtFS safely; request permission before a required VM restart. |
| `scripts/ensure-retrodeck-share.sh` | macOS + Ubuntu | Mount the 9p share, check writable access, and prove host-to-guest and guest-to-host file visibility. |
| `scripts/install-retrodeck-session.sh` | macOS + Ubuntu | Install the dedicated LightDM RetroDECK session. |
| `scripts/ensure-session-helper.sh` | macOS + Ubuntu | Install/update session-mode selector and privileged switch worker. |
| `scripts/flatpak4mac-session-mode` / `scripts/flatpak4mac-session-switch-worker` | Ubuntu | Change the selected LightDM session and coordinate desktop switch/restart. |
| `scripts/install-dev-environment.sh` | macOS + Ubuntu | Install optional development, Git and input-method tooling in `--dev` mode. |
| `launcher/` | macOS | Flatpak Manager launch integration and guest/session commands. |
| `reset.sh` / `uninstall.sh` | macOS | Separate, confirmed cleanup workflows; never part of automatic provisioning. |

## Quick Start: base provisioning

1. Validate host platform and required script files.
2. Ensure UTM, prepare the cached/working Ubuntu image and cloud-init seed,
   and create or reuse the identified Flatpak4Mac VM.
3. Stop for the user's confirmation that the boot disk is adequately resized
   and that the seed disk, network and GPU are configured correctly.
4. Start the VM, discover candidate addresses and authenticate SSH before
   accepting a candidate as the project guest.
5. Install/refresh the guest systemd provisioning service, then wait for
   required markers, packages and LightDM readiness. Report failure logs
   rather than deleting or recreating a VM automatically.
6. Install the macOS launcher. **No local bundles are installed by default.**

Use `./quick-start.sh --install-bundles` to run the same base setup and then
install the contents of `autoinstall/` explicitly. Running it again is
intended to reuse the VM and installed packages; it is not a backup mechanism.

## Quick RetroDECK: normal mode

1. Read or ask for the host-side desktop choice (**KDE** or XFCE), and for KDE
   select **X11** (recommended/default) or Wayland. Preferences persist in
   `config/` and are not silently overwritten on reruns.
2. Validate bundled session/share scripts before starting guest work.
3. Call `quick-start.sh` **without bundle installation**.
4. Configure and verify the shared folder: macOS `retrodeck/` is mounted at
   Ubuntu `/home/flatpak/retrodeck` using UTM QEMU VirtFS/9p.
5. Configure initial local login/idle-lock policy without replacing an
   existing usable account password.
6. Ask independently whether to install/retain RetroDECK and whether to
   launch it (interactive defaults are Yes). Only an accepted install runs
   `scripts/install-flatpaks.sh`. Reuse an already installed system Flatpak;
   use a compatible Flathub fallback only when appropriate for guest CPU.
7. Install desktop/session helpers and select the dedicated RetroDECK session
   **only if launch was accepted**. Otherwise select the chosen desktop.

**Necessary restart exception:** UTM sharing settings sometimes require
stopping the VM. `configure-retrodeck-share.sh` asks first, changes only a
verified project VM and calls Quick Start again **after restarting** to
rediscover SSH and confirm provisioning. This is a recovery operation, not a
second bundle install.

**Branch limitation:** The dedicated RetroDECK session currently invokes
`net.retrodeck.retrodeck//arm-0.11.0` literally. An installed build on another
branch is not automatically selected. See [RetroDECK](RETRODECK.md).

## Development mode (`quick-retrodeck.sh --dev`)

The same VM and VirtFS startup steps run, but no `autoinstall/` bundles are
processed and RetroDECK is not launched. Development tools are installed via
`scripts/install-dev-environment.sh`, then the chosen desktop is selected.
The default is **KDE Plasma X11**. See [Development profile](DEV.md).

## Graphics and desktop sessions

UTM provides a VirtIO GPU; guest Mesa can report accelerated `virgl` OpenGL.
That alone does **not** guarantee that XWayland windows are displayed correctly.
On the tested Apple Silicon/UTM VirGL configuration, KDE Wayland produced
black X11 application windows (`xeyes`, `xclock`, ImageMagick and SourceGit),
even after disabling desktop effects and updating UTM. **Choose Plasma X11
for now.** Wayland is retained for further testing, not recommended as the
default. No forced software-rendering workaround is enabled.

The session switch worker selects LightDM sessions. Switching can interrupt
GUI and SSH sessions; ordinary SSH discovery does not require a running GUI.
The dedicated RetroDECK session returns to XFCE when the frontend exits to
avoid an automatic relaunch loop.

## Data ownership, configuration and recovery

- `vm/ubuntu-24.04/`: generated, disposable working VM image, cloud-init
  seed and **private SSH key**. Never publish the key or seed.
- `cache/ubuntu-24.04/`: optional checksum-verified pristine image cache,
  separate from the mutable VM disk.
- `config/`: saved guest SSH address and user desktop choices.
- `autoinstall/`: user-supplied Flatpak installers; not installed unless
  explicitly requested.
- `retrodeck/`: host-shared data folder. Its contents can be valuable and
  must be backed up independently.

The guest provisioning marker is `/var/lib/flatpak4mac/provisioned` and the
service is `flatpak4mac-provision.service`. Interrupted provisioning can be
diagnosed with `sudo journalctl -u flatpak4mac-provision.service` in Ubuntu;
rerunning Quick Start may recover it. `reset.sh` is destructive to the VM's
working disk, with identity and confirmation safeguards. `uninstall.sh` has
its own confirmation and retention choices; neither runs during Quick Start.

See [Installation](INSTALL.md), [Reset](RESET.md) and [Uninstall](UNINSTALL.md).
For an ARM64 build that keeps Git checkouts and build artifacts outside the
VM's QCOW2 disk, see [RetroDECK installation and build](RETRODECK.md).
