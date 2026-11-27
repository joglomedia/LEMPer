# LEMPer — Architecture Document

> **Version:** 4.0.0 (release preparation; historical audit sections retained)
> **Last Updated:** 2026-11-23
> **Author:** Senior Engineering Audit

---

## 1. Overview

### 1.1 What is LEMPer?

LEMPer (**L**inux **E**ngine-X **M**ariaDB **P**HP — "Installer" or "er") is an open-source,
Bash-based CLI administration tool that automates deployment, configuration, and ongoing
management of a LEMP/LEMP-like stack on Debian and Ubuntu Linux servers. It provides both
an installer (`install.sh` / `lemper.sh`) and a runtime CLI (`lemperctl`) for managing
virtual hosts, databases, SSL certificates, and supporting services.

The installed command is `lemperctl`; `lemper-cli` remains a compatibility
symlink. The implementation filename is still `bin/lemper-cli.sh`.

**Target audience:**
- System administrators who need to provision PHP hosting servers quickly.
- DevOps engineers managing fleets of Debian/Ubuntu VPS instances.
- Teams looking for a free, scriptable alternative to cPanel/Plesk/RunCloud/Cloudways.

**Supported distributions:**
- Ubuntu: Jammy (22.04), Noble (24.04), Resolute (26.04); native platform checks are documented in [the Resolute guide](UBUNTU_26_04.md).
- Debian: Bullseye (11), Bookworm (12)

---

## 2. Current Architecture

### 2.1 Project Structure (as of v3.4.0)

```
LEMPer/
├── bin/
│   └── lemper-cli.sh              # CLI entry point
├── lib/
│   ├── lemper-account.sh          # CLI plugin: system account creation
│   ├── lemper-adduser.sh          # CLI plugin: add user wrapper
│   ├── lemper-backup.sh           # CLI plugin: configuration backup/restore
│   ├── lemper-bench.sh            # CLI plugin: hardware, disk & network benchmark
│   ├── lemper-create.sh           # CLI plugin: vhost creation & framework auto-installer
│   ├── lemper-db.sh               # CLI plugin: MySQL/MariaDB database manager (backup/restore)
│   ├── lemper-encrypt.sh          # Config at-rest encryption utilities
│   ├── lemper-fixpermission.sh    # CLI plugin: fix file/directory permissions
│   ├── lemper-manage.sh           # CLI plugin: vhost management (enable/disable/SSL)
│   ├── lemper-modsec.sh           # CLI plugin: WAF status, reporting, CRS auto-tuning
│   ├── lemper-selfssl.sh          # CLI plugin: self-signed SSL generator (RSA 4096)
│   ├── lemper-site.sh             # CLI plugin: site dispatcher
│   ├── lemper-site-list.sh        # CLI plugin: vhost listing (table + JSON)
│   ├── lemper-site-show.sh        # CLI plugin: detailed vhost + FPM + SSL info
│   ├── lemper-tui.sh              # Interactive TUI (dashboard, site wizard, live logs)
│   └── core/
│       └── lemper-stacks.sh       # Installer/uninstaller orchestrator (shared)
├── scripts/
│   ├── utils.sh                   # Core helper library (shared, 1021 lines)
│   ├── install_dependencies.sh    # Base packages + Python
│   ├── install_nginx.sh           # Nginx installer (delegates to nginx/)
│   ├── install_php.sh             # PHP 8.2–8.5 only (EOL 5.6–8.1 removed)
│   ├── install_mariadb.sh         # MariaDB 11.4
│   ├── install_redis.sh           # Redis/Valkey (REDIS_BACKEND configurable)
│   ├── install_postgres.sh        # PostgreSQL (optional)
│   ├── install_memcached.sh       # Memcached
│   ├── install_imagemagick.sh     # ImageMagick
│   ├── install_mailer.sh          # Postfix + Dovecot
│   ├── install_pureftpd.sh        # Pure-FTPd (TLS)
│   ├── install_vsftpd.sh          # vsftpd
│   ├── install_certbotle.sh       # Let's Encrypt ACME v2 (DNS-01 wildcard)
│   ├── install_fail2ban.sh        # Fail2ban (enabled by default)
│   ├── install_crowdsec.sh        # CrowdSec HIPS + WordPress scenarios
│   ├── install_bun.sh             # Bun.js runtime (replaces Node.js)
│   ├── install_modsec.sh          # ModSecurity v3 + packaged OWASP CRS
│   ├── install_tools.sh           # CLI tool + TUI + encrypt plugin
│   ├── remove_*.sh                # Per-component removal scripts
│   ├── server_cleanup.sh          # Pre-install service cleanup
│   ├── server_optimization.sh     # Swap, sysctl tuning
│   ├── server_security.sh         # SSH hardening + UFW/firewall
│   ├── nginx/
│   │   ├── nginx_common.sh        # Shared variables & helpers
│   │   ├── nginx_repo.sh          # Repository-based install
│   │   ├── nginx_ssl_builders.sh  # OpenSSL 3.2.4 / LibreSSL source builds
│   │   ├── nginx_extra_modules.sh # Third-party module compilation
│   │   ├── nginx_module_config.sh # Dynamic module configuration
│   │   ├── nginx_build.sh         # Source compilation orchestration
│   │   ├── nginx_post_install.sh  # Post-install config deployment
│   │   └── nginx_ssl_cert.sh      # Hostname SSL cert generation
│   └── README.md                  # Scripts documentation
├── etc/
│   ├── nginx/                     # Nginx configs, includes, vhosts
│   │   ├── includes/
│   │   │   ├── ssl.conf
│   │   │   ├── fastcgi.conf
│   │   │   ├── compression_brotli.conf
│   │   │   ├── security_headers.conf
│   │   │   ├── rules_security.conf
│   │   │   └── modsec.conf          # ModSecurity v3 + OWASP CRS
│   │   └── vhost/
│   │       ├── README.md
│   │       └── site_wordpress.conf  # ModSecurity (was NAXSI)
│   ├── php/8.5/                   # PHP FPM configs (only 8.2–8.5 remain)
│   │   ├── fpm/php-fpm.conf
│   │   └── fpm/pool.d/lemper.conf  # cgi.fix_pathinfo=0
│   ├── mysql/mariadb.conf.d/      # MariaDB 11.4 configs
│   ├── redis/redis.conf           # Redis config
│   ├── systemd/
│   │   ├── redis-server.service
│   │   └── valkey-server.service  # Valkey backend
│   ├── openssl/cert.conf          # RSA 4096 cert template
│   ├── fail2ban/                  # Fail2ban configs
│   └── init.d/                    # SysV init scripts
├── share/
│   └── nginx/html/                # Static files (error pages, index)
├── docs/                          # Architecture, roadmap, audits, and UAT reports
│   ├── ARCHITECTURE.md
│   ├── ARCHITECTURE_ALIGNMENT.md
│   ├── ROADMAP.md
│   ├── ROADMAP_AUDIT.md
│   └── UAT_REPORT.md
├── .env.dist                      # Configuration template (INI format)
├── .gitignore
├── CONTRIBUTING.md
├── DEVELOPER.md
├── AGENTS.md
├── CHANGELOG.md
├── LICENSE.md
├── README.md
├── install.sh                     # Standalone installer (~47 lines, wrapper)
├── update.sh                      # Legacy security/stack update bootstrap
├── lemper.sh                      # Interactive installer (~551 lines, 551 lines)
├── remove.sh                      # Standalone uninstaller (~48 lines, wrapper)
├── tests/
│   ├── test_sanitization.bats     # Input sanitization (9 tests)
│   ├── test_structure.bats        # Structural integrity (68 tests)
│   ├── test_syntax.bats           # ShellCheck + bash -n (2 tests)
│   └── unit/                      # Mock-based unit tests (28 tests)
│       ├── env_helper.bash
│       ├── validators.bats
│       ├── php_temp_dirs.bats
│       ├── db_backup_restore.bats
│       ├── resource_profile.bats
│       └── update_helpers.bats    # PHP2Shell updater helpers (10 tests)
└── .github/workflows/main.yml     # CI: ShellCheck + bats (107 tests)
```

