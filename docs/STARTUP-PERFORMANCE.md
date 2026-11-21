# Session startup performance and diagnostics

Flatpak4Mac uses a dedicated LightDM X11 session for RetroDECK and an XFCE
session for desktop management. Switching between them requires restarting
LightDM (and Xorg); this remains necessary in the current design. Switching to
the already-running mode avoids that restart.

## Time a switch from macOS

```bash
time ~/flatpak4mac/launcher/flatpak4mac-host.sh --backend utm session retrodeck
time ~/flatpak4mac/launcher/flatpak4mac-host.sh --backend utm session xfce
```

A command returning does **not** prove the application has drawn its first
frame. It only confirms that the expected processes are present.

## Guest-side milestones

```bash
sudo journalctl -b -t flatpak4mac-session-switch -t flatpak4mac-retrodeck \
  -o short-iso --no-pager
sudo journalctl -b -u lightdm -o short-iso --no-pager | tail -80
ps -eo pid,user,etimes,args | grep -E \
  '[l]ightdm|[X]org|[x]fce4-session|[f]latpak4mac-retrodeck|[r]etrodeck'
```

The `flatpak4mac-session-switch` events show the command, LightDM restart,
and first observed target session processes. The `flatpak4mac-retrodeck`
events show when the dedicated session starts, when Flatpak is launched, and
when the application exits. They do not measure first rendered frame or GPU
initialisation independently; these require additional application-level
instrumentation.

## Slowness and failures

* Compare the time between LightDM restart and the RetroDECK session start:
  a large gap suggests display manager or Xorg setup.
* Compare RetroDECK session start to `Starting RetroDECK Flatpak`: a large gap
  suggests mount checking or session initialisation.
* If the Flatpak process remains but the screen is black, gather RetroDECK's
  own logs before changing rendering. This update intentionally does not
  enable software rendering or alter the VirtIO GPU configuration.
* In XFCE, additional startup services may run after `xfce4-session` appears.
* Guest boot `systemd-analyze blame` is **not** a direct measure of session
  switching latency.

The previous unconditional four-second post-RetroDECK exit wait is replaced
with observation of a change in the LightDM main process ID. The fail-safe has a 15s
maximum if the restart does not happen.
