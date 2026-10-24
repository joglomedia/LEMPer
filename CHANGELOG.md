# Changelog

All notable changes to LEMPer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed

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
