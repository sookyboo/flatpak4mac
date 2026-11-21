# Reset the Flatpak4Mac VM

> **Experimental project:** Back up anything important outside the VM before
> testing or resetting it. `reset.sh` deletes the VM's working virtual disk;
> files stored only inside that guest cannot be recovered by retaining the
> separate `retrodeck/` host share or Ubuntu image cache.

Run from macOS Terminal:

```bash
cd ~/flatpak4mac
./reset.sh
```

The reset script deletes the **Flatpak4Mac UTM VM** and its **working image directory** (`~/flatpak4mac/vm/`). It preserves the pristine cloud-image download cache (`cache/`), RetroDECK game data (`retrodeck/`), local Flatpak installers (`autoinstall/`), project configuration (`config/`), scripts, and documentation.

**Before running:** Shut down the Flatpak4Mac VM in UTM completely. UTM VM deletion requires an explicit `yes` confirmation and a UUID/name match against the project-created marker. If the VM is running, untracked, or cannot be safely identified, reset stops without removing its working files. VM deletion is irreversible.

When the VM has been removed, reset deletes `vm/` verbosely; if no VM exists, it cleans up the directory directly. It does not touch other UTM VMs, UTM.app, XQuartz, or project data. An old saved guest IP in `config/phase5.env` can be replaced automatically by Quick Start when the new VM is discovered.

To recreate:

```bash
./quick-retrodeck.sh   # or ./quick-start.sh
```

If cached Ubuntu image data exists and caching is enabled, Quick Start can reuse it rather than downloading Ubuntu again. UTM root disk resizing is still a manual step.

For a full uninstall instead, use `./uninstall.sh`.
