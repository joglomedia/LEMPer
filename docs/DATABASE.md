# Database management and diagnostics

Use `lemperctl db` for MySQL/MariaDB operations. `lemper-cli` remains an alias.
The following behavior is implemented in the v4 working tree.

## SQL backups and restoration

Owned sites also support domain shortcuts:

```bash
sudo lemperctl db backup example.com
sudo lemperctl db restore example.com /var/backups/lemper/ARCHIVE.sql.gz
sudo lemperctl db backup-schedule example.com --dbschedule='0 2 * * *'
```

The domain must have a LEMPer ownership record with a database. Missing or
conflicting legacy mappings fail; reconcile ownership or use the explicit DB
flags below. The shortcut never guesses a name or reads an application's `.env`.

```bash
sudo lemperctl db backup --dbname=appdb
sudo lemperctl db backup --dbname=appdb --dbfile=/var/backups/lemper/sql
sudo lemperctl db export --dbname=appdb --dbfile=/var/backups/lemper/appdb.sql
sudo lemperctl db restore --dbname=appdb --dbfile=/var/backups/lemper/sql/ARCHIVE.sql.gz
sudo lemperctl db import --dbname=appdb --dbfile=/var/backups/lemper/appdb.sql
```

`backup` creates a timestamped gzip SQL dump, with a unique suffix to avoid
same-second collisions. `export` writes plain SQL. Dumps use a transaction
snapshot for transactional tables, publish atomically with mode `0600`, and
report failure without publishing an incomplete file. Nontransactional tables
need a separate consistency strategy if applications continue writing to them.
The backup directory and its existing ancestors must be owned by root and
must not be writable by other accounts. Root-owned sticky `/tmp` and `/var/tmp`
are allowed as ancestors of protected fixture directories. Symlink directories
and output targets are rejected. Do not use a website user's writable directory
as a root backup destination.

`restore` and `import` require an existing database and a readable regular file.
They check compressed input before running SQL, disable local-file loading and
interactive client commands, and propagate decompression/client failures.
Restoration can overwrite database data; use a verified backup and the intended
target. Inspect unfamiliar SQL files before restoring them.

Database identifiers, prefixes and collations use ASCII letters/underscores
followed by letters/digits/underscores, with at most 64 characters. Account names
allow letters/digits/underscores followed by letters/digits/underscores/dots/
hyphens, up to 32 characters. Ports must be between 1 and 65535. Arbitrary
`--extra-args` variable assignment is rejected; the legacy account fields
`dbuser2`, `dbhost2`, `dbpass2`, and `dbrootpass` remain accepted.

Default `localhost:3306` connections retain Unix-socket authentication.
Use `--dbhost=127.0.0.1` for TCP or specify a remote host/custom port.

## Passwords and scheduling

Use a root-owned password file with mode `0600`, or `LEMPER_DB_PASSWORD` in a
protected process environment. `--dbpass` is retained for compatibility but
appears in the caller's process arguments. Do not place secrets in shell history.

```bash
sudo lemperctl db account create --dbuser=appuser --dbpass-file=/root/app-db.pass
sudo lemperctl db account passwd --dbuser=appuser --dbpass-file=/root/new-db.pass
sudo lemperctl db backup-schedule --dbname=appdb --dbschedule='0 2 * * *'
sudo lemperctl db backup-schedule --dbname=appdb --dbuser=appuser \
  --dbpass-file=/root/app-db.pass --dbfile=/var/backups/lemper/sql \
  --dbschedule='*/15 2-4 * * 1,5'
```

Passwords must be single-line values. Password changes accept the new value through the same protected file interface;
quotes and backslashes remain literal password data. Scheduled backups accept
five numeric cron fields with wildcards, lists, ranges and positive steps.
Names, shell fragments and `%` separators are rejected. Scheduled output paths
must be absolute and contain only letters/digits/underscores/dots/slashes/hyphens.

A repeat schedule replaces only the entry for that exact database and preserves
other jobs. Generated commands use `lemperctl`, retain host/port/output settings,
and store explicit credentials under `/etc/lemper/backup-credentials/` with
mode `0600`. Root backups without an explicit password use the configured root
credential or local socket authentication. Changing a schedule does not prune
old unmanaged dumps. Use `db prune` or opt into managed SQL retention as below.

`--dry-run` validates inputs without creating backup directories, replacing
exports, restoring SQL, or writing credentials/crontabs. Configuration backups
from `lemperctl backup` are a separate feature and exclude database data.

