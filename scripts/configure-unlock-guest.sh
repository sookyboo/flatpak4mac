#!/usr/bin/env bash
# Apply Flatpak4Mac's initial local account and idle-lock policy.
# Safe to rerun. Deliberately does not overwrite user-defined passwords.
set -Eeuo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
getent passwd flatpak >/dev/null || { echo 'Missing VM user flatpak' >&2; exit 1; }

# Ubuntu cloud-init often creates a locked account for SSH key + autologin.
# Only assign the requested initial password when no usable password exists.
password_state="$(passwd -S flatpak | awk '{print $2}')"
case "$password_state" in
  L|LK|NP)
    printf 'flatpak:flatpak\n' | chpasswd
    echo 'Initial flatpak account password set.'
    ;;
  P|PS)
    echo 'flatpak account already has a password; leaving it unchanged.'
    ;;
  *)
    echo "ERROR: Unrecognised flatpak password state: $password_state" >&2
    exit 1
    ;;
esac

# Edit only the selected keys, preserving other KDE/XFCE settings.
# Python 3 is included in the Ubuntu 24.04 base image.
/usr/bin/python3 - <<'PY'
from pathlib import Path
import configparser
import os

home = Path('/home/flatpak')
config = home / '.config'
config.mkdir(parents=True, exist_ok=True)

# KDE Plasma 5 screen locker: disable *automatic* lock and lock-on-resume.
# Do not remove the locker: users may still lock manually if desired.
file = config / 'kscreenlockerrc'
cp = configparser.RawConfigParser(strict=False)
cp.optionxform = str
if file.exists():
    cp.read(file)
if not cp.has_section('Daemon'):
    cp.add_section('Daemon')
for key, value in {'Autolock':'false', 'LockOnResume':'false', 'Timeout':'0'}.items():
    cp.set('Daemon', key, value)
with file.open('w') as stream:
    cp.write(stream, space_around_delimiters=False)

# XFCE's xfce4-screensaver configuration is read when the session starts.
# Disable idle activation and screen lock; do not remove other XFCE settings.
from xml.etree import ElementTree as ET
xf = config / 'xfce4' / 'xfconf' / 'xfce-perchannel-xml' / 'xfce4-screensaver.xml'
xf.parent.mkdir(parents=True, exist_ok=True)
try:
    tree = ET.parse(xf)
    root = tree.getroot()
except (ET.ParseError, FileNotFoundError):
    root = ET.Element('channel', {'name': 'xfce4-screensaver', 'version': '1.0'})
    tree = ET.ElementTree(root)
def category(name):
    for child in root.findall('property'):
        if child.get('name') == name:
            return child
    return ET.SubElement(root, 'property', {'name': name, 'type': 'empty'})
def boolean(parent, name, value):
    for child in parent.findall('property'):
        if child.get('name') == name:
            child.attrib.update(type='bool', value=value)
            return
    ET.SubElement(parent, 'property', {'name':name, 'type':'bool', 'value':value})
boolean(category('saver'), 'enabled', 'false')
boolean(category('lock'), 'enabled', 'false')
boolean(category('lock'), 'lock-on-suspend', 'false')
tree.write(xf, encoding='UTF-8', xml_declaration=True)

# Light Locker and XFCE screensaver autostart: opt out per user, without
# uninstalling the programs or changing global system settings.
autostart = config / 'autostart'
autostart.mkdir(parents=True, exist_ok=True)
for filename in ('light-locker.desktop', 'xfce4-screensaver.desktop'):
    desktop = autostart / filename
    desktop.write_text('[Desktop Entry]\nType=Application\nName=Disabled idle screen locker\nHidden=true\n')

uid, gid = 1000, 1000
import pwd
pw = pwd.getpwnam('flatpak')
uid, gid = pw.pw_uid, pw.pw_gid
for path in (config, file, xf.parent.parent.parent, xf.parent.parent, xf.parent, xf, autostart, autostart / 'light-locker.desktop', autostart / 'xfce4-screensaver.desktop'):
    # Only the modified files and their parent paths are touched; no recursive chown.
    if path.exists() and not path.is_symlink():
        os.chown(path, uid, gid)
PY

echo 'Idle screen locking disabled for KDE Plasma and XFCE on future logins.'