### 2.2 Execution Flow

#### 2.2.1 Installation Flow

```
lemper.sh / install.sh
    │
    ├─> sudo check (root)
    ├─> preflight_system_check()   ← utils.sh
    │     • OS detection (get_distrib_name, get_release_name)
    │     • Architecture detection
    │     • Timezone setting
    │     • Network interface detection
    │     • IP address detection
    │     • Hostname validation (production only)
    │     • Build directory creation
    │
    ├─> init_log() + init_config()
    ├─> create_account() ← lib/lemper-account.sh
    │
    ├─> [Sourced Scripts — sequential]:
    │     install_dependencies.sh    → Python, base packages, locale, timezone
    │     server_cleanup.sh          → Remove Apache, old Nginx/PHP/MySQL
    │     install_certbotle.sh       → Let's Encrypt certbot (pip venv)
    │     install_nginx.sh           → Nginx (repo or source) + modules
    │     install_php.sh             → PHP-FPM (Ondřej's PPA / Sury)
    │     install_phalcon.sh         → Phalcon PHP extension (optional)
    │     install_mariadb.sh         → MariaDB (official repo)
    │     install_postgres.sh        → PostgreSQL (optional)
    │     install_redis.sh           → Redis or Valkey (configurable via REDIS_BACKEND)
    │     install_mongodb.sh         → MongoDB (optional)
    │     install_memcached.sh       → Memcached (optional)
    │     install_imagemagick.sh     → ImageMagick
    │     install_mailer.sh          → Postfix + Dovecot + DKIM
    │     install_pureftpd.sh / install_vsftpd.sh
    │     install_fail2ban.sh        → Fail2ban
    │     install_crowdsec.sh        → CrowdSec HIPS (optional, off by default)
    │     install_bun.sh             → Bun.js runtime (for asset building)
    │     install_tools.sh           → lemperctl + web admin tools (site list/show plugins)
    │     server_optimization.sh     → Swap, sysctl tuning
    │     server_security.sh         → SSH hardening, UFW/CSF/APF
    │
    └─> Credentials recap + log file output
```

#### 2.2.2 CLI (Runtime) Flow

```
lemperctl <command> [subcommand] [options]
    │
    ├─> requires_root()
    ├─> Load /etc/lemper/lemper.conf (via eval-based sourcing)
    ├─> init_lemper_cli()
    │     ├──> help/version
    │     └──> Source plugin from /etc/lemper/cli-plugins/lemper-<command>
    │           ├──> site → lemper-site.sh
    │           │     ├──> add/create → lemper-create.sh (full vhost + framework setup)
    │           │     ├──> mod/manage → lemper-manage.sh (enable/disable SSL, cache, etc.)
    │           │     ├──> list → lemper-site-list.sh (table/JSON listing of vhosts)
    │           │     └──> show → lemper-site-show.sh (detailed vhost + FPM + SSL)
    │           ├──> db → lemper-db.sh (account/create/drop/import/export/backup/restore)
    │           ├──> account → lemper-account.sh (interactive user creator)
    │           ├──> adduser → lemper-adduser.sh (interactive)
    │           ├──> selfssl → lemper-selfssl.sh (self-signed cert generation)
    │           ├──> fixpermission → lemper-fixpermission.sh
    │           └──> bench → lemper-bench.sh
    │
    └──> Each plugin runs getopt-based arg parsing + business logic
```

### 2.3 Configuration Model

| File | Purpose | Sensitive? |
|---|---|---|
| `.env` (gitignored) | Master install config — INI sections, plain text | ✅ Yes (passwords) |
| `/etc/lemper/lemper.conf` | Runtime config written during install | ✅ Yes (credentials) |
| `/etc/lemper/vhost.d/*.conf` | Per-domain app metadata (DB creds, admin creds) | ✅ Yes |
| `/etc/nginx/lemper-admin.htpasswd` | Management listener administrators | ✅ Yes (password hashes) |
| `/srv/.htpasswd` | Legacy or custom web authentication | ✅ Yes (password hashes) |

The `.env` file uses a pseudo-INI format with `[section]` headers that Bash's `source` cannot
parse natively. `utils.sh` loads it through `safe_parse_dotenv()`, which:

1. Skips comments, blank lines, and `[section]` headers.
2. Splits each line on the first `=` using `IFS` (never `eval`).
3. Validates the key against `^[A-Za-z_][A-Za-z0-9_]*$` to prevent injection.
4. Strips optional surrounding quotes from the value.

Values already present in the file override caller-supplied environment variables — so
one-off overrides must be written to `.env` (or use variables absent from it, such as
`LEMPER_PROFILE`).

#### 2.3.1 Resource Profiles

`detect_resource_profile()` in `utils.sh` classifies the host from `MemTotal` in
`/proc/meminfo`, reduced by the cgroup v1/v2 memory limit when the installer runs inside a
container or slice:

