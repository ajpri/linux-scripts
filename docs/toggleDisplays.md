# toggleDisplays.sh

[Back to script index](../README.md) · [Script source](../toggleDisplays.sh)

Toggles two displays between EXTEND and MIRROR using xrandr. The right display stays primary. In EXTEND, the left display sits to the left of the right display. In MIRROR, both displays use the same mode and position.

With no argument, it flips the saved state in `${XDG_CACHE_HOME:-$HOME/.cache}/toggleDisplays.state`. On the first run, with no saved state, it detects the current layout and picks the opposite. `force-extend` and `force-mirror` override the toggle.

Display names, the mirror mode, and debug output are configurable by environment variable, with defaults of DisplayPort-0, DisplayPort-1, and 1920x1080:

```bash
TOGGLE_DISPLAYS_RIGHT=DisplayPort-0 TOGGLE_DISPLAYS_LEFT=DisplayPort-1 TOGGLE_DISPLAYS_MODE=1920x1080 ./toggleDisplays.sh
```

Download it with:

```bash
curl -fL -o toggleDisplays.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/toggleDisplays.sh
chmod +x toggleDisplays.sh
```
