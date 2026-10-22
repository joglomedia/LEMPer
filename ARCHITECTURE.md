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

### 2.1 Project Structure

```
LEMPer/
├── bin/
│   └── lemper-cli.sh              # CLI entry point (symlinked to /usr/local/bin/lemper-cli)
├── lib/
│   ├── lemper-account.sh          # CLI plugin: system account creation (interactive)
│   ├── lemper-adduser.sh          # CLI plugin: add user wrapper
│   ├── lemper-bench.sh            # CLI plugin: hardware & network benchmark
│   ├── lemper-create.sh           # CLI plugin: vhost creation & framework auto-installer
│   ├── lemper-db.sh               # CLI plugin: MySQL/MariaDB database manager
│   ├── lemper-fixpermission.sh    # CLI plugin: fix file/directory permissions
│   ├── lemper-manage.sh           # CLI plugin: vhost management (enable/disable/SSL/etc.)
│   └── lemper-selfssl.sh          # CLI plugin: self-signed SSL generator
├── scripts/
│   ├── utils.sh                   # Core helper library (shared by all scripts)
│   ├── install_dependencies.sh    # Base package & Python installation
│   ├── install_nginx.sh           # Nginx installer (delegates to nginx/ submodules)
│   ├── install_php.sh             # PHP + FPM installer
│   ├── install_phalcon.sh         # Phalcon PHP framework
│   ├── install_mariadb.sh         # MariaDB installer
│   ├── install_postgres.sh        # PostgreSQL installer
│   ├── install_redis.sh           # Redis installer
│   ├── install_mongodb.sh         # MongoDB installer
│   ├── install_memcached.sh       # Memcached installer
│   ├── install_imagemagick.sh     # ImageMagick installer
│   ├── install_mailer.sh          # Postfix + Dovecot mailer
│   ├── install_pureftpd.sh        # Pure-FTPd installer
│   ├── install_vsftpd.sh          # vsftpd installer
│   ├── install_certbotle.sh       # Let's Encrypt certbot installer
│   ├── install_fail2ban.sh        # Fail2ban installer
│   ├── install_tools.sh           # CLI tool + web admin tools installer
│   ├── install_nodejs.sh          # Node.js installer (not in main flow)
│   ├── install_tools.sh           # Tools installation
│   ├── server_cleanup.sh          # Pre-install service cleanup
│   ├── server_optimization.sh     # Kernel parameter tuning
│   ├── server_security.sh         # SSH hardening + firewall config
│   ├── remove_*.sh                # Per-component removal scripts
│   ├── nginx/                     # Nginx build sub-modules
│   │   ├── nginx_common.sh        # Shared variables & helpers
│   │   ├── nginx_repo.sh          # Repository-based install (ondrej/myguard)
│   │   ├── nginx_ssl_builders.sh  # OpenSSL/LibreSSL/BoringSSL source builds
│   │   ├── nginx_extra_modules.sh # Third-party module compilation
│   │   ├── nginx_module_config.sh # Dynamic module configuration
│   │   ├── nginx_build.sh         # Source compilation orchestration
│   │   ├── nginx_post_install.sh  # Post-install config file deployment
│   │   └── nginx_ssl_cert.sh      # Hostname SSL cert generation
│   ├── mariadb_repo_setup         # MariaDB repo setup script (bundled binary)
│   └── README.md                  # Minimal scripts readme
├── etc/                           # Template configuration files (copied to target system)
│   ├── nginx/                     # Nginx configs, includes, vhosts, error pages
│   ├── php/{5.6,7.0,...,8.4}/     # PHP FPM configs per version
│   ├── mysql/                     # MariaDB/MySQL configs
│   ├── redis/redis.conf           # Redis config
│   ├── memcached/                 # Memcached configs
│   ├── pure-ftpd/                 # Pure-FTPd configs
│   ├── openssl/                   # CA/CSR/cert templates
│   ├── fail2ban/                  # Fail2ban filters
│   ├── systemd/                   # Systemd service files
│   └── init.d/                    # SysV init scripts
├── share/
│   └── nginx/html/               # Static files (error pages, index page)
│   └── memcached/scripts/         # Memcached tools
├── shunit2/
│   └── run_test.sh               # Unit test runner
├── .github/
│   ├── workflows/main.yml         # CI: shellcheck + integration tests
│   ├── ISSUE_TEMPLATE/            # Issue templates
│   └── assets/                    # Logo & favicon
├── .env.dist                      # Configuration template (INI format)
├── .gitignore                     # Ignore .env, logs, compiled files
├── CONTRIBUTING.md                # Minimal contribution guide
├── LICENSE.md                     # GPLv3
├── README.md                      # Project readme
├── install.sh                     # Standalone installer entry point
├── lemper.sh                      # Interactive installer/uninstaller with CLI args
├── remove.sh                      # Standalone uninstaller entry point
└── .env.dist                      # Configuration template
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
    │     install_redis.sh           → Redis
    │     install_mongodb.sh         → MongoDB (optional)
    │     install_memcached.sh       → Memcached (optional)
    │     install_imagemagick.sh     → ImageMagick
    │     install_mailer.sh          → Postfix + Dovecot + DKIM
    │     install_pureftpd.sh / install_vsftpd.sh
    │     install_fail2ban.sh        → Fail2ban
    │     install_tools.sh           → lemper-cli + web admin tools
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
    │           │     └──> mod/manage → lemper-manage.sh (enable/disable SSL, cache, etc.)
    │           ├──> db → lemper-db.sh (account/create/drop/import/export/query)
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

### 2.5 CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/main.yml`) runs on every push/PR to
`2.x.x` and `master` branches:

