#!/usr/bin/env bash
# Back up the Hubitat hub database over HTTP and expire old daily backups.
# Requires Bash, curl, file, GNU coreutils, and flock.

set -euo pipefail
export LC_ALL=C
umask 077

usage() {
    cat <<'HELP'
Usage: hubitat-backup.sh HUB_HOST LOCAL_DIR KEEP_DAYS

Save the hub database from /hub/backupDB as Hubitat-YYYYMMDD.lzf.
HUB_HOST may be a hostname, IPv4 address, or IPv6 literal.
Use brackets around an IPv6 literal when specifying a port.
KEEP_DAYS is a positive integer and includes today in the retention window.
Use a separate private destination directory for each hub.
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
if (( $# != 3 )); then
    usage >&2
    exit 2
fi

hub_host=$1
local_dir=$2
keep_days=$3

# Bare IPv6 addresses have at least two colons and need brackets in HTTP URLs.
ipv6_literal='[[:xdigit:].]*:[[:xdigit:].:]*:[[:xdigit:].:]*(%[a-zA-Z0-9_.~-]+)?'
if [[ $hub_host =~ ^$ipv6_literal$ ]]; then
    hub_host="[$hub_host]"
fi
[[ $hub_host != -* &&
    ( $hub_host =~ ^[a-zA-Z0-9_.-]+(:[0-9]+)?$ ||
      $hub_host =~ ^\[$ipv6_literal\](:[0-9]+)?$ ) ]] ||
    die 'Specify a hostname or IP address without a scheme or username.'
[[ -n $local_dir ]] || die 'The destination directory cannot be empty.'
[[ $keep_days =~ ^0*[1-9][0-9]*$ ]] || die 'KEEP_DAYS must be a positive integer.'

for tool in curl file flock; do
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
backup_file="Hubitat-${backup_date//-/}.lzf"
# Use the local date above, then subtract calendar days in UTC to avoid DST shifts.
expired_through=$(TZ=UTC0 date -d "$backup_date $keep_days days ago" +%Y%m%d 2>/dev/null) ||
    die 'KEEP_DAYS is outside the supported date range.'
[[ $expired_through =~ ^[0-9]{8}$ ]] || die 'KEEP_DAYS is outside the supported date range.'

temp_file=$(mktemp ./.hubitat-backup.XXXXXXXX) || die 'Could not create a temporary backup.'
trap 'rm -f -- "$temp_file"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Hitting backupDB creates a fresh backup and downloads it in one go.
if ! http_status=$(curl -fsS --connect-timeout 10 --max-time 120 \
    --output "$temp_file" --write-out '%{http_code}' \
    "http://$hub_host/hub/backupDB?fileName=latest"); then
    die 'Could not download the hub backup.'
fi
[[ $http_status == 200 ]] || die "Expected a complete backup (HTTP 200), got HTTP $http_status."

# An H2 FileStore starts with three 16-byte header blocks, followed by payload blocks.
backup_size=$(stat -c %s -- "$temp_file") || die 'Could not read the downloaded file size.'
(( backup_size > 48 && backup_size % 16 == 0 )) ||
    die 'The downloaded file is too short or has an incomplete H2 block.'
if ! file_check=$(file -b -- "$temp_file" 2>&1) || [[ $file_check != *'H2 Database'* ]]; then
    die 'The downloaded file is not a Hubitat database backup.'
fi

mv -fT -- "$temp_file" "$backup_file" || die 'Could not save the validated backup.'
printf 'Saved %s/%s\n' "${PWD%/}" "$backup_file"

for old_backup in ./Hubitat-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].lzf; do
    [[ -f $old_backup && ! -L $old_backup ]] || continue
    file_date=${old_backup#./Hubitat-}
    file_date=${file_date%.lzf}
    [[ $file_date > $expired_through ]] && continue
    [[ $(TZ=UTC0 date -d "$file_date" +%Y%m%d 2>/dev/null) == "$file_date" ]] || continue
    rm -- "$old_backup" || die "Could not remove expired backup: ${old_backup#./}"
done