## Site diagnostics

```bash
sudo lemperctl site show example.com --app
sudo lemperctl site show example.com --json
```

Text metadata and JSON redact database/admin passwords and include only known
public metadata fields. `--json` implies `--all` and returns one JSON object;
`-j` remains equivalent. Malformed metadata fails without printing secret-bearing
parse errors. Root access is still required. For deliberate credential recovery,
read the root-only `/etc/lemper/vhost.d/DOMAIN.conf` file in a private terminal;
diagnostic commands do not disclose those values.

## APT repository migration

PHP/Sury, the PHP and optional OpenSwoole PPAs, and MariaDB use repository-specific
`Signed-By` keyrings. PPA fingerprints require exactly the expected primary key; the MariaDB keyring retains
upstream checksum verification. The installer does not execute a downloaded
MariaDB setup helper. The retained bundled helper also emits scoped source lines.
Existing PHP/MariaDB repository selections are preserved and scoped in place.

Changed `.list`/`.sources` files retain a `.lemper-before-key-scope` backup.
Mixed-repository deb822 `URIs` stanzas must be split before assigning a key.
Dedicated legacy key files are retired only when all fingerprints belong to the
scoped keyring and no active source still references the filename. Shared and
unrelated keyrings are preserved for explicit review. Migration errors stop
installation; failed key downloads do not replace an existing key.

## SQL retention

```bash
sudo lemperctl db backup --dbname=appdb --keep=7
sudo lemperctl db prune --dbname=appdb --dbfile=/var/backups/lemper --keep=7
```

`SQL_BACKUP_KEEP=0` defaults to no automatic rotation. Set a positive count in
configuration or pass `--keep` when backing up to prune after a successful dump.
New gzip dumps receive a root-only SHA256 sidecar. Pruning checks ownership,
filename shape, checksum and gzip validity, then keeps the newest successful
archives for that exact database. Same-second dumps use file timestamps to break
ties. Other databases, plain SQL exports, symlinks, corrupt dumps and unmanaged
legacy archives are preserved. Use `--dry-run` to review deletion selections.

## MariaDB backup-account provisioning

The MariaDB installer reconciles a dedicated local backup account on initial
installation and when the server is already present. `MARIABACKUP_USER` and
`MARIABACKUP_PASS` are the canonical settings. Legacy
`MARIABACKUP_USERNAME`/`MARIABACKUP_PASSWORD` are accepted, then cleared when the
canonical settings are saved. The template user `lemperdb` yields to a supplied
legacy name; conflicting explicit names/passwords are rejected. `root` cannot
be used as the backup account.

A new account gets a generated password when none is supplied. An existing
account requires working supplied credentials or credentials recovered from its
legacy backup configuration; provisioning verifies authentication and preserves
its password. It repairs a missing drop-in and grants the backup permissions.
Configured credentials, including quotes and backslashes, remain literal data.
Passwords must be single-line values without control characters. Dotenv loading
and schema validation remove one matching outer quote pair and preserve inner
quotes. The shared writer adds an outer wrapper when required to preserve actual
quote characters through repeated profile updates/merges.

The installer writes `/etc/mysql/mariadb.conf.d/50-mariabackup.cnf` and the
updated LEMPer profile atomically with mode `0600`, preserving profile encryption
and unrelated settings. Previous files have protected `.pre-backup.*`,
`.pre-root.*` or `.pre-inline.*` recovery copies. Known legacy inline credentials
are moved into `.lemper-inline-mariabackup.cnf` with mode `0600`; `my.cnf` includes
that file at the original position so intervening tuning keeps its precedence.
The include and canonical drop-in are synchronized. Other groups and distribution
symlinks are preserved. Inline migration precedes database authentication, and
trusted legacy drop-ins are made private even when later authentication fails.
Custom inline backup tuning needs explicit reconciliation rather than silent removal.

Legacy option recovery uses a Python 3 guard and MariaDB's native option parser.
The installer supplies Python 3 when needed. Untrusted includes and encoded
control characters are rejected before recovery can truncate or reinterpret them.

Root credentials are saved privately before bootstrap SQL changes. RNG and
profile-write failures stop installation. Backup credentials are saved before
account/grant mutations so a failed operation can
be retried without losing a newly generated password. No existing account is
reset or dropped. Failures return a nonzero status; dry-run creates no files,
queries, accounts or grants. Native MariaDB backup/prepare is validated separately
from the managed logical SQL backup/restore commands above.
