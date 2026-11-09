# linux-scripts

Shell scripts for Linux setup, Chrome profile migration, installation image and media downloads, display control, No Part Finance integration, and Hubitat Maker API control.

## Contents

- [fedorasetup.sh](#fedorasetupsh)
- [foginstall.sh](#foginstallsh)
- [download-iso.sh](#download-isosh)
- [chrome-backup.sh](#chrome-backupsh)
- [yt-downloader.sh](#yt-downloadersh)
- [toggleDisplays.sh](#toggledisplayssh)
- [npf-cli.sh](#npf-clish)
- [hubitat-cli.sh](#hubitat-clish)

## fedorasetup.sh

Provisions a Fedora machine: installs Docker CE, schedules a weekly Docker image prune, installs XCP-ng guest utilities, neofetch, nano, and mailx, configures ssmtp as a mail relay, and spins up Portainer and Watchtower.

```bash
wget -O - https://raw.githubusercontent.com/ajpri/linux-scripts/main/fedorasetup.sh | bash
```

## foginstall.sh

Installs a FOG imaging server on Debian/Ubuntu: installs git, clones FOGProject, and runs the FOG installer.

```bash
curl -sSL https://raw.githubusercontent.com/ajpri/linux-scripts/main/foginstall.sh | bash
```

## download-iso.sh

One self-contained Linux command for downloading and verifying installation images.
Downloads run without prompts and support unattended cron jobs; interactive runs
can offer to install missing dependencies first. Run it without arguments
for ready-to-use examples showing the defaults configured in the script.

### Quick start

```bash
curl -fL -o download-iso.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/download-iso.sh
chmod +x download-iso.sh
./download-iso.sh
```

Choose a product to start a download. The folder is optional, defaults to the
current directory, and **must already exist**. The script never creates it.

```bash
# Download using the product's defaults into the current directory
./download-iso.sh qubes
./download-iso.sh gparted
./download-iso.sh chromeosflex
./download-iso.sh omv
./download-iso.sh netbootxyz

# Choose a folder and edition
./download-iso.sh ubuntu /mnt/isos --edition server
./download-iso.sh LinuxMint --edition xfce
./download-iso.sh popos --edition nvidia
./download-iso.sh win11 --edition pro

# Preserve existing ISO files, or suppress routine output
./download-iso.sh qubes /mnt/isos --keep-existing
./download-iso.sh gparted --silent

# Redirect progress and messages to a log
./download-iso.sh ubuntu > ubuntu.log 2>&1

# See version choices, defaults, filenames, and cleanup rules for a product
./download-iso.sh qubes --help
```

### Supported products

All images target x86-64/amd64. Product names are case-insensitive.

| Product argument | Download selection |
| --- | --- |
| `win11` | Current Windows 11 English (US); untouched multi-edition or an `ei.cfg` edition selector |
| `winserver` | Windows Server Evaluation; version 2022 or 2025 |
| `ubuntu` | Configured release family, newest point ISO; Desktop or Server |
| `debian` | Configured major release, newest point release; netinst ISO |
| `fedora` | Configured final release; Workstation Live or Server DVD |
| `xcpng` | Configured XCP-ng family; exact versions/previews also supported |
| `proxmox` | Configured Proxmox VE family; exact builds/previews also supported |
| `truenas` | Configured Linux-based TrueNAS SCALE/Community Edition family |
| `pfsense` | Current Netgate online installer; not an offline pfSense CE ISO |
| `opnsense` | Configured OPNsense Community family; newest published DVD installer |
| `hbcdpe` | Current Hiren's BootCD PE |
| `clonezilla` | Current stable Debian-based Clonezilla Live |
| `memtest86plus` | Current open-source Memtest86+ standard 64-bit ISO |
| `LinuxMint` | Current stable Linux Mint; Cinnamon, MATE, or Xfce |
| `popos` | Current Pop!_OS; generic or NVIDIA image |
| `arch` | Current dated Arch Linux installation ISO |
| `gparted` | Current stable GParted Live |
| `qubes` | Configured Qubes OS family; newest stable point ISO |
| `chromeosflex` | Current stable Google ChromeOS Flex recovery disk image, saved as `.img` |
| `openmediavault` / `omv` | Configured major, newest numerically named amd64 ISO from the project's SourceForge directory |
| `netbootxyz` / `netboot.xyz` | Current rolling netboot.xyz BIOS/UEFI network-boot ISO |

Aliases: `memtest86+` for `memtest86plus`, and `pop` for `popos`.

Default versions and editions are grouped near the top of `download-iso.sh`.
Changing those settings automatically updates the no-argument help examples.
Use that help as the source of current defaults; this README does not duplicate
release numbers that would need updating separately.

### Options and file handling

```text
download-iso.sh PRODUCT [EXISTING_FOLDER] [OPTIONS]
```

| Option | Behavior |
| --- | --- |
| `--version VALUE` | Overrides the configured version for products supporting version selection; see product help for accepted formats |
| `--edition VALUE` | Selects an available edition for Windows 11, Ubuntu, Fedora, Linux Mint, or Pop!_OS |
| `--keep-existing` | Preserves all history and an existing exact output filename, after downloading and verifying a fresh copy |
| `--silent`, `-s` | Suppresses routine messages and progress; errors remain on stderr and failures return nonzero |
| `--check-deps` | Checks tools only; never prompts, installs, or downloads. Exit 0 if available, nonzero if missing |
| `--help`, `-h` | Shows general or product-specific help without downloading |

Options can appear before or after the folder. Quote paths with spaces, and use
`--` before a folder name beginning with a dash. `--version=VALUE` and
`--edition=VALUE` are also accepted where supported.

Every download invocation fetches a fresh copy, including with `--keep-existing`.
There is no version check that skips a transfer. The selected source filename is
logged. Output names include the local run-start date as `YYMMDD`; versioned
products also include their release or family, such as
`Qubes_<family>_<YYMMDD>.iso`. GParted uses `gparted_<YYMMDD>.iso`.
ChromeOS Flex uses `ChromeOSFlex_<YYMMDD>.img`, with no version selector.
OpenMediaVault uses `OpenMediaVault_<major.minor>_<YYMMDD>.iso`; its default major is
configured near the top of the script, or overridden with `omv --version 8`.
Releases are selected numerically; an 8.3.1 download produces
`OpenMediaVault_8.3_<YYMMDD>.iso`, with the full source version logged. Cleanup
covers the same major, including legacy major-only names, and preserves other majors.
netboot.xyz uses `netboot.xyz_<YYMMDD>.iso` and has no version selector.

Without `--keep-existing`, a verified download replaces today's exact filename
and prunes managed history according to that product's cleanup rules. Product
help describes the scope. Other products and unrelated files are preserved.
Downloads stage in the destination and publish atomically after verification;
failures before publication preserve existing images. Per-product locks prevent
concurrent downloads of the same product into the same folder. Locking uses
Python’s standard-library `fcntl.flock`; no `flock` command/package is required.

### Requirements and verification

Requires Linux, Bash 4+, curl, Python 3 (standard library), and CA certificates.
Qubes additionally requires `gpg`.

```bash
# Check all products, including Qubes and Windows edition customization tools
./download-iso.sh --check-deps

# Check only the selected product and edition
./download-iso.sh win11 --edition pro --check-deps
./download-iso.sh fedora --check-deps
```

Dependency-only checks do not require or touch a download folder. Missing tools
are listed with an installation command for supported OS families. Add `--silent`
to hide a successful check's message; errors still appear.

The script checks dependencies needed by the selected product and edition. On
Fedora and Debian/Ubuntu families (including derivatives identified through
`/etc/os-release`), it shows the appropriate package command and offers to install
missing tools. Installation requires an explicit **yes**; `sudo` may request your
password. After installation it checks the tools again and continues the download.

The offer appears only when standard input, standard output, and standard error are terminals.
Cron, redirected logs, piped input, and `--silent` never prompt or install packages;
they exit nonzero with the missing tools and the manual installation command.
Other Linux distributions can run the downloader with dependencies preinstalled,
but automatic installation is limited to the families above with `apt-get`/`dnf`
available. Fedora Atomic desktops require their own package-management workflow.

```bash
# Debian/Ubuntu dependencies
sudo apt install bash curl python3 ca-certificates

# Additional dependency for Qubes downloads
sudo apt install gnupg

# Additional dependencies for Windows 11 edition customization
sudo apt install p7zip-full genisoimage

# Fedora dependencies
sudo dnf install bash curl python3 ca-certificates

# Additional dependency for Qubes downloads
sudo dnf install gnupg2

# Additional dependencies for Windows 11 edition customization
sudo dnf install 7zip genisoimage
```

These manual examples use `apt`; the script uses `apt-get` for its stable scripting
interface, as [recommended by Debian](https://www.debian.org/doc/manuals/debian-reference/ch02).
The full 7-Zip executable may be named `7z` or `7zz`; reduced `7za`/`7zr` builds
are not used for Windows UDF extraction. Fedora package mappings follow its
official [7zip](https://packages.fedoraproject.org/pkgs/7zip/7zip/) and
[genisoimage](https://packages.fedoraproject.org/pkgs/cdrkit/genisoimage/) listings.

HTTPS certificate validation stays enabled. Published SHA256 checksums and ISO
structure are verified. For compressed downloads, the archive checksum is checked
before extraction. Windows Server Evaluation is the exception: it checks Microsoft
source URLs, expected size, strong ETag when available, and ISO structure; its
calculated SHA256 is logged without an official checksum comparison.
ChromeOS Flex is the other checksum exception: Google's official recovery feed
publishes SHA-1 rather than SHA256. The hash covers the ZIP, as specified in
[Google's recovery format](https://chromium.googlesource.com/chromiumos/user-recovery-tools/+/HEAD/README_formats.txt).
The script checks the stable ZIP's size, exact
member name, ZIP CRC, extracted image size and published ZIP SHA-1. It also verifies
the protective MBR, primary/backup GPT checksums and matching partition tables,
partition bounds, and ChromeOS/EFI partition types. A calculated image SHA256 is
logged for reference. No additional packages are needed.

ChromeOS Flex uses the exact versioned stable image from
[Google's recovery feed](https://dl.google.com/dl/edgedl/chromeos/recovery/cloudready_recovery2.json);
beta, development, and LTS channels are excluded. Google's original `.bin` bytes
are extracted unchanged and saved with an `.img` extension. This is a USB disk
image, not an ISO conversion. The script only downloads it; it does not write to
USB devices. Allow room for both the ZIP and the extracted image during staging.
Only `ChromeOSFlex_<YYMMDD>.img` history is pruned; other files are preserved.
See [Google's installation instructions](https://support.google.com/chromeosflex/answer/11541904?hl=en)
for using the image.

**Qubes also requires a valid detached PGP signature on the ISO.** Its release key
must be certified by the Qubes master key whose fingerprint is pinned in the
script. Verification uses a temporary keyring without changing personal GPG keys
or trust settings. Invalid or missing verification data causes failure; there is
no option to bypass it. Other products do not verify detached signatures.

pfSense uses the FileEagle mirror for Netgate Installer and requires its archive
to match Netgate's official checksum. Windows Server downloads Evaluation media.
See each product's help for its sources and specific selection behavior.

OpenMediaVault verifies the chosen ISO against its `.sha256` sidecar on the
[project's SourceForge mirror](https://sourceforge.net/projects/openmediavault/files/iso/).
Its installer requires an Internet connection. netboot.xyz verifies the standard
ISO against the official boot server's SHA256 manifest; this small image loads
a network-boot menu and downloads the selected OS environment when booted.
See [netboot.xyz downloads](https://netboot.xyz/downloads/).

VMware ESXi is currently not supported. Broadcom's official free ISO download
requires account login and acceptance of its terms, so it does not use the
account-free workflow provided here. See
[Broadcom's download instructions](https://knowledge.broadcom.com/external/article/399823/vmware-esxi-80-update-3e-now-available-a.html).

### Windows 11 edition selection

```bash
./download-iso.sh win11 --edition multi          # Original, unchanged Microsoft ISO
./download-iso.sh win11 --edition pro            # Setup selects Windows 11 Pro
./download-iso.sh win11 --edition pro-workstations
./download-iso.sh win11 --edition ProfessionalN  # Microsoft IDs also accepted
```

`multi` is the default. It keeps the existing filename format,
`Win11_<version>_<YYMMDD>.iso`, with no `Multi` label and no customization tools
required. A customized image includes the edition, for example
`Win11_Pro_<version>_<YYMMDD>.iso`. Cleanup histories are separate by edition.

Edition aliases include Home, Home N, Home Single Language, Pro, Pro N,
Education, Education N, Pro Education, Pro Education N, and Pro for Workstations
and its N variant. Names are case-insensitive; use hyphens between words.
Microsoft edition IDs are also recognized. Unknown names fail before downloading.
7-Zip reads edition metadata from the downloaded WIM/ESD; no `wimlib-imagex`
package is needed. Recognized editions must actually exist there or the command
fails with an available-edition list. No edition is silently substituted.

Customization verifies Microsoft's source checksum first, adds `sources/ei.cfg`
with the selected edition (`Retail`, `VL=0`), and rebuilds UDF media. It retains
the other installation images and adds no product key. An installation answer
file takes precedence over `ei.cfg`.

The rebuild checks BIOS/UEFI boot images, every payload file, and the new selector.
Its calculated SHA256 is logged separately; a customized ISO does not match
Microsoft's original checksum. Allow about three ISO sizes of temporary staging
space, in addition to any existing destination files. `--keep-existing` still
downloads, customizes, and verifies a fresh copy before retaining an existing file.

### Monthly cron example

Use absolute paths and an existing download folder:

```cron
0 3 1 * * /bin/bash /path/to/download-iso.sh qubes /mnt/isos >> /path/to/qubes.log 2>&1
```

The script creates no log automatically; shell redirection controls logging.
Allow room for the fresh download alongside existing files, plus extraction space
for compressed images. Normal exits remove staging files; forced termination or
power loss can leave hidden staging directories. Monitor job logs for failures or
upstream source changes.

## chrome-backup.sh

Interactive backup and restore for Google Chrome's `Default` profile, including
migration from Pop!_OS to Fedora. Run as your normal desktop user, without sudo.

### Install and requirements

```bash
curl -fL -o chrome-backup.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/chrome-backup.sh
chmod +x chrome-backup.sh
./chrome-backup.sh
```

Requires Bash, rsync, `pkill`/`pgrep`, GNU coreutils, and findutils. ZIP creation
also requires `zip`; ZIP restore requires `unzip` and `zipinfo` from the unzip
package. Missing dependencies are reported; nothing is installed automatically.

```bash
# Pop!_OS / Debian / Ubuntu
sudo apt install rsync procps coreutils findutils zip unzip

# Fedora
sudo dnf install rsync procps-ng coreutils findutils zip unzip
```

### Backup

Choose **1) Backup profile**, then enter the destination folder, for example
`~/Desktop/chrome-backup`. The script creates the folder if necessary and refuses
to reuse a destination containing `Default` or `Local State`.

It copies `~/.config/google-chrome/Default/` and
`~/.config/google-chrome/Local State` with rsync, excluding directories named
`Cache`, `Code Cache`, and `GPUCache` at any depth. It verifies the copy with
rsync checksums and reports the size and file count. Other Chrome profiles are
not included.

After verification, choose whether to create a ZIP. Choosing **yes** creates
`<destination>.zip`, checks its integrity, publishes it without overwriting an
existing archive, then removes the folder backup. A failed ZIP creation or
verification preserves the folder. Unrelated files in a preexisting destination
are preserved; the folder remains if it contains those files. Choosing **no**
keeps the folder backup. ZIP creation refuses profiles containing symlinks.

The ZIP contains `Default/` and `Local State` directly at its root. Allow disk
space for both the folder and ZIP while compression runs.

**Saved passwords are encrypted with the OS keyring and may not decrypt on a
fresh install. Export passwords to CSV separately before migrating.**

### Restore and preview

Copy the backup folder or ZIP to the new machine, run the script, and choose
**2) Restore profile**. Enter the source folder or ZIP file. A valid source must
contain `Default/Preferences` and `Local State`; ZIP entries must use the root
layout described above. Corrupt archives, unsafe paths, symlinks, and special
files in ZIPs are rejected. ZIP restore uses temporary extraction space, removed
when the script exits.

Type `YES` at the overwrite prompt to replace the current `Default` contents
and `Local State`. Restore deletes stale profile files and caches, verifies file
contents, and prints a size/file-count summary. Other profile directories are
preserved, but the shared `Local State` file is replaced.

```bash
# Choose Restore to preview either a folder or ZIP without changing the profile
./chrome-backup.sh --dry-run

./chrome-backup.sh --help
```

Both backup and restore, including restore previews, **force-close the current
user's Chrome processes** and wait up to 15 seconds for them to disappear. If
Chrome is still running, the operation stops. Keep Chrome closed until the
operation finishes. Backup and live Chrome paths must not overlap. Ctrl-C exits
cleanly; an interrupted copy may be incomplete.

## yt-downloader.sh

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

## toggleDisplays.sh

Toggles two displays between EXTEND and MIRROR using xrandr. The right display stays primary. In EXTEND, the left display sits to the left of the right display. In MIRROR, both displays use the same mode and position.

With no argument, it flips the saved state in `${XDG_CACHE_HOME:-$HOME/.cache}/toggleDisplays.state`. On the first run, with no saved state, it detects the current layout and picks the opposite. `force-extend` and `force-mirror` override the toggle.

Display names, the mirror mode, and debug output are configurable by environment variable, with defaults of DisplayPort-0, DisplayPort-1, and 1920x1080:

```bash
TOGGLE_DISPLAYS_RIGHT=DisplayPort-0 TOGGLE_DISPLAYS_LEFT=DisplayPort-1 TOGGLE_DISPLAYS_MODE=1920x1080 ./toggleDisplays.sh
```

Download it with:

```bash
curl -fL -o toggleDisplays.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/toggleDisplays.sh
chmod +x toggleDisplays.sh
```


## npf-cli.sh

Single-file, menu-driven Bash client for the No Part Finance integration API.
Browse account balances, categories, transaction history, pending proposals, and
submission status. Submit ordinary transactions or transfers/payments interactively
or from TXT/JSON answer files. Account and category inputs use exact names, with
IDs resolved internally. Submissions require Owner or Member approval in the
application before they affect balances.

Requires Bash 4+, `curl`, `jq`, and standard Unix utilities. No separate example
files or `.env` file are needed.

### Install and configure

```bash
curl -fL -o npf-cli.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/npf-cli.sh
chmod +x npf-cli.sh
./npf-cli.sh
```

The first interactive run prompts for the HTTPS API URL and integration key, then
opens the menu. The key prompt hides input. Configuration is saved privately in
`~/.config/npf-cli/config` (or `$XDG_CONFIG_HOME/npf-cli/config`). The default URL
is `https://exptrack.pritchett.info`; set another deployment URL as needed.

```bash
./npf-cli.sh config                          # Configure URL and key
./npf-cli.sh config url https://finance.example.com
./npf-cli.sh config key                      # Hidden key prompt
./npf-cli.sh config show                     # Shows URL; never prints the key
./npf-cli.sh help
```

`--env FILE` before the command selects an optional alternative configuration file
for automation. Existing literal `EXPTRACK_BASE_URL`, `EXPTRACK_API_KEY`,
`EXPTRACK_TIMEOUT`, and `EXPTRACK_PAGE_SIZE` settings remain supported. Values are
never executed as shell code. Keep credentials out of Git and avoid `bash -x`,
which can expose them.

### Browse and submit

```bash
./npf-cli.sh accounts
./npf-cli.sh categories
./npf-cli.sh transactions --account 'Checking' --period thisMonth
./npf-cli.sh transactions --category 'Recurring Needs' --start 2026-10-01 --end 2026-10-31
./npf-cli.sh pending
./npf-cli.sh status
./npf-cli.sh new
./npf-cli.sh transfer
```

Account balances show credit debt as a positive amount labeled `owed`, and
positive overpayment balances as `credit`. History uses the API's display amounts,
retaining negative refunds and income reversals. Names are case-sensitive;
unknown, ambiguous, or ineligible submission names are rejected. History and
status results are paginated; terminal users choose whether to fetch another
page, while redirected input fetches all pages.

### Answer files and built-in examples

```bash
./npf-cli.sh example > groceries.txt
./npf-cli.sh example transfer > transfer.txt
./npf-cli.sh example json > groceries.json
# Edit dates, names, descriptions, and amounts before previewing/submitting.
./npf-cli.sh preview groceries.txt
./npf-cli.sh submit groceries.txt
```

The default example is one ordinary transaction in literal `key=value` text:

```text
type=transaction
date=2026-11-04
account=Checking
category=Groceries
description=Weekly groceries
amount=50.00
```

Use one proposal per text file. Blank lines and full-line `#` comments are allowed;
values need no quotes or escaping. JSON accepts an object or an array of proposals;
amounts must be strings. Transfers use `type=transfer`, `fromAccount`, and
`toAccount`, with no category. Dates must be explicit `YYYY-MM-DD` calendar dates.
Entered USD amounts accept up to two decimal places: ordinary expenses and income
are positive, refunds and income reversals are negative, and transfers are
strictly positive.

`submissionId` is optional. The script generates missing IDs and saves them in a
private `<answer-file>.exptrack-state.json` companion before submitting. Keep that
file with the unchanged answer file for retries, especially after a timeout.
`preview` reads the catalogs and saves retry state without sending a proposal.
Changed content with generated retry state is rejected; use a new answer file
for a new transaction. Do not discard retry state to retry an uncertain request,
as doing so could create a duplicate proposal.

Interactive answers and their retry state are stored under
`~/.local/state/npf-cli/answers` (or `$XDG_STATE_HOME/npf-cli/answers`). JSON batches
are validated before sending, then submitted individually; batches are not atomic.
An error stops further submissions, and earlier items may already have succeeded.

## hubitat-cli.sh

Single-file Bash client for Hubitat Maker API with an interactive menu and CLI
commands. Read device state and events, send device commands, manage hub modes
and HSM, read/set hub variables, list rooms, and configure event callbacks.
Supports local/cloud access, device labels or IDs, JSON answer files, and previews.

### Install and requirements

```bash
curl -fL -o hubitat-cli.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/hubitat-cli.sh
chmod +x hubitat-cli.sh
./hubitat-cli.sh
```

Run the script without arguments to start guided setup and open the menu.
The script is self-contained; no example env or Python files are required.

Requires Bash 4+, curl, jq, and standard Unix utilities.

```bash
# Debian / Ubuntu
sudo apt install curl jq

# Fedora
sudo dnf install curl jq
```

### Hub setup and configuration

1. On your hub, open **Apps → Add App / Add Built-In App → Maker API**.
2. Authorize the devices and hub variables you want to access. Enable local
   and/or cloud access as needed. Enable **Allow control of modes** and
   **Allow control of HSM** if you want those features; HSM must be installed.
3. Select **Update**, then find the generated endpoint URLs. Copy the base URL
   and access token from the appropriate local or cloud URL. Select **Done**.
4. Run the script without arguments. On the first interactive run, it displays
   setup instructions, prompts for the base URL and token, saves your settings,
   and opens the menu. The token is hidden while you type:

```bash
./hubitat-cli.sh                  # First run: guided setup, then the menu
./hubitat-cli.sh config           # Run setup again whenever needed
```

For a generated URL such as
`http://192.168.1.50/apps/api/123/devices?access_token=YOUR_TOKEN`, enter
`http://192.168.1.50/apps/api/123` as the base URL and `YOUR_TOKEN` separately.
The app ID is the Maker API instance ID, not a device ID.

Cloud bases look like
`https://cloud.hubitat.com/api/YOUR-HUB-ID/apps/123`. Copy the actual URL
from your Maker API app, since the hub ID and app ID are specific to your hub.

Configuration is stored with mode `600` at
`~/.config/hubitat-cli/config`, or `$XDG_CONFIG_HOME/hubitat-cli/config`.
Use an alternative env file if preferred:

```bash
./hubitat-cli.sh --env /path/to/hubitat.env config
./hubitat-cli.sh --env /path/to/hubitat.env devices
./hubitat-cli.sh --env /path/to/hubitat.env menu
```

An adjacent `.env` is used only when explicitly selected with `--env`. The
supported keys are `HUBITAT_BASE_URL`, `HUBITAT_ACCESS_TOKEN`, and
`HUBITAT_TIMEOUT` (default `30` seconds). Inherited environment variables work
too; file values take precedence. Configuration is literal `KEY=value` data.
Matching outer quotes are stripped; shell substitutions, escapes, `export`,
and inline comments are not interpreted. Comments must be on their own lines.

```bash
./hubitat-cli.sh config show          # Token is hidden
./hubitat-cli.sh config token         # Hidden prompt to replace token
./hubitat-cli.sh config url http://192.168.1.51/apps/api/123
```

### Menu and command-line examples

Global options (`--env FILE`, `--json`, `--dry-run`) go **before** the command.
Device labels and mode/variable names are exact and case-sensitive. An unlabeled
device uses its name. A numeric selector or `id:123` selects a device ID; use
`id:NUMBER` to disambiguate duplicate labels. `devices` lists the available IDs.

```bash
./hubitat-cli.sh devices
./hubitat-cli.sh --json devices
./hubitat-cli.sh devices --all
./hubitat-cli.sh device 'Living Room Light'
./hubitat-cli.sh events 'Living Room Light'
./hubitat-cli.sh commands 'Living Room Light'
./hubitat-cli.sh attribute 'Living Room Light' switch

./hubitat-cli.sh send 'Living Room Light' on
./hubitat-cli.sh send 'Living Room Light' setLevel 50 2
./hubitat-cli.sh send id:42 setColor '{"hue":10,"saturation":100,"level":50}'
./hubitat-cli.sh label id:42 'Bedroom Dimmer'

./hubitat-cli.sh modes
./hubitat-cli.sh mode 'Evening'
./hubitat-cli.sh mode id:2
./hubitat-cli.sh hsm
./hubitat-cli.sh hsm armAway

./hubitat-cli.sh variables
./hubitat-cli.sh variable 'Greeting'
./hubitat-cli.sh variable 'Greeting' 'Welcome home'
./hubitat-cli.sh rooms
./hubitat-cli.sh room 7

./hubitat-cli.sh post-url 'http://192.168.1.10:8080/events'
./hubitat-cli.sh post-url clear
./hubitat-cli.sh --dry-run send 'Living Room Light' setLevel 50
./hubitat-cli.sh help
```

Multiple command arguments are joined with commas into one parameter segment,
as required by Maker API. `setLevel 50 2` sends `setLevel/50,2`, with URL encoding
applied automatically. JSON is one argument. Commands and their arguments depend
on the device driver; inspect `commands` and the device detail page on your hub.
The script checks command availability; the hub validates argument counts/types.

HSM actions are `armAway`, `armHome`, `armNight`, `disarm`, `disarmAll`, `armAll`,
and `CancelAlerts`. These are commands; returned status names such as `armedAway`
are different. Match the capitalization shown above.

`post-url` configures where the **hub sends** event POSTs. It replaces this Maker
API instance's existing callback. The script does not start a webhook receiver.
The receiver must be reachable from the hub. Enable location event forwarding
in Maker API if you need mode, HSM, or variable event notifications. `clear`
removes the callback; there is no callback-read command because calling the
bare `/postURL` endpoint clears it.

### Answer files

```bash
./hubitat-cli.sh example > evening.local.json
# Edit the device/mode/variable names for your hub.
./hubitat-cli.sh preview evening.local.json
./hubitat-cli.sh submit evening.local.json
```

A file contains one JSON action object or a nonempty array of actions. Supported
schemas are below; replace the example values. Only include the actions you need.

```json
[
  {"action":"send","device":"Living Room Light","command":"on","args":[]},
  {"action":"send","device":"Living Room Light","command":"setLevel","args":[50,2]},
  {"action":"send","device":"id:42","command":"setColor","args":["{\"hex\":\"FF0400\"}"]},
  {"action":"mode","name":"Evening"},
  {"action":"hsm","value":"armHome"},
  {"action":"variable","name":"Greeting","value":"Welcome home"},
  {"action":"label","device":"id:42","value":"Bedroom Dimmer"},
  {"action":"post-url","value":"http://192.168.1.10:8080/events"}
]
```

`send.args` is optional and contains strings, numbers, or booleans. Pass JSON
parameters as JSON **strings**, as in the `setColor` example. Variable values
can be strings, numbers, or booleans. Unknown fields are rejected to catch typos.

Preview validates the entire file, resolves names and command availability, and
prints planned paths and query arguments. It performs reads but sends no writes.
`--dry-run submit FILE` has the same effect. Previews omit the access token but
contain action parameters, so treat previews containing lock codes as private.

Submit plans every action before starting writes, then executes in order. It
returns one JSON response per line (NDJSON), with progress on stderr. A failure
stops the batch. Actions already sent remain applied; batches are not atomic and
have no retry protection. Check hub state before resubmitting. All names resolve
against the hub state before the batch starts, including when a batch renames a
device. The menu previews batches and asks before sending them.

### Behavior and limitations

- Direct CLI writes and individual menu actions execute immediately. Commands
  can control locks, alarms, and other physical devices. Maker API permissions
  determine the available devices and features.
- Maker API uses GET requests for both reads and writes. The client never
  follows redirects or automatically retries requests. A timeout does not mean
  a command failed to execute. Read the device state before repeating a write.
- Successful command responses report what the API returned. Device state may
  update asynchronously; query it again to confirm the physical result. An empty
  successful write response is shown as `{"accepted":true}`.
- Most commands print JSON. `devices` prints a tab-separated table unless
  `--json` is supplied; `devices --all` always prints full JSON. Failures exit
  nonzero with diagnostics on stderr. Menu failures return to the menu.
- `--dry-run` still needs a working hub for label resolution, mode selection,
  and device command validation. It is not an offline simulator.
- HTTPS certificate verification stays enabled. Local HTTP is supported as
  provided by Hubitat. Access tokens are sent as API query parameters, read from
  a private temporary file to keep them out of curl's process arguments. Keep
  config files private and do not run with `bash -x`, which exposes secrets.
- Maker API may reject commands even when the device lists them. Parameters
  containing commas are subject to Maker API's own parameter splitting. Empty
  path values (including empty hub-variable values) are not supported. Room
  listing/detail is supported; room editing and driver changes are outside this
  client's command set.

### Documentation and verification

Implemented against Hubitat's official documentation, reviewed November 5, 2026:

- [Maker API endpoints and setup](https://docs2.hubitat.com/en/apps/maker-api)
- [HSM interface and command values](https://docs2.hubitat.com/en/developer/interfaces/hubitat-safety-monitor-interface)
- [App Object: local/cloud API URL formats](https://docs2.hubitat.com/en/developer/app/app-object)

The attribute reference's heading specifies
`/devices/ID/attribute/ATTRIBUTE`, while its example omits `/attribute`. This
client follows the documented heading. Confirm that endpoint with your hub's
generated URLs if your firmware behaves differently.

No live Hubitat endpoint was available during development. Bash syntax checks,
10 local mock-server tests, and an interactive first-run setup check passed.
These verified client behavior, not firmware/driver compatibility. Only the
self-contained shell script is distributed here.
