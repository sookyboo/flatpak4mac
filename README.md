# Flatpak4Mac

Homebrew-free Flatpak on macOS using an Ubuntu 24.04 UTM VM. The quick installers are `quick-start.sh` (general use) and `quick-retrodeck.sh` (private local RetroDECK bundle or compatible Flathub build). XQuartz remains optional.

Flatpak4Mac began as a way to **build and test RetroDECK for ARM devices** using
an ARM64 Linux guest on Apple Silicon. It is also useful for other Linux
Flatpak and development workflows.

> **Pre-release / experimental:** This project needs further testing on macOS,
> UTM and ARM64 Linux. VMs created with it can be reset, reprovisioned or
> deleted as the scripts evolve. **Do not store anything important only inside
> a Flatpak4Mac VM.** Keep your source code, game saves, ROMs, credentials and
> other valuable files backed up independently outside the VM. A configured
> host share is not a substitute for a backup.

**Recommended display:** KDE Plasma **X11**, the default. On the tested UTM
VirGL/Apple Silicon combination, KDE Wayland/XWayland produced black windows
in X11 applications including `xeyes` and SourceGit. Disabling desktop effects
and updating UTM did not resolve it. Wayland remains optional for experiments,
but use X11 until the rendering issue has been investigated and verified fixed.

For script responsibilities, execution flows and recovery behaviour, see
[Architecture and script flow](docs/ARCHITECTURE.md).

To install a prebuilt RetroDECK ARM64 Flatpak, check whether a Flathub ARM64
release is available, or build RetroDECK 0.11 with `--dev` using the host-shared
workspace, see [RetroDECK installation and ARM64 build guide](docs/RETRODECK.md).

`./quick-start.sh` provisions the VM without installing files from `autoinstall/`.
Use `./quick-start.sh --install-bundles` when you explicitly want to install
those files system-wide, or approve installation from `./quick-retrodeck.sh`.

**Clean install:** Read [`docs/INSTALL.md`](docs/INSTALL.md). The VM image, cloud-init seed and SSH key are stored in `vm/ubuntu-24.04/`, under the extracted `~/flatpak4mac/` directory. Existing RetroDECK data in `retrodeck/` are never cleared automatically.

**Important:** UTM's GUI is used for the one-time primary disk resize to at least 40 GiB (64 GiB recommended) before first boot. Cloud-init refuses desktop package installation on an undersized root disk and only marks provisioning complete on success.

Provisioning uses SSH-first cloud-init, a systemd service and authenticated
guest discovery. See [installation instructions](docs/INSTALL.md).

**Configuration:** `~/flatpak4mac/config/phase5.env`,
`~/flatpak4mac/config/app-modes.tsv` and desktop preferences live in the project.
KDE Plasma X11 is the default; Wayland remains selectable. Choices are saved
and reused on reruns.

**Uninstall:** `./uninstall.sh` removes the project VM (if safely identified and stopped) and generated files while retaining `retrodeck/` intact. See [`docs/UNINSTALL.md`](docs/UNINSTALL.md).

**Ubuntu image cache:** First-run setup offers to retain the pristine downloaded
cloud image (default yes) under `cache/ubuntu-24.04/`; the VM uses a separate
working image under `vm/ubuntu-24.04/`. See `docs/INSTALL.md`.

**Interactive uninstall:** `./uninstall.sh` asks whether to retain `retrodeck/`
and the cloud-image `cache/` (both default yes). Deleting managed resources
outside the project, such as the UTM VM, requires separate confirmation.

## Reset only the VM

Run `./reset.sh` to delete the recorded, stopped Flatpak4Mac UTM VM and the `vm/` working-image directory. It asks before deleting the external VM and keeps `cache/`, `retrodeck/`, `autoinstall/`, `config/`, and the scripts. See `docs/RESET.md`.

### Reliability and data protection

- System-wide Flatpak/Flathub installation, with safe duplicate-remote cleanup.
- KDE Discover uses its Flatpak backend; PackageKit backend removed. Graphics
  rendering remains unchanged (no software-rendering workaround).
