#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [-y] [--no-autoremove]\n' "${0##*/}"
    printf 'Update system packages, Flatpaks, Snaps, and supported yt-dlp releases.\n'
    printf '  -y, --assume-yes  Approve package updates and removal of unused dependencies.\n'
    printf '  --no-autoremove   Skip removal of unused packages and Flatpak runtimes.\n'
    printf '  -h, --help        Show this help.\n'
}

run() {
    local description=$1 status
    shift
    printf '\n%s\n' "$description"
    "$@" || {
        status=$?
        printf 'Failed: %s (exit %s)\n' "$description" "$status" >&2
        exit "$status"
    }
}

update_pacman() {
    local installed status=0
    local -a options=() orphans=()

    if (( assume_yes )); then
        options=(--noconfirm)
    fi
    run 'Refreshing and upgrading Pacman packages' "${as_root[@]}" pacman -Syu "${options[@]}"
    if (( autoremove )); then
        installed=$(pacman -Qdtq 2>&1) || status=$?
        if (( status == 0 )) && [[ -n $installed ]]; then
            mapfile -t orphans <<<"$installed"
            run 'Removing unused Pacman packages' "${as_root[@]}" pacman -R "${options[@]}" -- "${orphans[@]}"
        elif (( status != 0 )) && [[ $status != 1 || -n $installed ]]; then
            printf 'Failed: Listing unused Pacman packages (exit %s)\n%s\n' "$status" "$installed" >&2
            exit "$status"
        fi
    fi
    if type -P paccache >/dev/null; then
        run 'Pruning cached Pacman downloads' "${as_root[@]}" paccache -r
    else
        run 'Cleaning cached Pacman downloads' "${as_root[@]}" pacman -Sc "${options[@]}"
    fi
}

update_zypper() {
    local os_id= operation=update status attempt
    local -a options=()

    if [[ -r /etc/os-release ]]; then
        os_id=$( . /etc/os-release; printf '%s' "${ID:-}" )
    fi
    case "$os_id" in
        opensuse-tumbleweed|opensuse-slowroll) operation=dup ;;
        opensuse-microos|opensuse-aeon|opensuse-kalpa|sle-micro|sl-micro)
            printf 'This system uses transactional updates. Use its transactional updater.\n' >&2
            exit 1
            ;;
    esac
    if (( assume_yes )); then
        options=(--non-interactive)
    fi
    run 'Refreshing Zypper repositories' "${as_root[@]}" zypper "${options[@]}" refresh
    for attempt in 1 2; do
        printf '\nUpgrading Zypper packages (%s)\n' "$operation"
        status=0
        "${as_root[@]}" zypper "${options[@]}" "$operation" || status=$?
        case "$status" in
            0) break ;;
            102) reboot_recommended=1; break ;;
            103) [[ $attempt == 1 ]] && continue ;;
        esac
        printf 'Failed: Upgrading Zypper packages (exit %s)\n' "$status" >&2
        exit "$status"
    done
    run 'Cleaning cached Zypper downloads' "${as_root[@]}" zypper "${options[@]}" clean
}

update_packages() {
    local -a apt_options=() apt_environment=()

    case "$manager" in
        apt-get)
            if (( assume_yes )); then
                apt_environment=(DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1 NEEDRESTART_MODE=l)
                apt_options=(-o Dpkg::Options::=--force-confold)
            fi
            run 'Refreshing APT package lists' "${as_root[@]}" apt-get -o APT::Update::Error-Mode=any update
            run 'Upgrading APT packages' "${as_root[@]}" "${apt_environment[@]}" \
                apt-get "${yes_option[@]}" "${apt_options[@]}" upgrade
            if (( autoremove )); then
                run 'Removing unused APT packages' "${as_root[@]}" "${apt_environment[@]}" \
                    apt-get "${yes_option[@]}" "${apt_options[@]}" autoremove
            fi
            run 'Cleaning obsolete APT downloads' "${as_root[@]}" apt-get autoclean
            ;;
        dnf)
            run 'Refreshing and upgrading DNF packages' "${as_root[@]}" dnf "${yes_option[@]}" --refresh upgrade
            if (( autoremove )); then
                run 'Removing unused DNF packages' "${as_root[@]}" dnf "${yes_option[@]}" autoremove
            fi
            run 'Cleaning cached DNF downloads' "${as_root[@]}" dnf clean packages
            ;;
        yum)
            run 'Expiring YUM package metadata' "${as_root[@]}" yum clean expire-cache
            run 'Upgrading YUM packages' "${as_root[@]}" yum "${yes_option[@]}" update
            if (( autoremove )); then
                run 'Removing unused YUM packages' "${as_root[@]}" yum "${yes_option[@]}" autoremove
            fi
            run 'Cleaning cached YUM downloads' "${as_root[@]}" yum clean packages
            ;;
        pacman) update_pacman ;;
        zypper) update_zypper ;;
    esac
}

