# yt-downloader.sh

[Back to script index](../README.md) · [Script source](../yt-downloader.sh)

Daily YouTube / YouTube Music downloads, definitions-driven, using yt-dlp.

Reads a definitions file, one row per download, and runs yt-dlp for
each row. `video` rows download mp4, `audio` rows extract mp3.
Each row gets its own download-archive file, in
`~/Videos/YoutubeDownload/archives/`, named
`<PLAYLIST_ID>-<type>.archive.txt`. Progress and failures go to
`~/Videos/YoutubeDownload/yt-downloader.log`. The script exits
non-zero if any row failed, and continues to the next row after a
failure. No yt-dlp upgrade step, no mail step, and no chown step;
run it as the user who owns the downloads.

Definitions file: create your own, do not commit your real one.

Default location: `~/.config/yt-downloader-definitions.txt`
Or pass a different file as the first argument:
`yt-downloader.sh /path/to/definitions.txt`

Format, one row per download, pipe-separated, no header:

```
URL|type|output directory
```

Example rows, placeholders only:

```
https://www.youtube.com/playlist?list=EXAMPLE_PLAYLIST_ID|video|$HOME/Videos/YoutubeDownload/video
https://www.youtube.com/playlist?list=EXAMPLE_PLAYLIST_ID|audio|$HOME/Videos/YoutubeDownload/audio
https://www.youtube.com/playlist?list=ANOTHER_EXAMPLE_ID|audio|$HOME/Videos/YoutubeDownload/lofi
```

Install: copy `yt-downloader.sh` to `~/bin/yt-downloader.sh`,
`chmod +x ~/bin/yt-downloader.sh`, save your definitions file to
`~/.config/yt-downloader-definitions.txt`, and add a daily crontab
entry, for example `25 6 * * * ~/bin/yt-downloader.sh`.

Download it with:

```bash
curl -fL -o yt-downloader.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/yt-downloader.sh
chmod +x yt-downloader.sh
```
