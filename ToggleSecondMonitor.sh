#!/bin/bash
# ToggleSecondMonitor.sh - switch between one display and two extended displays.
# Requirements: Bash, Python 3 with PyGObject, and a GNOME Wayland session.
set -euo pipefail

usage() {
  printf '%s\n' 'Usage: ToggleSecondMonitor.sh [-h|--help]' \
    'Toggle between the primary display alone and two extended displays.' \
    'Set SECOND_MONITOR_KEEP and SECOND_MONITOR_TOGGLE to select connectors.'
}

case "$#:${1:-}" in
  0:) ;;
  1:-h|1:--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" &&
      ( -n "${XDG_SESSION_TYPE:-}" || -z "${WAYLAND_DISPLAY:-}" ) ]]; then
  printf '%s\n' 'ToggleSecondMonitor: run from a GNOME Wayland session' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' 'ToggleSecondMonitor: Python 3 with PyGObject is required' >&2
  exit 1
fi

# Use typed D-Bus values and submit the layout in one configuration.
exec python3 - <<'PY'
import os
import sys

try:
    from gi.repository import Gio, GLib
except ImportError:
    sys.exit("ToggleSecondMonitor: Python 3 with PyGObject is required")


DISPLAY_CONFIG = "org.gnome.Mutter.DisplayConfig"
DISPLAY_PATH = "/org/gnome/Mutter/DisplayConfig"


def display_call(bus, method, args=None):
    return bus.call_sync(
        DISPLAY_CONFIG, DISPLAY_PATH, DISPLAY_CONFIG, method, args,
        None, Gio.DBusCallFlags.NONE, 10000, None,
    )


def output_settings(connector, monitors, active):
    modes, properties = monitors[connector]
    mode = next((item for item in modes if item[6].get("is-current")), None)
    if mode is None:
        mode = next((item for item in modes if item[6].get("is-preferred")), None)
    if mode is None:
        raise ValueError(f"{connector} has no current or preferred mode")

    group = active.get(connector)
    scale = group[2] if group and group[2] in mode[5] else mode[4]
    transform = group[3] if group else 0
    output_props = {
        key: GLib.Variant("u", properties[key])
        for key in ("color-mode", "rgb-range") if key in properties
    }
    if "is-underscanning" in properties:
        output_props["underscanning"] = GLib.Variant("b", properties["is-underscanning"])
    return mode, scale, transform, (connector, mode[0], output_props)


def toggle():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    serial, physical, logical, properties = display_call(bus, "GetCurrentState").unpack()
    monitors = {
        spec[0]: (modes, props) for spec, modes, props in physical
        if not props.get("is-for-lease")
    }
    active = {spec[0]: group for group in logical for spec in group[5]}
    primary = next((group[5][0][0] for group in logical if group[4]), None)
    keep = os.environ.get("SECOND_MONITOR_KEEP") or primary
    if keep not in monitors or keep not in active:
        raise ValueError("the display to keep must be connected and active")

    second = os.environ.get("SECOND_MONITOR_TOGGLE")
    if not second:
        candidates = monitors.keys() - {keep}
        if len(candidates) != 1:
            raise ValueError("set SECOND_MONITOR_TOGGLE to select the second display")
        second = candidates.pop()
    if second == keep or second not in monitors:
        raise ValueError("the second display must be a different connected connector")
    if active.keys() - {keep, second}:
        raise ValueError("another display is active; leaving the layout alone")

    layout_mode = properties.get("layout-mode", 1)
    _, keep_scale, keep_transform, keep_output = output_settings(keep, monitors, active)
    if second in active:
        config = [(0, 0, keep_scale, keep_transform, True, [keep_output])]
        message = f"Disabled {second}; kept {keep} active"
    else:
        mode, scale, transform, output = output_settings(second, monitors, active)
        if properties.get("global-scale-required"):
            if keep_scale not in mode[5]:
                raise ValueError("the second display cannot use the primary display's scale")
            scale = keep_scale
        width = mode[2] if transform % 2 else mode[1]
        if layout_mode == 1:
            width = int(width / scale + 0.5)
        config = [
            (0, 0, scale, transform, False, [output]),
            (width, 0, keep_scale, keep_transform, True, [keep_output]),
        ]
        message = f"Enabled {second} to the left of {keep}"

    options = {}
    if properties.get("supports-changing-layout-mode"):
        options["layout-mode"] = GLib.Variant("u", layout_mode)
    leased = [spec for spec, _, props in physical if props.get("is-for-lease")]
    if leased:
        options["monitors-for-lease"] = GLib.Variant("a(ssss)", leased)
    # Method 1 applies the layout for the current session.
    args = GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (serial, 1, config, options))
    display_call(bus, "ApplyMonitorsConfig", args)
    print(message)


try:
    toggle()
except (GLib.Error, ValueError) as error:
    sys.exit(f"ToggleSecondMonitor: {error}")
PY
