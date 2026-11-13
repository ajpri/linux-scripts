#!/bin/bash
# Download the latest stable OpenRCT2 AppImage and update its GNOME shortcut.
set -euo pipefail

die() {
    printf 'OpenRCT2: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s DESTINATION_DIRECTORY\n' "${0##*/}"
}

if [[ $# == 1 && ( $1 == -h || $1 == --help ) ]]; then
    usage
    exit 0
fi
if [[ $# != 1 || -z $1 ]]; then
    usage >&2
    exit 2
fi

for command in curl jq flock; do
    command -v "$command" >/dev/null || die "Required command missing: $command"
done

case $(uname -m) in
    x86_64) architecture=x86_64 ;;
    aarch64) architecture=arm64 ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
esac

destination=$1
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
applications_dir=$data_home/applications
icon_dir=$data_home/icons/hicolor/256x256/apps
mkdir -p -- "$destination" "$applications_dir"
destination=$(realpath -- "$destination")
current=$destination/OpenRCT2.AppImage
previous=$destination/OpenRCT2-previous.AppImage
desktop_file=$applications_dir/openrct2-appimage.desktop

# Serialize updates to the same directory without leaving a lock file behind.
exec {lock_fd}<"$destination"
flock -x "$lock_fd"

for image in "$current" "$previous"; do
    if [[ -L $image || ( -e $image && ! -f $image ) ]]; then
        die "Expected a regular file at $image"
    fi
done

curl_options=(--disable --fail --silent --show-error --location
    --proto '=https' --proto-redir '=https' --connect-timeout 15 --retry 2)
release=$(curl "${curl_options[@]}" --max-time 60 \
    https://api.github.com/repos/OpenRCT2/OpenRCT2/releases/latest)
asset=$(jq -er --arg suffix "-linux-$architecture.AppImage" '
    select(.draft == false and .prerelease == false)
    | [.assets[] | select(.name | endswith($suffix))]
    | select(length == 1) | .[0]
    | select(.digest | type == "string" and test("^sha256:[a-f0-9]{64}$"))
    | [.browser_download_url, .digest] | @tsv
' <<< "$release") || die "Latest stable release has no matching AppImage with a SHA-256 digest for $architecture."
IFS=$'\t' read -r url digest <<< "$asset"
[[ $url == https://github.com/OpenRCT2/OpenRCT2/releases/download/* ]] \
    || die 'Unexpected AppImage download URL.'

matches_digest() {
    local checksum
    checksum=$(sha256sum < "$1") || return 1
    [[ ${checksum%% *} == "${digest#sha256:}" ]]
}

staging=
desktop_temp=
icon_temp=
cleanup() {
    [[ -z $staging ]] || rm -rf -- "$staging"
    [[ -z $desktop_temp ]] || rm -f -- "$desktop_temp"
    [[ -z $icon_temp ]] || rm -rf -- "$icon_temp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -f $current ]] && matches_digest "$current"; then
    chmod u+x -- "$current"
else
    staging=$(mktemp -d -- "$destination/.openrct2.XXXXXXXX")
    download=$staging/OpenRCT2.AppImage
    curl "${curl_options[@]}" --max-time 900 --output "$download" "$url"
    matches_digest "$download" || die 'Downloaded AppImage failed SHA-256 verification.'
    chmod u+x -- "$download"
    if [[ -f $current ]]; then
        cp -p --reflink=auto -- "$current" "$staging/previous.AppImage"
        chmod u+x -- "$staging/previous.AppImage"
        mv -fT -- "$staging/previous.AppImage" "$previous"
    fi
    mv -fT -- "$download" "$current"
    printf 'Installed %s\n' "$current"
fi

icon=applications-games
mkdir -p -- "$icon_dir"
icon_temp=$(mktemp -d -- "$icon_dir/.openrct2.XXXXXXXX")
# Extract only the bundled icon from the verified AppImage, without starting the game.
if (cd -- "$icon_temp" && "$current" --appimage-extract openrct2.png >/dev/null) \
    && [[ -f $icon_temp/squashfs-root/openrct2.png && ! -L $icon_temp/squashfs-root/openrct2.png ]]; then
    install -m 644 -- "$icon_temp/squashfs-root/openrct2.png" "$icon_temp/openrct2-appimage.png"
    mv -fT -- "$icon_temp/openrct2-appimage.png" "$icon_dir/openrct2-appimage.png"
else
    printf 'OpenRCT2: Could not extract the bundled application icon.\n' >&2
fi
if [[ -f $icon_dir/openrct2-appimage.png ]]; then
    # An absolute path lets GNOME load the PNG directly through the desktop entry.
    icon_path=$(realpath -- "$icon_dir/openrct2-appimage.png")
    icon=$(printf '%s' "$icon_path" | sed 's/\\/\\\\/g; s/\t/\\t/g; s/\r/\\r/g')
    icon=${icon//$'\n'/\\n}
fi

# Escape both the desktop-entry string and its quoted Exec argument.
exec_path=$(printf '%s' "$current" | sed 's/\\/\\\\\\\\/g; s/["$`]/\\\\&/g; s/%/%%/g; s/\t/\\t/g; s/\r/\\r/g')
exec_path=${exec_path//$'\n'/\\n}
desktop_temp=$(mktemp -- "$applications_dir/.openrct2-appimage.XXXXXXXX")
cat > "$desktop_temp" <<EOF
[Desktop Entry]
Type=Application
Name=OpenRCT2
Exec="$exec_path"
Icon=$icon
Terminal=false
Categories=Game;Simulation;
EOF
chmod 644 -- "$desktop_temp"
mv -fT -- "$desktop_temp" "$desktop_file"
