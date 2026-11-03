#!/bin/bash
# yt-downloader v1 - daily YouTube / YouTube Music downloads, definitions-driven
#
# How to use on the machine:
#   1. Save this file as yt-downloader.sh in ~/bin/.
#   2. Save the definitions file as ~/.config/yt-downloader-definitions.txt
#      (in the root of .config, no subfolder).
#   3. chmod +x ~/bin/yt-downloader.sh
#   4. Run it from your own crontab, daily, for example:
#      25 6 * * * ~/bin/yt-downloader.sh
#      Running as the user who owns the downloads means they are owned
#      by that user from the start, so there is no chown step.
#
# Definitions lookup, in order:
#   1. First command line argument, if given: the definitions file.
#      Example: yt-downloader.sh /path/to/other-definitions.txt
#   2. ~/.config/yt-downloader-definitions.txt
#   If the chosen file is missing, the script errors out and does not
#   fall back to the other location.
#
# v1 scope:
#   - No yt-dlp upgrade step. Upgrades move to a separate script.
#   - No mail step. A smarter mail step will be added later.
#   - Progress and failures go to the log file below, and the script
#     exits non-zero if any row failed.
#
# Definitions file: create your own, do not commit your real one.
# Format, one row per download, pipe-separated, no header:
#   URL|type|output directory
#   type is "video" or "audio". Lines starting with # and blank lines
#   are skipped. The output path is a directory, not a file.
#   Default location: ~/.config/yt-downloader-definitions.txt
#   A command line argument, if given, replaces that default.
#
# Example rows, placeholders only:
#   https://www.youtube.com/playlist?list=EXAMPLE_PLAYLIST_ID|video|$HOME/Videos/YoutubeDownload/video
#   https://www.youtube.com/playlist?list=EXAMPLE_PLAYLIST_ID|audio|$HOME/Videos/YoutubeDownload/audio
#   https://www.youtube.com/playlist?list=ANOTHER_EXAMPLE_ID|audio|$HOME/Videos/YoutubeDownload/lofi
#
# Archive files:
#   One archive per row, in $YTDL_ARCHIVE_DIR (default below), named
#   after the playlist ID, with the type added so video and audio rows
#   from the same playlist keep separate archives. Examples:
#     EXAMPLE_PLAYLIST_ID-video.archive.txt
#     EXAMPLE_PLAYLIST_ID-audio.archive.txt
#     ANOTHER_EXAMPLE_ID-audio.archive.txt
#   v1 starts with fresh archives. The first v1 run will re-download
#   everything. Old archives are not transferred.

set -u

if [ $# -ge 1 ] && [ -n "$1" ]; then
    DEFINITIONS_FILE="$1"
else
    DEFINITIONS_FILE="$HOME/.config/yt-downloader-definitions.txt"
fi
ARCHIVE_DIR="${YTDL_ARCHIVE_DIR:-$HOME/Videos/YoutubeDownload/archives}"
LOG_FILE="${YTDL_LOG:-$HOME/Videos/YoutubeDownload/yt-downloader.log}"

mkdir -p "$ARCHIVE_DIR" "$(dirname "$LOG_FILE")"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

if [ ! -f "$DEFINITIONS_FILE" ]; then
    log "ERROR: definitions file not found: $DEFINITIONS_FILE"
    exit 1
fi

failures=0

while IFS='|' read -r url type path || [ -n "$url" ]; do
    # Trim leading/trailing whitespace from each field.
    url="$(printf '%s' "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    type="$(printf '%s' "$type" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    path="$(printf '%s' "$path" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    # Skip blank lines and comment lines.
    case "$url" in
        ''|'#'*) continue ;;
    esac

    if [ -z "$type" ] || [ -z "$path" ]; then
        log "ERROR: bad definitions row, skipping: $url"
        failures=$((failures + 1))
        continue
    fi

    # Playlist ID from the URL (?list=... or &list=...). Fall back to
    # the output folder name if the URL has no list parameter, so the
    # archive name is never empty.
    playlist_id="$(printf '%s' "$url" | sed -n 's/.*[?&]list=\([^&]*\).*/\1/p')"
    if [ -z "$playlist_id" ]; then
        playlist_id="$(basename "$path")"
    fi
    archive="$ARCHIVE_DIR/$playlist_id-$type.archive.txt"
    mkdir -p "$path" "$ARCHIVE_DIR"

    log "Starting $type: $url -> $path (archive: $archive)"

    case "$type" in
        video)
            yt-dlp -f mp4 -i --yes-playlist --download-archive "$archive" -P "$path" "$url"
            ;;
        audio)
            yt-dlp -f 'ba' -i --yes-playlist --download-archive "$archive" -x --audio-format mp3 -P "$path" "$url"
            ;;
        *)
            log "ERROR: unknown type '$type' for $url, skipping"
            failures=$((failures + 1))
            continue
            ;;
    esac

    status=$?
    if [ "$status" -ne 0 ]; then
        log "FAILED ($status): $type $url"
        failures=$((failures + 1))
    else
        log "Done: $type $url"
    fi
done < "$DEFINITIONS_FILE"

log "Finished with $failures failure(s)"

if [ "$failures" -gt 0 ]; then
    exit 1
fi
exit 0
