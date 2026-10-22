# LEMPer — Roadmap & Improvement Plan

> **Version:** 3.0.0 (proposed)
> **Last Updated:** 2026-10-22
> **Status:** Proposed — awaiting approval before execution
>
> This document presents the audit findings and improvement recommendations for the LEMPer
> codebase. It is organized by priority area (Security, Architecture, Functionality,
> UX, Stack Currency) and includes a phased rollout plan.

---

## 1. Audit Summary

A comprehensive audit of the LEMPer codebase was conducted, covering:

| Area | Files Audited | Issues Found |
|---|---|---|
| Security | `utils.sh`, `lib/lemper-*`, `install.sh`, `lemper.sh`, `etc/` configs | 12 critical/medium issues |
| Architecture | All `.sh` files, `.env.dist`, CI config | Monolithic, no modularity, weak tests |
| Functionality | All install scripts, CLI plugins, config templates | 9 bugs, 3 typos, outdated defaults |
| UI/UX | `bin/lemper-cli.sh`, `lib/lemper-create.sh`, `lib/lemper-manage.sh` | Poor CLI UX, no progress feedback |
| Stack Currency | `.env.dist`, PHP configs, Nginx modules | PHP 5.6–7.4 supported (EOL), old MariaDB |

---

## 2. Prioritized Recommendations

### Phase 0 — Immediate Security Fixes (P0 — Critical)

These are **blocking issues** that must be fixed before any other work.

#### 2.1 Fix `fial` Typo (Bug)

**Issue:** `fial` is an undefined function called in error paths, causing silent `set -e`
aborts with unhelpful error messages.

**Files:**
- `lib/lemper-create.sh:957` — `fial "..."` → `fail "..."`
- `lib/lemper-db.sh:593` — `fial "..."` → `fail "..."`

**Effort:** Trivial (2-line fix)

---

#### 2.2 Fix `cgi.fix_pathinfo = 1` (Security — High)

**Issue:** `cgi.fix_pathinfo = 1` in all PHP-FPM pool configurations allows path traversal
attacks. An attacker can upload a file like `image.jpg/evil.php` and have Nginx route it
to the PHP interpreter.

**Files:**
- `etc/php/*/fpm/pool.d/lemper.conf` (14 versions: 5.6–8.4)
- `etc/php/*/fpm/pool.d/www.conf` (14 versions: 5.6–8.4)
- `lib/lemper-create.sh:636` — generated pool config template

**Fix:** Change `php_flag[cgi.fix_pathinfo] = 1` → `php_flag[cgi.fix_pathinfo] = 0`

**Effort:** Low (sed across all config files)

---

#### 2.3 Remove NOPASSWD:ALL for `lemper` User (Security — Critical)

**Issue:** The default `lemper` system user is granted `NOPASSWD:ALL` sudo access, which
is effectively root-equivalent. This is a critical privilege escalation risk if the
`lemper` account is compromised.

**File:** `scripts/utils.sh:740-741`

**Current code:**
```bash
run echo "${LEMPER_USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-lemper-users
```

**Fix:** Remove this line entirely, or replace with a restricted sudoers entry:
```bash
# Lemper user can restart specific services only
run echo "${LEMPER_USERNAME} ALL=(root) NOPASSWD: /bin/systemctl restart nginx, /bin/systemctl restart php*, /bin/systemctl reload nginx" >> /etc/sudoers.d/90-lemper-users
```

**Effort:** Low

---

#### 2.4 Suppress Credential Display in stdout (Security — High)

**Issue:** Installation prints all passwords (MySQL root, Redis, MongoDB, LEMPer account,
etc.) to stdout, making them visible in CI logs, terminal scrollback, and potentially
captured by screen recording.

**Files:**
- `install.sh:284-288` — credentials printed + optionally emailed
- `lemper.sh:194-280` — credentials recap block

**Fix:**
- Remove the credential recap by default.
- Write credentials only to an encrypted file (`gpg`-encrypted or mode 0600).
- Add a `--show-credentials` CLI flag for explicit opt-in.

