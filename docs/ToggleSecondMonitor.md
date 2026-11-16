# ToggleSecondMonitor.sh

[Back to script index](../README.md) · [Script source](../ToggleSecondMonitor.sh)

Switches a GNOME Wayland desktop between one display and two extended displays.
When both displays are active, it disables the second display. Run it again to
enable the second display to the left of the primary. The script uses the live
layout and applies temporary changes for the current session.

```bash
./ToggleSecondMonitor.sh
./ToggleSecondMonitor.sh --help
```

## Display configuration

Run from your GNOME Wayland session with access to its D-Bus session bus. The
script uses Mutter's display configuration API through Python 3 and PyGObject.
The package is `python3-gobject` on Fedora and `python3-gi` on Debian and Ubuntu.

With two connected displays, the script keeps GNOME's primary display and
toggles the other one. If the primary is a mirror group, it keeps the first
connector in that group by default. Run `gdctl show` where available to list
connectors. Use `SECOND_MONITOR_KEEP` to choose the display to keep and
`SECOND_MONITOR_TOGGLE` to select the second display when several are connected.

```bash
SECOND_MONITOR_KEEP=DP-1 SECOND_MONITOR_TOGGLE=HDMI-1 ./ToggleSecondMonitor.sh
```

The display to keep must already be active. It becomes the primary display and
retains its current mode, rotation, and supported scale. The script stops if
any display outside the selected pair is active.

To switch between mirrored and extended layouts, see [toggleDisplays.sh](toggleDisplays.md).