1. **Setup:** Copies `.env.dist` → `.env`, adjusts config for CI environment.
2. **ShellCheck:** Runs `shellcheck -s bash -x` on every script file.
3. **Unit Tests:** Runs `shunit2/run_test.sh` which sources and executes installation scripts
   and checks for resulting binaries.

**Limitations:**
- No code coverage reporting.
- Tests run full installations (no mocking/isolation).
- No lint gate on the `lib/` directory (though shellcheck does check it).
- No security scanning (bandit, semgrep, etc.).
- Only runs on `ubuntu-latest` (no Debian testing matrix).

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
  `/etc/sudoers.d/90-lemper-users` — a significant privilege escalation risk.
- SSH hardening is implemented via `server_security.sh` (port change, key-only auth,
  root login disable).
- FTP uses Pure-FTPd or vsftpd with TLS support.

### 3.2 Secrets Management

- All passwords are stored in plaintext in `/etc/lemper/lemper.conf`.
- A `secure_config()` function exists (AES-256-GCM encryption with the lemper password as key)
  but is **commented out** and never called.
- Credentials are printed to stdout at the end of installation.
- The install log file (`lemper_install.log`) contains credential data.

### 3.3 Network Security

- Firewall: UFW (default), CSF, or APF (user-selectable).
- Fail2ban for intrusion prevention (optional, off by default).
- Nginx WAF: NAXSI rules (optional, legacy).
- SSL: Let's Encrypt (certbot) or self-signed CA (RSA 2048, SHA-256).
- No TLS for database connections by default.
- No secrets rotation mechanism.

### 3.4 Known Vulnerabilities

| ID | Issue | Severity | Location |
|---|---|---|---|
| SEC-01 | `cgi.fix_pathinfo = 1` allows path traversal to execute arbitrary PHP files | High | All PHP pool configs |
| SEC-02 | NOPASSWD:ALL sudo for non-root `lemper` user | Critical | `utils.sh:741` |
| SEC-03 | Passwords passed as CLI args (visible in `ps` output) | Medium | `lemper-create.sh`, `lemper-db.sh` |
| SEC-04 | `cgi.fix_pathinfo` set to 1 in default PHP pools | High | `www.conf` templates |
| SEC-05 | Self-signed SSL uses 2048-bit RSA (should be 4096) | Medium | `nginx_ssl_cert.sh`, `lemper-selfssl.sh` |
| SEC-06 | `eval`-based dotenv loading (potential injection) | High | `utils.sh:31`, `lemper-cli.sh:55` |
| SEC-07 | `apt-key` is deprecated and insecure | Low | `nginx_repo.sh:45` |
| SEC-08 | Credentials printed to stdout and optionally emailed | High | `install.sh:288`, `lemper.sh:194-280` |
| SEC-09 | `fial` typo (undefined function) in error paths | Medium | `lemper-create.sh:957`, `lemper-db.sh:593` |
| SEC-10 | No input sanitization on domain → passed to `sed`, `openssl` | Medium | `lemper-selfssl.sh`, `lemper-create.sh` |
| SEC-11 | Credentials stored in `/etc/lemper/lemper.conf` without encryption | High | `utils.sh:846-851` |
| SEC-12 | Open_basedir set but tmp dirs under `~/.lemper` may leak | Medium | `lemper-create.sh:615-616` |

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

### 4.4 Module Decomposition (Planned)

The current flat structure (`lib/lemper-*.sh`, `scripts/install_*.sh`) will be
reorganized into clear functional modules:

