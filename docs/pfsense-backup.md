# pfsense-backup.sh

[Back to script index](../README.md) · [Script source](../pfsense-backup.sh)

Pull the pfSense configuration XML to a Linux machine over SSH and keep one
backup per day.

## Requirements

Use Bash, the OpenSSH client, `xmllint`, GNU coreutils, and `flock` from
util-linux. On Debian and Ubuntu, `xmllint` is in `libxml2-utils`. On Fedora,
install `libxml2` for `xmllint`.

The pfSense account needs SSH shell access and permission to read
`/cf/conf/config.xml`.

## Set up SSH

On the machine that runs the backups, create a dedicated SSH key.

```bash
mkdir -p -m 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -f "$HOME/.ssh/firewall-backup"
```

For unattended runs, use an SSH agent that the scheduled job can access or a
dedicated key with an empty passphrase. Keep the private key readable only by
the backup account.

In pfSense, enable SSH under **System → Advanced → Admin Access** and add
the contents of `~/.ssh/firewall-backup.pub` to the remote account's
**Authorized Keys** under **System → User Manager**. pfSense regenerates
`authorized_keys` from its configuration, so a key installed with
`ssh-copy-id` can disappear after a reboot or account update.
[Netgate's SSH setup guide](https://docs.netgate.com/pfsense/en/latest/recipes/ssh-access.html)

To select a dedicated key, add a host entry to the backup account's
`~/.ssh/config`.

```sshconfig
Host firewall-backup
    HostName firewall.example.net
    IdentityFile ~/.ssh/firewall-backup
    IdentitiesOnly yes
```

Connect once to verify and accept the firewall's SSH host key. Then test
key-based read access without prompts or printing the configuration.

```bash
ssh -o PreferredAuthentications=publickey -l backupuser firewall-backup true
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o PreferredAuthentications=publickey -l backupuser firewall-backup \
    'test -r /cf/conf/config.xml'
```

## Run a backup

```text
pfsense-backup.sh REMOTE_HOST LOCAL_DIR KEEP_DAYS [REMOTE_USER]
```

```bash
bash ./pfsense-backup.sh firewall-backup "$HOME/backups/pfsense" 14 backupuser
```

The remote host can be a hostname, IP address, or SSH config alias. The
optional remote user defaults to the Linux username running the script.
SSH runs without prompts and requires a trusted host key.

The script creates the destination if needed and saves
`pfSense-YYYYMMDD.xml` using the backup machine's local date. It checks that
the download is well-formed XML with a `<pfsense>` root before replacing a
backup for the same date. A failed SSH transfer or XML check preserves
existing backups. The check verifies the file format. Restore compatibility
depends on the target pfSense version and configuration.

The retention window includes today. With `14`, the script keeps today and
the preceding 13 calendar days. After a successful save, it removes only
older regular files in the destination whose names match the backup pattern
and contain a valid date.

Use a private destination outside the repository and a separate directory for
each firewall. New directories have mode `0700`, and backup files have mode
`0600`. The XML can contain secrets such as VPN keys.
[Netgate's backup caveats](https://docs.netgate.com/pfsense/en/latest/backup/caveats.html)

## Schedule daily backups

After a manual backup succeeds, install the script for the user who owns the
SSH key and open that user's crontab.

```bash
install -D -m 0755 ./pfsense-backup.sh "$HOME/bin/pfsense-backup.sh"
crontab -e
```

This example runs at 6:00 a.m. in the cron daemon's time zone, keeps 14 days
of backups, and leaves error output available to cron.

```cron
0 6 * * * ~/bin/pfsense-backup.sh firewall-backup ~/backups/pfsense 14 backupuser >/dev/null
```