**Effort:** Medium

---

#### 2.5 Remove Email Credential Delivery (Security — Medium)

**Issue:** Credentials are optionally sent via `mail` command to the admin email.

**File:** `install.sh:287-288`

**Fix:** Remove the email delivery entirely. Credentials should only be saved to a
restricted file.

**Effort:** Low

---

### Phase 1 — Security Hardening (P1 — High/Medium)

#### 2.6 Replace `eval`-Based Config Loading (Security — High)

**Issue:** Both `scripts/utils.sh:31` and `bin/lemper-cli.sh:55` use `source <(grep ... |
sed ...)` which effectively `eval`s the contents of `.env`/`lemper.conf`. If any value
contains shell metacharacters, arbitrary code execution is possible.

**Files:** `scripts/utils.sh`, `bin/lemper-cli.sh`

**Fix:** Replace with a safe line-by-line parser that uses `IFS='='` and `declare`:
```bash
safe_load_env() {
    while IFS='=' read -r key value; do
        [[ -z "${key}" || "${key}" =~ ^[[:space:]]*# || "${key}" =~ ^[[:space:]]*\[ ]] && continue
        key="${key// /}"
        value="${value#\"}"
        value="${value%\"}"
        export "${key}=${value}"
    done < "${ENVFILE}"
}
```

**Effort:** Medium — must maintain backward compatibility with existing `.env` and
`lemper.conf` formats.

---

#### 2.7 Upgrade Self-Signed SSL to RSA-4096 (Security — Medium)

**Issue:** Self-signed certificates use RSA-2048, which is below the current OWASP
recommendation (3072+ bits minimum, 4096 recommended for CAs).

**Files:**
- `scripts/nginx/nginx_ssl_cert.sh:79` — `rsa:2048` → `rsa:4096`
- `lib/lemper-selfssl.sh:107-108` — `rsa:2048` → `rsa:4096`
- `lib/lemper-manage.sh:791` — `rsa:2048` → `rsa:4096`

**Also update** `etc/openssl/cert.conf` to include proper SAN (Subject Alternative Name)
defaults.

**Effort:** Low

---

#### 2.8 Replace `apt-key` with Keyring Files (Security — Low)

**Issue:** `apt-key` is deprecated and stores all repository keys in a single keyring,
creating trust-confusion vulnerabilities.

**File:** `scripts/nginx/nginx_repo.sh:45`, `scripts/install_php.sh:62`

**Fix:** Replace:
```bash
apt-key adv --keyserver ...
```
with:
```bash
curl -sSL https://... | gpg --dearmor -o /usr/share/keyrings/repo.gpg
# In .list file: deb [signed-by=/usr/share/keyrings/repo.gpg] ...
```

**Effort:** Low

---

#### 2.9 Add Input Sanitization Layer (Security — Medium)

**Issue:** Domain names are passed directly to `sed`, `openssl`, and file paths without
sanitization. While `validate_fqdn()` is called in some paths, other paths (e.g.,
self-signed SSL generation) do not validate.

**Files:** `lib/lemper-selfssl.sh`, `lib/lemper-create.sh`, `lib/lemper-manage.sh`

**Fix:**
- Validate all user inputs (domain names, IP addresses, usernames) before use.
- Use `printf '%q'` or manual escaping when interpolating into `sed`/`openssl` commands.
- Add a `sanitize_sed_replacement()` helper function.

**Effort:** Medium

---

#### 2.10 Enable Encrypted Config at Rest (Security — High)

**Issue:** `/etc/lemper/lemper.conf` stores all credentials in plaintext. A
`secure_config()` function (AES-256-GCM) exists but is commented out.

**Files:** `scripts/utils.sh:854-861`, `lemper.sh:286`, `install.sh:295`

**Fix:**
- Uncomment and call `secure_config()` after installation.
- Add a decryption step at CLI startup that prompts for the lemper password.
- **Alternative (v3.0 preferred):** Use `pass` (password-store) or GPG-encrypted config.

**Effort:** High — requires changes to both install and CLI startup paths.

