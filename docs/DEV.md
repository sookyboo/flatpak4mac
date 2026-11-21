# Optional ARM64 development environment

> **Experimental VM:** Do not keep your only copies of source code, build
> artifacts or credentials inside this guest. Keep independent backups outside
> the VM; the installation and graphics flows need further testing.

Run on macOS:

```sh
./quick-retrodeck.sh --dev
```

This installs developer tools and selects your configured desktop (KDE Plasma
X11 by default; XFCE and Plasma Wayland remain available). It does not process
`autoinstall/` bundles or launch RetroDECK. To switch into KDE later:

```sh
./launcher/flatpak4mac-host.sh --backend utm session plasma
```

Return to gaming with `session retrodeck`; the previous XFCE desktop also remains available as `session xfce`. Switching sessions restarts LightDM, closing graphical applications. Neither renderer nor VM graphics settings are modified.

## Included tools and Ubuntu package choices

- `build-essential`, `pkg-config` and native `libsdl2-dev` support C/C++ and SDL2 builds.
- `kde-spectacle` supplies screenshots; `plasma-discover` with
  `plasma-discover-backend-flatpak` supplies Flatpak management.
- `libfuse2t64` supports AppImage mounting.
- `kde-plasma-desktop` provides Plasma; the project retains LightDM rather than switching to SDDM.
- `chromium` is installed via system Flathub if available, rather than Ubuntu's Snap-transitional `chromium-browser`; a failed Chromium Flatpak install warns but does not fail the other dev tools.
- Other tools include `konsole`, `yakuake`, `kate`, `jq`, `ffmpeg`, `git`, `krusader`, `qdirstat`, `filelight`, `mc`, `ark`, `7zip`, `unzip`, `zip`, `kio-extras`, `flatpak-builder`, `podman`, `crun`, `vulkan-tools`, `mesa-utils` and `curl`.

**For now, choose Plasma X11.** X11 applications have shown black windows under
Plasma Wayland/XWayland with UTM VirGL on Apple Silicon. This limitation is
not specific to SourceGit and has not yet been resolved.

Development mode installs SourceGit 2026.24 from the official upstream ARM64 `.deb`
release at `sourcegit-org/sourcegit`, verifies its pinned SHA-256 checksum and Debian package identity,
and configures the official GitHub CLI (`gh`) APT repository with signing-key
verification. Authentication is left to the user (`gh auth login`). Both are
external downloads, not bundled in the project archive. The environment also
installs the listed GUI and build tools.

SourceGit is optional: if the pinned release asset cannot be downloaded,
fails checksum or package-identity verification, or cannot be installed,
the installer warns and continues with the other development tools. It never
downloads an unverified alternative or silently substitutes a newer release.

Input methods are managed by the desktop. The installer preserves an existing
`~/.xinputrc` choice and does not overwrite the user's IBus/Fcitx5 settings.
An unconfigured guest uses `im-config none` to avoid launching a second input
daemon inside KDE. Users can configure multilingual input through desktop
settings when needed.

The dev profile is additive and repeatable: it does not remove XFCE, your existing RetroDECK Flatpak, your ROMs, or your UTM share. It can use several additional GB of guest and host disk space; verify free space on macOS before installing.
