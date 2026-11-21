#!/usr/bin/env bash
# Verify that Ubuntu's AppArmor policy lets unprivileged Bubblewrap configure
# its own loopback interface. No global AppArmor/sysctl weakening is needed.
set -Eeuo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

bwrap_probe() {
  # Crucial: check as the normal user. Running bwrap as root would not
  # reproduce the unprivileged-namespace failure seen by Flatpak.
  runuser -u flatpak -- bwrap \
    --ro-bind / / --dev-bind /dev /dev \
    --proc /proc --unshare-net /bin/true
}

if ! command -v bwrap >/dev/null 2>&1; then
  echo 'Bubblewrap is not installed; installing it before the sandbox probe.'
  DEBIAN_FRONTEND=noninteractive apt-get install -y bubblewrap
fi
if bwrap_probe; then
  echo 'Bubblewrap unprivileged network namespace test passed; AppArmor configuration unchanged.'
  exit 0
fi

if [[ ! -f /usr/share/apparmor/extra-profiles/bwrap-userns-restrict ]]; then
  echo 'Installing Ubuntu AppArmor profile packages for Bubblewrap.'
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-profiles apparmor-utils
fi

profile_src=/usr/share/apparmor/extra-profiles/bwrap-userns-restrict
profile_dest=/etc/apparmor.d/bwrap-userns-restrict
[[ -f "$profile_src" ]] || {
  echo "ERROR: Ubuntu Bubblewrap AppArmor profile unavailable: $profile_src" >&2
  exit 1
}
command -v apparmor_parser >/dev/null || {
  DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils
}

# The profile is a distro-maintained policy. Do not overwrite a locally
# customised profile; a failure should be diagnosed rather than silently
# changing the administrator's security settings.
if [[ -e "$profile_dest" ]]; then
  if ! cmp -s "$profile_src" "$profile_dest"; then
    echo "NOTICE: Existing custom profile left untouched: $profile_dest" >&2
  fi
else
  install -m 0644 "$profile_src" "$profile_dest"
fi
apparmor_parser -r "$profile_dest"

if ! bwrap_probe; then
  echo 'ERROR: Bubblewrap still cannot set up its network namespace.' >&2
  echo 'Inspect AppArmor denials: sudo journalctl -k -b | grep apparmor' >&2
  exit 1
fi
echo 'Bubblewrap sandbox network namespace verified with AppArmor enabled.'
