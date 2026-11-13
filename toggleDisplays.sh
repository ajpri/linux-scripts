#!/bin/bash
# toggleDisplays.sh - toggle two GNOME Wayland displays between EXTEND and MIRROR.
#
# In EXTEND, the left display sits beside the primary right display.
# In MIRROR, both displays share a resolution and position.
#
# Usage:
#   toggleDisplays.sh                Toggle between layouts.
#   toggleDisplays.sh force-extend   Switch to EXTEND.
#   toggleDisplays.sh force-mirror   Switch to MIRROR.
#   toggleDisplays.sh -h | --help    Show usage.
#
# Configuration, by environment variable:
#   TOGGLE_DISPLAYS_RIGHT   Right connector (auto-detected by default)
#   TOGGLE_DISPLAYS_LEFT    Left connector (auto-detected by default)
#   TOGGLE_DISPLAYS_MODE    Mirror resolution (default: 1920x1080)
#   TOGGLE_DISPLAYS_DEBUG   Set to 1 for debug output.
#
# The script reads the live layout and applies changes for this session.
#
# Requirements: Bash, Python 3 with PyGObject, and a GNOME Wayland session.
#
# Download it with:
#   curl -fL -o toggleDisplays.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/toggleDisplays.sh
#   chmod +x toggleDisplays.sh

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  "")
    target=""
    ;;
  force-extend)
    target="EXTEND"
    ;;
  force-mirror)
    target="MIRROR"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "toggleDisplays: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" &&
      ( -n "${XDG_SESSION_TYPE:-}" || -z "${WAYLAND_DISPLAY:-}" ) ]]; then
  echo "toggleDisplays: run this script from a GNOME Wayland session" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "toggleDisplays: Python 3 with PyGObject is required" >&2
  exit 1
fi

# Use typed D-Bus values and submit both outputs in one configuration.
exec python3 - "$target" "${TOGGLE_DISPLAYS_MODE:-1920x1080}" <<'PY'
import os
import sys

try:
    from gi.repository import Gio, GLib
except ImportError:
    sys.exit("toggleDisplays: Python 3 with PyGObject is required on GNOME Wayland")


DISPLAY_CONFIG = "org.gnome.Mutter.DisplayConfig"
DISPLAY_PATH = "/org/gnome/Mutter/DisplayConfig"


def display_call(bus, method, args=None):
    return bus.call_sync(
        DISPLAY_CONFIG, DISPLAY_PATH, DISPLAY_CONFIG, method, args,
        None, Gio.DBusCallFlags.NONE, 10000, None,
    )


def select_outputs(monitors, active):
    right = os.environ.get("TOGGLE_DISPLAYS_RIGHT") or None
    left = os.environ.get("TOGGLE_DISPLAYS_LEFT") or None
    for side, connector in (("right", right), ("left", left)):
        if connector and connector not in monitors:
            found = ", ".join(monitors) or "none"
            raise ValueError(f"{side} display {connector} unavailable; found: {found}")
    if right and left:
        if right == left:
            raise ValueError("left and right connectors must be different")
        return left, right
    if right or left:
        selected = right or left
        candidates = (active.keys() & monitors.keys()) - {selected}
        if not candidates:
            candidates = monitors.keys() - {selected}
        if len(candidates) == 1:
            other = candidates.pop()
            return left or other, right or other
    elif len(active) == 2:
        first, second = active
        if active[first] is active[second]:
            # A mirror group has no horizontal positions. We put right first.
            return second, first
        if active[first][0] != active[second][0]:
            left, right = sorted(active, key=lambda connector: active[connector][0])
            return left, right
    found = ", ".join(active) or "none"
    raise ValueError(
        f"cannot determine left and right from active displays ({found}); "
        "set TOGGLE_DISPLAYS_LEFT and TOGGLE_DISPLAYS_RIGHT"
    )


