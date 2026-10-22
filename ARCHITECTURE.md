# LEMPer — Architecture Document

> **Version:** 2.7.1 → 3.0.0 (proposed)
> **Last Updated:** 2026-10-22
> **Author:** Senior Engineering Audit

---

## 1. Overview

### 1.1 What is LEMPer?

LEMPer (**L**inux **E**ngine-X **M**ariaDB **P**HP — "Installer" or "er") is an open-source,
Bash-based CLI administration tool that automates deployment, configuration, and ongoing
management of a LEMP/LEMP-like stack on Debian and Ubuntu Linux servers. It provides both
an installer (`install.sh` / `lemper.sh`) and a runtime CLI (`lemper-cli`) for managing
virtual hosts, databases, SSL certificates, and supporting services.

**Target audience:**
- System administrators who need to provision PHP hosting servers quickly.
- DevOps engineers managing fleets of Debian/Ubuntu VPS instances.
- Teams looking for a free, scriptable alternative to cPanel/Plesk/RunCloud/Cloudways.

**Supported distributions:**
- Ubuntu: Bionic (18.04), Focal (20.04), Jammy (22.04), Noble (24.04)
- Debian: Buster (10), Bullseye (11), Bookworm (12)

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
│   ├── lemper-bench.sh            # CLI plugin: hardware & network benchmark
│   ├── lemper-create.sh           # CLI plugin: vhost creation & framework auto-installer
│   ├── lemper-db.sh               # CLI plugin: MySQL/MariaDB database manager (backup/restore)
│   ├── lemper-encrypt.sh          # Config at-rest encryption utilities
│   ├── lemper-fixpermission.sh    # CLI plugin: fix file/directory permissions
│   ├── lemper-manage.sh           # CLI plugin: vhost management (enable/disable/SSL)
│   ├── lemper-selfssl.sh          # CLI plugin: self-signed SSL generator (RSA 4096)
│   ├── lemper-site.sh             # CLI plugin: site dispatcher
│   ├── lemper-site-list.sh        # CLI plugin: vhost listing (table + JSON)
│   ├── lemper-site-show.sh        # CLI plugin: detailed vhost + FPM + SSL info
│   ├── lemper-tui.sh              # Interactive TUI dashboard
│   └── core/
│       └── lemper-stacks.sh       # Installer/uninstaller orchestrator (shared)
├── scripts/
│   ├── utils.sh                   # Core helper library (shared, 1021 lines)
│   ├── install_dependencies.sh    # Base packages + Python
│   ├── install_nginx.sh           # Nginx installer (delegates to nginx/)
│   ├── install_php.sh             # PHP 8.1–8.4 only (EOL 5.6–8.0 removed)
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
│   ├── install_modsec.sh          # ModSecurity v3 + OWASP CRS v3.3.5
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
│   ├── php/8.4/                   # PHP FPM configs (only 8.1–8.4 remain)
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
├── .env.dist                      # Configuration template (INI format)
├── .gitignore
├── CONTRIBUTING.md
├── DEVELOPER.md
├── AGENTIC.md
├── ARCHITECTURE.md
├── ROADMAP.md
├── LICENSE.md
├── README.md
├── install.sh                     # Standalone installer (~47 lines, wrapper)
├── lemper.sh                      # Interactive installer (~551 lines, 551 lines)
├── remove.sh                      # Standalone uninstaller (~48 lines, wrapper)
├── tests/
│   ├── test_helper.bash
│   ├── test_sanitization.bats    # Input sanitization (9 tests)
│   ├── test_structure.bats        # Structural integrity (35 tests)
│   └── test_syntax.bats           # ShellCheck + bash -n (2 tests)
└── .github/workflows/main.yml    # CI: ShellCheck + bats (44 tests)
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
    │     install_tools.sh           → lemper-cli + web admin tools (site list/show plugins)
    │     server_optimization.sh     → Swap, sysctl tuning
    │     server_security.sh         → SSH hardening, UFW/CSF/APF
    │
    └─> Credentials recap + log file output
```

#### 2.2.2 CLI (Runtime) Flow

```
lemper-cli <command> [subcommand] [options]
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
| `/srv/.htpasswd` | Web auth users | ✅ Yes (password hashes) |

The `.env` file uses a pseudo-INI format with `[section]` headers that Bash's `source` cannot
parse natively. The loader strips comments and sections, then `eval`s each `key=value` line:

```bash
source <(grep -v '^#' "${ENVFILE}" | grep -v '^\[' | \
    sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
```