---

### Phase 2 — Architecture & Code Quality (P1 — High)

#### 2.11 Eliminate Duplicated Install/Remove Logic

**Issue:** `install.sh` and `lemper.sh` contain nearly identical installation and
removal logic. When one is updated, the other is often missed.

**Files:** `install.sh`, `lemper.sh`

**Fix:**
- Make `lemper.sh` the single orchestrator.
- Have `install.sh` and `remove.sh` be thin wrappers that delegate to `lemper.sh`:
  ```bash
  # install.sh
  exec ./lemper.sh install "$@"
  ```

**Effort:** Medium

---

#### 2.12 Reorganize into Modular Directory Structure

**Issue:** The project mixes installation scripts (`scripts/`), CLI plugins (`lib/`),
and configuration templates (`etc/`) in a flat structure that is hard to navigate.

**Fix:** Move to the layered structure described in ARCHITECTURE.md §4.4:
```
lib/core/      — config, logging, colors, cli dispatch
lib/runtime/   — CLI plugins (account, site, db, ssl, util)
lib/services/  — Service installation modules
```

**Effort:** High — requires updating all import/sourcing paths. Plan for v3.0.

---

#### 2.13 Add ShellCheck to All Nginx Submodules

**Issue:** The CI runs ShellCheck on `scripts/install_*.sh` and `scripts/server_*.sh` but
the pattern `scripts/nginx/*.sh` is not included.

**File:** `.github/workflows/main.yml`

**Fix:** Add `shellcheck -s bash scripts/nginx/*.sh` to the CI pipeline.

**Effort:** Low

---

#### 2.14 Fix CI References to Non-Existent .env Variables

**Issue:** The CI workflow references `NGX_PAGESPEED` and `PHP_LOADER="none"` which don't
exist in `.env.dist`, causing `sed` commands that silently match nothing.

**File:** `.github/workflows/main.yml:31,33`

**Fix:** Remove these `sed` lines or update to match actual `.env.dist` keys.

**Effort:** Low

---

#### 2.15 Add bats-core Integration Tests

**Issue:** Current tests in `shunit2/run_test.sh` require a running system and perform
actual installations. They cannot run on macOS or in constrained CI environments.

**Fix:**
- Add `tests/integration/` directory with `bats-core` tests for CLI logic.
- Use mocks for system commands (`systemctl`, `apt-get`, etc.).
- Add test matrix in CI for Debian + Ubuntu.

**Effort:** High — requires setting up bats-core in CI and writing mock-based tests.

---

### Phase 3 — Functionality Improvements (P1 — Medium)

#### 2.16 Add `lemper-cli site list` Subcommand

**Issue:** There is no way to list all configured virtual hosts without inspecting the
filesystem directly.

**Files:** `lib/lemper-manage.sh`

**Fix:** Add `site list` command that reads `/etc/nginx/sites-available/` and displays
domain names, framework, SSL status, PHP version.

**Effort:** Medium

---

#### 2.17 Add `lemper-cli site show <domain>` Subcommand

**Issue:** No way to display the full configuration for a specific vhost.

**Fix:** Add `site show` that displays the vhost config, FPM pool, app metadata, SSL
status, and linked credentials.

**Effort:** Medium

---

#### 2.18 Add Database Backup & Restore Commands

**Issue:** The README mentions "database backup tool" as a TODO, and `lemper-db.sh`
has export/import but no scheduled backup rotation.

**Fix:**
- Add `lemper-cli db backup <domain>` — creates timestamped SQL dump.
- Add `lemper-cli db restore <domain> <file>` — restores from dump.
- Add `lemper-cli db backup-schedule <domain>` — adds cron entry.

**Effort:** Medium

---

#### 2.19 Add Bun.js Runtime Integration (replaces Node.js)

**Issue:** PHP frameworks like Laravel often need a JavaScript runtime for asset building
(e.g., Vite, Mix). The project has an empty `scripts/install_nodejs.sh` stub and no
runtime integration.