- RetroDECK host sharing is configured using UTM AppleScript when permitted;
  UTM may have to restart the project VM. Guest-side mounting is verified.

**Share conflict handling:** When UTM has another host folder registered for the
Flatpak4Mac VM, Quick RetroDECK shows its path and asks before replacing it.
The default is No. It never silently replaces an existing shared folder.

Provisioning checks the root filesystem, repairs an invalid GSettings schema
database when required, and validates LightDM and Flatpak readiness. Quick
Start is safe to rerun: previously installed packages are recognized, and the
explicit bundle installer checks for already installed bundles. Neither
operation changes the VM's rendering configuration.


### RetroDECK dedicated session

When RetroDECK is installed, `./quick-retrodeck.sh` installs a dedicated LightDM
X11 session; it selects that session only if you approve automatic RetroDECK
launch. Otherwise it selects the chosen desktop (KDE Plasma X11 by default).
XFCE stays installed but does **not** run behind
RetroDECK. This preserves the existing GPU path (no software-rendering flags).
On exit, the session selects XFCE for the next login, preventing an automatic
RetroDECK relaunch loop. The macOS **Flatpak Manager** offers **Switch to XFCE
Desktop** and **Switch to RetroDECK**; switching closes running graphical apps.
You may also switch from a macOS terminal using:

```sh
~/flatpak4mac/launcher/flatpak4mac-host.sh --backend utm session xfce
~/flatpak4mac/launcher/flatpak4mac-host.sh --backend utm session retrodeck
```

Use KDE Plasma X11 when opening Discover on the UTM display (XFCE also works).
Do not run a second RetroDECK
Flatpak instance over an existing desktop session.

### Switching graphical sessions

Use `~/flatpak4mac/launcher/flatpak4mac-host.sh --backend utm session retrodeck`
or `... session xfce`. The switcher updates LightDM's effective
`/etc/lightdm/lightdm.conf.d/60-flatpak-autologin.conf` and restarts LightDM
when the requested desktop is not currently running. This closes open graphical
applications but does not reboot Ubuntu or reset the VM. Re-running provisioning
preserves the selected session. No software-rendering override is applied.

## Session startup diagnostics

See `docs/STARTUP-PERFORMANCE.md` for timing commands, LightDM/Flatpak journal
markers and guidance on diagnosing slow XFCE or RetroDECK starts.

### XFCE/RetroDECK session startup diagnostics

Provisioning validates the compiled GSettings schema database, automatically
rebuilding it if GLib reports missing schemas or an invalid GVDB header. This
prevents accessibility, GVFS and desktop-portal crashes that can add long D-Bus
timeouts when starting XFCE. This check also runs on previously provisioned
VMs, before Quick Start marks the VM ready. No software-rendering overrides are
used.

The session switcher reports when the LightDM session process starts, not
when the first frame is rendered. For RetroDECK, it checks Flatpak instances
where possible without requiring the short-lived `flatpak run` launcher to
remain alive. Use `journalctl -t flatpak4mac-retrodeck -b` for detailed timing.

### SSH into the Ubuntu VM

From macOS, run `./ssh.sh` in the project directory (or `~/flatpak4mac/ssh.sh`).
It uses the project's private key, checks the saved guest address and attempts
UTM/MAC-based IP rediscovery if DHCP has changed. SSH options may be supplied,
for example `./ssh.sh -L 8080:localhost:8080`. Exit with `Ctrl-D`.
The VM must be booted and SSH available; no password is required.

## Optional ARM64 development profile

Run `./quick-retrodeck.sh --dev` to install development tools and select the
configured desktop (KDE Plasma X11 by default), along with
SourceGit (pinned, checksum-verified 2026.24 ARM64 Debian package), GitHub CLI and the Ubuntu
utilities. If SourceGit cannot be downloaded or verified, it is skipped
with a warning; the rest of the development setup continues. The development
workflow skips RetroDECK and autoinstall bundles.
Switch to KDE via `./launcher/flatpak4mac-host.sh --backend utm session plasma`.
See `docs/DEV.md`.
