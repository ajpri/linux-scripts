#!/bin/bash
# Back up or restore the current user's Google Chrome Default profile on Linux.
# Usage: ./chrome-backup.sh [--dry-run]
# Backup layout: PARENT/chrome-backup-yy-mm-dd.zip (ZIP is the default).
# Uncompressed backups: PARENT/chrome-backup-yy-mm-dd/{Default/,Local State}.
# --dry-run previews restore changes without writing to the Chrome profile.
# Requirements: Bash, rsync, procps (pkill/pgrep), GNU coreutils, findutils.
# ZIP support additionally requires zip and unzip (including zipinfo).
# Run as your normal desktop user. Keep Chrome closed throughout the operation.

set -euo pipefail
export LC_ALL=C
umask 077

CHROME_ROOT="${HOME:?HOME must be set}/.config/google-chrome"
CHROME_TIMEOUT=15
CHROME_PROCESSES='chrome|chrome_crashpad'
DRY_RUN=0
TEMP_DIRS=()
ACTIVE_PID=''
STATUS_PID=''
CACHE_EXCLUDES=(--exclude='Cache/' --exclude='Code Cache/' --exclude='GPUCache/')

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

trap 'printf "\nCancelled. An interrupted copy may be incomplete.\n" >&2; exit 130' INT
trap 'printf "\nTerminated. An interrupted copy may be incomplete.\n" >&2; exit 143' TERM
cleanup() {
    local directory
    if [[ -n $STATUS_PID ]]; then
        kill "$STATUS_PID" 2>/dev/null || true
        wait "$STATUS_PID" 2>/dev/null || true
    fi
    if [[ -n $ACTIVE_PID ]]; then
        kill -TERM "$ACTIVE_PID" 2>/dev/null || true
        wait "$ACTIVE_PID" 2>/dev/null || true
    fi
    for directory in "${TEMP_DIRS[@]}"; do
        rm -rf -- "$directory"
    done
}
trap cleanup EXIT

# Long checks/compression have no reliable percentage; show elapsed time instead.
# Keep diagnostics visible and return the command's status unchanged.
run_with_status() {
    local label=$1 started=$SECONDS status elapsed
    shift
    printf '%s...\n' "$label" >&2
    "$@" &
    ACTIVE_PID=$!
    (
        while true; do
            sleep 1
            elapsed=$((SECONDS - started))
            if [[ -t 2 ]]; then
                printf '\r%s... %ss elapsed' "$label" "$elapsed" >&2
            elif (( elapsed % 5 == 0 )); then
                printf '%s... %ss elapsed\n' "$label" "$elapsed" >&2
            fi
        done
    ) &
    STATUS_PID=$!
    if wait "$ACTIVE_PID"; then status=0; else status=$?; fi
    ACTIVE_PID=''
    kill "$STATUS_PID" 2>/dev/null || true
    wait "$STATUS_PID" 2>/dev/null || true
    STATUS_PID=''
    if [[ -t 2 ]]; then printf '\r\033[K' >&2; fi
    if [[ $status == 0 ]]; then
        printf '%s completed (%ss).\n' "$label" "$((SECONDS - started))" >&2
    else
        printf '%s failed (status %s).\n' "$label" "$status" >&2
    fi
    return "$status"
}

show_help() {
    cat <<HELP
Usage: $0 [--dry-run]

Select backup, restore, or quit from the menu.
Backups contain Default/ and Local State; cache directories are excluded.
Choose a parent destination folder. A dated chrome-backup-yy-mm-dd subfolder
is created inside it; repeated backups add -2, -3, etc. to avoid overwriting.
ZIP is the default: create the ZIP inside that same parent folder and remove
the dated subfolder after verification. Choose no to keep an uncompressed backup.
ZIP failures preserve the dated subfolder. Existing parent-folder files are kept.
Restore accepts a folder or a ZIP with Default/ and Local State at its root.
Restore replaces Default's contents (including removing old caches) and Local State.
--dry-run previews restore changes; backup is unavailable in this mode.
Chrome is force-closed for both operations, including a restore preview.
Copies show rsync byte progress, speed, and time; long checks and ZIP operations
show elapsed time. During compression each dot represents about 10 MiB processed.
Run as your normal desktop user, without sudo. Keep Chrome closed until finished.
HELP
}