**Fix:**
- Add `INSTALL_BUNJS` config option to `.env.dist`.
- Create `scripts/install_bun.sh` and `scripts/remove_bun.sh`.
- Install Bun.js via official apt repository or binary release.
- Wire into `install.sh` / `remove.sh` via `lib/core/lemper-stacks.sh`.
- **Note:** Bun.js is used instead of Node.js — it is a drop-in replacement with
  built-in npm client, test runner, and bundler, offering significantly faster
  performance for asset building pipelines.

**Effort:** Medium

---

#### 2.19B Add Valkey as Redis Drop-in Replacement Option

**Issue:** Redis is the default in-memory data store, but Valkey (a Redis-compatible
fork maintained by the Linux Foundation) offers an alternative with active development
and no licensing concerns around Redis modules.

**Fix:**
- Add `REDIS_BACKEND="redis"` config option to `.env.dist` (supports `redis` or `valkey`).
- Modify `scripts/install_redis.sh` to branch on `REDIS_BACKEND` — adds Valkey apt
  repository and installs `valkey-server` package when selected.
- Add `scripts/install_valkey.sh` source compilation support (Valkey source build).
- Create `etc/systemd/valkey-server.service` systemd unit template.
- Update `lib/core/lemper-stacks.sh` to source Valkey removal script when applicable.

**Effort:** Medium

---

#### 2.20 Add CrowdSec HIPS Integration

**Issue:** The README lists "Add CrowdSec" as a TODO. Fail2ban is the only HIPS, and it
is off by default.

**Fix:**
- Create `scripts/install_crowdsec.sh`.
- Create `scripts/remove_crowdsec.sh`.
- Add `INSTALL_CROWDSEC` config to `.env.dist`.
- Wire into `install.sh` / `remove.sh`.

**Effort:** High

---

#### 2.21 Add Let's Encrypt ACME v2 Wildcard Support via DNS-01

**Issue:** Wildcard certs are supported but require manual DNS challenge. No automatic
integration with DNS providers (Cloudflare, DigitalOcean, etc.).

**Fix:**
- Add `ACME_DNS_PROVIDER` and `ACME_DNS_API_TOKEN` to `.env.dist`.
- Use `certbot-dns-cloudflare` or similar plugin.
- Update `enable_ssl()` in `lib/lemper-manage.sh` to support DNS-01 challenge.

**Effort:** Medium

---

### Phase 4 — UI/UX Improvements (P1 — Medium)

#### 2.22 Add Progress Indicators

**Issue:** Installation output is a wall of text with no progress feedback for long
operations (source compilation, large downloads).

**Fix:**
- Add spinner/progress wrapper for long-running commands.
- Add estimated time remaining where possible.
- Use `pv` or similar for download progress bars.

**Effort:** Medium

---

#### 2.23 Improve CLI Help Output

**Issue:** `lemper-cli --help` shows only 3 commands (`create`, `database`, `manage`).
The actual CLI supports `site`, `db`, and more (aliased differently).

**Fix:** Rewrite `cmd_help()` in `bin/lemper-cli.sh` to list all available commands with
descriptions. Add subcommand-level help (`lemper-cli site --help`).

**Effort:** Medium

---

#### 2.24 Add Interactive TUI Mode (Optional)

**Issue:** The CLI is purely argument-based. No interactive dashboard for server status.

**Fix (v3.x):** Add `lemper-cli dashboard` that displays server status (services, disk,
memory, swap, recent logs) in a text-based UI using `whiptail` or `dialog`.

**Effort:** High

---

### Phase 5 — Stack Currency & EOL Cleanup (P1 — Medium)

#### 2.25 Remove PHP 5.6–7.4 Support

**Issue:** PHP 5.6–7.4 are EOL. Their config templates in `etc/php/{5.6,7.0,7.1,7.2,7.3,7.4}/`
add maintenance burden and could mislead users into installing insecure versions.

**Fix:**
- Remove `etc/php/{5.6,7.0,7.1,7.2,7.3,7.4}/` directories entirely.
- Update `lib/lemper-create.sh:77` to require PHP 8.0+.
- Update README to reflect 8.0+ only.