This pattern is used in both `utils.sh` and `bin/lemper-cli.sh`.

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
└── lemper-bench
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
3. **Bats Tests:** Runs `bats tests/` — **44/44 pass** across 4 test files.

**Test coverage (44 tests):**
- `test_sanitization.bats` — 9 tests (FQDN, IPv4, username, sed injection sanitization)
- `test_structure.bats` — 35 tests (project structure, wiring, config flags)
- `test_syntax.bats` — 2 tests (bash -n + shellcheck on all scripts)

**Limitations:**
- No code coverage reporting.
- Tests are structural (grep-based) + syntax — no mock-based unit tests.
- No security scanning (bandit, semgrep, lynis as code).
- Only runs on `ubuntu-latest` (no Debian matrix).
- `sed -i` usage throughout codebase is not portable to macOS.

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
  and `secure_shred()`. `bin/lemper-cli.sh` pre-parses `--password`/`-P` flag, decrypts
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
- **✅ Nginx WAF: ModSecurity v3 + OWASP CRS v3.3.5** (replaced legacy NAXSI).
- **✅ SSL: Let's Encrypt (certbot)** with ACME v2 DNS-01 wildcard support.
  Self-signed CA: **RSA 4096-bit**, SHA-256 (upgraded from 2048-bit).
- No TLS for database connections by default.
- No secrets rotation mechanism.

### 3.4 Known Vulnerabilities (Audit Status)

| ID | Issue | Severity | Location | Status |
|---|---|---|---|---|
| SEC-01 | `cgi.fix_pathinfo = 1` allows path traversal | High | All PHP pool configs | ✅ **Mitigated** — set to `0` in all pool configs |
| SEC-02 | NOPASSWD:ALL sudo for `lemper` user | Critical | `utils.sh` sudoers | ⚠️ **Open** — flagged for v3.5.0 |
| SEC-03 | Passwords passed as CLI args (`ps` visible) | Medium | `lemper-create.sh`, `lemper-db.sh` | ⚠️ **Open** — flagged for v3.5.0 |
| SEC-04 | `cgi.fix_pathinfo` set to 1 in default PHP pools | High | `www.conf` templates | ✅ **Mitigated** — set to `0` |
| SEC-05 | Self-signed SSL uses 2048-bit RSA | Medium | `nginx_ssl_cert.sh`, `lemper-selfssl.sh` | ✅ **Fixed** — upgraded to RSA 4096 |
| SEC-06 | `eval`-based dotenv loading (injection risk) | High | `utils.sh:31`, `lemper-cli.sh:55` | ⚠️ **Partial** — `load_config()` in `lemper-encrypt.sh` still uses eval |
| SEC-07 | `apt-key` is deprecated and insecure | Low | `nginx_repo.sh:45` | ✅ **Fixed** — uses `signed-by` keyring files |
| SEC-08 | Credentials printed to stdout | High | `install.sh`, `lemper.sh` | ⚠️ **Open** — flagged for v3.5.0 |
| SEC-09 | `fial` typo (undefined function) | Medium | `lemper-create.sh`, `lemper-db.sh` | ✅ **Fixed** (Phase 0) |
| SEC-10 | No input sanitization on domain → `sed`/`openssl` | Medium | `lemper-selfssl.sh`, `lemper-create.sh` | ✅ **Fixed** — `validate_fqdn()` + `sanitize_sed_replacement()` in `utils.sh` |
| SEC-11 | Credentials stored in `/etc/lemper/lemper.conf` without encryption | High | `utils.sh:846-851` | ✅ **Partially fixed** — `ENCRYPT_CONFIG_AT_REST` option available (default off) |
| SEC-12 | Open_basedir tmp dirs under `~/.lemper` may leak | Medium | `lemper-create.sh` | ⚠️ **Open** — noted, low immediate risk |

---

## 4. Proposed Target Architecture (v3.0)

### 4.1 Guiding Principles

1. **Security-first** — Eliminate all plaintext credential exposure, fix all known vulnerabilities.
2. **Modularity** — Split monolithic scripts into well-defined, testable modules.
3. **Testability** — Unit-testable functions with mockable dependencies.
4. **Maintainability** — Consistent patterns, clear conventions, comprehensive linting.
5. **Developer experience** — Clear contribution workflow, automated CI gates.
6. **AI-agent friendly** — Structured code, clear boundaries, predictable patterns.

