# RetroDECK on Flatpak4Mac: install or build for ARM64

Flatpak4Mac was originally created to build and test RetroDECK for ARM devices.
The ARM64 RetroDECK 0.11 branch is **development software**; behaviour and
component availability may change. Flatpak4Mac itself also needs further
testing. Do not keep important data only inside the VM. Back up ROMs, saves,
source code and build artifacts on the Mac or another independent device.

**Use KDE Plasma X11** in the UTM guest for now: the tested Wayland/XWayland
configuration displayed black X11 application windows. Wayland remains an
experimental option.

## Option 1: install a prebuilt ARM64 bundle

On an Apple Silicon Mac, place an ARM64 private Flatpak bundle (for example `RetroDECK-0.11.0-aarch64.flatpak`) in `autoinstall/` and run:

```sh
./quick-retrodeck.sh
```

This invokes Quick Start and ensures a writable UTM VirtFS share between the
Mac's `retrodeck/` and the guest's `/home/flatpak/retrodeck`. Normal mode asks
separately whether to install/retain RetroDECK and whether to launch it when
setup finishes (both prompts default to Yes). Declining launch selects your
chosen desktop instead. No XQuartz installation is required.

**Experimental VM:** Do not keep irreplaceable RetroDECK data or source files
only inside this VM. Maintain independent backups outside it. KDE Plasma X11
is recommended for desktop use because X11 windows have appeared black under
Plasma Wayland/XWayland on the tested UTM graphics path.

The script creates only the `retrodeck/` folder, not ROM, BIOS, save or port subfolders. On first launch, point RetroDECK at `/home/flatpak/retrodeck` if it asks for a data directory; it should create the necessary structure itself.

Flathub fallback requires a build compatible with the guest's ARM64
architecture. Do not assume macOS Rosetta can transparently run x86_64 Flatpaks
inside an ARM Linux guest; supply a native ARM64 bundle when necessary.

For a fresh install, follow [installation](INSTALL.md) first. The generated
image is under `vm/ubuntu-24.04/`.

On the **Mac**, put a trusted native `aarch64` `.flatpak` bundle into
`~/flatpak4mac/autoinstall/`. To install it into an existing VM without
changing the desktop session, run:

```bash
cd ~/flatpak4mac
./quick-start.sh --install-bundles
```

Alternatively, run `./quick-retrodeck.sh` and accept the **Install RetroDECK**
prompt. The script only processes the bundles after you approve installation.
If an older installation is present, confirm its branch before attempting to
launch the dedicated session (see the limitation below).

## Option 2: install from Flathub, if ARM64 becomes available