**Effort:** Low–Medium

---

#### 2.26 Update Default PHP Version

**Issue:** `DEFAULT_PHP_VERSION="8.2"` is outdated. PHP 8.3 is stable, 8.4 is released.

**Fix:** Update to `DEFAULT_PHP_VERSION="8.4"` in `.env.dist`.

**Effort:** Trivial

---

#### 2.27 Remove Deprecated `apt-key` and Update Repository Setup

**Issue:** Ubuntu 24.04 (Noble) drops `apt-key`. Source builds reference old OpenSSL
versions.

**Fix:**
- Replace all `apt-key` usage with `signed-by` keyring files.
- Update `NGINX_CUSTOMSSL_VERSION` to `openssl-3.3.1` or `openssl-3.4.x`.
- Update MariaDB default version from `11.1` to `11.4`.

**Effort:** Low–Medium

---

#### 2.28 Update Fail2ban Default to Enabled

**Issue:** `INSTALL_FAIL2BAN=false` by default. A security-focused tool should enable it
by default.

**Fix:** Change to `INSTALL_FAIL2BAN=true` in `.env.dist`.

**Effort:** Trivial

---

#### 2.29 Remove or Modernize NAXSI WAF

**Issue:** NAXSI is a legacy WAF with limited maintenance. The modern alternative is
ModSecurity v3 with OWASP CRS.

**Fix:**
- Add `INSTALL_MODSECURITY` config option.
- Create ModSecurity v3 + OWASP CRS installation.
- Keep NAXSI as opt-in but mark deprecated.

**Effort:** High

---

#### 2.30 Update Certbot Renewal Cron

**Issue:** The certbot renewal cron job uses `service nginx reload -s` which is incorrect
(the `-s` flag sends a signal, not a reload).

**File:** `scripts/install_certbotle.sh:109`

**Fix:** Change to `systemctl reload nginx` or add `--deploy-hook`.

**Effort:** Low

---

## 3. Phased Rollout Plan

### Phase 0: Immediate (v2.7.2 release) — Security & Bug Fixes

| # | Task | Priority | Effort | Estimated Time |
|---|---|---|---|---|
| 2.1 | Fix `fial` → `fail` typo | Critical | Trivial | < 1h |
| 2.2 | Fix `cgi.fix_pathinfo = 0` | High | Low | 2h |
| 2.3 | Remove NOPASSWD:ALL sudo | Critical | Low | 2h |
| 2.6 | Fix CI references to non-existent vars | Medium | Low | 1h |
| 2.13 | Add ShellCheck to nginx submodules in CI | Medium | Low | 1h |

**Total estimated time:** ~6 hours

---

### Phase 1: Security Hardening (v2.8.0 release)

| # | Task | Priority | Effort | Estimated Time |
|---|---|---|---|---|
| 2.4 | Suppress credential display in stdout | High | Medium | 4h |
| 2.5 | Remove email credential delivery | Medium | Low | 1h |
| 2.7 | Upgrade SSL to RSA-4096 | Medium | Low | 2h |
| 2.8 | Replace `apt-key` with keyrings | Low | Low | 3h |
| 2.30 | Fix certbot renewal cron | Medium | Low | 1h |

**Total estimated time:** ~11 hours

---

### Phase 2: Architecture (v3.0.0 release)

| # | Task | Priority | Effort | Estimated Time |
|---|---|---|---|---|
| 2.11 | Eliminate duplicated install/remove logic | High | Medium | 6h |
| 2.12 | Reorganize into modular directory structure | High | High | 20h |
| 2.9 | Add input sanitization layer | Medium | Medium | 8h |
| 2.15 | Add bats-core integration tests | Medium | High | 16h |

**Total estimated time:** ~50 hours

---

### Phase 3: Functionality (v3.1.0–v3.3.0)