```
LEMPer/
├── bin/
│   └── lemper-cli.sh              # CLI entry point
├── lib/
│   ├── core/                      # Core framework
│   │   ├── config.sh              # Configuration loading & validation
│   │   ├── logging.sh             # Structured logging
│   │   ├── colors.sh              # Terminal color helpers
│   │   └── cli.sh                 # CLI dispatcher + arg parsing
│   ├── runtime/                   # Runtime management CLI plugins
│   │   ├── account.sh             # Account management
│   │   ├── site_create.sh         # Vhost creation
│   │   ├── site_manage.sh         # Vhost management
│   │   ├── database.sh            # Database operations
│   │   ├── ssl.sh                 # SSL certificate operations
│   │   └── util.sh                # Utility commands (bench, fixperm)
│   └── services/                  # Service installation modules
│       ├── nginx.sh               # Nginx installer
│       ├── php.sh                 # PHP-FPM installer
│       ├── mariadb.sh             # MariaDB installer
│       ├── redis.sh               # Redis installer
│       ├── postgres.sh            # PostgreSQL installer
│       ├── memcached.sh           # Memcached installer
│       ├── mongodb.sh             # MongoDB installer
│       ├── ftp.sh                 # FTP server installer
│       ├── certbot.sh             # Let's Encrypt installer
│       ├── fail2ban.sh            # Fail2ban installer
│       ├── firewall.sh            # Firewall configurator
│       ├── mailer.sh              # Mail server installer
│       └── tools.sh               # Web admin tools + CLI tool
├── scripts/                       # Legacy scripts (being migrated)
├── etc/                           # Configuration templates
├── share/                         # Static assets
├── tests/                         # Unit & integration tests
│   ├── unit/
│   └── integration/
└── docs/                          # Documentation
    ├── ARCHITECTURE.md
    ├── DEVELOPER.md
    ├── AGENTIC.md
    └── ROADMAP.md
```

---

## 5. Technology Stack Summary

| Component | Current | Target (v3.0) |
|---|---|---|
| **Language** | Bash 4+ | Bash 5+ |
| **ShellCheck** | v0.10.0 | Latest |
| **Test framework** | shunit2 | shunit2 + bats-core |
| **CI** | GitHub Actions | GitHub Actions (enhanced) |
| **Web server** | Nginx (repo or source) | Nginx (repo default, source optional) |
| **PHP** | 5.6–8.4 (Ondřej's PPA) | 8.1–8.4 (Ondřej's PPA) |
| **Database** | MariaDB 11.1, PostgreSQL 17 | MariaDB 11.4+, PostgreSQL 17 |
| **Cache** | Redis, Memcached | Redis (ACL), Memcached (SASL) |
| **FTP** | Pure-FTPd, vsftpd | Pure-FTPd (TLS) |
| **SSL** | Let's Encrypt, self-signed RSA-2048 | Let's Encrypt, self-signed RSA-4096 |
| **Firewall** | UFW, CSF, APF | UFW + nftables, CrowdSec optional |
| **Security** | Fail2ban | Fail2ban + CrowdSec |
| **Config format** | .env (INI) | .env (structured) + JSON schema validation |
| **Secrets** | Plaintext | Encrypted at rest |

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

## 7. Risk Assessment

| Risk | Impact | Likelihood | Mitigation Planned |
|---|---|---|---|
| NOPASSWD sudo for lemper user | Critical | High | Remove NOPASSWD, use sudo group with restricted commands |
| `cgi.fix_pathinfo=1` | High | Certain | Set to 0 in all pool configs |
| Plaintext credential storage | High | Certain | Encrypt lemper.conf or use secret file references |
| `eval`-based config loading | Medium | Medium | Replace with safe parser |
| Credential email to admin | Medium | Certain | Remove email feature, require explicit copy |
| Source-built Nginx with many 3rd-party modules | Medium | Low | Default to repo install, make source opt-in |
| No test isolation | Medium | High | Mock-based unit tests |
| Deprecated `apt-key` usage | Low | Certain | Use `signed-by` with keyring files |
| Stale PHP 5.6–7.4 templates | Low | Certain | Remove EOL version support |
| `fial` typo causing silent failures | Medium | Low | Fix to `fail` |

---

## 8. References

- [LEMPer GitHub](https://github.com/joglomedia/LEMPer)
- [Nginx Module Docs](https://nginx.org/en/docs/)
- [PHP-FPM Pool Config](https://www.php.net/manual/en/install.fpm.configuration.php)
- [Ondřej Surý's Nginx PPA](https://launchpad.net/~ondrej/+archive/ubuntu/nginx)
- [Sury PHP Repository](https://packages.sury.org/php/)
- [MariaDB Repositories](https://mariadb.com/kb/en/mariadb:repositories/)
- [Let's Encrypt ACME v2](https://letsencrypt.org/docs/)