update_flatpak_scope() {
    local scope=$1 installed status
    local -a refs=()
    shift

    if (( ! autoremove )); then
        # Passing explicit refs avoids Flatpak's automatic unused-runtime sweep.
        if installed=$("$@" flatpak list "--$scope" --all --columns=ref); then
            [[ -n $installed ]] || return 0
            mapfile -t refs <<<"$installed"
        else
            status=$?
            printf 'Failed: Listing %s Flatpaks (exit %s)\n' "$scope" "$status" >&2
            exit "$status"
        fi
    fi

    run "Updating $scope Flatpaks" "$@" flatpak update "--$scope" "${yes_option[@]}" "${refs[@]}"
    if (( autoremove )); then
        run "Removing unused $scope Flatpak runtimes" "$@" flatpak uninstall "--$scope" --unused "${yes_option[@]}"
    fi
}

update_flatpak() {
    if ! type -P flatpak >/dev/null; then
        return
    fi

    update_flatpak_scope system "${as_root[@]}"
    if (( EUID != 0 )); then
        update_flatpak_scope user
    fi
}

report_reboot() {
    local output status=0
    local -a check=()

    if (( ! reboot_recommended )) && [[ ! -f /run/reboot-required && ! -f /var/run/reboot-required ]]; then
        case "$manager" in
            dnf) check=(dnf needs-restarting --reboothint) ;;
            yum) check=(needs-restarting -r) ;;
            zypper) check=(zypper --non-interactive needs-rebooting) ;;
            *) return 0 ;;
        esac
        output=$("${check[@]}" 2>/dev/null) || status=$?
        if [[ $manager == zypper ]]; then
            [[ $status == 102 ]] || return 0
        else
            # A DNF/YUM reboot hint has status 1 and prints a report to standard output.
            [[ $status == 1 && -n $output ]] || return 0
        fi
    fi

    printf '\nA reboot is recommended to finish applying updates.\n'
}

package_owns_file() {
    case "$manager" in
        apt-get) dpkg-query -S -- "$1" >/dev/null 2>&1 ;;
        dnf|yum|zypper) rpm -qf -- "$1" >/dev/null 2>&1 ;;
        pacman) pacman -Qo -- "$1" >/dev/null 2>&1 ;;
    esac
}

update_yt_dlp() {
    local executable target details
    local release_pattern='\[debug\] yt-dlp version [^[:space:]]+ from yt-dlp/(yt-dlp|yt-dlp-nightly-builds|yt-dlp-master-builds) [^[:cntrl:]]*\((zip|(musl)?linux(_aarch64)?_exe)\)'
    local -a yt_options=(--ignore-config --no-plugin-dirs)

    if (( EUID == 0 )) && [[ -n ${SUDO_USER:-} ]]; then
        printf '\nSkipping yt-dlp when the script is started with sudo.\n'
        return
    fi
    if ! executable=$(type -P yt-dlp); then
        return
    fi
    target=$(readlink -f -- "$executable")
    if package_owns_file "$executable" || { [[ $target != "$executable" ]] && package_owns_file "$target"; }; then
        printf '\nyt-dlp is managed by %s.\n' "$manager"
        return
    fi

    # The version in the debug header identifies the release source and build type.
    if ! details=$("$executable" "${yt_options[@]}" --no-colors --verbose --list-impersonate-targets 2>&1) ||
        [[ ! $details =~ $release_pattern ]]; then
        printf '\nSkipping yt-dlp at %s (installation type unrecognized or managed separately).\n' "$executable"
        return
    fi
    if [[ ! -w $target || ! -w ${target%/*} ]]; then
        printf '\nSkipping yt-dlp at %s (run as the account that can update it).\n' "$target"
        return
    fi

    run 'Updating standalone yt-dlp' "$executable" "${yt_options[@]}" -U
}

assume_yes=0
autoremove=1
reboot_recommended=0
for option in "$@"; do
    case "$option" in
        -y|--assume-yes) assume_yes=1 ;;
        --no-autoremove) autoremove=0 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

manager=
for candidate in apt-get dnf yum pacman zypper; do
    if type -P "$candidate" >/dev/null; then
        manager=$candidate
        break
    fi
done
if [[ -z $manager ]]; then
    printf 'No supported package manager found (APT, DNF, YUM, Pacman, or Zypper).\n' >&2
    exit 1
fi

yes_option=()
as_root=(env)
if (( assume_yes )); then
    yes_option=(-y)
fi
if (( EUID != 0 )); then
    if ! type -P sudo >/dev/null; then
        printf 'System package updates require root privileges or sudo.\n' >&2
        exit 1
    fi
    as_root=(sudo -H)
    if (( assume_yes )); then
        as_root+=(-n)
    fi
fi

update_packages
update_flatpak
if type -P snap >/dev/null; then
    run 'Refreshing installed Snaps' "${as_root[@]}" snap refresh
fi
update_yt_dlp
report_reboot