| # | Task | Priority | Effort | Estimated Time |
|---|---|---|---|---|
| 2.16 | Add `site list` subcommand | Medium | Medium | 6h |
| 2.17 | Add `site show` subcommand | Medium | Medium | 6h |
| 2.18 | Add DB backup/restore commands | Medium | Medium | 8h |
| 2.19 | Add Bun.js runtime integration | Medium | Medium | 6h |
| 2.19B | Add Valkey as Redis drop-in replacement | Medium | Medium | 6h |
| 2.21 | Add ACME v2 DNS-01 wildcard support | Medium | Medium | 8h |
| 2.20 | Add CrowdSec HIPS integration | Medium | High | 16h |

**Total estimated time:** ~50 hours

---

### Phase 4: UI/UX & Stack Modernization (v3.2.0–v3.4.0)

| # | Task | Priority | Effort | Estimated Time |
|---|---|---|---|---|
| 2.22 | Add progress indicators | Medium | Medium | 6h |
| 2.23 | Improve CLI help output | Medium | Medium | 6h |
| 2.25 | Remove PHP 5.6–7.4 support | Medium | Low–Medium | 4h |
| 2.26 | Update default PHP to 8.4 | Low | Trivial | 1h |
| 2.27 | Update OpenSSL/MariaDB versions | Medium | Low–Medium | 4h |
| 2.28 | Enable Fail2ban by default | Medium | Trivial | 1h |
| 2.24 | Add interactive TUI mode | Low | High | 20h |

**Total estimated time:** ~42 hours

---

### Phase 5: Security Infrastructure (v3.0.0)

| # | Task | Priority | Effort | Estimated Time |
|---|---|---|---|---|
| 2.10 | Enable encrypted config at rest | High | High | 20h |
| 2.29 | Modernize WAF (ModSecurity v3) | Medium | High | 16h |

**Total estimated time:** ~36 hours

---

## 4. Risk Register

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Removing NOPASSWD:ALL breaks user scripts that rely on passwordless sudo | High | Medium | Document migration, add restricted sudoers config as opt-in |
| Replacing `eval` config loader breaks existing `.env` parsing | Medium | High | Maintain backward-compatible fallback, test all key types |
| Reorganizing directory structure breaks CI and user automation | High | Medium | Provide symlink compatibility layer, update CI in same PR |
| Removing PHP 5.6–7.4 breaks existing vhost configs | Medium | Medium | Auto-detect installed PHP, warn on upgrade, provide migration script |
| Encrypted config breaks non-interactive CLI use | High | Medium | Add `--password` flag and environment variable fallback |
| bats-core migration requires rewriting all tests | Medium | High | Keep shunit2 tests running alongside, migrate gradually |

---

## 5. Version Target Map

| Version | Focus Area | Key Deliverables |
|---|---|---|
| **v2.7.2** | Immediate security fixes | Fix typos, `cgi.fix_pathinfo`, NOPASSWD, CI |
| **v2.8.0** | Security hardening | Credential suppression, RSA-4096, keyring, certbot fix |
| **v2.9.0** | EOL cleanup | Remove PHP <8.0, update defaults |
| **v3.0.0** | Architecture overhaul | Modular structure, safe config loading, encrypted secrets, bats-core tests |
| **v3.1.0** | CLI enhancement | `site list`, `site show`, DB backup/restore |
| **v3.2.0** | Integration | CrowdSec, Node.js, ACME DNS-01 |
| **v3.3.0** | UI/UX | Progress indicators, improved help |
| **v3.4.0** | Advanced | ModSecurity v3, optional TUI dashboard |

---

## 6. Next Steps

1. **Review and approve this roadmap** with the project maintainer.
2. **Phase 0** can begin immediately — all fixes are low-risk and well-scoped.
3. **Phase 2** (architecture overhaul) should be planned as a major v3.0 release with
   a feature freeze on the `3.x.x` branch.
4. **Documentation** (this set: ARCHITECTURE, DEVELOPER, AGENTIC, ROADMAP) will be
   maintained alongside the codebase and updated with each release.

---

## 7. Appendix: Full Issue Index

