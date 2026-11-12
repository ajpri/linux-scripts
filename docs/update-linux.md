# update-linux.sh

[Back to script index](../README.md) · [Script source](../update-linux.sh)

Run this script to refresh package metadata, install updates, remove unused
dependencies where supported, and clean downloaded packages. It looks for
`apt-get`, `dnf`, `yum`, `pacman`, and `zypper` on `PATH`, in that order.

- **APT, DNF, and YUM** upgrade packages and remove unused dependencies. APT
  removes obsolete downloads with `autoclean`. DNF and YUM clear their downloaded
  package caches.
- **Pacman** refreshes and upgrades together with `pacman -Syu`. It removes
  packages marked as dependencies that no installed package requires or uses
  as an optional dependency. It uses `paccache -r` from the optional
  `pacman-contrib` package to keep recent cached versions when available.
  Otherwise, `pacman -Sc` uses Pacman's configured cache retention policy.
- **Zypper** uses `zypper dup` on openSUSE Tumbleweed and Slowroll, and
  `zypper update` on Leap and other conventional Zypper systems. It cleans
  downloaded packages. To review unused packages manually, run
  `zypper packages --unneeded`. Transactional openSUSE variants use their own
  updater.

## Run it

```bash
./update-linux.sh                    # Review package manager prompts
./update-linux.sh -y                 # Approve updates and unused dependency removal
./update-linux.sh -y --no-autoremove  # Update and clean caches, keeping unused dependencies
./update-linux.sh --help
```

The script requires Bash, standard Linux utilities, and one of the supported
package managers. Run it directly from your regular account. The system package
and system Flatpak and Snap commands use sudo when needed. The user Flatpak
commands and standalone yt-dlp updater use your account's permissions.

`-y` (also `--assume-yes`) uses non-interactive sudo and approves system and
Flatpak transactions. For APT, it also uses non-interactive debconf, keeps
locally modified configuration files at dpkg and ucf prompts, and asks
needrestart to list affected services where supported. Zypper uses its
non-interactive defaults, including its license and trust policies. Individual packages
may restart their own services during updates. The script never initiates a
reboot. If a maintenance command fails, the script reports the step and returns
its exit status. Completed steps take effect immediately.

`--no-autoremove` skips removal of unused system packages and Flatpak runtimes.
Updates and package-cache cleanup still run.

After successful maintenance, the script prints a reboot notice if it finds
the system's `reboot-required` marker or gets a reboot recommendation from
Zypper or an available DNF or YUM `needs-restarting` tool. The notice is
informational and leaves the exit status unchanged.

## Optional updates

- **Flatpak.** Update apps and runtimes in the default system-wide installation
  and the invoking account's per-user installation, then remove unused runtimes
  from each. Runs as root cover the default system-wide installation.
- **Snap.** On conventional Linux distributions with snapd, run `snap refresh`
  for installed Snaps. A manual refresh can proceed during a system-wide
  auto-refresh hold. Snapd manages revision retention and its own update schedule.
- **yt-dlp.** Check the executable on `PATH`. The system package upgrade covers
  distro-managed copies. Recognized official standalone builds that support
  self-updates use `yt-dlp -U` on their existing channel when the invoking account
  can write the executable and its directory. Pip, pipx, source, and other
  unrecognized builds are skipped. Running the whole script through sudo skips
  the standalone updater.

## Scheduled runs

Run the script with `-y` and ensure the job's `PATH` includes any user-installed
yt-dlp you want to update. Schedule under the regular account to cover that
account's Flatpaks and yt-dlp. The job needs a sudo policy that allows the
system commands without a password, including the environment assignments used
for APT. A job scheduled directly as root covers system packages, system-wide
Flatpaks, Snaps, and supported standalone yt-dlp on root's `PATH`.
