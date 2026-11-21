# Uninstall Flatpak4Mac

Run `cd ~/flatpak4mac && ./uninstall.sh` in an interactive macOS Terminal.

The script asks two independent **default-yes** questions:

1. Keep `retrodeck/` and everything RetroDECK created (ROMs, ports, saves)?
2. Keep `cache/` and its pristine downloaded Ubuntu cloud image?

Every other entry **inside** `~/flatpak4mac/`, including `vm/`, `config/`,
`autoinstall/` and installer scripts, is removed without individual prompts.
Each removal is printed. `uninstall.sh` remains so the active script is not
removed out from under itself.

Items **outside** the project are never silently removed. The separately
installed Flatpak Manager.app and a positively identified, **stopped** UTM VM
require separate **default-no** confirmations before deletion. UTM.app,
XQuartz, unrelated VMs and external user configuration are not deleted.
If the UTM VM is retained, its management metadata is removed with the project.

**Warning:** `autoinstall/` may contain private Flatpak bundles. Back them up
before uninstalling. There is no undo for deletion of files or UTM VM disks.
