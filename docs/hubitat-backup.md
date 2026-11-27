# hubitat-backup.sh

[Back to script index](../README.md) · [Script source](../hubitat-backup.sh)

Pull the Hubitat hub database to a Linux machine over HTTP and keep one
backup per day.

## Requirements

Use Bash, `curl`, `file`, GNU coreutils, and `flock` from util-linux. On
Debian and Ubuntu, `file` is in the `file` package. On Fedora, install
`file` for the backup format check.

The hub must be reachable over HTTP from the backup machine. No login is
needed while hub security is off; if hub security is on, the backup
endpoint requires a login session first, so the script stops with an error
instead of saving a login page.

## Run a backup

```text
hubitat-backup.sh HUB_HOST LOCAL_DIR KEEP_DAYS
```

```bash
./hubitat-backup.sh hubitat.local "$HOME/backups/hubitat" 30
./hubitat-backup.sh '2001:db8::10' "$HOME/backups/hubitat" 30
```

Use a hostname, IPv4 address, or IPv6 literal. An IPv6 literal can be bare
or bracketed. For a custom port on an IPv6 address, use brackets, as in
`[2001:db8::10]:8080`. The backup endpoint creates a fresh backup and
downloads it in one request.

The script creates the destination if needed and saves
`Hubitat-YYYYMMDD.lzf` using the backup machine's local date. Before replacing
a backup for the same date, it requires HTTP 200 and checks the H2 file
signature and size. A failed transfer or format check preserves existing
backups and skips retention cleanup. A restore on a compatible hub is needed
to verify the encrypted database contents.

The retention window includes today. With `30`, the script keeps today and
the preceding 29 calendar days. After a successful save, it removes only
older regular files in the destination whose names match the backup pattern
and contain a valid date.

Use a private destination outside the repository and a separate directory for
each hub. New directories have mode `0700`, and backup files have mode
`0600`. The backup contains the hub database, including device settings and
stored credentials, so treat it like any other secret. The local backup
covers the hub database only; the Zigbee and Z-Wave radio data is not
included. Hub Protect cloud backup is the supported way to include it.

## Schedule daily backups

After a manual backup succeeds, install the script and open your crontab.

```bash
install -D -m 0755 ./hubitat-backup.sh "$HOME/bin/hubitat-backup.sh"
crontab -e
```

This example runs at 4:00 a.m. in the cron daemon's time zone, keeps 30 days
of backups, and leaves error output available to cron.

```cron
0 4 * * * ~/bin/hubitat-backup.sh hubitat.local ~/backups/hubitat 30 >/dev/null
```
