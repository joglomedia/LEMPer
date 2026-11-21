# Database management and diagnostics

Use `lemperctl db` for MySQL/MariaDB operations. `lemper-cli` remains an alias.
The following behavior is implemented in the v4 working tree.

## SQL backups and restoration

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
old dumps: SQL retention remains planned work.

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