At the time this guide was prepared, the [RetroDECK Flathub listing](https://flathub.org/apps/net.retrodeck.retrodeck)
advertised `x86_64`, not `aarch64`. Check availability in the VM rather than
assuming that an ARM build is published:

```bash
flatpak remote-info --system --arch=aarch64 flathub net.retrodeck.retrodeck
```

If the command reports a compatible ARM64 ref, install it system-wide:

```bash
sudo flatpak install --system --arch=aarch64 flathub net.retrodeck.retrodeck
```

If the ARM64 ref is unavailable, use an ARM64 build bundle or the development
build below. An `x86_64` Flatpak cannot be used directly in this ARM64 guest.

## Option 3: build RetroDECK 0.11 for AArch64 with `--dev`

The instructions below adapt the ARM 0.11 build workflow to Flatpak4Mac.
**All Git checkouts, component scratch files, Flatpak build outputs and the
local OSTree repository live on the host-shared folder**, minimizing growth
of the VM disk. The guest still needs disk space for installed packages,
Flatpak SDKs/runtimes and the final system-wide installation.

### Start the development environment

On **macOS**:

```bash
cd ~/flatpak4mac
./quick-retrodeck.sh --dev
```

This provisions Ubuntu ARM64, sets up the VirtFS mount, installs build tools
including `flatpak-builder`, and selects KDE Plasma X11 by default. It does
not install or launch RetroDECK. Development tools such as SourceGit are
optional when a verified release cannot be identified.

Use `./ssh.sh` from the Mac to log in to Ubuntu. All commands in the remaining
build sections run **inside the Ubuntu guest** unless stated otherwise.

Check architecture and the mounted, writable share:

```bash
uname -m
flatpak --default-arch
findmnt /home/flatpak/retrodeck
test -w /home/flatpak/retrodeck && echo 'Shared directory is writable'
```

Both architecture checks should report `aarch64` (some tools say `arm64`).
The mount should be the UTM `9p`/VirtFS share. On the Mac its corresponding
path is `~/flatpak4mac/retrodeck/`. **Do not build in the guest's home directory
or `/tmp`**: that would unnecessarily grow the QCOW2 VM image.

### Prepare the shared build workspace

```bash
export RETRODECK_BUILD_ROOT=/home/flatpak/retrodeck/build
mkdir -p "$RETRODECK_BUILD_ROOT"
cd "$RETRODECK_BUILD_ROOT"
df -h .
```

This is `~/flatpak4mac/retrodeck/build/` on the Mac. Leave at least **35 GB**
available on the host volume for source trees, component archives, scratch
files, Flatpak outputs and the local repo; some builds may require more. Keep
backups outside this directory. The share and the VM root may have different
free-space limits.

Add Flathub for the build user's dependencies if needed:

```bash
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
```

### Clone the matching ARM branches

Keep the two worktrees adjacent; the ARM manifest uses sibling relative paths.
These are the `sookyboo` development forks provided for this build workflow:

```bash
cd "$RETRODECK_BUILD_ROOT"
git clone --branch arm-0.11.0 --single-branch \
  https://github.com/sookyboo/components.git components-arm-0.11.0
git clone --branch arm-0.11.0 --single-branch \
  https://github.com/sookyboo/RetroDECK.git RetroDECK-arm-0.11.0
```

The shared build directory should contain:

```text
build/
├── components-arm-0.11.0/
└── RetroDECK-arm-0.11.0/
```

### Build the AArch64 components

The scratch directory is also on VirtFS. Use a low job count if memory is
limited; the default below is one worker.

```bash
cd "$RETRODECK_BUILD_ROOT"
export ARM_BUILD_JOBS="${ARM_BUILD_JOBS:-1}"
export BUILD_TMPDIR="$RETRODECK_BUILD_ROOT/.build-tmp"
mkdir -p "$BUILD_TMPDIR"
export TMPDIR="$BUILD_TMPDIR"
export ESDE_BUILD_JOBS="$ARM_BUILD_JOBS"

cd components-arm-0.11.0
for component in \
  retroarch framework pico-8 ppsspp ruffle scummvm \
  azahar dolphin melonds mame xemu portmaster \
  duckstation vita3k rpcs3 cemu steam-rom-manager es-de; do
  printf '\nBuilding %s for AArch64\n' "$component"
  if ! bash "linux-arm64/$component/build-component.sh"; then
    printf 'Build failed for %s; stopped the loop.\n' "$component" >&2
    break
  fi
done
```

ES-DE is last because it integrates component definitions. Successful builds
normally leave archives and checksums in component `artifacts/` directories.
Inspect any failure before proceeding; the loop deliberately stops at the
first failed component.

### Build the Flatpak in the shared directory

```bash
cd "$RETRODECK_BUILD_ROOT/RetroDECK-arm-0.11.0"

flatpak-builder \
  --user \
  --force-clean \
  --disable-rofiles-fuse \
  --jobs="$ARM_BUILD_JOBS" \
  --arch=aarch64 \
  --default-branch=arm-0.11.0 \
  --install-deps-from=flathub \
  --state-dir="$RETRODECK_BUILD_ROOT/.flatpak-builder-state" \
  --repo=repo-arm64 \
  build-arm64 \
  net.retrodeck.retrodeck.arm64.yml
```

The `build-arm64/`, `.flatpak-builder-state/` and `repo-arm64/` directories
are all under the Mac-shared workspace. Remove `--force-clean` for retries
when reusing completed Flatpak Builder work is appropriate. Flatpak itself
may still maintain SDK/runtime caches in the guest user's or system's Flatpak
installation.

**VirtFS caveat:** A 9p share may lack POSIX features required by particular
build tools or OSTree (for example hard links or extended attributes). This
layout is intended to avoid VM disk growth, but has **not yet been verified
end-to-end**. If a build fails with unsupported filesystem operations,
investigate the exact failure; do not blindly relocate large outputs into
the VM or assume the build succeeded.

### Install the locally built ARM64 app

The dedicated Flatpak4Mac RetroDECK session launches a **system-wide** app,
so use a system-wide installation for integration with that session:

```bash
cd "$RETRODECK_BUILD_ROOT/RetroDECK-arm-0.11.0"
sudo flatpak remote-add --system --no-gpg-verify --if-not-exists \
  retrodeck-arm-0.11.0-local "$PWD/repo-arm64"
sudo flatpak install --system --arch=aarch64 \
  retrodeck-arm-0.11.0-local \
  net.retrodeck.retrodeck//arm-0.11.0
```

This local remote is for your own generated repo, not an untrusted network
repository. `--no-gpg-verify` disables signature verification for this one
local remote. Confirm that installation succeeded before switching sessions:

```bash
flatpak info --system net.retrodeck.retrodeck//arm-0.11.0
```

Then you can use the existing Flatpak4Mac session switcher from the Mac to
launch the dedicated RetroDECK session, or launch the app inside the desktop:

```bash
flatpak run --system net.retrodeck.retrodeck//arm-0.11.0
```

### Optional: create a portable ARM64 Flatpak bundle

This uses additional disk space and can be memory-intensive. Skip it if the
local OSTree installation above is enough.

```bash
cd "$RETRODECK_BUILD_ROOT/RetroDECK-arm-0.11.0"
mkdir -p output
flatpak build-bundle \
  --arch=aarch64 \
  repo-arm64 \
  output/RetroDECK-0.11.0-aarch64.flatpak \
  net.retrodeck.retrodeck \
  arm-0.11.0
```

Because the build tree is shared, that bundle is visible on the **Mac** at:

```text
~/flatpak4mac/retrodeck/build/RetroDECK-arm-0.11.0/output/RetroDECK-0.11.0-aarch64.flatpak
```

If you prefer the normal Flatpak4Mac `autoinstall/` flow, copy the bundle on
the **Mac**, then request installation:

```bash
cp ~/flatpak4mac/retrodeck/build/RetroDECK-arm-0.11.0/output/RetroDECK-0.11.0-aarch64.flatpak \
  ~/flatpak4mac/autoinstall/
cd ~/flatpak4mac
./quick-start.sh --install-bundles
```

The script transfers the bundle and installs it system-wide. Do not perform
both this installation and the local-repository installation unless you have
a reason to replace/update the installed ref. **Note:** The bundle installer
temporarily copies the complete bundle to the guest's `/tmp` before Flatpak
installs it; this can grow the QCOW2 image. Prefer the local-repository path
for development builds when keeping guest disk growth low is the priority.

## Automatic VirtFS sharing

`quick-retrodeck.sh` now configures UTM's QEMU VirtFS setting and shared
macOS directory using UTM AppleScript. It requires the project-created VM UUID
marker, and asks before restarting a running guest. UTM must permit AppleScript
automation. The mount must pass a host-to-guest and guest-to-host write check
before RetroDECK launches. If the AppleScript operation is unsupported, stop
the VM and set **Sharing > VirtFS** to `~/flatpak4mac/retrodeck` manually.

RetroDECK is installed **system-wide**; the user folder contains only data.
XQuartz and Discover software rendering are not changed.

### UTM AppleScript VirtFS configuration

The host sharing helper uses `update configuration vm with {directory share mode:VirtFS}` followed by `update registry vm with {POSIX file sharePath}`. It does not mutate UTM's read-only AppleScript configuration record. The VM must be stopped for both operations. If UTM rejects the update, follow the manual UTM Sharing instructions and rerun `quick-retrodeck.sh`; keep the existing Ubuntu VM.

### Existing UTM shared directory

If UTM already has a different shared directory registered, `quick-retrodeck.sh`
now displays the existing host path and offers to replace it (default **No**).
UTM's QEMU VirtFS configuration normally exposes one shared directory via the
`share` tag. Replacing it changes the VM's previously configured host folder;
files in that folder are **not deleted**. The script requires explicit approval,
then stops the VM before editing its configuration. If you decline, configure
sharing manually in UTM instead.

### UTM path and write-permission recovery

UTM can report the directory with a trailing slash even when the configured
path is identical to `flatpak4mac/retrodeck`. The setup script normalises that
trailing slash and reuses the existing VirtFS share without offering to replace it.
If the guest mounts the share read-only to the regular `flatpak` user while root
can write, the mount verification attempts a **non-recursive** ownership change
on `/home/flatpak/retrodeck` and checks normal-user write access again. It never
changes ROM or save-file ownership recursively.

### Detecting an installed private build

Local `.flatpak` bundles are processed by the shared bundle installer when you
approve installation. Quick RetroDECK checks
`flatpak --system info net.retrodeck.retrodeck` before trying Flathub. The
filename does not have to be `retrodeck.flatpak`, and an already-installed
private ARM64 build is reused. This avoids false errors after successful
installation.

**Current branch limitation:** The dedicated RetroDECK session currently runs
`net.retrodeck.retrodeck//arm-0.11.0` explicitly. Installing a different ARM64
branch does not automatically change that launcher. Until branch selection is
implemented, confirm this exact branch is installed before choosing to launch
the dedicated session:

```sh
flatpak info --system net.retrodeck.retrodeck//arm-0.11.0
```

If only another branch is installed, do not select automatic RetroDECK launch;
use the desktop session and investigate branch compatibility separately.
