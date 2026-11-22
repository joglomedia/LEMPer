# [L]inux [E]ngine-X [M]ariaDB [P]HP Install[er]

<p align="center">
  <img src="/.github/assets/lemper-logo.svg?raw=true" alt="Served by LEMPer Stack © @joglomedia"/>
</p>

<p align="center">
<a href="https://github.com/joglomedia/LEMPer/releases"><img src="https://img.shields.io/github/v/tag/joglomedia/LEMPer?label=version" alt="LEMPer version"></a>
<a href="https://github.com/joglomedia/LEMPer/stargazers"><img src="https://img.shields.io/github/stars/joglomedia/LEMPer.svg" alt="GitHub stars"></a>
<a href="https://github.com/joglomedia/LEMPer/network"><img src="https://img.shields.io/github/forks/joglomedia/LEMPer.svg" alt="GitHub forks"></a>
<a href="https://github.com/joglomedia/LEMPer/issues"><img src="https://img.shields.io/github/issues/joglomedia/LEMPer.svg" alt="GitHub issues"></a>
<a href="https://github.com/joglomedia/LEMPer/actions/workflows/main.yml"><img src="https://github.com/joglomedia/LEMPer/actions/workflows/main.yml/badge.svg" alt="GitHub CI"></a>
<a href="https://raw.githubusercontent.com/joglomedia/LEMPer/master/LICENSE.md"><img src="https://img.shields.io/badge/license-GPLv3-blue.svg" alt="GitHub license"></a>
</p>

<p align="center">
LEMPer stands for Linux, Engine-X (Nginx), MariaDB and PHP installer written in Bash script, also known as LEMP / LNMP installer. This is just a small toolset (a bunch collection of scripts) that I use to deploy and manage LEMP stack on Debian and Ubuntu server. LEMPer is crafted to support wide-range PHP framework & CMS. It is available as <em>Free Alternative</em> to the paid control panel such as cPanel, Plesk, CloudWays, Ploi, RunCloud, ServerPilot, etc.
</p>

## Features

