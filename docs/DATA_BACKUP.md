# Encrypted application and mail backups

Restic is the optional data-backup backend. It is separate from SQL dumps and
`lemperctl backup`, which archives configuration. New installs default to
`INSTALL_RESTIC=false`; minimal profiles skip it.

## Install and configure

Set `RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE` in the installed profile
before installation if you need custom locations. Defaults are an encrypted
repository at `/var/backups/lemper/data` and a root-only password file at
`/etc/lemper/restic.pass`.

```bash
sudo lemperctl stack install restic --yes
sudo lemperctl data init
sudo lemperctl data backup /home/lemper/webapps /var/vmail
sudo lemperctl data snapshots
sudo lemperctl data check
```

Installation generates a password file only when missing and opens an existing
repository before attempting initialization. Existing repositories that cannot
be opened are reported as failures. Keep a protected offline copy of the password:
repository data cannot be recovered without it. Never include that password in
process arguments, logs, shell history, or the repository being protected.

Local repository directories and existing ancestors must be root-owned and not
writable by other accounts. Absolute application/mail directories are accepted;
pseudo-filesystems, symlink source roots and sources containing their own
repository are rejected. Restic does not follow file symlinks when backing up.

Remote Restic S3, B2, Azure, GCS, HTTPS REST and SFTP repositories are accepted as
configuration data. Credentials belong in protected environment/provider files;
embedded URL passwords are rejected. SFTP accepts a safe user/host and absolute
path, with SSH keys/known-host verification configured separately. Remote backend
credentials, permissions and restore access must be tested for that destination.
Local encrypted repositories were used in this implementation's UAT.

## Scheduling and retention

```bash
sudo lemperctl data schedule /home/lemper/webapps /var/vmail
sudo systemctl status lemper-data-backup.timer
sudo systemctl start lemper-data-backup.service
sudo lemperctl data prune --keep=7
```

The daily systemd timer adds a randomized delay and catches up after downtime.
Its root-only path list lives under `/etc/lemper/data-backup/`. Scheduled paths
must contain only letters/digits/underscores/dots/slashes/hyphens. The runner reads
the installed profile, performs the backup, then retains `DATA_BACKUP_KEEP`
successful snapshots per host/path/tag group. Failed backups skip pruning.

Only snapshots tagged `lemper-data` participate in LEMPer retention; unrelated
snapshots are preserved. Restic provides repository locking and authenticated
snapshot storage. Shared LEMPer operation locking serializes scheduled backup,
retention, restore and other managed mutations. Repeated schedules retain a
previous path-list copy and refuse replacing unmarked existing systemd units.

## Restore and removal

```bash
sudo lemperctl data restore latest --target /var/backups/lemper/data-restore
sudo lemperctl data restore SNAPSHOT_ID --target /var/backups/lemper/data-restore
sudo lemperctl stack remove restic --yes
```

Restores require an empty protected staging directory; the driver creates it
with mode `0700`. Verify recovered files, ownership and application behavior
before deliberately replacing live content. Restoration does not overwrite a
populated destination. SQL consistency requires separate database backups;
transactional database files are not safely backed up by merely selecting a
running server's data directory. Maildir/application consistency also depends on
concurrent writers; coordinate maintenance where necessary.

Removal stops the owned timer and removes owned packages, preserving repository,
credentials and scheduling configuration. `--force` permits explicit removal of
an unowned package. `--dry-run` validates selections without changing repositories,
files, timers or restored data.