### 4.2 Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    LEMPer CLI (bin/)                     │
│                    lemper-cli.sh                          │
├─────────────────────────────────────────────────────────┤
│                    Plugin Dispatcher                      │
│                    (init_lemper_cli)                      │
├─────────────────────────────────────────────────────────┤
│                    Core Library (lib/)                    │
│                    ┌───────────┬───────────┬───────────┐ │
│                    │  Account  │  Site     │  Database │ │
│                    │  Mgmt     │  Mgmt     │  Mgmt     │ │
│                    └───────────┴───────────┴───────────┘ │
├─────────────────────────────────────────────────────────┤
│                    Shared Utils (scripts/)                │
│                    utils.sh, config.sh, logging.sh        │
│                    distro.sh, network.sh, security.sh     │
├─────────────────────────────────────────────────────────┤
│              OS / Package Manager (apt) / systemd        │
└─────────────────────────────────────────────────────────┘
```

### 4.3 Key Architectural Changes

| Area | Current | Proposed (v3.0) |
|---|---|---|
| **Config format** | `.env` INI-style, `eval`-loaded | Structured `.env` or YAML with schema validation |
| **Secrets** | Plaintext files | Encrypted config or secret file references, no credential display |
| **CLI** | Sourced plugins, no arg validation library | Consistent `getopt`-based or bash-argparsing framework |
| **Tests** | shunit2 integration tests only | shunit2 unit tests + shellcheck + bashate + lynis as code-scanning |
| **Security** | Optional fail2ban, commented encryption | Fail2ban + CrowdSec, encrypted secrets, secure defaults |
| **CI** | ShellCheck + install tests on Ubuntu | Multi-distro matrix, security audit, dependency scan, release automation |
| **Documentation** | Minimal README + CONTRIBUTING | Full ARCHITECTURE, DEVELOPER, AGENTIC, ROADMAP docs |
| **PHP support** | 5.6–8.4 (many EOL) | 8.1+ only (EOL versions removed) |
| **SSH** | Password or key auth | Key-only by default, ed25519 |
| **Firewall** | UFW/CSF/APF | UFW + nftables backend, optional CrowdSec |
| **SSL** | RSA 2048 self-signed | RSA 4096 or ed25519, OCSP stapling, ACME v2 |

### 4.4 Module Decomposition (Planned → Partially Implemented)

The current flat structure (`lib/lemper-*.sh`, `scripts/install_*.sh`) was intended to be
reorganized into clear functional modules. **Status: scaffolds created but migration incomplete.**

```
LEMPer/
├── bin/
│   └── lemper-cli.sh              # CLI entry point
├── lib/
│   ├── core/                      # ✅ Scaffold created · ⚠️ Only lemper-stacks.sh present
│   │   ├── lemper-stacks.sh       # ✅ Done: lemper_install() + lemper_remove() orchestrator
│   │   ├── .gitkeep               # ✅ Dir marker (lib/core, runtime, services)
│   │   ├── config.sh              # ❌ Not migrated — utils.sh still holds config logic
│   │   ├── logging.sh             # ❌ Not migrated — utils.sh holds logging
│   │   ├── colors.sh              # ❌ Not migrated — utils.sh holds colors
│   │   └── cli.sh                 # ❌ Not migrated — bin/lemper-cli.sh holds dispatcher
│   ├── runtime/                   # ⚠️ Scaffold only — all plugins still in lib/ (flat)
│   │   ├── .gitkeep
│   │   ├── account.sh             # ❌ lib/lemper-account.sh
│   │   ├── site_create.sh         # ❌ lib/lemper-create.sh
│   │   ├── site_manage.sh         # ❌ lib/lemper-manage.sh
│   │   ├── database.sh            # ❌ lib/lemper-db.sh
│   │   ├── ssl.sh                 # ❌ lib/lemper-selfssl.sh
│   │   ├── util.sh                # ❌ lib/lemper-bench.sh, lemper-fixpermission.sh
│   │   ├── site_list.sh           # ❌ lib/lemper-site-list.sh
│   │   ├── site_show.sh           # ❌ lib/lemper-site-show.sh
│   │   ├── site.sh                # ❌ lib/lemper-site.sh
│   │   ├── tui.sh                 # ❌ lib/lemper-tui.sh
│   │   └── encrypt.sh             # ❌ lib/lemper-encrypt.sh
│   └── services/                  # ⚠️ Scaffold only — all installers still in scripts/
│       ├── .gitkeep
│       ├── nginx.sh               # ❌ scripts/install_nginx.sh
│       ├── php.sh                 # ❌ scripts/install_php.sh
│       ├── mariadb.sh             # ❌ scripts/install_mariadb.sh
│       ├── redis.sh               # ❌ scripts/install_redis.sh
│       ├── postgres.sh            # ❌ scripts/install_postgres.sh
│       ├── memcached.sh           # ❌ scripts/install_memcached.sh
│       ├── mongodb.sh             # ❌ scripts/install_mongodb.sh
│       ├── bun.sh                 # ❌ scripts/install_bun.sh
│       ├── ftp.sh                 # ❌ scripts/install_pureftpd.sh, install_vsftpd.sh
│       ├── certbot.sh             # ❌ scripts/install_certbotle.sh
│       ├── fail2ban.sh            # ❌ scripts/install_fail2ban.sh
│       ├── firewall.sh            # ❌ scripts/server_security.sh
│       ├── mailer.sh              # ❌ scripts/install_mailer.sh
│       └── tools.sh               # ❌ scripts/install_tools.sh
├── scripts/                       # ✅ Active — scripts sourced by lemper-stacks.sh
├── etc/                           # ✅ Active — configuration templates
├── share/                         # ✅ Active — static assets
├── tests/                         # ✅ Active — bats test suite
└── docs/                          # ⚠️ Docs in repo root (not docs/ subdir)
    ├── ARCHITECTURE.md            # ✅ Root
    ├── DEVELOPER.md               # ✅ Root
    ├── AGENTIC.md                 # ✅ Root
    └── ROADMAP.md                 # ✅ Root
