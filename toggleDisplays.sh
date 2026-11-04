#!/bin/bash
# toggleDisplays.sh - toggle two displays between EXTEND and MIRROR.
#
# Right display stays primary. In EXTEND, the left display sits to the
# left of the right display. In MIRROR, both displays use the same mode
# and position.
#
# Usage:
#   toggleDisplays.sh                Toggle based on the saved state,
#                                    or the current layout on first run.
#   toggleDisplays.sh force-extend   Switch to EXTEND.
#   toggleDisplays.sh force-mirror   Switch to MIRROR.
#   toggleDisplays.sh -h | --help    Show usage.
#
# Configuration, by environment variable:
#   TOGGLE_DISPLAYS_RIGHT   Right display name (default: DisplayPort-0)
#   TOGGLE_DISPLAYS_LEFT    Left display name (default: DisplayPort-1)
#   TOGGLE_DISPLAYS_MODE    Shared mode for mirror (default: 1920x1080)
#   TOGGLE_DISPLAYS_DEBUG   Set to 1 for debug output.
#
# State is saved in ${XDG_CACHE_HOME:-$HOME/.cache}/toggleDisplays.state
# and is only updated when xrandr succeeds.
#
# Requirements: Linux, Bash, xrandr.
#
# Download it with:
#   curl -fL -o toggleDisplays.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/toggleDisplays.sh
#   chmod +x toggleDisplays.sh

set -u

rightOut="${TOGGLE_DISPLAYS_RIGHT:-DisplayPort-0}"
leftOut="${TOGGLE_DISPLAYS_LEFT:-DisplayPort-1}"
commonMode="${TOGGLE_DISPLAYS_MODE:-1920x1080}"

stateDir="${XDG_CACHE_HOME:-$HOME/.cache}"
stateFile="$stateDir/toggleDisplays.state"

debug() {
  if [[ "${TOGGLE_DISPLAYS_DEBUG:-0}" == "1" ]]; then
    echo "[debug] $*" >&2
  fi
}

die() {
  echo "toggleDisplays: $*" >&2
  exit 1
}

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# //; s/^#$//'
}

# usage: toggleDisplays.sh [force-extend|force-mirror|-h|--help]
target=""
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

command -v xrandr >/dev/null 2>&1 || die "xrandr not found"

debug "rightOut=$rightOut leftOut=$leftOut commonMode=$commonMode"
debug "stateFile=$stateFile"

mkdir -p "$stateDir" || die "cannot create state directory: $stateDir"

# isConnected returns 0 when the named output is connected.
isConnected() {
  local outName="$1"
  xrandr --query | awk -v o="$outName" '$1==o && $2=="connected" { found=1; exit } END { exit !found }'
}

isConnected "$rightOut" || die "right display not connected: $rightOut"
isConnected "$leftOut" || die "left display not connected: $leftOut"

# getGeom returns the full WxH+X+Y token for a connected output.
getGeom() {
  local outName="$1"
  xrandr --query | awk -v o="$outName" '
    $1==o && $2=="connected" {
      for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) { print $i; exit }
    }'
}

# isMirrored uses a strict comparison of both outputs' geometry tokens.
isMirrored() {
  local gR gL
  gR="$(getGeom "$rightOut")"
  gL="$(getGeom "$leftOut")"
  debug "current geometry right=$gR left=$gL"
  [[ -n "$gR" && "$gR" == "$gL" ]]
}

# Decide the target when no force argument was given: flip the saved
# state, or, with no usable saved state, pick the opposite of the
# current layout.
if [[ -z "$target" ]]; then
  if [[ -f "$stateFile" ]]; then
    prev="$(tr -d '[:space:]' < "$stateFile" 2>/dev/null || true)"
    debug "previous state=$prev"
    if [[ "$prev" == "EXTEND" ]]; then
      target="MIRROR"
    elif [[ "$prev" == "MIRROR" ]]; then
      target="EXTEND"
    elif isMirrored; then
      target="EXTEND"
    else
      target="MIRROR"
    fi
  else
    if isMirrored; then
      target="EXTEND"
    else
      target="MIRROR"
    fi
  fi
fi

debug "target=$target"

if [[ "$target" == "EXTEND" ]]; then
  debug "switching to EXTEND with right primary and left to the left"
  # A brief off for the left output helps unreliable drivers settle.
  xrandr --output "$leftOut" --off || true
  xrandr \
    --output "$rightOut" --auto --primary \
    --output "$leftOut"  --auto --left-of "$rightOut"
  rc=$?
  debug "xrandr extend exitCode=$rc"
  if [[ $rc -ne 0 ]]; then
    die "xrandr failed to switch to EXTEND (exit $rc); state unchanged"
  fi
  echo "EXTEND" > "$stateFile"
else
  debug "switching to MIRROR at $commonMode"
  # Force both to the same mode and position, right stays primary.
  # A brief off for the left output helps avoid stale geometry.
  xrandr --output "$leftOut" --off || true
  xrandr \
    --output "$rightOut" --mode "$commonMode" --primary --pos 0x0 \
    --output "$leftOut"  --mode "$commonMode" --same-as "$rightOut"
  rc=$?
  debug "xrandr mirror exitCode=$rc"
  if [[ $rc -ne 0 ]]; then
    die "xrandr failed to switch to MIRROR (exit $rc); state unchanged"
  fi
  echo "MIRROR" > "$stateFile"
fi

echo "Switched to $target"
debug "done"
