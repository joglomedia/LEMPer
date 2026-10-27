# Changelog

All notable changes to LEMPer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.6.0] - 2026-10-27

### Added

- PHP-FPM and Nginx audit hardening:
  - Adaptive resource profiles (`micro`, `small`, `medium`, `large`) that size
    PHP-FPM workers, OPcache, and Nginx from detected RAM and CPU.
  - `nginx-lowend.conf` template for hosts with less than 1 GiB RAM.
  - Opt-in rate limiting, archive-file deny rules, ETag control, and secure
    session-cookie handling (`COOKIE_SECURE`).
- TUI live log streaming for Nginx, PHP-FPM, MariaDB, auth, and Fail2ban logs.
- Interactive site-creation wizard in the TUI.
- `lemper-cli modsec` plugin with `status`, `report`, and `tune --auto` commands
  for OWASP CRS paranoia/threshold tuning with `nginx -t` validation and rollback.
- systemd-resolved DNS cache flushing around ACME DNS-01 issuance and renewal
  deploy hooks.
- SEC-20 through SEC-26 hardening fixes and the SEC-27 PHP2Shell entry in the
  security register.
- Opt-in `rewrite_log` (`NGINX_REWRITE_LOG`) for debugging rewrite rules.
  Enabling it also raises the Nginx error log from `warn` to `notice`, since
  rewrite messages are logged at notice level (issue #169).
- Opt-in HTTP/3 (QUIC): `NGINX_HTTP3=true` adds QUIC listeners, `http3 on`,
  and an `Alt-Svc` header to TLS vhosts. Source builds compile the v3 module
  when a QUIC-capable TLS library is selected, and the installer detects the
  module and skips HTTP/3 when a repository build lacks it (issue #175).
- CORS can be enabled or disabled per vhost with
  `lemper-cli site mod --enable-cors` and `--disable-cors` (issue #52). The
  generated include defaults to a wildcard origin and can be restricted by
  editing its `set $cors` line.
- CI installs and verifies the FTP server (issues #135 and #146). The Ubuntu
  job checks the repository-installed Pure-FTPd service, TLS bundle, and auth
  links, and a new `ftp-source` matrix compiles Pure-FTPd 1.0.54 and VSFTPD
  3.0.5 from source on Ubuntu 22.04 and 24.04.
- `lemper-cli backup` archives and restores the configuration LEMPer manages:
  `/etc/lemper`, Nginx, PHP, MySQL/MariaDB, PostgreSQL, MongoDB,
  Redis/Valkey, Memcached, Fail2ban, CrowdSec, ModSecurity tuning, Let's
  Encrypt, mail, FTP, systemd units, and legacy `.env` files. `create`,
  `list`, `show`, `verify`, `restore`, and `prune` subcommands are included.
  Restore validates archive members against an allow-list, writes a
  pre-restore snapshot, tests Nginx afterwards, and rolls back on failure.
  Archives contain secrets and are created root-only (0600).
- `lemper-cli update php --migrate-to=VERSION` moves every vhost that still
  uses an EOL PHP onto that version. `--force=VERSION` is the same switch;
  a bare `--force` is rejected so the destination stays explicit. EOL
  `fastcgi_pass` sockets and EOL `set $php_version` lines are rewritten.
  The pool user is taken from `phpX.Y-fpm.USER.sock` (a bare socket uses
  `www`). A missing destination pool is copied from the EOL pool, or written
  from a small template when that file is gone. Existing destination pools
  are kept. Nginx is tested before reload, and the previous vhosts are stored
  under `/etc/lemper/backups/php-migrate-<UTC>/`. The old PHP packages and
  pools stay installed.

### Changed

- Default PHP installs are 8.2, 8.3, 8.4, and 8.5. `PHP_VERSIONS` in
  `.env.dist` no longer lists 8.1, and the interactive installer menu
  matches that set. An explicit 8.1 (or any other unsupported version) in
  `PHP_VERSIONS` or `--php-version` is skipped.
- Repository nginx installs use the MyGuard nginx-only APT source
  (`https://deb.myguard.nl/apt/nginx/<codename>`) with a scoped signing key
  and a pin that covers nginx packages only. `NGINX_REPO_SRC=ondrej` selects
  that source; the Ondřej nginx archive is no longer published.
- `./update.sh` and `lemper-cli update lemper` reinstall the administration
  tools by running `scripts/install_tools.sh` from the recorded checkout.
  That refreshes the CLI, every plugin, Adminer, TinyFileManager, and the
  PHP admin panels. The checkout `.env` is used when it exists; otherwise
  the installed `/etc/lemper/lemper.conf` is used. `--check` still audits
  without reinstalling those tools. `--install-only` reinstalls the tools
  and does not upgrade stack packages.
- Install and remove scripts share the 2014-2026 license header and resolve
  the checkout root before loading helpers, so a standalone run no longer
  depends on the caller's working directory. `install.sh`, `remove.sh`, and
  `lemper.sh` answer `--help` before asking for root. The CrowdSec installer
  downloads the upstream release tarball and runs `wizard.sh --bininstall`
  on amd64 (other architectures compile the tagged source), installs the
  current hub collections, and saves the repository setup script instead of
  piping it to bash. Removal stops an inactive CrowdSec unit without
  aborting, deletes wizard-installed binaries and plugins, and runs
  `apt-get autoremove` only after CrowdSec packages were purged.
- All CLI plugins now share one license header (copyright 2014-2026), declare
  `CMD_PARENT`/`CMD_NAME`, and expose `--help`/`--version`. `lemper-encrypt` is
  a library only; it is no longer installed as a no-op CLI plugin. The install
  and update paths create the advertised `create`/`add`/`manage`/`mod` aliases,
  plus the missing `site db`/`site database` links.
- `lemper-cli bench` was rewritten. The old script parsed `wget -q` output,
  which suppresses the progress line, so every download reported an empty
  speed. It now uses curl's speed counter with a per-endpoint timeout,
  downloads current Cloudflare/Vultr/OVH endpoints, reports failed endpoints
  instead of blanks, handles GNU/BusyBox/BSD `dd` output, and cleans up its
  disk test file. New `--hardware`, `--disk`, `--network`, `--size`,
  `--disk-size`, and `--timeout` options replace the all-or-nothing run.
  The TUI gains a Benchmark menu for quick, network-only, and full runs.
- `lemper-cli --help` now nests subcommands one level under their parent
  command instead of padding them to the description column. `update check`
  prints an aligned PHP status table with column widths computed from the
  installed versions, state, and fixed-release values.
- Replaced the deprecated AdminerEvo (4.8.4) web database manager with upstream
  [Adminer](https://github.com/vrana/adminer) 6.2.0, configurable through
  `ADMINER_VERSION` in `.env` (issue #183). Existing `/lcp/dbadmin` files are
  overwritten on upgrade. The install recap no longer checks undefined
  `INSTALL_ADMINER`/`INSTALL_FILEMANAGER` flags and lists both tools when
  Nginx is installed.
- Reorganized the Nginx configuration to remove repeated boilerplate (issue
  #29). The default and admin vhosts now pull PHP-FPM handlers from
  `includes/php_handlers.conf` and the loopback status endpoints from
  `includes/monitoring.conf` instead of repeating 18 handler and status blocks
  in each file. The security/restriction/static-file include order is
  documented in `etc/nginx/includes/README.md` and ARCHITECTURE.md, and stale
  comments in `nginx.conf` and `nginx-lowend.conf` now point at the real
  per-vhost include paths.

### Removed

- PHP 8.1 from the default install set and the shipped configuration.
  `etc/php/8.1/` is gone, the `.php81` Nginx handler is gone, and
  `/lcp/phpinfo.php81` is no longer created. `remove_php.sh` can still
  uninstall a PHP 8.1 that is already on the host. PHP 8.1 is EOL and has
  no vendor patch for PHP2Shell.
- Node.js from the planned installer list. Bun.js is the JavaScript runtime.
- Ubuntu 20.04 (Focal) and Linux Mint 20 support. The preflight check now
  rejects them; the minimum supported Ubuntu release is 22.04 (Jammy).
- Remaining PageSpeed references from the developer docs (ROADMAP, AGENTIC).
  The archived Nginx PageSpeed module was already removed; no PageSpeed
  module, directive, package, or cache configuration remains (issue #178).

### Fixed

- `lemper-cli update php` no longer aborts a branch upgrade when
  `phpX.Y-json` is installed. Current Ondřej packages publish that name
  only as a virtual package provided by the FPM, CLI, and CGI SAPIs, so
  apt reports "no installation candidate" and upgrades nothing else on
  the branch. The retired JSON package is removed, and any other PHP
  package without a candidate is skipped.
- Repository Nginx installs no longer request `libmaxminddb-dev`. Ubuntu's
  development package requires the distro `libmaxminddb0` exactly, while the
  MyGuard nginx archive publishes a newer library that the GeoIP modules
  already depend on. Source builds still install the headers themselves.
- `lemper-cli update` no longer aborts when a legacy Ondřej nginx source
  returns 403. Sources for `ondrej/nginx`, `ondrej/nginx-mainline`, and
  `packages.sury.org/nginx` are disabled before `apt-get update`. The Ondřej
  PHP repository stays enabled. `update nginx` and the nginx step of
  `update all` then enable the MyGuard nginx-only repository, pin those
  packages to `deb.myguard.nl`, and upgrade them while keeping existing
  `/etc/nginx` files (`--force-confold`). MyGuard's current nginx is mainline
  and links `libssl-nginx` beside the system OpenSSL. That Ondřej-to-MyGuard
  package switch has not been verified on a live server.
- `lemper-cli tui` draws its menu again. The menu text was captured by the
  command substitution that reads the selection, so the terminal showed only
  `Select [1-8] or 'q' to quit:` and every choice was ignored.
- `lemper-cli fixpermission` now requires an explicit path and refuses `/`,
  `/etc`, `/usr`, `/var`, and other system roots. Previously a missing argument
  silently did nothing and a bare `/` would have chmod-ed the whole filesystem.
- `lemper-cli account` and `lemper-cli adduser` handle `--help`/`--version`
  before touching the system. `adduser` builds its `useradd` arguments from
  validated values, so empty options are no longer passed as arguments.
- `lemper-cli selfssl`, `site list`, `site show`, and `update` now accept
  `-h`/`--help` and `-v`/`--version` consistently with the other commands.
- `lemper-cli account` validates usernames before using them in `useradd`,
  `sed`, and `.htpasswd` updates.
- TUI menu actions now dispatch through `lemper-cli` instead of executing
  plugin files directly. Plugins expect the CLI's helper functions, so direct
  execution was rejected with "Direct access to this script is not permitted."
  Selecting the Exit menu item also quits now; previously only `q`/`0` worked.
- `lemper-cli tui` now launches. The plugin only ran when executed directly,
  but the CLI sources plugins, so its entry point never fired and the command
  exited silently. The TUI also accepts `--help` and `--version` instead of
  opening the menu.
- Pure-FTPd now starts reliably (issue #135). The installer creates the `ftp`
  system account when it is missing, writes each setting to
  `/etc/pure-ftpd/conf` (the directory `pure-ftpd-wrapper` actually reads),
  generates `/etc/ssl/private/pure-ftpd.pem` as a certificate **and** private
  key bundle instead of pointing TLS at a certificate-only snakeoil PEM, and
  verifies the service after restarting it. Source installs get a native
  systemd unit instead of a copied sysv-generator unit in `/run`. The packaged
  sysv init script is forced into standalone mode, because inetd mode exits
  successfully without listening on port 21. Re-running the installer
  re-applies this configuration, so hosts that already hit the bug are
  repaired in place instead of being skipped.
- VSFTPD can be compiled from source on OpenSSL 3 hosts (issue #146). The build
  now allows deprecation warnings instead of failing on `-Werror`, installs
  `libssl-dev`/`libpam0g-dev`/`libcap-dev`, and the source branch no longer
  falls back to the repository package behind the user's back. TLS is
  configured for TLS 1.2/1.3 and falls back to a generated self-signed
  certificate when no certificate pair exists. The build also finds libpam in
  the multiarch directory, so PAM links on arm64.
- Pure-FTPd source installs target 1.0.54, drop the unneeded MySQL client
  dependency, and no longer install a stale `pure-ftpd.conf` that the packaged
  service ignores.
- `lemper.sh` now runs from its own checkout instead of cloning a nested copy
  of the repository and switching it to `master` on every start-up. It resolves
  the repository root from the script location, enters it before using relative
  paths, and answers `--help` before the root and `.env` checks, so
  `./lemper.sh --help` no longer fails with "dotenv file doesn't exist".
  `BASE_DIR` in `lib/core/lemper-stacks.sh` is now derived from that module's
  location, and `scripts/utils.sh` locates `.env` next to `scripts/` instead of
  rewriting a guessed path with `sed`.
- Re-running the installer now reconciles `PHP_EXTENSIONS` for PHP versions
  that are already installed instead of skipping them entirely. MongoDB, Redis,
  and Memcache are enabled for both the CLI and FPM SAPIs through `phpenmod`
  and verified with `php-fpm<version> -m`; the previous helpers only acted when
  the CLI already reported the module, which left extensions invisible to
  Nginx/PHP-FPM (issue #180).
- `.env` values that contain spaces and `=` padding are parsed intact, so a
  4096-bit OpenSSH public key no longer aborts installation with
  `xargs: unmatched double quote` or `unexpected EOF while looking for
  matching '"'` (issues #42, #144). The parser also ignores CRLF line endings
  and lines without a `key=value` separator.
- `lemper.sh --with-ssh-pub-key` now writes `RSA_PUB_KEY`, the key that
  `server_security.sh` actually reads, through the new `set_env_value` helper
  instead of an unescaped `sed` replacement. Key validation accepts RSA,
  Ed25519, ECDSA, and FIDO keys instead of matching any string containing
  `ssh-rs`, and option handling now loads the helper functions before parsing
  flags.
- Uninstall no longer removes packages and configuration for services that
  predate LEMPer. Installers record provisioned services under
  `/etc/lemper/installed/`, and the Nginx remover leaves a pre-existing server
  untouched unless `FORCE_REMOVE=true` (issue #182). The README now states that
  LEMPer targets clean installations.
- ModSecurity installation now uses the packages the nginx repository actually
  ships: `libnginx-mod-http-modsecurity` and `modsecurity-crs` (issue #177).
  Previously the installer selected a non-existent package name, created an
  invalid `modules-enabled` symlink, and pointed the rules at a
  `crs-setup.conf` that only exists as `.example` after cloning. The connector
  is now enabled through the package's `modules-available` file, CRS is
  configured under `/etc/modsecurity/crs`, and audit logs are written to
  `/var/log/modsecurity/modsec_audit.log`. Removal purges the same packages and
  strips the include from `sites-available` vhosts without breaking the
  `sites-enabled` symlinks.
- SSL-enabled vhosts created by `lemper-cli site mod --enable-ssl` now receive
  `http2 on;`. HTTP/2 uses the non-deprecated directive form everywhere; the
  shipped `default-ssl` vhost already used it (issue #171).
- Restored the executable bit on `update.sh`, which the CI test suite asserts and
  the bootstrap relies on to run directly.
- Configured bashate to skip the project's established legacy formatting codes
  (E001, E002, E003, E010, E011, E020) so the lint gate matches the existing
  shell style.
- Repository-based Nginx installs now honor `NGINX_REPO_SRC` (default
  `myguard`). The setting was previously ignored in favor of the Ondřej PPA,
  which no longer serves packages; the sury nginx repository is likewise gone.
- Nginx post-install now copies `etc/nginx/cors` to `/etc/nginx/`. The main
  configuration includes that file, so skipping the copy made `nginx -t` fail
  with `open() "/etc/nginx/cors" failed`.
- Valkey installs now use the distribution package when available (Ubuntu
  24.04+, Debian 13) and enable `bookworm-backports` on Debian 12. The previous
  external repository and GitHub-hosted key URL are no longer published.
- The shunit2 Redis/Valkey check now verifies `valkey-cli` and `valkey-server`
  when `REDIS_BACKEND=valkey`, instead of assuming the `redis-*` binaries exist.
- Nginx TLS setup now generates DH parameters from the predefined RFC 7919
  `ffdhe2048` group instead of running a CPU-heavy prime search. The previous
  code used `KEY_HASH_LENGTH=4096`, which produced `dhparam-4096.pem` while
  `ssl.conf` requires `dhparam-2048.pem`, so `nginx -t` failed. Configure the
  group with `DH_PARAM_GROUP`.
- Valkey installs no longer overwrite the distribution's `/etc/valkey/valkey.conf`
  with the Redis template. The template pointed at `/var/lib/redis` and
  `/var/log/redis`, which the `valkey` user cannot access, so
  `valkey-server.service` failed to start. LEMPer settings are now appended to
  the packaged config, and a temporary template is only used for source installs.
- Missing MongoDB and Redis PHP extensions are now reported as warnings instead
  of fatal errors, because they are optional components.
- Config-at-rest encryption now uses AES-256-CBC, which `openssl enc` supports.
  The previous AES-256-GCM path failed with `AEAD ciphers not supported`, so
  `save_config` silently discarded every credential, including the MariaDB root
  password. Encrypted-file detection now also recognizes the base64
  `U2FsdGVkX1` header produced by `openssl enc -a`, and the CLI trusts that
  header instead of relying on `ENCRYPT_CONFIG_AT_REST`, which sudo strips
  from the environment.
- Repository-based Nginx installs now install the enabled `libnginx-mod-*`
  packages. A duplicate `install_nginx_from_repo` definition in
  `nginx_build.sh` shadowed the one in `nginx_repo.sh` and captured the
  stderr-only module list into an empty variable, so only the base `nginx`
  package was installed and `stream {}` failed with `unknown directive`.
- The Nginx stream block is only appended when the stream module is actually
  available (static build or enabled `load_module` config), so `nginx -t`
  succeeds even when `NGX_STREAM=true` but the module is missing.
- Config encryption now resolves `/etc/lemper/.config_key` before
  `LEMPER_PASSWORD`. The installer encrypted with the admin password while the
  sudo-launched CLI only had the key file, so `lemper-cli` could not decrypt
  `/etc/lemper/lemper.conf`. Decryption failures now print an error instead of
  silently exiting under `set -e`.
- WordPress site creation passes `--skip-check` to `wp config create`. WP-CLI
  otherwise validates the deliberately masked `__LEMPER_DB_PASS__` placeholder
  against the database and fails with `Access denied`, before the real password
  is substituted into `wp-config.php`.
- The CLI now provides `sed_inplace`, `sanitize_sed_replacement`, and the
  resource-sizing helpers used by the site plugin. `lemper-cli site add`
  previously ran those functions only when sourced by the installer, so the
  plugin failed with `command not found`.
- Removed the PECL/PEAR fallback from `install_php.sh` and stopped installing
  `php-pear`, `dh-php`, and `pkg-php-tools`. Every extension in the default
  `PHP_EXTENSIONS` set is packaged by the Ondřej/Sury repository, while the
  PECL path emitted PEAR `Cannot use bool as array` warnings under PHP 8.5 and
  could abort the install on abandoned modules that no longer build. Extensions
  that resolve to no package are now listed in a warning with a pointer to PIE
  for manual installation.
- The extension resolver skips `json` (PHP 8.0+) and `opcache` (PHP 8.5+,
  where it is built into the PHP binary) instead of reporting them as missing
  packages. PHP 8.5 has no `php8.5-opcache` package.
- `geoip` and `mcrypt` were removed from the default `PHP_EXTENSIONS` list.
  Both are abandoned upstream and are not installed automatically.
- Documented that PIE is the manual path, not an installer dependency:
  `php/pie` requires Composer package names (`vendor/package`) and cannot
  target Debian's per-version `php_suffix` layout, so it is not a drop-in
  replacement for this installer's bare extension names. See `ARCHITECTURE.md`.
- CI workflows use `actions/checkout@v6` (Node 24) so the runner no longer
  prints the Node 20 deprecation warning.
- Fail2ban installs set `PYTHONWARNINGS=ignore::SyntaxWarning` for the package
  install. The distribution package byte-compiles its own test files and emits
  `SyntaxWarning: invalid escape sequence` on newer Python; the warnings are
  upstream noise, affect no running service, and no longer clutter CI logs.

## [3.5.2] - 2026-10-24

### Added

- PHP 8.5 as a first-class supported version:
  - `etc/php/8.5/` FPM templates (`php-fpm.conf`, `php.ini`, `lemper` and `www`
    pools) using `php8.5-fpm.sock`, `php8.5-fpm.pid`, and PHP 8.5 log paths.
  - PHP 8.5 option in the interactive installer menu and in the "all versions"
    selection (`8.1`–`8.5`).
  - PHP 8.5 option in the interactive removal menu, with the all/none entries
    renumbered accordingly.
  - `.php85` Nginx handlers in `default` and `default-ssl` vhosts, and both
    templates now default to the PHP 8.5 FastCGI socket.
  - `/lcp/phpinfo.php85` endpoint in `install_tools.sh`.
- PHP 8.5.12 to the PHP2Shell fixed-release map.

### Changed

- `DEFAULT_PHP_VERSION` is now `8.5`; `PHP_VERSIONS` defaults to
  `"8.1 8.2 8.3 8.4 8.5"`.
- README, ARCHITECTURE, AGENTIC, DEVELOPER, and ROADMAP documentation updated
  for the 8.1–8.5 support matrix.

### Fixed

- `scripts/remove_php.sh` referenced an undefined `$PHPv` when checking for
  installed PHP packages, so `php<version>` and `php-fpm<version>` detection
  and the "not installed" message were wrong. The removal loop and the final
  cleanup check now use `$PHP_VER` / `php${PHP_VER}`.

### Validation

- ShellCheck clean and 107/107 bats tests passing locally and in the Ubuntu
  24.04 Podman container.

## [3.5.1] - 2026-10-24

### Added

- `update.sh` bootstrap for legacy installations. It installs the current CLI,
  installs the updater plugin, records the checkout path in
  `/etc/lemper/update-source`, and then patches the stack. Supports
  `--install-only`, `--check`, `--source-dir`, `--post-max-size`, and `--yes`.
- `lemper update` CLI plugin (`lib/lemper-update.sh`) with `check`, `php`,
  `nginx`, `mariadb`, `lemper`, and `all` commands.
- `tests/unit/update_helpers.bats` covering version comparison, branch
  classification, idempotent pool mitigation, and bootstrap wiring.

### Security

- PHP2Shell remediation for CVE-2026-109618 and CVE-2026-109619:
  - Supported branches are upgraded from apt and verified against fixed
    releases 8.2.35, 8.3.36, 8.4.27, and 8.5.12.
  - EOL branches (8.1 and older) have no vendor patch. Their pools are backed
    up to `/etc/lemper/backups/php2shell-<UTC>/` and locked down with
    `memory_limit=-1`, `post_max_size=32M`,
    `session.upload_progress.enabled=0`, plus `fatal_error_backtraces=0` on
    PHP 8.5, then reported as requiring migration.
  - Source-built Nginx is detected and reported instead of being modified.
  - Concurrent runs are serialized with `flock`; logs are written to
    `/var/log/lemper/update-<UTC>.log`.

### Changed

- ShellCheck, bashate, and script syntax tests now cover `update.sh`.
- README, ARCHITECTURE, and DEVELOPER document the bootstrap, the update
  commands, and the limits of EOL mitigation.

## [3.5.0] - 2026-10-22

### Security

- Replaced `NOPASSWD:ALL` with restricted sudoers rules.
- Suppressed credential display by default.
- Replaced the `eval`-based config loader with a safe parser.
- Added the portable `sed_inplace()` wrapper for BSD and GNU `sed`.
- Added bashate linting, ShellCheck v0.11.0, Debian 12 CI coverage, and an
  Ubuntu 24.04 CI runner.
- Removed stale PHP 5.6–8.0 templates.

## [3.4.0] - 2026-10-22

### Added

- ModSecurity v3 WAF with OWASP Core Rule Set.
- AES-256-GCM encrypted configuration at rest.
- Interactive TUI dashboard.

## [3.3.0] - 2026-10-22

### Added

- Progress indicators and improved CLI help output.
- PHP 8.4 support and default.
- Fail2ban enabled by default.
- MariaDB 11.4 and OpenSSL 3.2 defaults.

## [3.2.0] - 2026-10-22

### Added

- CrowdSec HIPS integration with WordPress scenarios.
- Valkey as a Redis drop-in replacement.
- ACME v2 DNS-01 wildcard certificate support.

### Changed

- Removed PHP 5.6–7.4 support and templates.

## [3.1.0] - 2026-10-22

### Added

- `site list` and `site show` subcommands.
- Database backup, restore, and scheduling commands.
- Bun.js runtime integration.

## [3.0.0] - 2026-10-22

### Added

- Modular directory structure and `lemper-stacks.sh` orchestrator.
- Safe configuration loading and encrypted secrets.
- bats-core test suite.

## [2.9.0] - 2026-10-22

### Changed

- Removed PHP versions older than 8.0.
- Updated default stack versions.

## [2.8.0] - 2026-10-22

### Security

- Credential suppression, RSA-4096 keys, apt keyring support, and certbot fixes.

## [2.7.2] - 2026-10-22

### Fixed

- Undefined `fial` typo in error paths.
- `cgi.fix_pathinfo` path-traversal exposure.
- Sudo privilege escalation and CI configuration issues.