```

**Migration decision:** The proposed directory restructuring would require renaming and
moving ~50+ script files while maintaining backward-compatible symlink/destination paths
on target systems. Given the scope and risk, the project should prioritize the **functional
improvements already delivered** (security, PHP 8.4, Valkey, Bun.js, CrowdSec, ModSecurity,
encrypted config, TUI) over a purely structural refactor. The directory scaffolds remain
in place as a future-enhancement path.

---

## 5. Technology Stack Summary (as of v3.4.0)

| Component | Current | Target (v3.0) | Status |
|---|---|---|---|
| **Language** | Bash 4+ | Bash 5+ | ✅ Achieved |
| **ShellCheck** | v0.10.0 | Latest | ✅ v0.11.0 locally, v0.10.0 in CI — both exit 0 |
| **Test framework** | shunit2 | shunit2 + bats-core | ✅ bats-core 1.14.0, 44 tests |
| **CI** | GitHub Actions | GitHub Actions (enhanced) | ✅ ShellCheck + bats matrix |
| **Web server** | Nginx (repo or source) | Nginx (repo default, source optional) | ✅ |
| **PHP** | 5.6–8.4 (EOL versions in templates) | 8.1–8.4 (Ondřej's PPA) | ✅ EOL removed from installer, stale templates remain |
| **Database** | MariaDB 11.1 | MariaDB 11.4 | ✅ Upgraded |
| **Cache** | Redis | Redis or Valkey (configurable) | ✅ Valkey added (REDIS_BACKEND) |
| **JS runtime** | (unused) | Bun.js | ✅ Bun.js installed |
| **FTP** | Pure-FTPd, vsftpd | Pure-FTPd (TLS) | ✅ |
| **SSL** | RSA 2048 self-signed | RSA 4096, ACME v2 DNS-01 wildcard | ✅ Both implemented |
| **Firewall** | UFW, CSF, APF | UFW, CrowdSec | ✅ CrowdSec added |
| **Security** | Fail2ban (optional) | Fail2ban (default) + CrowdSec | ✅ Fail2ban enabled by default |
| **WAF** | NAXSI | ModSecurity v3 + OWASP CRS | ✅ Migrated |
| **Config format** | .env (INI) | .env (INI) + schema validation | ⚠️ Encryption added, schema validation planned |
| **Secrets** | Plaintext | Encrypted at rest | ✅ Available (default off) |

---

## 6. Data Flow Diagrams

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
User runs: lemper-cli site add -d example.com -f wordpress
    │
    ├─> /usr/local/bin/lemper-cli (symlink → bin/lemper-cli.sh)
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

## 7. Risk Assessment (Updated v3.4.0)

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
- [Ondřej Surý's Nginx PPA](https://launchpad.net/~ondrej/+archive/ubuntu/nginx)
- [Sury PHP Repository](https://packages.sury.org/php/)
- [MariaDB Repositories](https://mariadb.com/kb/en/mariadb:repositories/)
- [Let's Encrypt ACME v2](https://letsencrypt.org/docs/)
