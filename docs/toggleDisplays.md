# toggleDisplays.sh

[Back to script index](../README.md) · [Script source](../toggleDisplays.sh)

Toggles two GNOME Wayland displays between EXTEND and MIRROR. In EXTEND, the left display sits beside the primary right display. In MIRROR, both displays share a resolution and position.

```bash
./toggleDisplays.sh
./toggleDisplays.sh force-extend
./toggleDisplays.sh force-mirror
```

Use `TOGGLE_DISPLAYS_MODE` to set a mirror resolution both displays support. The default is `1920x1080`. Set `TOGGLE_DISPLAYS_DEBUG=1` to log the chosen outputs and target.

## Display configuration

Run from your GNOME desktop session with access to its D-Bus session bus. The script uses Mutter's display configuration API through Python 3 and PyGObject. The package is `python3-gobject` on Fedora and `python3-gi` on Debian and Ubuntu. On systems with `gdctl`, run `gdctl show` to list connectors and `gdctl show --modes` to list supported resolutions. You can also query the session directly.

```bash
gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.gnome.Mutter.DisplayConfig.GetCurrentState
```

With two active displays in a side-by-side layout, the script detects left and right from their current positions. Other connected displays can stay inactive. In a mirrored layout, it treats the first member of the mirror group as the right display, which is the order the script uses when setting up mirroring. Set the connectors explicitly to choose a specific order for a mirror group created in GNOME Settings, or to select a pair when the live layout is ambiguous. The script stops if the operation would turn off another active display.

```bash
TOGGLE_DISPLAYS_LEFT=DP-1 TOGGLE_DISPLAYS_RIGHT=HDMI-1 ./toggleDisplays.sh
```

The toggle uses the live layout, so changes made in GNOME Settings are picked up on the next run. Changes made by the script are temporary for the session. EXTEND uses each display's preferred mode. MIRROR uses the configured resolution, the right display's rotation, and a scale supported by both displays. When extending from a mirror group, both displays start from its shared scale and rotation.

## Download

```bash
curl -fL -o toggleDisplays.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/toggleDisplays.sh
chmod +x toggleDisplays.sh
```