| Profile | RAM | FPM `max_children` cap | Opcache (MB / strings MB / files) | Nginx | MariaDB (buffer pool / conns / perf schema) |
|---|---|---|---|---|---|
| `micro` | < 1 GiB | 4 | 64 / 8 / 8000 | `nginx-lowend.conf`, 1 worker, 512 connections | 128M / 30 / OFF |
| `small` | 1–2 GiB | 6 | 128 / 16 / 16229 | 1024 connections, 50k open-file cache | 256M / 50 / OFF |
| `medium` | 2–4 GiB | 10 | 256 / 32 / 32531 | 2048 connections, 200k open-file cache | 512M / 75 / ON |
| `large` | ≥ 4 GiB | 16 | 512 / 64 / 32531 | one worker per core | 1G (2G on ≥ 8 GiB) / 100 / ON |

`calc_php_max_children()` further caps workers to 35% of RAM, assuming each worker costs
`memory_limit / 3` (minimum 64 MiB). `calc_php_pool_sizing()` derives `start_servers`,
`min_spare_servers`, and `max_spare_servers` while preserving the FPM invariant
`min_spare ≤ start ≤ max_spare`.

Overrides:

- `SERVER_PROFILE` in `.env` (or `LEMPER_PROFILE` in the environment) forces a profile.
- `PHP_FPM_MAX_CHILDREN` overrides the computed worker count.
- `PHP_MEMORY_LIMIT` and `OPCACHE_MEMORY_MB` change the sizing inputs.

The tuning is applied at install time to the shipped `www` pool, to pools created by
`lemper site create`, to nginx through `nginx_post_install.sh`, and to MariaDB through the
generated `/etc/mysql/mariadb.conf.d/99-lemper-tuning.cnf` drop-in. Smaller profiles
disable `performance_schema` to reclaim memory; large hosts cap the buffer pool so PHP
and nginx keep headroom.

#### 2.3.2 Nginx Configuration Layout

The shipped configuration is split by scope, and every file is copied verbatim
from `etc/nginx/` to `/etc/nginx/`:

| Path | Scope | Contents |
|---|---|---|
| `nginx.conf` / `nginx-lowend.conf` | `http {}` | Global tuning, maps, cache zones, vhost loading |
| `conf.d/` | `http {}` | Optional drop-ins (`mail.conf`) |
| `cors`, `fastcgi_cache`, `fastcgi_https_map`, `proxy_cache`, `upstream` | `http {}` | Glue maps included by the main config |
| `includes/` | `server {}` or `location {}` | PHP handlers, monitoring, security, compression, TLS, cache, WAF |
| `vhost/site_<framework>.conf` | `server {}` | Framework rewrite rules only |
| `sites-available/` | `server {}` | Full vhosts, including the generated default |
| `sites-enabled/` | — | Symlinks into `sites-available/` |

Vhost ordering is deliberate: compression first, then the security and
restriction rules, then the static-file locations, then the framework rules,
and finally the PHP handlers and monitoring endpoints. Restriction rules must
precede the static-file regex locations so a `deny` is not shadowed.

Repeated handler boilerplate lives in `includes/php_handlers.conf` (`.php` plus
`.php85`–`.php82`) and `includes/monitoring.conf` (loopback-only
`/nginx_status` and `/php-fpm_status`). Both are included in the public and
admin server blocks and, for `/lcp`, inside the basic-auth protected prefix
location so the nested handlers inherit its access rules.

### 2.4 Plugin Architecture (CLI)

During installation, `install_tools.sh` copies library scripts from `lib/` to
`/etc/lemper/cli-plugins/`:

```
/etc/lemper/cli-plugins/
├── lemper-account         → symlinks: (none)
├── lemper-adduser         → symlinks: (none)
├── lemper-site            → dispatcher for site subcommands
├── lemper-site-create     → symlink: lemper-site-add
├── lemper-site-update     → symlink: lemper-site-mod
├── lemper-db              → symlink: lemper-site-db → lemper-site-database
├── lemper-selfssl
├── lemper-fixpermission
├── lemper-bench
├── lemper-update           → stack updater (check/php/nginx/mariadb/lemper/all)
└── lemper-backup           → configuration archive (create/list/show/verify/restore/prune)
```

The CLI dispatches by sourcing the plugin file (not executing it), which means all plugin
scripts share the same process and can access parent-scope functions/variables.

### 2.5 CI/CD Pipeline (v3.4.0)

The GitHub Actions workflow (`.github/workflows/main.yml`) runs on every push/PR to
`2.x.x` and `master` branches:

1. **Setup:** Copies `.env.dist` → `.env`, adjusts config for CI environment.
   Toggled for CI: `REDIS_BACKEND="valkey"`, `INSTALL_CROWDSEC=true`,
   `ACME_WILDCARD=true`, `INSTALL_MODSEC=true`, `ENCRYPT_CONFIG_AT_REST=true`.
2. **ShellCheck:** Runs `shellcheck -s bash -x` on every script file — **exit 0**.
3. **Bats Tests:** Runs `bats tests/ tests/unit/` — see current Bats/CI results.

**Representative test coverage (historical listing):**
- `test_sanitization.bats` — 9 tests (FQDN, IPv4, username, sed injection sanitization)
- `test_structure.bats` — 100 tests (project structure, wiring, config flags, temp-dir isolation, Nginx/PHP hardening, resource profiles)
- `test_syntax.bats` — 2 tests (bash -n + shellcheck on all scripts)
- `unit/validators.bats` — 6 tests (validators, sanitizers, mocked nginx)
- `unit/php_temp_dirs.bats` — 2 tests (mock-based temp-dir creation)
- `unit/db_backup_restore.bats` — 4 tests (mocked DB backup/restore)
- `unit/config_backup.bats` — 8 tests (configuration archive create/verify/restore/prune, temp backup root)
- `unit/config_encryption.bats` — 2 tests (at-rest config encryption)
- `unit/dotenv.bats` — 7 tests (dotenv parsing and overrides)
- `unit/ftp_installers.bats` — 11 tests (Pure-FTPd/vsftpd install and reconciliation)
- `unit/resource_profile.bats` — 6 tests (RAM detection, profile selection, FPM/MariaDB sizing, pool tuning)
- `unit/bench_plugin.bats` — 10 tests (section selection, dd/speed parsing, mocked downloads, endpoint overrides, disk cleanup)
- `unit/tui_dispatch.bats` — 8 tests (sourced entry point, help/version, benchmark menu, CLI dispatch)
- `unit/update_helpers.bats` — 11 tests (version comparison, branch classification, pool mitigation idempotency, bootstrap wiring)
- `unit/plugin_conventions.bats` — 12 tests (2014-2026 headers, 77-column boxes, command metadata, help/version, safe fixpermission, CLI aliases, library-only encrypt)

**Limitations:**
- No code coverage reporting.
- No security scanning (bandit, semgrep, lynis as code).
- Only runs on `ubuntu-latest` (no Debian matrix).

### 2.6 Dependency Model

Scripts follow a consistent "guard + source" pattern:

