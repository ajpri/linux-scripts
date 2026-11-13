# OpenRCT2 AppImage updater

[Repository README](../README.md) · [Script source](../download-openrct2.sh)

Run the script as your desktop user and pass the directory where you want to
keep the AppImage. The script creates the directory if needed.

```bash
./download-openrct2.sh "$HOME/Applications/AppImage"
```

The script uses the [official GitHub stable release](https://github.com/OpenRCT2/OpenRCT2/releases/latest).
It requires Bash, curl, jq, CA certificates, GNU coreutils, sed, and flock.
The release must include a matching x86-64 or ARM64 AppImage with a SHA-256 digest.

The updater saves the verified download as `OpenRCT2.AppImage`, makes it
executable for your user, and refreshes `openrct2-appimage.desktop` in your user
applications directory (`~/.local/share/applications` by default). GNOME displays
the shortcut as **OpenRCT2** with the icon bundled in the official AppImage.
The script saves the icon in your user data directory and points the shortcut
directly to the PNG. If extraction fails, it
uses the last installed icon or the generic games icon. After moving the
AppImage, run the script with the new directory to update the shortcut.

When a new download replaces the current image, the updater keeps the old one as
`OpenRCT2-previous.AppImage` in the same directory. Run that file directly to
use the previous version. A failed download or digest check leaves both files
in place. If the current image already matches the latest release, the script
refreshes its executable permission and shortcut without downloading it again.

## Weekly updates

Use `crontab -e` to add this entry for Mondays at 1 a.m. in cron's local time.
Use the absolute paths for your script and destination.

```cron
0 1 * * 1 /path/to/download-openrct2.sh "/path/to/AppImage"
```

If you move the AppImage to another directory, update the destination in the
cron entry as well.