chrome_running() {
    local status
    if pgrep -u "$UID" -x "$CHROME_PROCESSES" >/dev/null; then
        return 0
    else
        status=$?
        [[ $status == 1 ]] || die "Could not check Chrome processes (pgrep status $status)."
        return 1
    fi
}

close_chrome() {
    local status deadline
    printf 'Force-closing Google Chrome for the current user...\n'
    if pkill -KILL -u "$UID" -x "$CHROME_PROCESSES"; then
        :
    else
        status=$?
        [[ $status == 1 ]] || die "Could not close Chrome (pkill status $status)."
    fi
    deadline=$((SECONDS + CHROME_TIMEOUT))
    while chrome_running; do
        (( SECONDS < deadline )) || die "Chrome is still running after ${CHROME_TIMEOUT}s; refusing to copy."
        sleep 1
    done
}

read_path() {
    local prompt=$1 value
    if ! IFS= read -r -p "$prompt" value; then
        printf '\nInput closed.\n'
        exit 0
    fi
    [[ -n $value ]] || die 'Path must not be empty.'
    # Expand a typed ~/ without eval; preserve spaces and shell metacharacters.
    case $value in
        '~') value=$HOME ;;
        '~/'*) value="$HOME/${value:2}" ;;
    esac
    REPLY=$(realpath -m -- "$value") || die 'Could not resolve path.'
}

reject_overlap() {
    local backup=$1 live
    live=$(realpath -m -- "$CHROME_ROOT")
    if [[ $backup == "$live" || $backup == "$live/"* || $live == "$backup/"* || $backup == / ]]; then
        die 'The backup folder and Chrome data folder must not overlap.'
    fi
}

validate_profile() {
    local folder=$1
    [[ -d "$folder/Default" && ! -L "$folder/Default" && -f "$folder/Default/Preferences" ]] ||
        die "No Default profile with a Preferences file found in: $folder"
    [[ -f "$folder/Local State" && ! -L "$folder/Local State" ]] ||
        die "Missing regular Local State file in: $folder"
}

validate_target() {
    local folder=$1
    [[ ! -L "$folder/Default" && ! -L "$folder/Local State" ]] ||
        die 'Refusing to overwrite a symlink at Default or Local State.'
    [[ ! -e "$folder/Default" || -d "$folder/Default" ]] || die 'Default must be a directory.'
    [[ ! -e "$folder/Local State" || -f "$folder/Local State" ]] || die 'Local State must be a regular file.'
}

verify_copy() {
    local source=$1 target=$2 changes work
    printf 'Verifying file contents with rsync checksums...\n'
    work=$(mktemp -d "${TMPDIR:-/tmp}/chrome-verify.XXXXXX")
    TEMP_DIRS+=("$work")
    run_with_status 'Checking profile checksums' rsync -rlnc --delete --delete-excluded --itemize-changes \
        "${CACHE_EXCLUDES[@]}" -- "$source/Default/" "$target/Default/" > "$work/changes" || die 'Profile verification failed.'
    changes=$(< "$work/changes")
    [[ -z $changes ]] || die "Profile verification found differences: $changes"
    run_with_status 'Checking Local State checksum' rsync -lnc --itemize-changes \
        -- "$source/Local State" "$target/Local State" > "$work/changes" ||
        die 'Local State verification failed.'
    changes=$(< "$work/changes")
    [[ -z $changes ]] || die "Local State verification found differences: $changes"
    printf 'Verification passed.\n'
}