```bash
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . "${BASE_DIR}/utils.sh"
    requires_root "$@"
    preflight_system_check
fi
```

This allows scripts to be sourced (sharing parent state) or run standalone. However, it
creates tight coupling: all scripts depend on the global `run()` function, `DRYRUN` variable,
and the dotenv-sourced environment variables being in scope.

### 2.7 PHP Extension Sources (Repository Only)

`install_php.sh` resolves each name in `PHP_EXTENSIONS` against the
distribution/Ondřej (Sury) repository:

1. `php${PHPv}-NAME` (version-specific package).
2. `php-NAME` (version-independent package).

There is no PECL fallback. PEAR and PECL were removed because every extension in
the default `PHP_EXTENSIONS` set is packaged by Ondřej/Sury, while PECL/PEAR emit
PHP 8.5 warnings (`Cannot use bool as array`) and build many abandoned extensions
against unsupported APIs. Extensions that resolve to neither package are listed in
a warning; the operator can install them manually.

[PIE](https://github.com/php/pie) is the official successor to PECL, but it is not a
drop-in replacement here: it installs Composer packages (`vendor/package`) rather
than bare extension names such as `geoip` or `memcache`, it requires PHP 8.1+ to
run, and it has no Debian/Ubuntu package or `php_suffix` equivalent for targeting
multiple installed PHP versions. It is therefore documented as the manual path
rather than wired into the installer. `geoip` and `mcrypt` are abandoned upstream
and excluded from the default `PHP_EXTENSIONS` list.

---

## 3. Security Model (Current)

### 3.1 Authentication & Authorization

- The default `lemper` system account receives **NOPASSWD:ALL** sudo access via
  `/etc/sudoers.d/90-lemper-users` — a critical privilege escalation risk.
  **Status: ⚠️ Not yet addressed — flagged for v3.5.0.**
- SSH hardening is implemented via `server_security.sh` (port change, key-only auth,
  root login disable).
- FTP uses Pure-FTPd or vsftpd with TLS support.

### 3.2 Secrets Management

- Config at rest encryption: **✅ Implemented** (Phase 5 Task 2.10). `lib/lemper-encrypt.sh`
  provides `encrypt_config()`, `decrypt_config()`, `load_config()`, `resolve_config_password()`,
  and `secure_shred()`. `bin/lemper-cli.sh` reads the optional `--config-password-stdin` input, decrypts
  config before loading, shreds temp file. `ENCRYPT_CONFIG_AT_REST=false` in `.env.dist`
  (defaults to off for backward compatibility).
- Credentials are printed to stdout at the end of installation. **Status: ⚠️ Still active.**
- The install log file (`lemper_install.log`) may still contain credential data.
  **Status: ⚠️ Still active — needs log scrubbing.**

### 3.3 Network Security

- Firewall: UFW (default), CSF, or APF (user-selectable).
- **✅ Fail2ban** enabled by default (`INSTALL_FAIL2BAN=true` in `.env.dist`).
- **✅ CrowdSec HIPS** installed (optional, off by default). Now includes WordPress +
  PHP web app scenarios.
- **✅ Nginx WAF: ModSecurity v3 + OWASP CRS** (replaced legacy NAXSI).
  CRS paranoia level and anomaly thresholds are tunable via
  `lemperctl modsec tune [--auto] --apply`.
- **✅ SSL: Let's Encrypt (certbot)** with ACME v2 DNS-01 wildcard support.
  Certbot deploy hooks reload Nginx and flush the systemd-resolved cache after renewal.
  Self-signed CA: **RSA 4096-bit**, SHA-256 (upgraded from 2048-bit).
- No TLS for database connections by default.
- No secrets rotation mechanism.

### 3.4 Known Vulnerabilities (Audit Status)

| ID | Issue | Severity | Location | Status |
|---|---|---|---|---|
| SEC-01 | `cgi.fix_pathinfo = 1` allows path traversal | High | All PHP pool configs | ✅ **Mitigated** — set to `0` in all pool configs |
| SEC-02 | NOPASSWD:ALL sudo for `lemper` user | Critical | `utils.sh` sudoers | ⚠️ **Open** — flagged for v3.5.0 |
| SEC-03 | Passwords passed as CLI args (`ps` visible) | Medium | `lemper-create.sh`, `lemper-db.sh` | ✅ **Fixed** — `MYSQL_PWD` env, stdin-fed SQL, `--dbpass-file`, password-free cron entries |
| SEC-04 | `cgi.fix_pathinfo` set to 1 in default PHP pools | High | `www.conf` templates | ✅ **Mitigated** — set to `0` |
| SEC-05 | Self-signed SSL uses 2048-bit RSA | Medium | `nginx_ssl_cert.sh`, `lemper-selfssl.sh` | ✅ **Fixed** — upgraded to RSA 4096 |
| SEC-06 | `eval`-based dotenv loading (injection risk) | High | `utils.sh:31`, `lemper-cli.sh:55` | ⚠️ **Partial** — `load_config()` in `lemper-encrypt.sh` still uses eval |
| SEC-07 | `apt-key` is deprecated and insecure | Low | `nginx_repo.sh:45` | ✅ **Fixed** — uses `signed-by` keyring files |
| SEC-08 | Credentials printed to stdout | High | `install.sh`, `lemper.sh` | ⚠️ **Open** — flagged for v3.5.0 |
| SEC-09 | `fial` typo (undefined function) | Medium | `lemper-create.sh`, `lemper-db.sh` | ✅ **Fixed** (Phase 0) |
| SEC-10 | No input sanitization on domain → `sed`/`openssl` | Medium | `lemper-selfssl.sh`, `lemper-create.sh` | ✅ **Fixed** — `validate_fqdn()` + `sanitize_sed_replacement()` in `utils.sh` |
| SEC-11 | Credentials stored in `/etc/lemper/lemper.conf` without encryption | High | `utils.sh:846-851` | ✅ **Partially fixed** — `ENCRYPT_CONFIG_AT_REST` option available (default off) |
| SEC-12 | Open_basedir tmp dirs under `~/.lemper` may leak | Medium | `lemper-create.sh` | ✅ **Fixed** — temp/session dirs moved to `/var/lib/php/lemper/<pool>` (0700) |
| SEC-13 | Hidden files (`.env`, `.git/`, backups) served by Nginx | Critical | `rules_restriction.conf` | ✅ **Fixed** — hidden-file deny enabled; `.well-known` still allowed |
| SEC-14 | PHP error disclosure via `display_errors = on` in pools | High | `etc/php/*/fpm/pool.d/*.conf` | ✅ **Fixed** — disabled, errors go to the pool log |
| SEC-15 | FastCGI cache ignored `Set-Cookie`/`Cache-Control`/`Vary` | High | `fastcgi_cache.conf` | ✅ **Fixed** — only `Expires`/`X-Accel-Expires` ignored; cache key/purge aligned |
| SEC-16 | Session cookies lacked `HttpOnly`/`SameSite`/strict mode | High | all FPM pools | ✅ **Fixed** — enforced via `php_admin_value`, 48-char session IDs |
| SEC-17 | FPM status/ping reachable from any client | Medium | vhost generators, default sites | ✅ **Fixed** — localhost only |
| SEC-18 | `/lcp/phpinfo.php84` bypassed basic auth | High | `sites-available/default*` | ✅ **Fixed** — versioned handlers nested under `/lcp` |
| SEC-19 | HSTS `preload; includeSubDomains` on by default | Medium | `ssl.conf` | ✅ **Fixed** — host-only default; opt-in stronger variant |
| SEC-20 | Admin vhosts (8082/8083) bypassed restriction rules | High | `sites-available/default*` | ✅ **Fixed** — same security/restriction includes as public vhosts |
| SEC-21 | `X-Powered-By: LEMPer/Gzip` advertised the stack | Low | `compression_gzip.conf` | ✅ **Fixed** — header removed |
| SEC-22 | `cache_static.conf` dropped inherited security headers | Medium | `cache_static.conf` | ✅ **Fixed** — security headers re-included |
| SEC-23 | Backup/dump files (`.bak`, `.old`, `.sql`, `.sqlite`, `.db`) served | High | `rules_restriction.conf` | ✅ **Fixed** — denied |
| SEC-24 | SVG files served without sandboxing | Medium | `rules_staticfiles.conf` | ✅ **Fixed** — `CSP sandbox` on SVG responses |
| SEC-25 | `session.save_path` was app-overridable, allowing session files in the doc root | High | `install_php.sh`, pool templates | ✅ **Fixed** — `php_admin_value`, `ini_set()` cannot relocate sessions |
| SEC-26 | PHP session files (`sess_*`) left in a web root were served | High | `rules_restriction.conf` | ✅ **Fixed** — denied as defense-in-depth |
| SEC-27 | PHP2Shell OOM/use-after-free RCE (CVE-2026-109618, CVE-2026-109619) | Critical | PHP < 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 | ✅ **Patchable** — `lemper update php`; EOL branches get compensating controls only |

### 3.5 Security Update Path (PHP2Shell)

Legacy hosts bootstrap the updater from a current checkout with `sudo ./update.sh`.
The bootstrap publishes `/usr/local/bin/lemperctl` with `lemper-cli` compatibility
links. The implementation stays at `/opt/lemper/current/bin/lemper-cli.sh`, and
`lib/lemper-update.sh` is exposed as `/etc/lemper/cli-plugins/lemper-update`.
Automatic refresh uses the protected deployed release. To install a different revision,
pass `--source-dir` with a trusted checkout.

The plugin (`lib/lemper-update.sh`) exposes:

| Command | Effect |
|---|---|
| `update check` | Read-only audit; exits non-zero unless every PHP branch is patched |
| `update php` | `apt-get --only-upgrade` on installed `php<branch>-*`; checks the installed package against the fixed release and verifies active FPM |
| `update nginx` | Disables a retired Ondřej nginx APT source, then upgrades package-managed nginx from the MyGuard nginx-only repository. Source builds are reported as requiring a rebuild |
| `update mariadb` | Upgrades MariaDB and restarts only if the version changed; warns on branch changes |
| `update lemper` | Refreshes tooling from the deployed release or an explicitly selected trusted checkout |
| `update all` | `apt-get update`, then PHP, nginx, MariaDB, and tooling |

Version classification uses `dpkg-query` (falling back to `php<branch> -r 'echo PHP_VERSION;'`)
and `sort -V` comparison after stripping epochs and Debian revisions. Supported branches
are patched normally. EOL branches (8.1 and older) have no vendor fix. `update php --migrate-to=8.3`
(or `--force=8.3`) rewrites EOL FastCGI sockets and `set $php_version` lines in the Nginx
vhosts, creates the destination FPM pool from the old pool when it exists, tests Nginx,
and reloads. A bare `--force` is rejected. Without that flag the plugin backs
up every FPM pool to `/etc/lemper/backups/php2shell-<UTC>/<branch>/` and admin-locks
`memory_limit=-1`, `post_max_size=32M`, `session.upload_progress.enabled=0` (plus
`fatal_error_backtraces=0` on PHP 8.5). Runs take an exclusive `flock` and log to `/var/log/lemper/update-<UTC>.log`.

---

## 4. Target Architecture (v4.0; CLI alignment implemented)

The v4 candidate implements the shared core modules, schema validation,
widely adopted array parser, per-service CLI, guarded site removal, key-only SSH
policy, provider-backed wildcard issuance/renewal, pinned release bootstrap, and release/
host-audit workflows. Public wrappers and installed paths retain compatibility.
Site/stack use cases and service drivers now occupy runtime/services, with
legacy scripts retained behind compatibility adapters.
Account/database/SSL/TUI/vhost-creation internals now use function-only runtime
modules. Mail/full-stack parser adoption and native nftables are implemented.
Accepted extraction of legacy management and installer internals is complete
(2.12/2.37). Request-global/API cleanup remains optional maintenance.
Local bootstrap, mail and PHP/Laravel
service UAT is recorded in [RELEASE_V4.md](RELEASE_V4.md), [MAIL.md](MAIL.md) and
[PHP_RUNTIME_LARAVEL.md](PHP_RUNTIME_LARAVEL.md). Candidate publication, public
ACME and selected external/live-transition validation remain. The committed
9b3963e candidate passed 24/24 CI jobs, including native AMD64 archive acceptance.
See the [current roadmap status](ROADMAP_AUDIT.md#current-delivery-and-release-status)
and [production UAT](PRODUCTION_UAT.md).

### 4.1 Guiding Principles

1. **Security-first** — Eliminate all plaintext credential exposure, fix all known vulnerabilities.
2. **Modularity** — Split monolithic scripts into well-defined, testable modules.
3. **Testability** — Unit-testable functions with mockable dependencies.
4. **Maintainability** — Consistent patterns, clear conventions, comprehensive linting.
5. **Developer experience** — Clear contribution workflow, automated CI gates.
6. **AI-agent friendly** — Structured code, clear boundaries, predictable patterns.

### 4.2 Layered Architecture

~~~text
bin/lemper-cli.sh (lemperctl; lemper-cli compatibility alias)
    → stack ... --all: lib/runtime/stack/entry.sh (profile and lifecycle adapter)
    → install.sh/remove.sh/update.sh/lemper.sh: same entry adapter
    → shared command registry and command adapters
    → lib/runtime/site/ and lib/runtime/stack/ use cases
    → lib/services/php/, lib/services/nginx/, and systemd driver
    → OS packages, files, databases and services

lib/core/: configuration/schema, arguments, execution/locks, registries,
           logging, validation, deployment and legacy shared primitives
lib/compat/: isolated adapters for self-dispatching component/site scripts
~~~

Public help/version loads static command definitions before root checks or private
configuration. New operations use status-returning execution and a shared lock.
Site creation and the TUI share the application catalog in `lib/core/registry.sh`
and the function-only capability driver in `lib/services/site/applications.sh`.
Complete Mautic/Roundcube distributions use `lib/services/site/releases.sh`,
restricted archive extraction, and `lib/services/nginx/release-site.sh` with a
tracked vhost template. New installations resolve the latest stable release and
its asset digest from GitHub once per deployment; runtime preflight precedes
mutations and extraction runs as the hosting user. Manual deployment remains
available by omitting the installation flag.
The same release contracts now cover SnappyMail, Nextcloud, MyBB, phpList, OJS
and Slim, with application-specific tracked Nginx fragments and Unix-socket PHP.
Nextcloud resolves its source repository's latest release to an exact production
asset; OJS uses PKP's stable manifest. Source distributions install Composer
dependencies as the hosting user and record HTTPS provenance separately from
published-digest verification. XenForo's licensed files use a manual vhost driver.
Unsupported skeleton requests fail before site mutations; automatic paths check
project markers before success and ownership recording. Manual application types
retain PHP vhost setup. Rendering and installer logic now has service owners;
see [MODULE_DECOMPOSITION.md](MODULE_DECOMPOSITION.md) and
[APPLICATIONS.md](APPLICATIONS.md).
Site batches validate targets before mutation, restore site configuration on
failure, and reload Nginx after the batch. External certificate/database effects
are separate from configuration recovery.

CLI-only bootstrap, full installation and tooling refresh share a command registry
and deployment helper. Root-owned code lives under `/opt/lemper`; an atomic
`current` symlink selects one release. Configuration, credentials, ownership
metadata and provisioning markers stay outside the code tree. Historical installed
paths are compatibility symlinks; config backup excludes these code links.
Selecting older code does not undo service or database changes.

### 4.3 Key Architectural Changes

| Area | Historical baseline | Target (v4.0) |
|---|---|---|
| **Config format** | `.env` INI-style, `eval`-loaded | Structured `.env` or YAML with schema validation |
| **Secrets** | Plaintext files | Encrypted config or secret file references, no credential display |
| **CLI** | Sourced plugins, no arg validation library | Shared array parser and normalized site/stack requests |
| **Tests** | shunit2 integration tests only | Bats behavior/contract tests, ShellCheck and Bashate; disposable Linux lifecycle checks |
| **Security** | Optional fail2ban, commented encryption | Fail2ban + CrowdSec, encrypted secrets, secure defaults |
| **CI** | ShellCheck + install tests on Ubuntu | Multi-distro matrix, security audit, dependency scan, release automation |
| **Documentation** | Minimal README + CONTRIBUTING | ARCHITECTURE, DEVELOPER, AGENTS, ROADMAP and alignment audit |
| **PHP support** | 5.6–8.4 (many EOL) | Install PHP 8.2–8.5; inventory-based EOL management/removal |
| **SSH** | Password or key auth | Key-only by default, ed25519 |
| **Firewall** | UFW/CSF/APF | UFW + nftables backend, optional CrowdSec |
| **SSL** | RSA 2048 self-signed | RSA 4096 or ed25519, OCSP stapling, ACME v2 |

### 4.4 Module Decomposition (implemented for v4; tasks 2.12/2.37)

~~~text
lib/
├── core/
│   ├── args.sh, config.sh, schema.sh, validation.sh
│   ├── registry.sh                 command exports, aliases, components, recipes
│   ├── execution.sh                returned statuses, dry-run, operation locking
│   ├── deployment.sh               snapshots, compatibility exports, atomic selector
│   ├── cli.sh                      dispatcher and compatibility helpers
│   ├── lemper-stacks.sh             compatibility loader for full-stack entry points
│   └── ...                         existing shared primitives
├── runtime/
│   ├── help.sh
│   ├── site/commands.sh             create/update/remove/adopt normalization and batches
│   ├── site/create.sh, manage.sh    compatibility request parsing and feature orchestration
│   ├── site/state.sh                site ownership and guarded purge
│   ├── account/, database/, ssl/, tui/ function-only public command handlers
│   ├── mail/, hosting/, data/        service use cases
│   ├── stack/commands.sh            independent component lifecycle orchestration
│   ├── components/lifecycle.sh      named component-driver dispatch
│   ├── stack/update.sh              update/check orchestration
│   └── stack/recipe.sh              full-stack orchestration over the component registry
├── services/
│   ├── php/lifecycle.sh             installed inventory, selection, references, updates
│   ├── nginx/site.sh                site configuration snapshots/removal/reload
│   ├── nginx/vhost.sh, php/pools.sh ordinary vhost and FPM pool rendering
│   ├── site/provision.sh, skeletons.sh site provisioning and framework setup
│   ├── nginx/features.sh, protection.sh, ssl/site.sh site feature drivers
│   ├── php/update.sh, migrate.sh    patching, mitigation and EOL migration
│   ├── */install.sh, */remove.sh    component implementations; security/FTP use named variants
│   ├── configuration/, system/     backup, benchmark and host administration
│   ├── accounts/, mariadb/, mail/    provisioning, database and mail drivers
│   ├── apt/, hosting/               repository migration and quota lifecycle
│   └── systemd.sh                  service validation and control
├── compat/
│   ├── components.sh               installer/remover child-process boundary
│   └── site.sh                     isolated legacy site/application actions
└── lemper-*.sh                     thin public compatibility plugins/loaders
scripts/install_*.sh, remove_*.sh   retained initialization and dispatch adapters
scripts/nginx/*.sh                 compatibility loaders for Nginx service modules
~~~

New runtime/service modules define functions without dispatching on source. Site
creation accepts the issue #92 positional syntax and aliases; site update supports
multiple domains and actions. Feature-first flags and legacy verb-first flags
normalize to the same request. PHP selection is operation-specific: supported
versions for installation, installed versions for management/removal, all installed
FPM instances for versionless control. Removal refuses referenced PHP versions.

Tasks 2.12 and 2.37 describe the same workstream. Its remaining A4 boundaries are
now extracted: ordinary site rendering/framework setup, site feature management,
updater internals and older component lifecycles. Backup, benchmark, site listing,
permissions, account creation, ModSecurity tuning and configuration encryption
also use named modules. Public CLI names, aliases, plugin paths and standalone
script filenames remain compatible; the TUI invokes the same public CLI.

`lemper_component_driver` resolves a registered action/component to a service
module and entry function. Both full-stack recipes and the CLI component adapter
call `lemper_component_apply`; standalone scripts initialize the profile and take
the shared lock before calling the same driver. Modules import without host
initialization or dispatch. Build defaults and updater state initialize explicitly.

This extraction preserves existing installer `run`/`fail` helpers and legacy
request context. Their terminating failure behavior remains confined to the
installer/CLI process boundaries; direct driver invocation requires that context.
It does not make legacy installers safe to execute on a workstation or establish
an independent public API for every internal function. New mutations continue to
use returned statuses, `lemper_exec` and the shared operation lock.

See [MODULE_DECOMPOSITION.md](MODULE_DECOMPOSITION.md) for the contracts, tradeoffs
and verification, and [the implementation follow-through](ROADMAP_AUDIT.md#a4-module-decomposition-follow-through--2026-11-23)
for acceptance evidence and remaining release gates.

---

## 5. Technology Stack Summary (v4 candidate)

| Component | Historical baseline | v4 implementation | Boundary |
|---|---|---|---|
| **Language** | Bash 4+ | Bash 5+ on Linux | Runtime/services and repository tooling stay Bash |
| **ShellCheck** | v0.10.0 | Pinned 0.11.0 with sourced analysis | Passed candidate CI |
| **Test framework** | shunit2 | Bats plus disposable shunit2 installation | Candidate 9b3963e passed 534 Bats tests |
| **CI** | Basic GitHub Actions | Multi-distro/component matrices and archive gate | 24/24 candidate jobs passed |
| **Web server** | Nginx repo/source | MyGuard repo or source build; optional HTTP/3 | QUIC requires a capable TLS/library build and reachable UDP |
| **PHP** | EOL branches and Launchpad PPA | Maintained Sury archive; shipped 8.2–8.5 templates | Inventory-based legacy management is retained |
| **Database** | MariaDB 11.1 | 11.4 normally; native 11.8 on Resolute | Major-series changes require deliberate migration |
| **Cache** | Redis | Redis or Valkey | Shared backend lifecycle |
| **JS runtime** | Unused | Bun.js | Optional |
| **FTP** | Pure-FTPd/vsftpd | Repo/source installers and TLS | Source-build matrix passed |
| **SSL** | RSA-2048 self-signed | RSA-4096 named paths and ACME DNS-01 | Public issuance/renewal requires production UAT |
| **Firewall** | UFW/CSF/APF | Native nftables with explicit UFW migration | Scoped rules and independent SSH recovery |
| **Security** | Optional Fail2ban | Default Fail2ban, optional CrowdSec | Native journal SSH jail supported |
| **WAF** | NAXSI | ModSecurity v3/OWASP CRS | NAXSI remains an explicit legacy option |
| **Config format** | Executable dotenv loading | Literal schema-validated dotenv | YAML is an optional extension |
| **Secrets** | Plaintext | Optional CBC/PBKDF2 encrypted configuration | Authenticated format migration is a separate decision |

---

## 6. Data Flow Diagrams

These diagrams preserve the earlier installer/CLI flow. Their executable-config
loading, unrestricted sudo and credential-display steps are historical and
superseded by the core/runtime/service contracts above; they are not current
implementation findings. Use §4 and [the current audit](ROADMAP_AUDIT.md) for v4.

### 6.1 Install Data Flow

```
User runs install.sh
    │
    ├─> .env (user config) ─────────────────────> scripts/utils.sh
    │    (INI format, plaintext credentials)
    │
    ├─> utils.sh loads .env via eval sourcing
    │
    ├─> install_dependencies.sh
    │    ├─> apt-get install base packages
    │    ├─> Install Python {DEFAULT_PYTHON_VERSION}
    │    ├─> Copy SSL config templates → /etc/lemper/ssl/
    │    └─> Configure locale & timezone
    │
    ├─> server_cleanup.sh
    │    └─> Remove Apache, old Nginx, old PHP, old MySQL
    │
    ├─> create_account()
    │    ├─> useradd lemper
    │    ├─> Generate password (openssl rand)
    │    └─> NOPASSWD:ALL sudo entry
    │
    ├─> For each component (Nginx, PHP, MariaDB, ...):
    │    ├─> Add repository
    │    ├─> apt-get install
    │    ├─> Copy config templates → /etc/
    │    ├─> Configure systemd services
    │    └─> Start/restart services
    │
    ├─> install_tools.sh
    │    ├─> Copy CLI plugins → /etc/lemper/cli-plugins/
    │    ├─> Install Adminer, phpRedisAdmin, phpMemcachedAdmin
    │    ├─> Install TinyFileManager
    │    └─> Install OpCache web admin
    │
    ├─> server_optimization.sh
    │    └─> Swap, sysctl tuning
    │
    ├─> server_security.sh
    │    ├─> SSH hardening
    │    └─> Firewall (UFW/CSF/APF)
    │
    └─> Save config to /etc/lemper/lemper.conf
        Print credentials to stdout
```

### 6.2 CLI Runtime Data Flow

```
User runs: lemperctl site add -d example.com -f wordpress
    │
    ├─> /usr/local/bin/lemperctl (symlink → /opt/lemper/current/bin/lemper-cli.sh)
    │
    ├─> Load /etc/lemper/lemper.conf via eval sourcing
    │
    ├─> init_lemper_cli()
    │    └─> Source /etc/lemper/cli-plugins/lemper-site
    │         └─> init_lemper_site("add", ...)
    │              └─> Source lemper-site-create
    │                   └─> init_lemper_create()
    │                        ├─> Parse args (getopt)
    │                        ├─> Create FPM pool config
    │                        ├─> Download framework (wp-cli, composer, git)
    │                        ├─> Create vhost config
    │                        ├─> Enable SSL (if --enable-ssl)
    │                        └─> Save app metadata → /etc/lemper/vhost.d/
    │
    └─> Output success/failure
```

---

## 7. Historical Risk Assessment (v3.4.0; superseded)

This table preserves the original risk snapshot. Its open/partial labels,
file counts and mitigation suggestions are not current findings. Account
privileges, literal configuration loading, default credential suppression, EOL
template cleanup and mock-based tests have since been implemented. Remaining
DB boundaries, explicit diagnostic output and repository key scope are
qualified in [ROADMAP_AUDIT.md](ROADMAP_AUDIT.md); use that report for current status.

| Risk | Impact | Likelihood | Mitigation Planned | Status |
|---|---|---|---|---|
| NOPASSWD sudo for lemper user | Critical | High | Remove NOPASSWD, use sudo group with restricted commands | ⚠️ Open — v3.5.0 |
| `cgi.fix_pathinfo=1` | High | Certain | Set to 0 in all pool configs | ✅ Mitigated — pool configs set to 0 |
| Plaintext credential storage | High | Certain | Encrypt lemper.conf or use secret file references | ✅ Partially — `ENCRYPT_CONFIG_AT_REST` available (default off) |
| `eval`-based config loading | Medium | Medium | Replace with safe parser | ⚠️ Partial — `load_config()` still uses eval |
| Credential display at install end | High | Certain | Suppress, require explicit recall | ⚠️ Open — v3.5.0 |
| Source-built Nginx with 3rd-party modules | Medium | Low | Default to repo, make source opt-in | ✅ Resolved — repo default |
| No test isolation | Medium | High | Mock-based unit tests | ⚠️ Open — bats structural tests in place |
| Deprecated `apt-key` usage | Low | Certain | Use `signed-by` with keyring files | ✅ Fixed |
| Stale PHP 5.6–7.4 templates | Low | Certain | Remove EOL version support | ⚠️ Partial — installer fixed, templates remain |
| `fial` typo causing silent failures | Medium | Low | Fix to `fail` | ✅ Fixed (Phase 0) |
| `sed -i` not macOS-portable | Low | Certain | Use portable sed pattern | ⚠️ Open — 210 usages across 20 files |
| No input sanitization on domains | Medium | Certain | `validate_fqdn()` + `sanitize_sed_*` | ✅ Fixed

---

## 8. References

- [LEMPer GitHub](https://github.com/joglomedia/LEMPer)
- [Nginx Module Docs](https://nginx.org/en/docs/)
- [PHP-FPM Pool Config](https://www.php.net/manual/en/install.fpm.configuration.php)
- [MyGuard Nginx repository](https://deb.myguard.nl/nginx-modules/)
- [Sury PHP Repository](https://packages.sury.org/php/)
- [MariaDB Repositories](https://mariadb.com/kb/en/mariadb:repositories/)
- [Let's Encrypt ACME v2](https://letsencrypt.org/docs/)

## v4 release preparation

The preferred full-stack interface is `lemperctl stack install --all --config
FILE --minimal --yes`. `get-lemper --install --config FILE` selects the same
validated installation flow; its default remains CLI-only. The four historical
scripts are compatibility entry points. Runtime modules define functions only;
legacy source-time behavior is contained by executed adapters.

See [RELEASE_V4.md](RELEASE_V4.md) for artifacts, validation, and publication steps.

## Mail hosting modules

`lib/lemper-mail.sh` loads the function-only `lib/runtime/mail/commands.sh`
use cases. `lib/services/mail/store.sh` validates identities, renders virtual
maps and protected password files, and publishes a complete generation through
one atomic selector with service rollback. `lib/services/mail/configure.sh`
manages package ownership, TLS, Postfix/Dovecot/OpenDKIM templates, installation,
and removal. `scripts/install_mailer.sh` and `scripts/remove_mailer.sh` are
compatibility entrypoints. The plugin is exported by the shared registry.

Mutable configuration is under `/etc/lemper-mail`; messages are under
`/var/vmail`. Keeping this state outside the versioned code and `/etc/lemper`
allows CLI refresh and full-stack removal to preserve mail. See
[MAIL.md](MAIL.md) for the operational contract and migration requirements.

## PHP defaults and mounted applications (#91, #170)

`runtime/stack/config.sh` owns the PHP default request; `services/php/defaults.sh`
validates and switches alternatives with rollback, while `core/config-update.sh`
prepares a protected profile replacement preserving encryption and credentials.
The installer delegates to the same alternatives driver. Existing FPM/vhost
selections remain explicit.

`runtime/site/apps.sh` validates Laravel mount requests and records ownership.
`services/nginx/apps.sh` renders the tracked template, reconciles include hooks
across SSL/non-SSL variants, validates/reloads Nginx, and restores snapshots on
failure. Parent-site purge and PHP-reference checks include mounted applications.
See [PHP_RUNTIME_LARAVEL.md](PHP_RUNTIME_LARAVEL.md) for the public contracts.

## P1 database and repository boundaries

Legacy DB commands now delegate backup/restore/import/export and scheduling to
`lib/services/mariadb/database.sh`, sharing input validation, protected outputs,
operation locking and explicit failure handling. Signing-key downloads and source
migration use `lib/services/apt/repositories.sh`. Site diagnostics redact metadata
in both text and JSON. See [DATABASE.md](DATABASE.md) and
[ROADMAP_AUDIT.md](ROADMAP_AUDIT.md) for delivered behavior and UAT limits.

`lib/services/php/repository.sh` shares maintained Sury setup and legacy PHP
source migration between installation and CLI updates, using the generic APT
parser and scoped trust. `lib/services/mariadb/repository.sh` selects database
defaults and guards native Resolute MariaDB 11.8 against accidental major-series
migration. Mail configuration selects separate Dovecot 2.3/2.4 templates from the
installed version. See [UBUNTU_26_04.md](UBUNTU_26_04.md) for platform checks.

## P2 lifecycle and data services

`data`, `monitor` and `firewall` are registered public plugins, backed by Restic,
Monit and native nftables service modules. Full recipes and per-service operations
share install/remove contracts; optional backups/monitoring remain disabled by
default. SQL/data retention is scoped to verified managed artifacts. Configuration,
repositories, credentials and recovery state remain outside exported code trees.

The firewall recovery runner copies reviewed root-owned code into protected state
and reads only recovery data. It works before CLI/bootstrap completion and without
loading encrypted configuration. A firewall mutex serializes apply/confirm/recovery
without waiting for unrelated long-running shared-lock operations.

Account, database, self-SSL, TUI and vhost-creation wrappers retain their original
filenames and initialization contract while handlers occupy `lib/runtime/` and
account provisioning occupies `lib/services/accounts/`. Site management, updater
and component installer business logic now has runtime/service owners. Public
wrappers retain initialization and dispatch; optional request-state cleanup is
separate from the completed decomposition contract.

## Hosting plans and quota drivers

`lib/runtime/hosting/commands.sh` orchestrates the public `hosting` plugin.
`lib/services/hosting/plans.sh` owns validated plan/assignment data and transactional
lifecycle; `quota.sh` owns ext4 capability/reporting/enforcement. Both are function-only
modules loaded through the shared registry/loader and exported with the CLI.
Account provisioning delegates before password activation. No driver edits filesystem
mount configuration or installs a kernel. See [HOSTING.md](HOSTING.md) for limits,
rollback, filesystem identity and external-change behavior.
