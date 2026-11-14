# Ventoy Linux release downloader

[Repository README](../README.md) · [Script source](../download-ventoy.sh)

Run the script as your regular user and pass the parent directory where you want
to keep Ventoy. The script creates the parent directory if needed.

```bash
./download-ventoy.sh "/path/to/download"
```

The script requires Bash, curl, jq, GNU coreutils, GNU tar, gzip, flock, and CA
certificates. It fetches the Linux archive from the
[latest stable Ventoy release](https://github.com/ventoy/Ventoy/releases/latest)
and verifies its SHA-256 digest against GitHub's release metadata.

The extracted tools go directly in `Ventoy/`, including `Ventoy2Disk.sh`. The
downloaded `.tar.gz` and the temporary versioned directory are removed. See the
[Ventoy documentation](https://www.ventoy.net/en/doc_start.html) for USB setup.

The updater creates a **Ventoy** application-menu shortcut in
`$XDG_DATA_HOME/applications` (`~/.local/share/applications` by default). The
shortcut uses the bundled Ventoy logo and opens the GUI from the `Ventoy/`
directory. It selects the executable for the host architecture, such as
`VentoyGUI.x86_64` on a 64-bit Intel or AMD system. When the package has no
matching GUI executable, the updater still downloads the release.

When a new package replaces `Ventoy/`, the script moves the old package to
`Ventoy-previous/`, replacing any older copy. You can run the tools directly from
either directory. Keep other files outside these directories so version rotation
can manage their contents. A failed download, checksum check, or extraction
leaves both copies in place. If the current copy already has the latest release
digest recorded, the script refreshes the shortcut and skips the archive
download and version rotation.

## Weekly updates

Use `crontab -e` to add this entry for Sundays at 8 a.m. in cron's local time.
Use absolute paths to the script and destination.

```cron
0 8 * * 0 /path/to/download-ventoy.sh "/path/to/download"
```