print_summary() {
    local folder=$1 size files
    size=$(du -sch -- "$folder/Default" "$folder/Local State")
    size=${size##*$'\n'}
    files=$(find "$folder/Default" "$folder/Local State" -type f -printf '.' | wc -c)
    printf 'Location: %s\nSize: %s\nFiles: %s\n' "$folder" "${size%%$'\t'*}" "$files"
}

require_zip_tools() {
    local command
    for command in zip unzip zipinfo; do
        command -v "$command" >/dev/null || die "ZIP support requires: $command (install zip and unzip)."
    done
}

create_zip() {
    local folder=$1 archive="${1}.zip" work links previous_directory=$PWD
    require_zip_tools
    [[ ! -e $archive && ! -L $archive ]] || die "Archive already exists: $archive"
    links=$(find "$folder/Default" "$folder/Local State" -type l -print -quit)
    [[ -z $links ]] || die 'ZIP backups require a profile without symlinks; the folder backup is still available.'
    work=$(mktemp -d -- "${folder}.zip-work.XXXXXX")
    TEMP_DIRS+=("$work")
    printf 'Creating ZIP archive; the folder backup will be removed after verification...\n'
    printf 'Compression progress: each dot represents about 10 MiB processed.\n'
    cd -- "$folder"
    run_with_status 'Compressing ZIP' zip -q -r -y -dg -ds 10m "$work/backup.zip" Default 'Local State'
    cd -- "$previous_directory"
    printf '\n'
    run_with_status 'Verifying ZIP integrity' unzip -tq "$work/backup.zip" || die 'ZIP integrity check failed.'
    # Rename on the same filesystem; also works on USB filesystems without hardlinks.
    mv -n -- "$work/backup.zip" "$archive" || die "Could not publish archive: $archive"
    [[ ! -e "$work/backup.zip" ]] || die "Archive already exists: $archive; folder backup preserved."
    printf 'ZIP verified: %s\n' "$archive"
    du -h -- "$archive"
    # A destination can predate this backup; remove only our two managed entries.
    rm -rf -- "$folder/Default" "$folder/Local State"
    if rmdir -- "$folder" 2>/dev/null; then
        printf 'Removed verified backup folder: %s\n' "$folder"
    else
        printf 'Removed folder backup entries; retained folder with unrelated files: %s\n' "$folder"
    fi
}

extract_zip() {
    local archive=$1 work entries entry listing
    command -v unzip >/dev/null || die 'ZIP restore requires unzip.'
    command -v zipinfo >/dev/null || die 'ZIP restore requires zipinfo (from the unzip package).'
    run_with_status 'Verifying source ZIP integrity' unzip -tq "$archive" || die 'ZIP integrity check failed.'
    entries=$(zipinfo -1 "$archive") || die 'Cannot list ZIP entries.'
    [[ -n $entries ]] || die 'ZIP is empty.'
    while IFS= read -r entry; do
        # Restrict extraction to our two managed entries, without traversal.
        case $entry in
            'Local State'|Default/) ;;
            Default/*) ;;
            *) die "Unexpected ZIP entry: $entry (expected Default/ and Local State at the ZIP root)." ;;
        esac
        case "/${entry%/}/" in
            *'/../'*|*'/./'*|*'//'*) die "Unsafe ZIP path: $entry" ;;
        esac
        [[ $entry != *'\'* && $entry != *$'\r'* ]] || die 'Unsafe ZIP filename.'
    done <<< "$entries"
    listing=$(zipinfo -l "$archive") || die 'Cannot inspect ZIP entry types.'
    while IFS= read -r entry; do
        case ${entry:0:1} in
            l|b|c|p|s) die 'ZIP contains a symlink or special file; refusing to extract.' ;;
        esac
    done <<< "$listing"
    work=$(mktemp -d "${TMPDIR:-/tmp}/chrome-restore.XXXXXX")
    TEMP_DIRS+=("$work")
    run_with_status 'Extracting ZIP' unzip -q "$archive" -d "$work" || die 'ZIP extraction failed.'
    REPLY=$work
}

backup_profile() {
    local parent destination base answer suffix=2
    [[ $DRY_RUN == 0 ]] || die 'Backup is unavailable with --dry-run; choose Restore or Quit.'
    close_chrome
    validate_profile "$CHROME_ROOT"
    read_path 'Parent destination folder (a dated backup will be created inside): '
    parent=$REPLY
    base="$parent/chrome-backup-$(date +%y-%m-%d)"
    reject_overlap "$base"
    mkdir -p -- "$parent" || die "Cannot create destination: $parent"
    [[ -d $parent && -w $parent && -x $parent ]] || die 'Destination is not a writable directory.'
    destination=$base
    while [[ -e $destination || -L $destination || -e ${destination}.zip || -L ${destination}.zip ]]; do
        destination="${base}-${suffix}"
        suffix=$((suffix + 1))
    done
    # Reserve a fresh directory; never merge into an existing backup.
    mkdir -- "$destination" || die "Cannot create backup subfolder: $destination"
    printf 'Backup folder: %s\nZIP location (default): %s.zip\n' "$destination" "$destination"
    chrome_running && die 'Chrome restarted; refusing to copy.'
    printf 'Backing up profile...\n'
    rsync -a --info=progress2 --human-readable "${CACHE_EXCLUDES[@]}" -- "$CHROME_ROOT/Default/" "$destination/Default/"
    rsync -a --info=progress2 --human-readable -- "$CHROME_ROOT/Local State" "$destination/Local State"
    verify_copy "$CHROME_ROOT" "$destination"
    print_summary "$destination"
    printf '\nReminder: saved passwords are encrypted with the OS keyring and may not decrypt\non a fresh install. Export passwords to CSV separately if you need to transfer them.\n'
    while true; do
        if ! IFS= read -r -p 'Create a ZIP and remove the folder backup after verification? [Y/n]: ' answer; then
            printf '\nInput closed; keeping the folder backup.\n'
            return
        fi
        case $answer in
            ''|y|Y|yes|YES) create_zip "$destination"; break ;;
            n|N|no|NO) printf 'Kept folder backup: %s\n' "$destination"; break ;;
            *) printf 'Please answer yes or no (Enter chooses ZIP).\n' ;;
        esac
    done
}

restore_profile() {
    local source answer
    close_chrome
    read_path 'Backup source folder or ZIP file: '
    source=$REPLY
    reject_overlap "$source"
    if [[ -f $source && -r $source ]]; then
        extract_zip "$source"
        source=$REPLY
    else
        [[ -d $source && -r $source && -x $source ]] || die 'Source folder or ZIP does not exist or is not readable.'
    fi
    validate_profile "$source"
    validate_target "$CHROME_ROOT"
    if [[ $DRY_RUN == 1 ]]; then
        printf 'DRY RUN: previewing restore to %s; no profile files will be written.\n' "$CHROME_ROOT"
        rsync -an --delete --delete-excluded --itemize-changes \
            "${CACHE_EXCLUDES[@]}" -- "$source/Default/" "$CHROME_ROOT/Default/"
        rsync -an --itemize-changes -- "$source/Local State" "$CHROME_ROOT/"
        print_summary "$source"
        printf 'Restore preview complete.\n'
        return
    fi
    printf 'Restore will overwrite %s/Default and Local State, and delete old profile files and caches.\n' "$CHROME_ROOT"
    if ! IFS= read -r -p 'Type YES to continue: ' answer; then
        printf '\nInput closed.\n'
        exit 0
    fi
    if [[ $answer != YES ]]; then
        printf 'Restore cancelled.\n'
        return
    fi
    chrome_running && die 'Chrome restarted; refusing to copy.'
    mkdir -p -- "$CHROME_ROOT"
    printf 'Restoring profile...\n'
    rsync -a --info=progress2 --human-readable --delete --delete-excluded "${CACHE_EXCLUDES[@]}" -- "$source/Default/" "$CHROME_ROOT/Default/"
    rsync -a --info=progress2 --human-readable -- "$source/Local State" "$CHROME_ROOT/Local State"
    verify_copy "$source" "$CHROME_ROOT"
    print_summary "$CHROME_ROOT"
    printf 'Restore complete.\n'
}

main() {
    local command choice
    case ${1:-} in
        --help|-h) show_help; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        '') ;;
        *) die "Unknown option: $1" ;;
    esac
    (( $# <= 1 )) || die 'Too many arguments.'
    for command in rsync pkill pgrep realpath mkdir rmdir sleep du find wc mktemp rm mv date; do
        command -v "$command" >/dev/null || die "Missing dependency: $command"
    done
    while true; do
        printf '\nGoogle Chrome profile backup and restore\n1) Backup profile\n2) Restore profile\n3) Quit\n'
        if ! IFS= read -r -p 'Choose [1-3]: ' choice; then
            printf '\nInput closed.\n'
            exit 0
        fi
        case $choice in
            1) backup_profile ;;
            2) restore_profile ;;
            3) exit 0 ;;
            *) printf 'Please choose 1, 2, or 3.\n' ;;
        esac
    done
}

main "$@"