| ID | Title | File(s) | Phase |
|---|---|---|---|
| SEC-01 | `cgi.fix_pathinfo = 1` enables path traversal | `etc/php/*/fpm/pool.d/*.conf`, `lib/lemper-create.sh` | Phase 0 |
| SEC-02 | NOPASSWD:ALL sudo for lemper user | `scripts/utils.sh:741` | Phase 0 |
| SEC-03 | Passwords passed as CLI args | `lib/lemper-create.sh`, `lib/lemper-db.sh` | Phase 1 |
| SEC-04 | `cgi.fix_pathinfo=1` in www.conf | `etc/php/*/fpm/pool.d/www.conf` | Phase 0 |
| SEC-05 | Self-signed SSL uses RSA-2048 | `nginx_ssl_cert.sh`, `lemper-selfssl.sh`, `lemper-manage.sh` | Phase 1 |
| SEC-06 | `eval`-based config loading | `scripts/utils.sh:31`, `bin/lemper-cli.sh:55` | Phase 2 |
| SEC-07 | Deprecated `apt-key` usage | `scripts/nginx/nginx_repo.sh:45`, `scripts/install_php.sh:62` | Phase 1 |
| SEC-08 | Credentials printed to stdout | `install.sh:284-288`, `lemper.sh:194-280` | Phase 1 |
| SEC-09 | `fial` typo in error paths | `lib/lemper-create.sh:957`, `lib/lemper-db.sh:593` | Phase 0 |
| SEC-10 | No input sanitization for domain/IP | `lib/lemper-selfssl.sh`, `lib/lemper-create.sh` | Phase 2 |
| SEC-11 | Plaintext credential storage | `scripts/utils.sh:846-851` | Phase 5 |
| SEC-12 | Open_basedir temp dirs under user home | `lib/lemper-create.sh:615-616` | Phase 1 |
| FUNC-01 | Node.js installer not in main flow | `scripts/install_nodejs.sh` (not called) | Phase 3 |
| FUNC-02 | No `site list` command | CLI missing | Phase 3 |
| FUNC-03 | No `site show` command | CLI missing | Phase 3 |
| FUNC-04 | No DB backup/restore commands | `lib/lemper-db.sh` | Phase 3 |
| FUNC-05 | Certbot renewal cron bug | `scripts/install_certbotle.sh:109` | Phase 1 |
| UX-01 | Poor CLI help text | `bin/lemper-cli.sh:158` | Phase 4 |
| UX-02 | No progress indicators | All install scripts | Phase 4 |
| UX-03 | No TUI/dashboard mode | CLI | Phase 4 |
| ARCH-01 | Duplicated install/remove logic | `install.sh` vs `lemper.sh` | Phase 2 |
| ARCH-02 | Flat directory structure | Entire codebase | Phase 2 |
| ARCH-03 | No bats-core integration tests | `shunit2/run_test.sh` | Phase 2 |
| ARCH-04 | CI references non-existent vars | `.github/workflows/main.yml` | Phase 0 |
| ARCH-05 | ShellCheck not run on nginx submodules | `.github/workflows/main.yml` | Phase 0 |
| STACK-01 | PHP 5.6–7.4 still supported (EOL) | `etc/php/{5.6,...,7.4}/` | Phase 4 |
| STACK-02 | Default PHP version outdated (8.2) | `.env.dist` | Phase 4 |
| STACK-03 | MariaDB default version old (11.1) | `.env.dist` | Phase 4 |
| STACK-04 | Old OpenSSL reference in config | `.env.dist` | Phase 4 |
| STACK-05 | Fail2ban off by default | `.env.dist` | Phase 4 |
| STACK-06 | NAXSI WAF is legacy | `etc/nginx/includes/*.rules` | Phase 5 |
| STACK-07 | No CrowdSec integration | TODO in README | Phase 3 |
| DOC-01 | No architecture documentation | Project root | ✅ Complete |
| DOC-02 | No developer guide | Project root | ✅ Complete |
| DOC-03 | No agentic guide | Project root | ✅ Complete |
| DOC-04 | No roadmap document | Project root | ✅ Complete |
