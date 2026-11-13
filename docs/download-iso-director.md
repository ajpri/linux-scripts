# download-iso-director.sh

[Back to script index](../README.md) · [Script source](../download-iso-director.sh)

Keep `download-iso-director.sh` beside [`download-iso.sh`](download-iso.md).
Pass an existing writable download directory as the director’s only argument.

```bash
./download-iso.sh --check-deps
./download-iso-director.sh "/path/to/existing/isos"
```

The director calls the downloader for the current local day of the month. The
same dates repeat each month. Edit the Bash `case` to change the schedule.

Days 01–28 cover all 21 products and their scheduled variants, including Windows
11 multi-edition and Pro, Windows Server 2022 and 2025, and the Fedora, Ubuntu,
Linux Mint, and Pop!_OS editions. Days 29–31 are open.

## Nightly cron example

In `crontab -e`, add a line like this to run at 3 a.m. local time. Replace the
script, download, and log paths with absolute paths.

```cron
0 3 * * * /path/to/download-iso-director.sh "/path/to/existing/isos" >> "/path/to/iso-director.log" 2>&1
```
