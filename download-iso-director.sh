#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || -z $1 ]]; then
    printf 'Usage: %s EXISTING_DOWNLOAD_DIRECTORY\n' "$0" >&2
    exit 2
fi

SAVE_PATH=$1
DOWNLOADER="$(dirname -- "${BASH_SOURCE[0]}")/download-iso.sh"
DAY=$(date +%d)

case "$DAY" in
    01) "$DOWNLOADER" fedora --edition workstation -- "$SAVE_PATH" ;;
    02) "$DOWNLOADER" netbootxyz -- "$SAVE_PATH" ;;
    03) "$DOWNLOADER" ubuntu --edition server -- "$SAVE_PATH" ;;
    04) "$DOWNLOADER" winserver --version 2025 -- "$SAVE_PATH" ;;
    05) "$DOWNLOADER" clonezilla -- "$SAVE_PATH" ;;
    06) "$DOWNLOADER" linuxmint --edition cinnamon -- "$SAVE_PATH" ;;
    07) "$DOWNLOADER" xcpng -- "$SAVE_PATH" ;;
    08) "$DOWNLOADER" popos --edition generic -- "$SAVE_PATH" ;;
    09) "$DOWNLOADER" pfsense -- "$SAVE_PATH" ;;
    10) "$DOWNLOADER" debian -- "$SAVE_PATH" ;;
    11) "$DOWNLOADER" win11 --edition pro -- "$SAVE_PATH" ;;
    12) "$DOWNLOADER" arch -- "$SAVE_PATH" ;;
    13) "$DOWNLOADER" truenas -- "$SAVE_PATH" ;;
    14) "$DOWNLOADER" gparted -- "$SAVE_PATH" ;;
    15) "$DOWNLOADER" fedora --edition server -- "$SAVE_PATH" ;;
    16) "$DOWNLOADER" linuxmint --edition xfce -- "$SAVE_PATH" ;;
    17) "$DOWNLOADER" win11 --edition multi -- "$SAVE_PATH" ;;
    18) "$DOWNLOADER" opnsense -- "$SAVE_PATH" ;;
    19) "$DOWNLOADER" qubes -- "$SAVE_PATH" ;;
    20) "$DOWNLOADER" popos --edition nvidia -- "$SAVE_PATH" ;;
    21) "$DOWNLOADER" memtest86plus -- "$SAVE_PATH" ;;
    22) "$DOWNLOADER" ubuntu --edition desktop -- "$SAVE_PATH" ;;
    23) "$DOWNLOADER" winserver --version 2022 -- "$SAVE_PATH" ;;
    24) "$DOWNLOADER" proxmox -- "$SAVE_PATH" ;;
    25) "$DOWNLOADER" linuxmint --edition mate -- "$SAVE_PATH" ;;
    26) "$DOWNLOADER" hbcdpe -- "$SAVE_PATH" ;;
    27) "$DOWNLOADER" chromeosflex -- "$SAVE_PATH" ;;
    28) "$DOWNLOADER" openmediavault -- "$SAVE_PATH" ;;
    29) : ;;  # Open
    30) : ;;  # Open
    31) : ;;  # Open
esac
