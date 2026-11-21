#!/usr/bin/env bash
# Install/update official SourceGit ARM64 .deb and GitHub CLI for Flatpak4Mac --dev.
# Invoked in the Ubuntu VM as root; never runs gh auth login automatically.
set -Eeuo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo 'ERROR: install-git-tools-guest.sh must run as root.' >&2
  exit 1
fi
arch="$(dpkg --print-architecture)"
if [[ "$arch" != arm64 ]]; then
  echo "ERROR: This development installer expects Ubuntu arm64, got $arch" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive

# The GitHub CLI repository is maintained by the gh developers. Install only
# after verifying its signing key against their published fingerprints.
apt-get install -y ca-certificates curl gnupg git
keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
repo=/etc/apt/sources.list.d/github-cli.list
mkdir -p -m 755 /etc/apt/keyrings
if [[ ! -s "$keyring" || ! -f "$repo" ]]; then
  tempkey="$(mktemp)"
  trap 'rm -f "${tempkey:-}" "${tmpdeb:-}"' EXIT
  curl --fail --show-error --silent --location --retry 3 \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$tempkey"
  # Allowed publishing keys documented by github.com/cli/cli/docs/install_linux.md.
  if ! gpg --batch --quiet --show-keys --with-colons "$tempkey" \
      | awk -F: '$1=="fpr" {print toupper($10)}' \
      | grep -Eq '^(2C6106201985B60E6C7AC87323F3D4EA75716059|7F38BBB59D064DBCB3D84D725612B36462313325)$'; then
    echo 'ERROR: GitHub CLI APT signing key does not match the official fingerprint.' >&2
    exit 1
  fi
  install -m 644 "$tempkey" "$keyring"
  printf 'deb [arch=arm64 signed-by=%s] https://cli.github.com/packages stable main\n' "$keyring" > "$repo"
  rm -f "$tempkey"
  trap - EXIT
fi
apt-get update
apt-get install -y gh

echo 'Installing verified SourceGit 2026.24 ARM64 release when available...'
# Pinned to the official release asset and its published SHA-256 checksum.
# SourceGit is optional; errors must not abort the rest of --dev provisioning.
asset='https://github.com/sourcegit-org/sourcegit/releases/download/v2026.24/sourcegit_2026.24-1_arm64.deb'
digest='c4e2ea3b7deee5f8bab82122ce1809c667f949817ab086a449cd8c6514422c66'
# The asset filename contains '-1', but the .deb control Version is 2026.24.
version='2026.24'
tmpdeb=''
trap 'rm -f "${tmpdeb:-}"' EXIT
# Leave an equal or newer installed version untouched. A user could have
# installed a prerelease manually; provisioning should not downgrade it.
installed="$(dpkg-query -W -f='${Version}' sourcegit 2>/dev/null || true)"
if [[ -n "$installed" ]] && dpkg --compare-versions "$installed" ge "$version"; then
  echo "SourceGit $installed is already installed (pinned release: $version)."
else
  tmpdeb="$(mktemp --suffix=.deb)"
  if ! curl --fail --show-error --silent --location --retry 3 "$asset" -o "$tmpdeb"; then
    echo 'WARNING: SourceGit download failed; skipping optional installation.' >&2
  elif ! printf '%s  %s\n' "$digest" "$tmpdeb" | sha256sum --check --status; then
    echo 'WARNING: SourceGit checksum mismatch; refusing to install.' >&2
  elif [[ "$(dpkg-deb --field "$tmpdeb" Architecture 2>/dev/null)" != arm64 ]] || \
       [[ "$(dpkg-deb --field "$tmpdeb" Package 2>/dev/null)" != sourcegit ]] || \
       [[ "$(dpkg-deb --field "$tmpdeb" Version 2>/dev/null)" != "$version" ]]; then
    echo 'WARNING: SourceGit package identity/version mismatch; refusing to install.' >&2
  elif ! apt-get install -y "$tmpdeb"; then
    echo 'WARNING: SourceGit installation failed; continuing without it.' >&2
  fi
fi

command -v gh >/dev/null
echo "GitHub CLI: $(gh --version | head -1)"
if dpkg-query -W -f='${Status}' sourcegit 2>/dev/null | grep -qx 'install ok installed'; then
  echo "SourceGit: $(dpkg-query -W -f='${Version}' sourcegit)"
else
  echo 'WARNING: SourceGit is not installed; other development tools remain available.' >&2
fi
echo 'Run gh auth login as flatpak to authenticate when desired.'
