# linux-scripts

Shell scripts for Linux setup, backups, downloads, display control, and API clients.

## Script index

| Script | Purpose | Guide |
| --- | --- | --- |
| [chrome-backup.sh](chrome-backup.sh) | Back up and restore a Google Chrome profile, with ZIP support and progress. | [Chrome backup guide](docs/chrome-backup.md) |
| [download-iso-director.sh](download-iso-director.sh) | Download an installation image on a fixed day of the month. | [ISO director guide](docs/download-iso-director.md) |
| [download-iso.sh](download-iso.sh) | Download and verify Linux, Windows, and other installation images. | [ISO download guide](docs/download-iso.md) |
| [download-openrct2.sh](download-openrct2.sh) | Download the latest stable OpenRCT2 AppImage and update its GNOME shortcut. | [OpenRCT2 guide](docs/download-openrct2.md) |
| [fedorasetup.sh](fedorasetup.sh) | Set up Docker, guest utilities, mail, and containers on Fedora. | [Fedora setup guide](docs/fedorasetup.md) |
| [foginstall.sh](foginstall.sh) | Install a FOG imaging server on Debian or Ubuntu. | [FOG installation guide](docs/foginstall.md) |
| [hubitat-cli.sh](hubitat-cli.sh) | Control devices and inspect Hubitat Maker API state. | [Hubitat guide](docs/hubitat-cli.md) |
| [npf-cli.sh](npf-cli.sh) | Browse No Part Finance data and submit transaction proposals. | [No Part Finance guide](docs/npf-cli.md) |
| [pfsense-backup.sh](pfsense-backup.sh) | Pull and validate daily pfSense configuration backups over SSH. | [pfSense backup guide](docs/pfsense-backup.md) |
| [toggleDisplays.sh](toggleDisplays.sh) | Switch two displays between extended and mirrored layouts on GNOME Wayland. | [Display guide](docs/toggleDisplays.md) |
| [update-linux.sh](update-linux.sh) | Update Linux packages, Flatpaks, Snaps, and standalone yt-dlp. | [Linux update guide](docs/update-linux.md) |
| [yt-downloader.sh](yt-downloader.sh) | Download video or audio from a list of YouTube playlists. | [YouTube download guide](docs/yt-downloader.md) |

The quick starts below assume you have downloaded or cloned this repository and
opened a terminal in its root directory. Each guide includes detailed setup,
configuration, examples, and limitations.

## chrome-backup.sh

Back up or restore Google Chrome's `Default` profile and `Local State`. Backups
use dated subfolders, with ZIP creation enabled by default.

**Requires:** Bash, rsync, procps, GNU coreutils, and findutils; zip/unzip for ZIP support.

```bash
bash ./chrome-backup.sh
bash ./chrome-backup.sh --dry-run  # Choose Restore to preview changes
```

[Full guide](docs/chrome-backup.md) — backup layout, restore, progress, and password handling.

## download-iso-director.sh

Pass an existing download directory to download the image assigned to today's date.

**Requires:** Bash and `download-iso.sh` in the same directory, with its dependencies installed.

```bash
./download-iso-director.sh "/path/to/existing/isos"
```

[Full guide](docs/download-iso-director.md) — calendar behavior, variants, and cron setup.

## download-iso.sh

Download installation images with checksum and format verification. Running
without arguments shows examples; the destination folder must already exist.

**Requires:** Bash 4+, curl, Python 3, and CA certificates; some products need extra tools.

```bash
bash ./download-iso.sh
bash ./download-iso.sh fedora ~/Downloads
```

[Full guide](docs/download-iso.md) — supported products, dependencies, options, and cron examples.

## download-openrct2.sh

Download and verify the latest stable OpenRCT2 AppImage, keep the previous copy,
and update its GNOME shortcut.

**Requires:** Bash, curl, jq, CA certificates, GNU coreutils, sed, and flock.

```bash
./download-openrct2.sh "$HOME/Applications/AppImage"
```

[Full guide](docs/download-openrct2.md) — shortcut, rollback, and cron setup.

## fedorasetup.sh

Provision a Fedora machine with Docker, XCP-ng guest utilities, mail relay
settings, Portainer, and Watchtower. Review the configured mail settings first.

**Requires:** Fedora, sudo privileges, and dnf/yum.

```bash
bash ./fedorasetup.sh
```

[Full guide](docs/fedorasetup.md) — setup behavior and installation command.

## foginstall.sh

Install Git, clone FOG Project, and launch its imaging-server installer.

**Requires:** Debian/Ubuntu, apt, and sudo privileges.

```bash
bash ./foginstall.sh
```

[Full guide](docs/foginstall.md) — installation details.

## hubitat-cli.sh

Inspect devices and send commands through Hubitat Maker API. The first run opens
configuration and an interactive menu.

**Requires:** Bash 4+, curl, jq, and a configured Hubitat Maker API instance.

```bash
bash ./hubitat-cli.sh
bash ./hubitat-cli.sh devices
```

[Full guide](docs/hubitat-cli.md) — hub setup, configuration, commands, and answer files.

## npf-cli.sh

Browse balances, categories, and transactions, and submit proposals to No Part
Finance. The first run prompts for your API URL and integration key.

**Requires:** Bash 4+, curl, jq, and a No Part Finance integration key.

```bash
bash ./npf-cli.sh
bash ./npf-cli.sh help
```

[Full guide](docs/npf-cli.md) — configuration, queries, approval behavior, and answer files.

## pfsense-backup.sh

Pull the pfSense configuration over key-based SSH, validate the XML, and remove
backups outside the requested retention window.

**Requires:** Bash, OpenSSH client, xmllint, GNU coreutils, and flock.

```bash
bash ./pfsense-backup.sh firewall-backup "$HOME/backups/pfsense" 14 backupuser
```

[Full guide](docs/pfsense-backup.md) — SSH key setup, filenames, and retention.

## toggleDisplays.sh

Toggle two displays between extended and mirrored layouts.

**Requires:** A GNOME Wayland session, Bash, and Python 3 with PyGObject.

```bash
./toggleDisplays.sh
./toggleDisplays.sh force-extend
```

[Full guide](docs/toggleDisplays.md) — connector detection and display configuration.

## update-linux.sh

Update system packages, remove unused dependencies, and clean the package cache.
Also update Flatpaks, Snaps, and supported standalone yt-dlp releases when installed.
The script never initiates a reboot.

**Requires:** Bash, one of APT, DNF, YUM, Pacman, or Zypper, and root privileges or sudo.

```bash
./update-linux.sh
./update-linux.sh -y
```

[Full guide](docs/update-linux.md) — unattended use, privileges, and supported installations.

## yt-downloader.sh

Download playlists as video or audio using a definitions file. Create that file
before running the script; downloads and failures are logged.

**Requires:** Bash, yt-dlp, ffmpeg for media processing, and a definitions file.

```bash
bash ./yt-downloader.sh ~/.config/yt-downloader-definitions.txt
```

[Full guide](docs/yt-downloader.md) — definitions format, archives, logging, and daily scheduling.

## Development note

Some utilities were developed with assistance from AI tools. Testing and
compatibility vary by script; review the source and documentation before running
them on your system.

Repository maintenance instructions are in [AGENTS.md](AGENTS.md).
