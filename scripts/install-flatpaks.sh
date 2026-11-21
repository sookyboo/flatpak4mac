#!/usr/bin/env bash
# Install local Flatpak bundles/references into the VM's system installation.
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
[[ -d "$F4M_DIR/autoinstall" ]] || fail 'autoinstall folder missing'
ssh_guest 'sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'
shopt -s nullglob
for bundle in "$F4M_DIR"/autoinstall/*.flatpak "$F4M_DIR"/autoinstall/*.flatpakref; do
  file="$(basename "$bundle")"
  [[ ! -L "$bundle" ]] || fail "Refusing symlink in autoinstall: $file"
  [[ "$file" =~ ^[a-zA-Z0-9_.-]+\.flatpak(ref)?$ ]] || fail "Unsupported autoinstall filename: $file"
  # RetroDECK's private ARM64 bundles are often very large. When its exact
  # installed ref is already present, don't transfer/install it again.
  # Other arbitrary bundle names are not assumed to encode a Flatpak ID.
  # macOS ships Bash 3.2, which does not support ${var,,}.
  file_lower="$(printf '%s' "$file" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  if [[ "$file_lower" == *retrodeck*.flatpak ]] && \
      ssh_guest 'flatpak info --system --arch=aarch64 net.retrodeck.retrodeck//arm-0.11.0 >/dev/null 2>&1'; then
    log "Already installed: net.retrodeck.retrodeck/aarch64/arm-0.11.0; skipping $file"
    continue
  fi
  log "Installing local Flatpak input: $file"
  tmp="/tmp/f4m-upload-$$-$file"
  validate_guest_env
  [[ -n "$F4M_HOST" ]] || fail 'Configure UTM_SSH_HOST before autoinstall'
  scp -q -i "$F4M_KEY" -P "$F4M_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "$bundle" "flatpak@$F4M_HOST:$tmp"
  # The guest removes the uploaded temporary input even when Flatpak fails.
  # Treat only an already-installed error as idempotent success, and require
  # that Flatpak reports the named app as actually installed. Other errors
  # (missing runtime, signature, OOM, disk full) remain fatal.
  ssh_guest "set -o pipefail; out=\$(sudo flatpak --system install -y --noninteractive $(printf '%q' "$tmp") 2>&1); rc=\$?; printf '%s\\n' \"\$out\"; rm -f $(printf '%q' "$tmp"); if (( rc == 0 )); then exit 0; fi; if [[ \"\$out\" =~ ([a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)+)[[:space:]]already[[:space:]]installed ]]; then app=\"\${BASH_REMATCH[1]}\"; if flatpak info --system \"\$app\" >/dev/null 2>&1; then printf 'Already installed: %s; skipping.\\n' \"\$app\"; exit 0; fi; fi; exit \"\$rc\""
done
log 'Autoinstall complete.'
