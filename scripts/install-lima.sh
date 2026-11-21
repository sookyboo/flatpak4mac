#!/bin/bash
# Phase 1: install Lima without Homebrew; create a Linux VM; install and test Flatpak.
# Safe to rerun. Does not alter shell profiles or delete existing VMs.
set -Eeuo pipefail

LIMA_VERSION="2.3.0"
VM_NAME="flatpak"
RUNTIME="org.freedesktop.Platform//25.08"
ROOT="${HOME}/.local/share/flatpak-macos"
INSTALL_DIR="${ROOT}/lima-${LIMA_VERSION}"
LIMA_HOME="${LIMA_HOME:-${HOME}/.lima}"
export LIMA_HOME

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

[[ "$(uname -s)" == "Darwin" ]] || die "Run this script on macOS."
[[ "$(id -u)" -ne 0 ]] || die "Run as your normal macOS user, not sudo/root."
require curl
require tar
require shasum
require sysctl
require sw_vers
require mktemp
require awk

MACOS_MAJOR="$(sw_vers -productVersion | awk -F. '{print $1}')"
[[ "$MACOS_MAJOR" =~ ^[0-9]+$ ]] || die "Unable to determine macOS version."
(( MACOS_MAJOR >= 13 )) || die "Apple Virtualization.framework via Lima VZ requires macOS 13+."
[[ "$(sysctl -n kern.hv_support 2>/dev/null || true)" == "1" ]] || die "Hardware virtualization is not available (kern.hv_support != 1)."

ARCH="$(uname -m)"
case "$ARCH" in
  arm64)
    LIMA_SHA="b7af444bd8f91d3c307477e562f2cf3bd7595d62b9429185e4fa841563578cfc"
    AGENTS_SHA="f43a1523a3a0a45692ca9cb3e5c61ae11b69ef04ca80081e8e05fe4df816a35a"
    ;;
  x86_64)
    LIMA_SHA="d58bc7d6b8158d638720d8c8fdb17eb58527dfead6a29a5b60f48a35ee4a65a6"
    AGENTS_SHA="cecb56c17ee4aaeac9412b079f175bba52d50b657829099f37b67b424c6364f3"
    ;;
  *) die "Unsupported Mac architecture: $ARCH" ;;
esac

mkdir -p "$ROOT"
TMP="$(mktemp -d "${ROOT}/.setup.XXXXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fetch_verified() {
  local filename="$1" expected="$2" dest="${TMP}/$1" actual
  local url="https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/${filename}"
  log "Downloading ${filename}"
  curl --fail --location --retry 5 --retry-delay 2 --retry-all-errors \
    --connect-timeout 20 --output "$dest" "$url" || die "Download failed: $url"
  actual="$(shasum -a 256 "$dest" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "SHA-256 mismatch for $filename (expected $expected, got $actual)"
}

if [[ -x "${INSTALL_DIR}/bin/limactl" && -f "${INSTALL_DIR}/.phase1-installed" ]]; then
  log "Lima ${LIMA_VERSION} already installed; skipping download"
else
  [[ ! -e "$INSTALL_DIR" ]] || die "Incomplete/non-managed install at $INSTALL_DIR; inspect or rename it before rerunning."
  LIMA_FILE="lima-${LIMA_VERSION}-Darwin-${ARCH}.tar.gz"
  AGENTS_FILE="lima-additional-guestagents-${LIMA_VERSION}-Darwin-${ARCH}.tar.gz"
  fetch_verified "$LIMA_FILE" "$LIMA_SHA"
  fetch_verified "$AGENTS_FILE" "$AGENTS_SHA"

  mkdir -p "${TMP}/install"
  tar -xzf "${TMP}/${LIMA_FILE}" -C "${TMP}/install"
  tar -xzf "${TMP}/${AGENTS_FILE}" -C "${TMP}/install"
  [[ -x "${TMP}/install/bin/limactl" ]] || die "Archive did not contain bin/limactl"
  : > "${TMP}/install/.phase1-installed"
  mv "${TMP}/install" "$INSTALL_DIR"
  log "Installed Lima into $INSTALL_DIR"
fi

LIMACTL="${INSTALL_DIR}/bin/limactl"
export PATH="${INSTALL_DIR}/bin:${PATH}"
"$LIMACTL" --version

# Only create a VM if it is not already known to Lima. A failed/incomplete
# Lima creation is left in place for Lima to recover or report explicitly.
if [[ -f "${LIMA_HOME}/${VM_NAME}/lima.yaml" ]]; then
  log "Starting existing VM '$VM_NAME' (if stopped)"
  "$LIMACTL" start "$VM_NAME"
else
  [[ ! -e "${LIMA_HOME}/${VM_NAME}" ]] || die "Found unexpected VM directory ${LIMA_HOME}/${VM_NAME}; refusing to overwrite."
  log "Creating Ubuntu VM '$VM_NAME' with Apple's VZ backend"
  "$LIMACTL" start --name="$VM_NAME" --vm-type=vz --tty=false template:ubuntu
fi

log "Installing Flatpak in Ubuntu (safe to rerun)"
# Pass the entire guest script as an argument: no dependence on SSH stdin
# forwarding and no accidental execution on the macOS host.
GUEST_SCRIPT=$(cat <<'GUEST'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v apt-get >/dev/null 2>&1; then
  echo 'ERROR: VM is not Ubuntu/Debian (apt-get unavailable).' >&2
  exit 1
fi
sudo apt-get update
sudo apt-get install -y flatpak dbus-user-session dbus-bin
sudo flatpak remote-add --system --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install --system --noninteractive -y flathub org.freedesktop.Platform//25.08

echo '==> Confirming sandbox actually launches'
dbus-run-session -- flatpak run --system --command=sh \
  org.freedesktop.Platform//25.08 -c \
  'test -f /.flatpak-info && printf "PASS: Flatpak sandbox launched (%s)\n" "$(uname -m)"'

echo '==> Installed Flatpak runtimes:'
flatpak list --system --runtime
GUEST
)
"$LIMACTL" shell --tty=false "$VM_NAME" bash -lc "$GUEST_SCRIPT"

log "Phase 1 successful"
printf 'VM: %s\nLima: %s\n' "$VM_NAME" "$LIMACTL"
printf '\nUseful commands:\n'
printf '  "%s" shell %s\n' "$LIMACTL" "$VM_NAME"
printf '  "%s" stop %s\n' "$LIMACTL" "$VM_NAME"
printf '  "%s" start %s\n' "$LIMACTL" "$VM_NAME"
