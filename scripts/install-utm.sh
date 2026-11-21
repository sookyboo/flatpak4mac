#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
need_macos
resolve_utm
if [[ -n "$UTM_APP" ]]; then log "UTM installed: $UTM_APP"; exit 0; fi
printf 'UTM is not installed.\n  1) Download latest official UTM DMG (open for installation)\n  2) Open official downloads page\n  3) Exit\n'
read -r -p 'Choose [1/2/3]: ' choice
case "$choice" in
  1)
    command -v python3 >/dev/null || fail 'Python 3 required to select the GitHub release; choose option 2.'
    mkdir -p "$HOME/Downloads"
    # GitHub release API: no unverified hardcoded release filename. Use official published DMG URL.
    url="$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' https://api.github.com/repos/utmapp/UTM/releases/latest | python3 -c 'import json,sys; x=json.load(sys.stdin); print(next((a["browser_download_url"] for a in x.get("assets",[]) if a["name"].lower().endswith(".dmg")),""))')"
    [[ "$url" == https://github.com/utmapp/UTM/releases/download/* ]] || fail 'Could not find an official DMG; visit https://github.com/utmapp/UTM/releases'
    dest="$HOME/Downloads/UTM-Flatpak4Mac.dmg"
    if [[ ! -s "$dest" ]]; then curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$dest.part"; mv "$dest.part" "$dest"; fi
    hdiutil verify "$dest" >/dev/null || fail 'DMG verification failed'
    open "$dest"
    printf 'Install UTM.app by dragging it to Applications, then rerun quick-start.sh.\n'
    exit 3;;
  2) open https://github.com/utmapp/UTM/releases; exit 3;;
  3) echo 'Exited without changes.'; exit 3;;
  *) fail 'Invalid choice.';;
esac
