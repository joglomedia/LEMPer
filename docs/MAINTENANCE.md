# Updates, backups and removal

Back up configuration, databases and application data before changing an existing
server. Full installation is intended for fresh servers; use the updater for
an existing installation. See [installation](INSTALLATION.md) for bootstrap options.

## Backups

Choose the backup that matches the data you need to recover:

| Data | Command | Guide |
|---|---|---|
| Managed service configuration and credentials | `lemperctl backup` | [Configuration backups](#configuration-backups) |
| SQL databases | `lemperctl db backup` | [Database management](DATABASE.md) |
| Application files and mail | `lemperctl data backup` | [Encrypted data backups](DATA_BACKUP.md) |

## Configuration backups

`lemperctl backup` archives managed Nginx, PHP, SQL/NoSQL, caches, security,
mail, FTP, Let's Encrypt and LEMPer configuration, including recorded legacy
`.env` files. It excludes application files and database data.

```bash
sudo lemperctl backup create
sudo lemperctl backup list
sudo lemperctl backup show latest
sudo lemperctl backup verify latest
sudo lemperctl backup restore --latest --reload
sudo lemperctl backup prune --keep 5
```

The default archive directory is `/var/backups/lemper/config`. Archives contain
credentials and private keys: they use mode `0600` in a root-only directory.
Keep protected copies away from public web roots.

Restore verifies archive integrity and allowed members, creates a pre-restore
snapshot, then validates Nginx. A failed Nginx check rolls back the restoration.
`--reload` reloads Nginx and PHP-FPM after successful validation; `--dry-run`
inspects the restore without applying it. The command prompts before restoration
unless `--yes` is supplied.

Custom legacy `.env` locations must be recorded in `/etc/lemper/update-source`
or supplied through `LEMPER_LEGACY_DIR`. Restoration to another host may require
that explicit checkout-directory override. Run `lemperctl backup --help` for
archive selection and retention options.

## Update an existing server

Install only the pinned v4.0.0 CLI before updating packages:

```bash
sudo lemperctl backup create
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0
sudo lemperctl update check
sudo lemperctl update all --yes
```

Use `lemper-cli` for the initial backup if that is the only installed alias.
Do not add `--install` to this bootstrap upgrade: full installation is a separate
operation. `update check` audits PHP remediation and returns zero only when all
installed branches pass its checks.

Individual updates are available:

```bash
sudo lemperctl update php --php-version=8.4
sudo lemperctl update php --post-max-size=8M
sudo lemperctl update nginx
sudo lemperctl update mariadb
```

PHP installation and updates share the maintained Sury archive driver. Existing
PHP PPA/Sury sources migrate with backups and rollback, preserving unrelated
sources and shared keys. See [repository migration](UBUNTU_26_04.md).

Nginx updates disable retired Ondřej Nginx sources and use MyGuard for packaged
Nginx. Existing `/etc/nginx` files are retained; back them up before switching
package providers. MyGuard supplies its own `libssl-nginx`. Source builds are
reported as needing a rebuild. The MyGuard package-provider switch has not been
verified on a native AMD64 server; ARM64 currently needs the source profile.

These commands do not upgrade the operating system or automatically migrate a
database/mail major version. Follow the platform and upstream migration guidance.

## PHP security updates and EOL migration

The updater remediates PHP2Shell (CVE-2026-109618 / CVE-2026-109619) with PHP
8.2.35+, 8.3.36+, 8.4.27+ or 8.5.12+. PHP 8.1 and older have no vendor patch.
Select an explicit installed destination for EOL sites:

```bash
sudo lemperctl update php --migrate-to=8.3
```

`--force=8.3` is a compatibility alias; bare `--force` is rejected. Migration
rewrites EOL FPM sockets and `set $php_version` lines, creates destination pools
for their users, validates Nginx and reloads it. Old packages/pools remain
installed; previous vhosts are saved under `/etc/lemper/backups/php-migrate-<UTC>/`.

Without migration, the updater backs up EOL pools and applies administrative
compensating controls: `memory_limit=-1`, `post_max_size=32M`,
`session.upload_progress.enabled=0`, and `fatal_error_backtraces=0` on PHP 8.5.
These controls do not replace a vendor patch. Check application compatibility
before changing runtimes; see [PHP and Laravel](PHP_RUNTIME_LARAVEL.md).

## Legacy checkout updates

From a current, reviewed checkout:

```bash
sudo bash update.sh
sudo bash update.sh --check
sudo bash update.sh --install-only
```

The default refreshes administration tools, records the checkout and updates
stack packages. `--check` installs the updater and audits without patching or
refreshing web tools. `--install-only` refreshes tools without updating stack
packages. Installed configuration is preserved.

## Remove the stack or a service

```bash
sudo lemperctl stack remove --all --yes
sudo lemperctl stack remove redis --yes
# Compatibility entry point from a checkout:
sudo bash remove.sh --yes
```

Full-stack removal can destroy service state; verify your backups first. Removal
uses provisioning markers and site-reference checks. Pre-existing components are
retained unless explicitly forced; per-service `--force` and the legacy
`FORCE_REMOVE=true` profile setting permit deliberate removal of unowned services.
Custom database data directories require deliberate cleanup.

Site removal normally retains application data. `site remove DOMAIN --purge`
deletes recorded, site-owned data after ownership/reference checks; `--yes`
skips confirmation separately. See [site ownership](CLI.md#site-ownership-and-removal)
before purging a site.
