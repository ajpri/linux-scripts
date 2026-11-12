#!/usr/bin/env bash
# Back up the pfSense configuration over SSH and expire old daily backups.
# Requires Bash, OpenSSH, xmllint, GNU coreutils, and flock.

set -euo pipefail
export LC_ALL=C
umask 077

usage() {
    cat <<'HELP'
Usage: pfsense-backup.sh REMOTE_HOST LOCAL_DIR KEEP_DAYS [REMOTE_USER]

Save /cf/conf/config.xml over key-based SSH as pfSense-YYYYMMDD.xml.
REMOTE_HOST may be a hostname, IP address, or SSH config alias.
REMOTE_USER defaults to the current local username.
KEEP_DAYS is a positive integer and includes today in the retention window.
Use a separate private destination directory for each firewall.
HELP
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi
if (( $# < 3 || $# > 4 )); then
    usage >&2
    exit 2
fi

remote_host=$1
local_dir=$2
keep_days=$3
remote_user=${4-$(id -un)}

[[ $remote_host =~ ^[a-zA-Z0-9_.:%-]+$ && $remote_host != -* ]] ||
    die 'Specify a hostname, IP address, or SSH alias without a username.'
[[ $remote_user =~ ^[a-zA-Z0-9_.-]+$ ]] || die 'Invalid remote username.'
[[ -n $local_dir ]] || die 'The destination directory cannot be empty.'
[[ $keep_days =~ ^0*[1-9][0-9]*$ ]] || die 'KEEP_DAYS must be a positive integer.'

for tool in ssh xmllint flock; do
    command -v "$tool" >/dev/null || die "Missing dependency: $tool"
done

# A ./ prefix makes relative paths literal, including a directory named "-".
if [[ $local_dir != /* ]]; then
    local_dir="./$local_dir"
fi
mkdir -p -- "$local_dir" || die 'Could not create the destination directory.'
cd -P -- "$local_dir" || die 'Could not enter the destination directory.'

# Serialize transfers and cleanup in this directory without creating a lock file.
exec 9<.
flock -x 9 || die 'Could not lock the destination directory.'

backup_date=$(date +%F)
backup_file="pfSense-${backup_date//-/}.xml"
# Use the local date above, then subtract calendar days in UTC to avoid DST shifts.
expired_through=$(TZ=UTC0 date -d "$backup_date $keep_days days ago" +%Y%m%d 2>/dev/null) ||
    die 'KEEP_DAYS is outside the supported date range.'
[[ $expired_through =~ ^[0-9]{8}$ ]] || die 'KEEP_DAYS is outside the supported date range.'

temp_file=$(mktemp ./.pfsense-backup.XXXXXXXX) || die 'Could not create a temporary backup.'
trap 'rm -f -- "$temp_file"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! ssh -nT -o BatchMode=yes -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -l "$remote_user" -- "$remote_host" 'cat /cf/conf/config.xml' > "$temp_file"; then
    die 'SSH could not read /cf/conf/config.xml.'
fi

# Reject parser diagnostics even when xmllint exits successfully.
# Keep them private because they can contain lines from the config.
if ! xml_check=$(xmllint --nonet --xpath 'boolean(/pfsense)' - < "$temp_file" 2>&1) ||
    [[ $xml_check != true ]]; then
    die 'The downloaded file is not well-formed XML with a <pfsense> root.'
fi

mv -fT -- "$temp_file" "$backup_file" || die 'Could not save the validated backup.'
printf 'Saved %s/%s\n' "${PWD%/}" "$backup_file"

for old_backup in ./pfSense-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].xml; do
    [[ -f $old_backup && ! -L $old_backup ]] || continue
    file_date=${old_backup#./pfSense-}
    file_date=${file_date%.xml}
    [[ $file_date > $expired_through ]] && continue
    [[ $(TZ=UTC0 date -d "$file_date" +%Y%m%d 2>/dev/null) == "$file_date" ]] || continue
    rm -- "$old_backup" || die "Could not remove expired backup: ${old_backup#./}"
done
