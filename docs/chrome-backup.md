# chrome-backup.sh

[Back to script index](../README.md) · [Script source](../chrome-backup.sh)

Interactive backup and restore for Google Chrome's `Default` profile on Linux.
Run as your normal desktop user, without sudo.

## Install and requirements

```bash
curl -fL -o chrome-backup.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/chrome-backup.sh
chmod +x chrome-backup.sh
./chrome-backup.sh
```

Requires Bash, rsync, `pkill`/`pgrep`, GNU coreutils, and findutils. ZIP creation
also requires `zip`; ZIP restore requires `unzip` and `zipinfo` from the unzip
package. Missing dependencies are reported; nothing is installed automatically.

```bash
# Debian / Ubuntu
sudo apt install rsync procps coreutils findutils zip unzip

# Fedora
sudo dnf install rsync procps-ng coreutils findutils zip unzip
```

## Backup

Choose **1) Backup profile**, then enter a **parent destination folder**, for
example `/mnt/backups` or `~/Desktop`. The script creates a dated
`chrome-backup-yy-mm-dd` subfolder inside that destination. Existing folders and
archives are preserved; repeated backups add `-2`, `-3`, and so on to the name.

It copies `~/.config/google-chrome/Default/` and
`~/.config/google-chrome/Local State` with rsync, excluding directories named
`Cache`, `Code Cache`, and `GPUCache` at any depth. It verifies the copy with
rsync checksums and reports the size and file count. Other Chrome profiles are
not included.

After verification, choose whether to create a ZIP. **Enter defaults to yes**:
the script creates `chrome-backup-yy-mm-dd.zip` inside the selected parent folder,
checks its integrity, publishes it without overwriting an existing archive, then
removes the dated folder backup. A failed ZIP creation or verification preserves
the folder. Choose **no** to keep the dated folder without compressing it. ZIP
creation refuses profiles containing symlinks.

For example, choosing `/mnt/backups` on November 10, 2026 produces:

```text
/mnt/backups/chrome-backup-26-11-10.zip
```

With ZIP disabled, it keeps:

```text
/mnt/backups/chrome-backup-26-11-10/
├── Default/
└── Local State
```

The ZIP also contains `Default/` and `Local State` directly at its root. Files
already in the parent destination are untouched. Allow disk space for both the
dated folder and ZIP while compression runs. USB filesystems do not need to
support hardlinks.

**Saved passwords are encrypted with the OS keyring and may not decrypt on a
fresh install. Export passwords to CSV separately if you need to transfer them.**

## Restore and preview

Run the script and choose **2) Restore profile**. Enter the source folder or ZIP
file. A valid source must contain `Default/Preferences` and `Local State`; ZIP
entries must use the root layout described above. Corrupt archives, unsafe paths,
symlinks, and special files in ZIPs are rejected. ZIP restore uses temporary
extraction space, removed when the script exits.

Type `YES` at the overwrite prompt to replace the current `Default` contents
and `Local State`. Restore deletes stale profile files and caches, verifies file
contents, and prints a size/file-count summary. Other profile directories are
preserved, but the shared `Local State` file is replaced.

```bash
# Choose Restore to preview either a folder or ZIP without changing the profile
./chrome-backup.sh --dry-run

./chrome-backup.sh --help
```

## Progress and process handling

Copies and restores show rsync's byte progress, percentage, transfer speed, and
time information. ZIP compression shows a dot for roughly every 10 MiB processed.
Checksum checks, ZIP integrity checks, compression, and extraction also show
elapsed time while running. Terminal status updates refresh in place; redirected
output gets elapsed-time messages every five seconds. Elapsed time is used where
there is no reliable completion percentage.

Both backup and restore, including restore previews, **force-close the current
user's Chrome processes** and wait up to 15 seconds for them to disappear. If
Chrome is still running, the operation stops. Keep Chrome closed until the
operation finishes. Backup and live Chrome paths must not overlap. Ctrl-C stops
an active check or ZIP operation and exits cleanly; an interrupted copy may be
incomplete.