def select_mode(connector, modes, resolution):
    if resolution is None:
        preferred = next((mode for mode in modes if mode[6].get("is-preferred")), None)
        if preferred is None:
            raise ValueError(f"{connector} has no preferred mode")
        return preferred
    candidates = [mode for mode in modes if f"{mode[1]}x{mode[2]}" == resolution]
    if not candidates:
        raise ValueError(f"{connector} does not support {resolution}")
    return max(candidates, key=lambda mode: (
        mode[6].get("is-current", False),
        mode[6].get("is-preferred", False),
        mode[6].get("refresh-rate-mode") != "variable",
        mode[3],
    ))


def toggle(requested, resolution):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    serial, physical, logical, properties = display_call(bus, "GetCurrentState").unpack()
    monitors = {
        spec[0]: (modes, props) for spec, modes, props in physical
        if not props.get("is-for-lease")
    }
    active = {spec[0]: group for group in logical for spec in group[5]}
    left, right = select_outputs(monitors, active)
    if active.keys() - {left, right}:
        raise ValueError("another display is active; this script configures only two displays")

    mirrored = left in active and active[left] is active.get(right)
    target = requested or ("EXTEND" if mirrored else "MIRROR")
    layout_mode = properties.get("layout-mode", 1)
    outputs, scales, transforms, modes = {}, {}, {}, {}
    mirror_resolution = resolution if target == "MIRROR" else None
    for connector in (left, right):
        available_modes, monitor_props = monitors[connector]
        mode = select_mode(connector, available_modes, mirror_resolution)
        mode_props = {
            key: GLib.Variant("u", monitor_props[key])
            for key in ("color-mode", "rgb-range") if key in monitor_props
        }
        if "is-underscanning" in monitor_props:
            mode_props["underscanning"] = GLib.Variant("b", monitor_props["is-underscanning"])
        outputs[connector] = (connector, mode[0], mode_props)
        modes[connector] = mode
        group = active.get(connector)
        scales[connector] = group[2] if group else mode[4]
        transforms[connector] = group[3] if group else 0

    left_mode, right_mode = modes[left], modes[right]
    if target == "MIRROR" or properties.get("global-scale-required"):
        common_scales = set(left_mode[5]).intersection(right_mode[5])
        if not common_scales:
            raise ValueError("the selected modes have no common display scale")
        scale = min(common_scales, key=lambda value: (abs(value - scales[right]), value))
        scales = {left: scale, right: scale}

    if target == "MIRROR":
        config = [(0, 0, scales[right], transforms[right], True, [outputs[right], outputs[left]])]
    else:
        for connector in (left, right):
            mode = modes[connector]
            if scales[connector] not in mode[5]:
                scales[connector] = mode[4]
        left_width = left_mode[2] if transforms[left] % 2 else left_mode[1]
        if layout_mode == 1:  # Logical positions account for scaling.
            left_width = int(left_width / scales[left] + 0.5)
        config = [
            (0, 0, scales[left], transforms[left], False, [outputs[left]]),
            (left_width, 0, scales[right], transforms[right], True, [outputs[right]]),
        ]

    options = {}
    if properties.get("supports-changing-layout-mode"):
        options["layout-mode"] = GLib.Variant("u", layout_mode)
    leased = [spec for spec, _, props in physical if props.get("is-for-lease")]
    if leased:
        options["monitors-for-lease"] = GLib.Variant("a(ssss)", leased)
    if os.environ.get("TOGGLE_DISPLAYS_DEBUG") == "1":
        print(f"[debug] GNOME left={left} right={right} mirrored={mirrored} target={target}", file=sys.stderr)
        print(f"[debug] {target} modes: {outputs[left][1]}, {outputs[right][1]}", file=sys.stderr)
    # Method 1 applies for this session without overwriting GNOME's saved layout.
    args = GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (serial, 1, config, options))
    display_call(bus, "ApplyMonitorsConfig", args)
    print(f"Switched to {target}")


try:
    toggle(sys.argv[1], sys.argv[2])
except (GLib.Error, ValueError) as error:
    sys.exit(f"toggleDisplays: GNOME Wayland: {error}")
PY
