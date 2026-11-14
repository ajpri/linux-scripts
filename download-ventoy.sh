#!/bin/bash
# Download the latest stable Ventoy Linux release and refresh its desktop shortcut.
set -euo pipefail

die() {
    printf 'Ventoy: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s DESTINATION_DIRECTORY\n' "${0##*/}"
}

desktop_escape() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//$'\t'/\\t}
    value=${value//$'\r'/\\r}
    value=${value//$'\n'/\\n}
    printf '%s' "$value"
}

refresh_launcher() (
    local architecture gui icon exec_path applications_dir desktop_temp
    architecture=$(uname -m)
    case $architecture in
        i[3-6]86) architecture=i386 ;;
        arm64) architecture=aarch64 ;;
    esac

    gui=$current/VentoyGUI.$architecture
    if [[ ! -f $gui || ! -x $gui ]]; then
        printf 'Ventoy: No bundled GUI executable for %s.\n' "$architecture" >&2
        return 0
    fi

    icon=$current/WebUI/static/img/VentoyLogo.png
    if [[ ! -f $icon ]]; then
        icon=drive-removable-media
    fi

    # Escape the quoted Exec argument before escaping the desktop-entry value.
    exec_path=${gui//\\/\\\\}
    exec_path=${exec_path//\"/\\\"}
    exec_path=${exec_path//\$/\\\$}
    exec_path=${exec_path//\`/\\\`}
    exec_path=${exec_path//%/%%}

    applications_dir=${XDG_DATA_HOME:-$HOME/.local/share}/applications
    mkdir -p -- "$applications_dir"
    desktop_temp=$(mktemp -- "$applications_dir/.ventoy.XXXXXXXX")
    trap 'rm -f -- "$desktop_temp"' EXIT
    cat > "$desktop_temp" <<EOF
[Desktop Entry]
Type=Application
Name=Ventoy
Exec="$(desktop_escape "$exec_path")"
Path=$(desktop_escape "$current")
Icon=$(desktop_escape "$icon")
Terminal=false
Categories=Utility;
EOF
    chmod 644 -- "$desktop_temp"
    mv -fT -- "$desktop_temp" "$applications_dir/ventoy.desktop"
)

restore_directories() {
    if [[ -d $staging/current ]]; then
        if [[ -d $current ]]; then
            mv -T -- "$current" "$extracted" || return 1
        fi
        mv -T -- "$staging/current" "$current" || return 1
    fi
    if [[ -d $staging/previous && ! -e $previous ]]; then
        mv -T -- "$staging/previous" "$previous" || return 1
    fi
}

cleanup() {
    if restore_directories; then
        rm -rf -- "$staging"
    else
        printf 'Ventoy: Could not restore directories. Recovery files are in %s\n' "$staging" >&2
        exit 1
    fi
}

update_ventoy() {
    local release asset tag package url digest archive checksum
    local curl_options=(--disable --fail --silent --show-error --location
        --proto '=https' --proto-redir '=https' --connect-timeout 15 --retry 2)
    release=$(curl "${curl_options[@]}" --max-time 60 \
        https://api.github.com/repos/ventoy/Ventoy/releases/latest)
    asset=$(jq -er '
        select(.draft == false and .prerelease == false)
        | .tag_name as $tag
        | select($tag | test("^v[0-9]+(\\.[0-9]+)+$"))
        | ("ventoy-" + ($tag | ltrimstr("v"))) as $package
        | [.assets[] | select(.name == ($package + "-linux.tar.gz"))]
        | select(length == 1) | .[0]
        | select(.digest | type == "string" and test("^sha256:[a-f0-9]{64}$"))
        | [$tag, $package, .browser_download_url, .digest] | @tsv
    ' <<< "$release") || die 'Latest stable release has no matching Linux archive with a SHA-256 digest.'
    IFS=$'\t' read -r tag package url digest <<< "$asset"
    [[ $url == "https://github.com/ventoy/Ventoy/releases/download/$tag/$package-linux.tar.gz" ]] \
        || die 'Unexpected Linux archive download URL.'

    if [[ -f $current/Ventoy2Disk.sh && -f $current/.ventoy-release && ! -L $current/.ventoy-release ]] \
        && [[ $(< "$current/.ventoy-release") == "$digest" ]]; then
        printf 'Ventoy %s is already current.\n' "${tag#v}"
        return 0
    fi

    staging=$(mktemp -d -- "$destination/.ventoy-download.XXXXXXXX")
    extracted=$staging/unpack/$package

    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    archive=$staging/$package-linux.tar.gz
    curl "${curl_options[@]}" --max-time 900 --output "$archive" "$url"
    checksum=$(sha256sum < "$archive")
    [[ ${checksum%% *} == "${digest#sha256:}" ]] || die 'Downloaded archive failed SHA-256 verification.'

    mkdir -- "$staging/unpack"
    tar --extract --gzip --file "$archive" --directory "$staging/unpack" --no-same-owner
    [[ -d $extracted && ! -L $extracted && -f $extracted/Ventoy2Disk.sh && ! -L $extracted/Ventoy2Disk.sh ]] \
        || die 'Archive did not contain the expected Ventoy package.'
    [[ ! -e $extracted/.ventoy-release && ! -L $extracted/.ventoy-release ]] \
        || die 'Archive already contains a .ventoy-release file.'
    printf '%s\n' "$digest" > "$extracted/.ventoy-release"

    if [[ -f $current/Ventoy2Disk.sh ]]; then
        if [[ -d $previous ]]; then
            mv -T -- "$previous" "$staging/previous"
        fi
        mv -T -- "$current" "$staging/current"
        mv -T -- "$extracted" "$current"
        mv -T -- "$staging/current" "$previous"
    else
        mv -T -- "$extracted" "$current"
    fi

    printf 'Downloaded Ventoy %s to %s\n' "${tag#v}" "$current"
}

if [[ $# == 1 && ( $1 == -h || $1 == --help ) ]]; then
    usage
    exit 0
fi
if [[ $# != 1 || -z $1 ]]; then
    usage >&2
    exit 2
fi

for command in curl jq flock tar gzip sha256sum; do
    command -v "$command" >/dev/null || die "Required command missing: $command"
done

mkdir -p -- "$1"
destination=$(realpath -- "$1")
current=$destination/Ventoy
previous=$destination/Ventoy-previous

exec {lock_fd}<"$destination"
flock -x "$lock_fd"

# Accept empty directories and existing Ventoy packages. Protect unrelated data.
shopt -s dotglob nullglob
for directory in "$current" "$previous"; do
    if [[ -L $directory || ( -e $directory && ! -d $directory ) ]]; then
        die "Expected a directory at $directory"
    fi
    entries=("$directory"/*)
    if (( ${#entries[@]} )) && [[ ! -f $directory/Ventoy2Disk.sh || -L $directory/Ventoy2Disk.sh ]]; then
        die "Directory contains files but does not look like a Ventoy package: $directory"
    fi
done

update_ventoy
refresh_launcher