* Nginx - A high performance web server and a reverse proxy server.
  * Community packages from @eilandert's [MyGuard repo](https://deb.myguard.nl/nginx-modules/) (default, includes the module packages) or built from source. The Ondřej nginx repository is no longer published.
  * Custom build from [source](https://github.com/nginx/nginx) featured with :
    * [Brotli module](https://github.com/google/ngx_brotli.git) an alternative compression to Gzip
    * [Lua Nginx module](https://github.com/openresty/lua-nginx-module) with LuaJIT 2 library
    * FastCGI [cache purge module](https://github.com/nginx-modules/ngx_cache_purge.git) for atomic cache purging
    * Customizable SSL library: OpenSSL (default), LibreSSL, and BoringSSL
    * and much more useful 3rd-party modules.
  * Pre-configured optimization for low-end VPS/cloud server, auto-tuned at install time from the host's RAM and CPU (`micro`, `small`, `medium`, `large` profiles). Need reliable VPS/cloud server? Get one from [DigitalOcean](https://masedi.net/l/digitalocean/), [UpCloud](https://masedi.net/l/upcloud/), or [Vultr](https://masedi.net/l/vultr/).
  * Nginx virtual host (vhost) configuration optimized for WordPress and several PHP Frameworks.
  * Per-vhost CORS control with `lemperctl site mod --enable-cors` and `--disable-cors`.
  * HTTP/2 on TLS vhosts, with opt-in HTTP/3 (QUIC) when the Nginx build provides the v3 module.
  * Free SSL certificates from [Let's Encrypt](https://letsencrypt.org/).
  * Get an A+ grade on several SSL Security Test ([Qualys SSL Labs](https://www.ssllabs.com/ssltest/analyze.html?d=masedi.net), [ImmuniWeb](https://www.immuniweb.com/ssl/?id=bVrykFnK), and Wormly).
* PHP - Most used language that [powers 78.9% of all websites](https://w3techs.com/technologies/details/pl-php) around the universe.
  * Community packages from [Ondřej's PHP repository](https://launchpad.net/~ondrej/+archive/ubuntu/php) (Sury on Debian).
  * Multiple PHP versions: 8.2 [Security], 8.3 [Security], 8.4 [Active], 8.5 [Latest, default]. PHP 8.1 is EOL and has no PHP2Shell patch.
  * PHP extensions are installed from apt repositories (Ondřej/Sury, plus the OpenSwoole PPA when selected). PECL/PEAR is no longer bundled: `geoip` and `mcrypt` are abandoned and excluded, and extensions with no package are reported so they can be built manually with [PIE](https://github.com/php/pie).
  * In-place security updater (`lemperctl update`) with compensating controls for EOL branches.
  * Run PHP as user who own the file (Multi-user isolation via FPM pool).
  * Feel the faster Nginx with secure multi-user environment like a top-notch shared hosting.
  * Supported PHP Framework and CMS:
    * Vanilla PHP: default,
    * Framework: codeigniter, laravel, lumen, phalcon, symfony,
    * Content Management: drupal, wordpress, wordpress-ms (multi-site),
    * Web Application: mautic, owncloud, roundcube, sendy, and
    * more coming soon.
  * PHP Zend OPcache (built into the PHP 8.5 binary).
  * PHP Loader, ionCube & SourceGuardian.
* SQL database with MariaDB (MySQL drop-in replacement) or PostgreSQL.
* NoSQL database with MongoDB.
* Key-value store database with Redis or Valkey (`REDIS_BACKEND`).
* In-memory cache with Memcached.
* Modern JavaScript/TypeScript runtime with Bun.js, including an npm-compatible client and bundler (`INSTALL_BUNJS`, enabled by default). Official amd64/arm64 release binaries use published checksums; `BUNJS_INSTALLER="source"` is the preferred method and legacy `repo` selects the same release path.
* FTP server with VSFTPD or Pure-FTPd.
* Web-based administration tools:
  * [Adminer](https://github.com/vrana/adminer) web-based SQL database manager (PhpMyAdmin replacement).
  * [phpRedisAdmin](https://github.com/erikdubbelboer/phpRedisAdmin) web-based Redis database manager.
  * [phpMemcachedAdmin](https://github.com/elijaa/phpmemcachedadmin) web-based Memcached manager.
  * phpOpCacheStatus web-based OPcache status panel.
  * [TinyFileManager](https://github.com/joglomedia/tinyfilemanager) alternative web-based filemanager (Experimental).
* Security hardening:
  * Optional CrowdSec host-based intrusion prevention with WordPress and PHP application scenarios (`INSTALL_CROWDSEC`).
  * Optional ModSecurity v3 WAF with the OWASP Core Rule Set, plus `lemperctl modsec` status, reporting, and auto-tuning (`INSTALL_MODSEC`).
  * Optional config-at-rest encryption (`ENCRYPT_CONFIG_AT_REST`) for LEMPer credentials, keyed by a root-only file (`/etc/lemper/.config_key`).
  * SSL/TLS defaults from the RFC 7919 `ffdhe2048` group, security headers, and optional rate limiting, archive-deny rules, and secure session cookies.
  * Optional HTTP/3 (QUIC) listeners and `Alt-Svc` advertising on TLS vhosts (`NGINX_HTTP3`, requires an Nginx built with `--with-http_v3_module`).
  * Loopback-only Nginx and PHP-FPM status endpoints for local monitoring.

## Setting Up

### Requirements

* Debian 11 (Bullseye) or 12 (Bookworm), or Ubuntu 22.04 or 24.04 (Linux Mint 21–22), on a 64-bit architecture.
* A fresh server with root (sudo) access. LEMPer is designed for a clean install and configures system services directly.
* Bash 5+, curl, tar, SHA256 tools, and a working apt repository connection.

### Install v4 from a release

The commands below target **v4.0.0**. They become available when that release is
published; the existing v3.6.0 release does not contain these bootstrap assets.

Install only the administration CLI with one command:

~~~bash
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0
~~~

The bootstrap downloads the versioned archive and verifies its SHA256 before
installing `lemperctl`. It preserves existing configuration and services.
The bootstrap's own checksum is available as `get-lemper.sha256` on the release.

For a fresh server, prepare a private configuration file first:

~~~bash
curl -fsSL https://raw.githubusercontent.com/joglomedia/LEMPer/v4.0.0/.env.dist -o lemper.env
chmod 0600 lemper.env
${EDITOR:-vi} lemper.env
~~~

Set `SERVER_HOSTNAME`, `SERVER_IP`, `LEMPER_ADMIN_EMAIL`, and `RSA_PUB_KEY`
to your server details, email, and SSH public key. Choose the PHP versions and
optional services in this file. On ARM64, select `NGINX_INSTALLER="source"`
while MyGuard has no compatible ARM64 Nginx binary.

Unattended installation now defaults to key-only SSH. Generate an ed25519 key
on your local computer and set RSA_PUB_KEY in your profile to its public key before
installing. The installer rejects a missing or invalid key before changing the
server. An explicit SSH_PASSWORDLESS=false supports a staged migration.
Previous SSH firewall ports remain allowed until you confirm a working login
and deliberately retire those allowances.

Then install the core service profile with one command:

~~~bash
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0 --install --config ./lemper.env --minimal --yes
~~~

`--minimal` installs Nginx, PHP, MariaDB, Certbot, Fail2ban, and the CLI.
It disables optional databases/caches, FTP, mail, Bun, ImageMagick, CrowdSec,
ModSecurity, and web administration panels. SSH and firewall policy still follow
your configuration. Optional Nginx source modules are disabled and the distro
PCRE library is used. Omit `--minimal` to install the services selected in the file.

Validate and inspect the plan first by adding `--dry-run`. An invalid profile
or missing SSH key stops installation before host changes.

### Install from a checkout or an installed CLI

~~~bash
git clone https://github.com/joglomedia/LEMPer.git
cd LEMPer
git checkout v4.0.0
cp .env.dist .env
chmod 0600 .env
${EDITOR:-vi} .env
sudo bash install.sh --config .env --minimal --yes
~~~

After the CLI is installed, use the same full-stack flow or manage one service:

~~~bash
sudo lemperctl stack install --all --config ./lemper.env --minimal --yes
sudo lemperctl stack install php --php-version 8.5
sudo lemperctl stack status nginx
~~~

`install.sh`, `remove.sh`, `update.sh`, and `lemper.sh` are compatibility
entry points into the shared lifecycle. Existing `lemper.sh install --with-...`
flags remain supported; configuration files are the preferred v4 interface.

### Remove LEMPer Stack

```bash
sudo lemperctl stack remove --all --yes
# From a checkout: sudo bash remove.sh --yes
```

Full-stack removal is destructive: back up databases and account data first.
For individual components, use `lemperctl stack remove SERVICE`; site reference
and provisioning checks still apply.

Uninstall only tears down services that LEMPer provisioned. A service that
already existed before installation (for example, a pre-installed Nginx) is
left in place with its packages and configuration; set `FORCE_REMOVE=true` in
`.env` to remove it anyway.

### Update an Existing Installation

Legacy installations can be patched in place from a current checkout. The bootstrap
installs the latest CLI and updater plugin, reinstalls the administration tools
from `scripts/install_tools.sh` (CLI plugins, Adminer, the file manager, and the
PHP status panels), records the checkout path, and then patches the stack
through the configured apt repositories.

```bash
sudo ./update.sh                 # reinstall admin tools, then update PHP, nginx, MariaDB, CLI
sudo ./update.sh --check         # install updater, then audit without patching or reinstalling tools
sudo ./update.sh --install-only  # reinstall admin tools; do not change stack packages
```

For an existing server, install the v4 CLI without `--install` so its
configuration and services are preserved, then check and update packages:

```bash
sudo lemperctl backup create
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0
sudo lemperctl update check
sudo lemperctl update all --yes
```

If an older installation has only `lemper-cli`, use that alias for the initial
backup. Do not rerun a fresh-server full installation as an upgrade. EOL PHP
branches still require an explicit migration target, as described below.

Once installed:

```bash
sudo lemperctl update check     # exit 0 only when every PHP branch is patched
sudo lemperctl update all
sudo lemperctl update php --post-max-size=8M
sudo lemperctl update nginx
```

`lemperctl update nginx` disables a retired Ondřej nginx APT source (that
PPA now answers 403) and upgrades a package-managed Nginx from the MyGuard
nginx-only repository. The Ondřej PHP repository stays enabled. MyGuard's
Nginx is mainline and links `libssl-nginx` beside the system OpenSSL, and
existing files in `/etc/nginx` are kept. Back up `/etc/nginx` before the
first switch from an Ondřej build; that package switch is not yet verified
on a live server.

The updater remediates **PHP2Shell** (CVE-2026-109618 / CVE-2026-109619) by installing
PHP 8.2.35+, 8.3.36+, 8.4.27+, or 8.5.12+ from the configured apt repositories. PHP 8.1
and older branches have no vendor patch. Move those vhosts with an explicit destination:

```bash
sudo lemperctl update php --migrate-to=8.3
# --force=8.3 is the same switch. A bare --force is rejected.
```

That rewrites EOL `fastcgi_pass` sockets and EOL `set $php_version` lines, creates
the destination FPM pool for each pool user when it does not exist yet, runs
`nginx -t`, and reloads. The pool user comes from `phpX.Y-fpm.USER.sock`; a bare
socket uses the `www` pool. Old packages and pools stay installed, and the previous
vhosts are kept under `/etc/lemper/backups/php-migrate-<UTC>/`. Without
`--migrate-to`, the updater still backs up EOL pools and admin-locks compensating
controls (`memory_limit=-1`, `post_max_size=32M`, `session.upload_progress.enabled=0`,
and `fatal_error_backtraces=0` on PHP 8.5). Source-built nginx is detected and
reported as needing a rebuild.

### LEMPer Command Line Administration Tool

Use `lemperctl` to create virtual hosts and manage the LEMPer stack. The legacy
`lemper-cli` command remains available as a compatibility symlink to the same CLI.

An interactive TUI is available for menu-driven management, live service logs, a guided site-creation wizard, and hardware, disk, and network benchmarks:

```bash
sudo lemperctl tui
```

#### LEMPer CLI Usage

Here are some examples of using LEMPer CLI.

##### PHP runtime defaults and Laravel applications

Select an installed PHP default for the system CLI and new sites:

```bash
sudo lemperctl stack config php --default-runtime=php@8.4
```

Existing vhosts keep their explicit FPM runtimes. The command preserves profile
encryption and rolls back alternatives if the change fails.

Mount an existing Laravel project under a managed domain:

```bash
sudo lemperctl site app add example.com --mount /demo \
  --webroot /home/lemper/apps/demo --runtime php@8.4 --runtime-user lemper
sudo lemperctl site app update example.com --mount /demo --runtime php@8.3
sudo lemperctl site app remove example.com --mount /demo --yes
```

Laravel mounts expose only `public/`, preserve their URL base path, and retain
project data on removal. See [the PHP/Laravel guide](docs/PHP_RUNTIME_LARAVEL.md)
for pool requirements, root-domain sites, redirects, migration, and recovery.

##### Site diagnostics and domain database backups

```bash
sudo lemperctl site show example.com --all
sudo lemperctl site show example.com --json
sudo lemperctl db backup example.com
sudo lemperctl db restore example.com /var/backups/lemper/ARCHIVE.sql.gz
sudo lemperctl db backup-schedule example.com --dbschedule='0 2 * * *'
```

Diagnostics include FPM configuration, certificate validity and site/application
ownership, with credential-bearing fields redacted. Python 3 supports both text
and JSON views. Domain DB commands require recorded site ownership and a database
mapping; explicit `--dbname`/`--dbfile` commands remain supported. See
[DATABASE.md](docs/DATABASE.md) for restore and retention behavior.

##### Hosting plans and quotas

Use a quota-ready ext4 filesystem for tenant disk and inode limits:

```bash
sudo lemperctl stack install quota
sudo lemperctl hosting check
sudo lemperctl hosting plan put starter \
  --disk-soft=1G --disk-hard=2G --files-soft=50000 --files-hard=60000
sudo lemperctl account alice --plan=starter
sudo lemperctl hosting status
sudo lemperctl hosting detach alice --yes
```

Enable filesystem user quotas through your distribution/provider before assigning
plans. LEMPer checks support and preserves existing limits; it does not remount
filesystems or replace the kernel. See [the hosting guide](docs/HOSTING.md) for
upgrades, recovery, unsupported filesystems and resources outside the quota.

##### Mail hosting

Host multiple mail domains with Postfix, Dovecot, and per-domain DKIM keys.
Prepare a certificate for `MAILER_HOSTNAME`, configure `SENDER_DOMAIN` and
`MAILER_CERT_PATH`, then install the mail component:

```bash
sudo lemperctl stack install mailer
sudo lemperctl mail account add admin@example.com
sudo lemperctl mail alias add postmaster@example.com admin@example.com
sudo lemperctl mail domain add example.net
sudo lemperctl mail account add sales@example.net
sudo lemperctl mail account edit sales@example.net --disable
sudo lemperctl mail dns example.net
```

Mailbox passwords are prompted securely. Clients use authenticated STARTTLS on
port 587 and IMAP TLS on port 993. Removing an account retains its mail unless
`--purge --yes` is specified. See [the mail guide](docs/MAIL.md) for DNS,
certificates, aliases, account deletion, existing-server migration, and backups.

##### LEMPer CLI add new vhost / website

```bash
lemperctl site add -u ${USER} -d example.test -f wordpress \
-w ${HOME}/webapps/example.test --install-app
```

:warning: For local/development environment, in order to make the test domain (e.g. example.test) working as expected, you need to do a small workaround by modifying the `/etc/hosts` file. By adding the local domain name to the hosts file and assign it with local/private IP address.

For a local development site, pass the local/private IP address with `--ipv4`:

```bash
lemperctl site add -u ${USER} -d example.test -f wordpress \
-w ${HOME}/webapps/example.test --ipv4=127.0.10.1 --install-app
```

For more info

```bash
lemperctl site add --help
```

##### LEMPer CLI manage vhost / website

Example, enable SSL

```bash
sudo lemperctl site mod --enable-ssl example.test
```

Example, enable FastCGI cache

```bash
sudo lemperctl site mod --enable-fastcgi-cache example.test
```

Example, enable or disable CORS

```bash
sudo lemperctl site mod --enable-cors example.test
sudo lemperctl site mod --disable-cors example.test
```

`--enable-cors` allows every origin by default. To restrict it, edit the
`set $cors` line in `/etc/nginx/includes/cors-example.test.conf` and reload
Nginx (`sudo systemctl reload nginx`).

For more info

```bash
sudo lemperctl site mod --help
```

##### LEMPer CLI SQL backups and site diagnostics

```bash
sudo lemperctl db backup --dbname=appdb
sudo lemperctl db restore --dbname=appdb --dbfile=/var/backups/lemper/ARCHIVE.sql.gz
sudo lemperctl db backup-schedule --dbname=appdb --dbschedule='0 2 * * *'
sudo lemperctl site show example.com --json
```

SQL dumps publish atomically with mode `0600`; failures leave no incomplete
backup. Use root-owned backup directories and protected password files.
`site show` redacts stored passwords; `--json` implies `--all`.
See [database management](docs/DATABASE.md) for input limits, password changes,
scheduling, restoration, and repository-key migration. SQL retention is available with `db prune --keep=COUNT` or `SQL_BACKUP_KEEP`.

##### LEMPer CLI back up and restore configuration

`lemperctl backup` archives the configuration LEMPer manages — Nginx, PHP,
MySQL/MariaDB, Redis/Valkey, Memcached, Fail2ban, CrowdSec, ModSecurity
tuning, mail, FTP, Let's Encrypt, `/etc/lemper`, and legacy `.env` files — so
a broken change can be rolled back. Web content and database data are not
included.

```bash
sudo lemperctl backup create          # archive to /var/backups/lemper/config
sudo lemperctl backup list            # list archives
sudo lemperctl backup show latest     # print the newest archive manifest
sudo lemperctl backup restore --latest --reload
sudo lemperctl backup prune --keep 5
```

`restore` verifies the archive and the member allow-list first, writes a
pre-restore snapshot to the same directory, runs `nginx -t` afterwards, and
rolls back automatically if the test fails. Archives contain credentials and
private keys, so they are created root-only (mode 0600).

Custom legacy checkout `.env` paths are accepted only when recorded locally in
`/etc/lemper/update-source` or supplied with `LEMPER_LEGACY_DIR`. Restoring an
archive on another host may require that explicit checkout-directory override.

##### Optional data backups, firewall and monitoring

```bash
sudo lemperctl stack install restic --yes
sudo lemperctl data backup /home/lemper/webapps /var/vmail
sudo lemperctl data schedule /home/lemper/webapps /var/vmail
sudo lemperctl data prune --keep=7
sudo lemperctl stack install monit --yes
sudo lemperctl monitor status
sudo lemperctl stack install nftables --yes
sudo lemperctl firewall status
```

Restic encrypts application/mail backups and restores into empty staging directories.
Monit provides authenticated loopback health status and opt-in SMTP alerts. Native
nftables preserves unrelated tables and arms SSH recovery until confirmation;
active UFW requires explicit `--migrate-from-ufw`. Both optional services default
to disabled and minimal profiles skip them. Read [data backups](docs/DATA_BACKUP.md),
[firewall migration](docs/FIREWALL.md), and [monitoring](docs/MONITORING.md) before
configuring repositories, retention, firewall changes or alerts.

##### LEMPer CLI benchmark the server

`lemperctl bench` reports hardware details, measures disk write/read speed,
and downloads a test file from global endpoints. Downloads use curl's own
speed counter with a per-endpoint timeout, and endpoints that fail are
reported as unavailable instead of printing an empty speed.

```bash
sudo lemperctl bench                          # hardware, disk, and network
sudo lemperctl bench --hardware --disk        # no downloads
sudo lemperctl bench --network --size 100 --timeout 60
sudo lemperctl bench --disk --disk-size 1024
```

The same tests are available from the TUI under **Benchmark**. Network tests
use bandwidth: each endpoint receives the configured test size (default
32 MB).

##### for more help

```bash
sudo lemperctl help
```

Note: LEMPer CLI automagically create new PHP-FPM user's pool configuration if it doesn't exists. You must add the user account first.

### Site/service commands and release bootstrap

`lemperctl` is the preferred CLI name; `lemper-cli` remains compatible.

~~~bash
sudo lemperctl site create example.com --type=wordpress --runtime=php@8.5 \
  --runtime-user="$USER" --install-skeleton --webroot="$HOME/example.com"
sudo lemperctl site update example.com second.example.com --ssl-enable --cors-enable
sudo lemperctl site enable example.com
sudo lemperctl site remove example.com              # retain application data
sudo lemperctl site remove example.com --purge       # remove recorded site-owned data
sudo lemperctl stack install nginx
sudo lemperctl stack restart php                     # all installed PHP-FPM versions
sudo lemperctl stack restart php --php-version 8.5
sudo lemperctl stack update php --php-version 8.4
sudo lemperctl stack remove php --php-version 8.1 --yes
sudo lemperctl stack status valkey
sudo lemperctl config check
~~~

`site add`, `manage/mod`, and `delete` alias create, update, and remove.
Feature-first flags such as `--ssl-enable` and legacy `--enable-ssl` share
behavior. Legacy create flags remain accepted. Batches reject conflicting actions
and invalid domains before mutation, return failure if any target fails, and
validate/reload Nginx after the batch.

Removal retains application data by default. `--purge` deletes the recorded
document root and site-owned application database after ownership/reference
checks. Shared accounts, PHP pools, certificate state and service packages are
retained. `--yes` bypasses confirmation separately; `--dry-run` makes no
changes. Existing sites can explicitly adopt ownership metadata before purge:

~~~bash
sudo lemperctl site adopt example.com --runtime-user="$USER" --runtime=php@8.1
~~~

Adoption checks the configured document root and its owner, then asks you to assert
ownership of that root and the application's recorded database. An explicit
`--webroot` must match the configured root. Adoption changes metadata; it
does not install or migrate PHP.

PHP installation permits 8.2–8.5. Management/removal resolves installed versions,
including EOL. Versionless update/control targets all installed versions (FPM
instances for control). Multi-version removal requires `--php-version` or
`--all-versions`; site references block removal. Supported PHP updates combine
package upgrades and security remediation; EOL updates retain the explicit
mitigation/migration policy of `update php`.

Install/remove uses recorded source and installed configuration. Removal requires
provisioning markers (per version for PHP); `--force` permits removal of a
pre-existing component while retaining site reference checks. Source builds
requiring a rebuild are reported.

`get-lemper --version VERSION` verifies the release SHA256 and installs CLI code
under `/opt/lemper/VERSION`. An atomic `/opt/lemper/current` selector and
compatibility links keep CLI/library code on one release. Configuration stays
under `/etc/lemper`. Full installation and tooling refresh share this registry
and export path. Selecting older code does not restore packages, databases or
service configuration. The default bootstrap installs no services;
`--install --config FILE` explicitly selects full-stack installation.
Release assets are published by the version-tag workflow.

Configuration values are validated before loading. config check also rejects
unknown options and unsupported PHP versions; normal runtime loading preserves
unknown legacy settings so existing installations can still be upgraded.

Hosting accounts created by account have no sudo privileges. account --admin
grants a new account restricted service administration; account --restrict-sudo
USERNAME deliberately migrates a recorded LEMPer account away from broad sudo.
Account credentials are saved in root-only /etc/lemper/accounts/USERNAME.conf.
App and service credentials are no longer printed in installation output or logs.

Wildcard SSL uses Cloudflare or DigitalOcean DNS-01 credentials for both issuance
and renewal. Set ACME_DNS_PROVIDER and ACME_DNS_API_TOKEN; unattended wildcard
installation also requires a configured server hostname. Credentials are stored
in a root-only provider file.

### Web-based Administration

You can access pre-installed web-based administration tools here.

```bash
http://YOUR_IP_ADDRESS:8082/lcp/
```

Adminer (web-based SQL database manager)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/dbadmin/
```

TinyFileManager (web-based file manager)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/filemanager/
```

phpOpCacheStatus (OPcache status panel)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/opcache.php
```

phpMemcachedAdmin and phpRedisAdmin

```bash
http://YOUR_IP_ADDRESS:8082/lcp/memcadmin/
http://YOUR_IP_ADDRESS:8082/lcp/redisadmin/
```

## TODOs

Implemented:

* [x] Add support for Debian (Bullseye, Bookworm) & Ubuntu (Jammy, Noble) distro
* [x] Add custom build latest [Nginx](https://nginx.org/en/) from source
* [x] Add [Let's Encrypt SSL](https://letsencrypt.org/)
* [x] Add network security (iptable rules, firewall configurator, else?)
* [x] Add database backup tool (Mariabackup, Percona Xtrabackup, else?)
* [x] Add PostgreSQL database (SQL object-relational database system)
* [x] Add Pure-FTPd installation as an alternative option to VSFTPD
* [x] Add enhanced security (firewall, Fail2ban, CrowdSec, ModSecurity WAF)
* [x] Add CrowdSec a modern Host-based Intrusion Prevention System (modern-replacement for Fail2ban)
* [x] Add Bun.js JavaScript/TypeScript runtime (npm-compatible client and bundler)
* [x] Add in-place security updater (`lemperctl update`, PHP2Shell remediation)
* [x] Add interactive TUI dashboard and site-creation wizard
* [x] Add user account management (`lemperctl account`, PHP-FPM pool isolation)

Further capabilities implemented:

* [x] Add encrypted application/mail file backups (Restic), scheduling, retention and staged restore
* [x] Add managed Monit health checks, authenticated loopback status and opt-in SMTP alerts
* [x] Add hosting disk/inode plans, per-user quota enforcement and guarded provisioning

Broader CPU/RAM/bandwidth limits and additional filesystem quota backends remain optional follow-up work.

Add your feature [request here](https://github.com/joglomedia/LEMPer/issues/new)!

## Security Vulnerabilities and Bugs

If you discover any security vulnerabilities or any bugs within _LEMPer Stack_, please open an [issue](https://github.com/joglomedia/LEMPer/issues/new).

## Contributing

* Fork it ([https://github.com/joglomedia/LEMPer/fork](https://github.com/joglomedia/LEMPer/fork))
* Create your feature branch (git checkout -b my-new-feature) or fix issue (git checkout -b fix-some-issue)
* Commit your changes (git commit -am 'Add some feature') or (git commit -am 'Fix some issue')
* Push to the branch (git push origin my-new-feature) or (git push origin fix-some-issue)
* Create a new Pull Request
* GitHub Workflows will be run to make sure that your changes does not have errors or warning

## Awesome People

**LEMPer Stack** is an open-source project licensed under the GNU GPLv3 license with its ongoing development made possible entirely by the support of all these smart and generous people, from code contributors to financial contributors. :purple_heart:

Thank you for considering contributing to this project!

### Project Maintainers

<table>
  <tbody>
    <tr>
        <td align="center" valign="top">
            <img width="125" height="125" src="https://github.com/joglomedia.png?s=150">
            <br>
            <strong>Edi Septriyanto</strong>
            <br>
            <a href="https://github.com/joglomedia">@joglomedia</a>
        </td>
     </tr>
  </tbody>
</table>

### Code Contributors

<a href="https://github.com/joglomedia/LEMPer/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=joglomedia/LEMPer" />
</a>

Made with [contributors-img](https://contrib.rocks).

### Financial Contributors

You can support development by using any of the methods below:

**[Buy Me a Bottle of Milk or a Cup of Coffee](https://paypal.me/masedi) !!**

## Licence

LEMPer Stack is open-source project licensed under the GNU GPLv3 license.

## Copyright

(c) 2014-2026 | [MasEDI.Net](https://masedi.net/)

### Enjoy LEMPer Stack ;)

Real installation/CLI UAT is documented in
[DEVELOPER.md §3.4.4](DEVELOPER.md#344-real-installation-and-cli-uat). Native
ARM64 testing uses the source Nginx profile while the MyGuard repository lacks
an ARM64 binary candidate. `ACME_REGISTER_ACCOUNT=false` installs Certbot and
renewal hooks without creating an external account.
See [UAT_REPORT.md](docs/UAT_REPORT.md) for the tested profile, results, and limitations.
