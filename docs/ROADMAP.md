# LEMPer — Roadmap &amp; Improvement Plan

> **Latest published version:** 3.6.0
> **Last Updated:** 2026-11-24
> **Verified candidate:** 9b3963e on the pushed `release/v4.0.0` branch
> **Status:** v4.0 foundations, mail hosting and PHP/Laravel enhancements are
> implemented but unreleased. A4 decomposition is delivered; deferred plans and release
> production validation and publication remain; candidate CI passed 24/24 jobs.
> See [ROADMAP_AUDIT.md](ROADMAP_AUDIT.md).
>
> v3.6.0 ships the TUI log viewer and site wizard, ModSecurity tuning, opt-in
> HTTP/3, per-site CORS, resource profiles, the MyGuard nginx archive, PHP 8.1
> removed from the default install, EOL vhost migration, Adminer 6.2.0, config
> backup, the CrowdSec installer, and the FTP fixes.
>
> This document presents the audit findings and improvement recommendations for the LEMPer
> codebase. It is organized by priority area (Security, Architecture, Functionality,
> UX, Stack Currency) and includes a phased rollout plan.

---

## Current implementation and remaining work

The [current delivery status](ROADMAP_AUDIT.md#current-delivery-and-release-status)
reconciles all 48 numbered task IDs, Architecture §4 and README/developer plans.
All accepted numbered capabilities are implemented or explicitly superseded. The
[A4 implementation](ROADMAP_AUDIT.md#a4-module-decomposition-follow-through--2026-11-23)
completes the remaining 2.12/2.37 extraction; release gates stay separate.

| Priority area | Implementation |
|---|---|
| Credentials | Removed default secret recaps/log entries, protected credential files and encryption/hash input; explicit site metadata views now redact secrets |
| Destructive paths | Canonical path and ownership checks before site configuration/data deletion |
| Accounts | Hosting/admin roles and explicit validated, backed-up legacy privilege migration |
| ACME | Shared Cloudflare/DigitalOcean DNS-01 credentials for issuance and renewal |
| Configuration | Typed schema, cross-option install preflight, strict config check, compatible legacy runtime loading |
| SSH | Key-only default, ed25519 guidance, root-managed keys, validation and rollback through reload |
| Shared code | Core modules and shared parsing across public paths; legacy adapters retain isolated parsing |
| Service/site CLI | Per-service lifecycle commands, PHP branch control, new site remove verb |
| Bootstrap/releases | Pinned CLI-only installation, immutable version directories, checksums, reproducible release workflow |
| CI audits | Provisioned-host Lynis report and package/source-pin dependency review |
| Mail/PHP/apps | Multi-domain incoming/outgoing mail, account/alias management, persistent PHP default selection and Laravel application mounts |

P1 follow-through is implemented: protected DB operations/scheduling, redacted
site diagnostics with working JSON, and scoped PHP/MariaDB signing keys. See
[DATABASE.md](DATABASE.md) and the audit for compatibility and validation limits.

P2 now delivers SQL retention, Restic application/mail backups and staged restore,
native nftables with SSH/UFW recovery, shared parsing across public paths, and
Monit monitoring/alert configuration. Runtime extraction covers account, database,
SSL, TUI and vhost creation handlers while retaining installed wrappers. See the
[current audit](ROADMAP_AUDIT.md) for source evidence and validation limits.

P3 now delivers hosting disk/inode plans and guarded quota lifecycle (issue #39),
EditorConfig/opt-in shfmt checks, published scoped function-entry coverage, and
interactive ETA/optional pv restoration progress. See [HOSTING.md](HOSTING.md).
Quota enforcement currently supports explicitly enabled ext4 user quotas; broader
resource limits and other filesystem backends remain optional enhancements.

Prioritized follow-through now delivers shared whole-value/semantic input
validation (2.9), curated repository migration and maintained custom TLS source
selection (2.8/2.27), complete diagnostic views (2.17), and ownership-resolved DB
domain shortcuts (2.18). Diagnostics, certificate issuance, repository setup and
Bun binary installation occupy service/runtime modules. A4 now also extracts
older management/application/installer bodies, completing the accepted 2.12/2.37
architecture scope. See [the implementation audit](ROADMAP_AUDIT.md#a4-module-decomposition-follow-through--2026-11-23)
for source evidence, checks and limits. Release validation/publication gates remain.

Current delivery status:

1. **P1 — implemented:** Protected MariaDB backup-account provisioning,
   literal credential handling, canonical keys, existing-account repair and
   legacy inline credential migration (A1).
2. **P1 — implemented:** Shared Linux dependencies, root test fixtures and
   isolated state across CI/release/coverage/Podman entry points (A2).
3. **P2 — implemented:** Shared CLI/TUI application capabilities reject unavailable
   skeleton installation before changes and verify project files before success.
   Mautic/Roundcube now resolve and deploy the latest stable complete releases; Sendy retains manual
   PHP vhosts (A3). See [APPLICATIONS.md](APPLICATIONS.md).
   Additional delivery includes SnappyMail, Nextcloud, MyBB, phpList, OJS and
   Slim automatic deployment, plus XenForo licensed manual vhosts (issues #66,
   #35 and #149). Application/database configuration remains upstream-managed.
4. **P2 — implemented:** Site rendering, feature management, update drivers,
   component lifecycles and remaining utility plugins use function-only modules.
   Public wrappers and installed exports remain compatible (A4; 2.12/2.37).

See [remaining work and evidence](ROADMAP_AUDIT.md#current-delivery-and-release-status).
Protected SQL backups, repository migration, diagnostic parity and domain DB
shortcuts remain implemented. The backup-account finding in the older installer
now has a dedicated service driver; the initial documentation audit is preserved
with implementation follow-through in the audit report.

Authenticated encryption remains an explicit format/provider decision; the
delivered encryption uses AES-256-CBC/PBKDF2. The maintained default custom TLS
source has been selected and tested. Full evidence,
dependencies and task-by-task qualifications are in [ROADMAP_AUDIT.md](ROADMAP_AUDIT.md).

Previously recorded validation includes 358 Bats tests, 13 archive-bootstrap UAT
cases, 55 mail checks and 11 PHP/Laravel checks on their respective baselines;
see [RELEASE_V4.md](RELEASE_V4.md), [MAIL.md](MAIL.md) and
[PHP_RUNTIME_LARAVEL.md](PHP_RUNTIME_LARAVEL.md). The original documentation audit
could not reach Podman. Subsequent P1 work
used the restarted machine; 30 real Ubuntu 24.04 ARM64 checks passed. Debian's
live PHP package validation encountered an upstream index checksum mismatch.
Latest recorded implementation validation includes **437 passing Bats tests**,
47 Ubuntu 24.04 ARM64 checks and 37 Debian 12 ARM64 checks; these are historical
results before 9b7511b was committed, not a full rerun in this audit. The current
audit reproduced the DB fixture environment difference: 18/18 pass as root,
12/18 as an ordinary user. P1 now fixes that execution contract: the shared
runner passed **456 tests on Ubuntu 24.04 and Debian 12 ARM64**; scoped function
coverage is **61/68 (89.7%)**, and native provisioning UAT passed **22 checks
on each distro**. A3's final Ubuntu 24.04 ARM64 run passed **465 Bats tests** and
**29 native application-capability checks**, including CodeIgniter's HTTP welcome
page. Other automatic application installers and Debian A3 UAT were not rerun.
The 2026-11-23 Mautic/Roundcube extension passed **473 Bats tests** and **57 native
acceptance checks** on Ubuntu 24.04 ARM64, including complete release packages,
upstream setup pages/assets, access restrictions and repeat preservation.
A4's final Ubuntu 24.04 ARM64 run passed **518 Bats tests**, including import and
compatibility contracts plus syntax/sourced ShellCheck. Fresh native Ubuntu 26.04
ARM64 acceptance passed **13/13 minimal bootstrap/install/HTTP/SSH/repeat/remove
checks** against an uncommitted source snapshot; broader platforms, optional
services and application deployments were not rerun for A4. See
[MODULE_DECOMPOSITION.md](MODULE_DECOMPOSITION.md).
The current `9b3963e` candidate passed
[24/24 GitHub jobs](https://github.com/joglomedia/LEMPer/actions/runs/45318207064),
including **534 Bats tests**, scoped function-entry coverage **86/94 (91.5%)**,
and **13/13 exact-archive checks on each of Ubuntu 24.04/26.04 and Debian 12 AMD64**.
All four assets rebuilt identically twice and their checksums verify. See
[current release evidence](RELEASE_V4.md#verified-candidate-9b3963e) and the
[production UAT checklist](PRODUCTION_UAT.md). Earlier results in this paragraph
and below are historical evidence for their named snapshots.
The fixed `d21b293` candidate passed **524 Bats tests** with scoped function-entry
coverage **86/94 (91.5%)**, and **13/13 exact-archive acceptance checks on each of
Debian 12 and Ubuntu 26.04 ARM64**. Tagged publication now requires the shared
archive acceptance gate; source and final verification notes are kept separate
from authorization to push/tag/publish.
At the earlier audit, GitHub returned no runs for the full 9b7511b SHA.
Current candidate CI and native AMD64 coverage are now verified. v4.0.0 is still
unpublished; public ACME, external integrations and selected legacy transitions
need their designated production UAT environments.

---

## 1. Historical Audit Summary

The original audit covered the areas below. Its findings, file/line references,
effort estimates and version targets are historical; they do not describe the
current source. Sections 2–3 retain the original task definitions and delivery
history. Use the current audit above for implementation status.


| Area           | Files Audited                                                         | Issues Found                             |
| -------------- | --------------------------------------------------------------------- | ---------------------------------------- |
| Security       | `utils.sh`, `lib/lemper-*`, `install.sh`, `lemper.sh`, `etc/` configs | 12 critical/medium issues                |
| Architecture   | All `.sh` files, `.env.dist`, CI config                               | Monolithic, no modularity, weak tests    |
| Functionality  | All install scripts, CLI plugins, config templates                    | 9 bugs, 3 typos, outdated defaults       |
| UI/UX          | `bin/lemper-cli.sh`, `lib/lemper-create.sh`, `lib/lemper-manage.sh`   | Poor CLI UX, no progress feedback        |
| Stack Currency | `.env.dist`, PHP configs, Nginx modules                               | PHP 5.6–7.4 supported (EOL), old MariaDB |


---

## 2. Prioritized Recommendations

### Phase 0 — Immediate Security Fixes (P0 — Critical)

The original plan treated these as blocking issues. Their current implementation
status and any remaining follow-through are recorded in ROADMAP_AUDIT.md.

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

**Issue:** Both `scripts/utils.sh:31` and `bin/lemper-cli.sh:55` use `source <(grep ... | sed ...)` which effectively `eval`s the contents of `.env`/`lemper.conf`. If any value
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

#### 2.8 Replace `apt-key` with Keyring Files (Security — Low) — Implemented for curated sources

**Current status:** Scoped signing keys and backed-up migration are implemented for
PHP and MariaDB in audit R3. PGDG/Redis/MongoDB and remaining PPAs now use the
shared backed-up migration contract. Ambiguous MongoDB upgrades and unsafe
source options fail preflight; unowned/shared keyrings remain for explicit review.

**Historical issue:** `apt-key` is deprecated and stores all repository keys in a single keyring,
creating trust-confusion vulnerabilities.

**File:** `scripts/nginx/nginx_repo.sh:45`, `scripts/install_php.sh:62`

**Original proposal:** Replace:

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

#### 2.9 Add Input Sanitization Layer (Security — Medium) — Reviewed runtime/backup boundaries implemented

**Current status:** Site/account/SSH validators and the legacy DB validation/
execution follow-through are implemented. Shared whole-value predicates now reject
multiline/control input, and semantic IPv6 checks cover compression and IPv4 tails.
Legacy text-returning wrappers delegate to the same core; site/SSL input validation
happens before mutation. The current audit additionally identifies configured
backup-account names/passwords interpolated into SQL and a shell program in
`scripts/install_mariadb.sh`; A1 now replaces this with a protected service driver.
Shared dotenv/schema parsing preserves one matching outer quote pair. See the
audit for verification and limitations.

**Historical issue:** Domain names are passed directly to `sed`, `openssl`, and file paths without
sanitization. While `validate_fqdn()` is called in some paths, other paths (e.g.,
self-signed SSL generation) do not validate.

**Files:** `lib/lemper-selfssl.sh`, `lib/lemper-create.sh`, `lib/lemper-manage.sh`

**Original proposal:**

- Validate all user inputs (domain names, IP addresses, usernames) before use.
- Use `printf '%q'` or manual escaping when interpolating into `sed`/`openssl` commands.
- Add a `sanitize_sed_replacement()` helper function.

**Effort:** Medium

---

#### 2.10 Enable Encrypted Config at Rest (Security — High)  ✅**COMPLETE**

**Issue:** `/etc/lemper/lemper.conf` stores all credentials in plaintext. A
`secure_config()` function (AES-256-CBC) exists but is commented out.

**Files:** `scripts/utils.sh:854-861`, `lib/lemper-encrypt.sh`, `bin/lemper-cli.sh`

**Fix:** ✅ Implemented

- Created `lib/lemper-encrypt.sh` with `encrypt_config()`, `decrypt_config()`,
`is_config_encrypted()`, `resolve_config_password()`, `secure_shred()`
- Uses AES-256-CBC/PBKDF2 (with a legacy KDF fallback where needed)
- `--password`/`-P` CLI flag added to `bin/lemper-cli.sh`; falls back to
`LEMPER_PASSWORD` env var or `/etc/lemper/.config_key` key file
  - Added `ENCRYPT_CONFIG_AT_REST` and `LEMPER_CONFIG_PASSWORD` to `.env.dist`
- `utils.sh` `save_config()` now decrypts → writes → re-encrypts when
`ENCRYPT_CONFIG_AT_REST=true`
- Backward compatible: plaintext configs load as before

**Effort:** High — changes to both install and CLI startup paths.

---

### Phase 2 — Architecture &amp; Code Quality (P1 — High)

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

#### 2.12 Reorganize into Modular Directory Structure — Implemented (unreleased)

**Current status:** Core/runtime/service/compatibility layers and installed
exports are implemented. A4 extracts ordinary site rendering, framework setup,
feature management, updater internals, component lifecycles and utility plugins.
Retained public wrappers contain initialization/compatibility dispatch. This is
the same completed workstream as 2.37; see [MODULE_DECOMPOSITION.md](MODULE_DECOMPOSITION.md).

**Issue:** The project mixes installation scripts (`scripts/`), CLI plugins (`lib/`),
and configuration templates (`etc/`) in a flat structure that is hard to navigate.

**Fix:** Move to the layered structure described in ARCHITECTURE.md §4.4:

```
lib/core/      — config, logging, colors, cli dispatch
lib/runtime/   — CLI plugins (account, site, db, ssl, util)
lib/services/  — Service installation modules
```

**Effort:** Delivered incrementally for v4, with retained imports and exports.

---

#### 2.13 Add ShellCheck to All Nginx Submodules

**Issue:** The CI runs ShellCheck on `scripts/install_*.sh` and `scripts/server_*.sh` but
the pattern `scripts/nginx/*.sh` is not included.

**File:** `.github/workflows/main.yml`

**Fix:** Add `shellcheck -s bash scripts/nginx/*.sh` to the CI pipeline.

**Effort:** Low

---

#### 2.14 Fix CI References to Non-Existent .env Variables  ✅**COMPLETE**

**Issue:** The CI workflow references `NGX_PAGESPEED` and `PHP_LOADER="none"` which don't
exist in `.env.dist`, causing `sed` commands that silently match nothing.

**Resolution:** CI now toggles `INSTALL_PHP_LOADER=true`, which exists in `.env.dist`.
The obsolete `NGX_PAGESPEED` line was removed together with the deprecated PageSpeed
module (issue #178). No PageSpeed code, module, or configuration remains.

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

#### 2.16 Add `lemperctl site list` Subcommand  ✅**COMPLETE**

**Issue:** There is no way to list all configured virtual hosts without inspecting the
filesystem directly.

**Files:** `lib/lemper-manage.sh`

**Fix:** Add `site list` command that reads `/etc/nginx/sites-available/` and displays
domain names, framework, SSL status, PHP version.

**Effort:** Medium

---

#### 2.17 Add `lemperctl site show <domain>` Subcommand — Implemented

**Current status:** Metadata is redacted in text and JSON; `--json` is registered
and implies `--all`. Malformed metadata fails without exposing values. See audit R2.
Text and JSON share Nginx/FPM configuration, certificate details and modern
site ownership/nested-app metadata. Credential-bearing fields are redacted,
Python import-path isolation is enabled, and retained metadata remains readable
for recovery. Plaintext linked credentials are intentionally excluded.

**Historical issue:** No way to display the full configuration for a specific vhost.

**Original proposal:** Add `site show` that displays the vhost config, FPM pool, app metadata, SSL
status, and linked credentials.

**Effort:** Medium

---

#### 2.18 Add Database Backup &amp; Restore Commands — Implemented

**Current status:** Timestamped SQL dumps, restore and cron scheduling exist.
Protected execution is delivered in R1; verified SQL retention is delivered in R4.
The engine accepts `--dbname`/`--dbfile` and the positional domain forms below.
Domain lookup requires recorded ownership and a database mapping; mismatches
with legacy metadata or conflicting explicit DB flags fail before operations.

**Historical issue:** The README mentions "database backup tool" as a TODO, and `lemper-db.sh`
has export/import but no scheduled backup rotation.

**Original proposal:**

- Add `lemperctl db backup <domain>` — creates timestamped SQL dump.
- Add `lemperctl db restore <domain> <file>` — restores from dump.
- Add `lemperctl db backup-schedule <domain>` — adds cron entry.

**Effort:** Medium

---

#### 2.19 Add Bun.js Runtime Integration (replaces Node.js)  ✅**COMPLETE**

**Issue:** PHP frameworks like Laravel often need a JavaScript runtime for asset building
(e.g., Vite, Mix). Node.js is not shipped; Bun.js is the runtime.

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

#### 2.19B Add Valkey as Redis Drop-in Replacement Option  ✅**COMPLETE**

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

#### 2.20 Add CrowdSec HIPS Integration  ✅**COMPLETE**

**Issue:** The README lists "Add CrowdSec" as a TODO. Fail2ban is the only HIPS, and it
is off by default.

**Fix:**

- Create `scripts/install_crowdsec.sh`.
- Create `scripts/remove_crowdsec.sh`.
- Add `INSTALL_CROWDSEC` config to `.env.dist`.
- Wire into `install.sh` / `remove.sh`.

**Effort:** High

---

#### 2.21 Add Let's Encrypt ACME v2 Wildcard Support via DNS-01  ✅**COMPLETE**

**Issue:** Wildcard certs are supported but require manual DNS challenge. No automatic
integration with DNS providers (Cloudflare, DigitalOcean, etc.).

**Fix:**

- Add `ACME_DNS_PROVIDER` and `ACME_DNS_API_TOKEN` to `.env.dist`.
- Use `certbot-dns-cloudflare` or similar plugin.
- Update `enable_ssl()` in `lib/lemper-manage.sh` to support DNS-01 challenge.

**Effort:** Medium

---

### Phase 4 — UI/UX Improvements (P1 — Medium)

#### 2.22 Add Progress Indicators  ✅**COMPLETE**

**Issue:** Installation output is a wall of text with no progress feedback for long
operations (source compilation, large downloads).

**Fix:**

- Add spinner/progress wrapper for long-running commands.
- Add estimated time remaining where possible.
- Use `pv` or similar for download progress bars.

**Effort:** Medium

---

#### 2.23 Improve CLI Help Output  ✅**COMPLETE**

**Issue:** `lemperctl --help` shows only 3 commands (`create`, `database`, `manage`).
The actual CLI supports `site`, `db`, and more (aliased differently).

**Fix:** Rewrite `cmd_help()` in `bin/lemper-cli.sh` to list all available commands with
descriptions. Add subcommand-level help (`lemperctl site --help`).

**Effort:** Medium

---

#### 2.24 Add Interactive TUI Mode (Optional)  ✅**COMPLETE**

**Issue:** The CLI is purely argument-based. No interactive dashboard for server status.

**Fix (v3.x):** Add `lemperctl dashboard` that displays server status (services, disk,
memory, swap, recent logs) in a text-based UI using `whiptail` or `dialog`.

**Effort:** High

---

### Phase 5 — Stack Currency &amp; EOL Cleanup (P1 — Medium)

#### 2.25 Remove PHP 5.6–7.4 Support  ✅**COMPLETE**

**Issue:** PHP 5.6–7.4 are EOL. Their config templates in `etc/php/{5.6,7.0,7.1,7.2,7.3,7.4}/`
add maintenance burden and could mislead users into installing insecure versions.

**Fix:**

- Remove `etc/php/{5.6,7.0,7.1,7.2,7.3,7.4}/` directories entirely.
- Update `lib/lemper-create.sh:77` to require PHP 8.0+.
- Update README to reflect 8.0+ only.

**Effort:** Low–Medium

---

#### 2.26 Update Default PHP Version  ✅**COMPLETE**

**Issue:** `DEFAULT_PHP_VERSION="8.2"` is outdated. PHP 8.3 is stable, 8.4 is released.

**Fix:** Update to `DEFAULT_PHP_VERSION="8.4"` in `.env.dist`.

**Effort:** Trivial

---

#### 2.27 Remove Deprecated `apt-key` and Update Repository Setup — Implemented selected TLS/repository policy

**Current status:** MariaDB 11.4 and several scoped keyrings are implemented.
Remaining curated repositories now share backed-up scoping. The builder honors
`NGINX_WITH_CUSTOMSSL`; the maintained opt-in default is OpenSSL 3.5.9 LTS, with
verified release SHA-256 downloads and Nginx-managed source integration. HTTP/3
module selection remains opt-in. Older explicit library selections keep their
compatibility routes with validated source tags.

**Historical issue:** Ubuntu 24.04 (Noble) drops `apt-key`. Source builds reference old OpenSSL
versions.

**Original proposal:**

- Replace all `apt-key` usage with `signed-by` keyring files.
- Update `NGINX_CUSTOMSSL_VERSION` to `openssl-3.3.1` or `openssl-3.4.x`.
- Update MariaDB default version from `11.1` to `11.4`.

**Effort:** Low–Medium

---

#### 2.28 Update Fail2ban Default to Enabled  ✅**COMPLETE**

**Issue:** `INSTALL_FAIL2BAN=false` by default. A security-focused tool should enable it
by default.

**Fix:** Change to `INSTALL_FAIL2BAN=true` in `.env.dist`.

**Effort:** Trivial

---

#### 2.29 Remove or Modernize NAXSI WAF  ✅**COMPLETE**

**Issue:** NAXSI is a legacy WAF with limited maintenance. The modern alternative is
ModSecurity v3 with OWASP CRS.

**Fix:**

- Add `INSTALL_MODSECURITY` config option.
- Create ModSecurity v3 + OWASP CRS installation.
- Keep NAXSI as opt-in but mark deprecated.

**Effort:** High

---

#### 2.30 Update Certbot Renewal Cron  ✅**COMPLETE**

**Issue:** The certbot renewal cron job uses `service nginx reload -s` which is incorrect
(the `-s` flag sends a signal, not a reload).

**File:** `scripts/install_certbotle.sh:185`

**Fix:** ✅ Already fixed in Phase 1 (commit `eec99d7`). Cron now uses:
`--deploy-hook "systemctl reload nginx"`

**Effort:** Low

---

## 3. Phased Rollout Plan

### Phase 0: Immediate (v2.7.2 release) — Security &amp; Bug Fixes


| #    | Task                                     | Priority | Effort  | Estimated Time |
| ---- | ---------------------------------------- | -------- | ------- | -------------- |
| 2.1  | Fix `fial` → `fail` typo                 | Critical | Trivial | &lt; 1h        |
| 2.2  | Fix `cgi.fix_pathinfo = 0`               | High     | Low     | 2h             |
| 2.3  | Remove NOPASSWD:ALL sudo                 | Critical | Low     | 2h             |
| 2.14 | Fix CI references to non-existent vars   | Medium   | Low     | 1h             |
| 2.13 | Add ShellCheck to nginx submodules in CI | Medium   | Low     | 1h             |


**Total estimated time:** ~6 hours

---

### Phase 1: Security Hardening (v2.8.0 release)


| #    | Task                                  | Priority | Effort | Estimated Time |
| ---- | ------------------------------------- | -------- | ------ | -------------- |
| 2.4  | Suppress credential display in stdout | High     | Medium | 4h             |
| 2.5  | Remove email credential delivery      | Medium   | Low    | 1h             |
| 2.7  | Upgrade SSL to RSA-4096               | Medium   | Low    | 2h             |
| 2.8  | Replace `apt-key` with keyrings       | Low      | Low    | 3h             |
| 2.30 | Fix certbot renewal cron              | Medium   | Low    | 1h             |


**Total estimated time:** ~11 hours

---

### Phase 2: Architecture (v3.0.0 release)


| #    | Task                                        | Priority | Effort | Estimated Time |
| ---- | ------------------------------------------- | -------- | ------ | -------------- |
| 2.11 | Eliminate duplicated install/remove logic   | High     | Medium | 6h             |
| 2.12 | Reorganize into modular directory structure | High     | High   | 20h            |
| 2.9  | Add input sanitization layer                | Medium   | Medium | 8h             |
| 2.15 | Add bats-core integration tests             | Medium   | High   | 16h            |


**Total estimated time:** ~50 hours

---

### Phase 3: Functionality (v3.1.0–v3.3.0)


| #     | Task                                    | Priority | Effort | Estimated Time | Status   |
| ----- | --------------------------------------- | -------- | ------ | -------------- | -------- |
| 2.16  | Add `site list` subcommand              | Medium   | Medium | 6h             | ✅ v3.1.0 |
| 2.17  | Add `site show` subcommand              | Medium   | Medium | 6h             | Delivered: shared diagnostic views and redaction |
| 2.18  | Add DB backup/restore commands          | Medium   | Medium | 8h             | Delivered: protected engine and owned domain shortcuts |
| 2.19  | Add Bun.js runtime integration          | Medium   | Medium | 6h             | ✅ v3.1.0 |
| 2.19B | Add Valkey as Redis drop-in replacement | Medium   | Medium | 6h             | ✅ v3.1.0 |
| 2.21  | Add ACME v2 DNS-01 wildcard support     | Medium   | Medium | 8h             | ✅ v3.2.0 |
| 2.20  | Add CrowdSec HIPS integration           | Medium   | High   | 16h            | ✅ v3.2.0 |


**Total estimated time:** ~50 hours

---

### Phase 4: UI/UX &amp; Stack Modernization (v3.2.0–v3.4.0)


| #    | Task                            | Priority | Effort     | Estimated Time | Status   |
| ---- | ------------------------------- | -------- | ---------- | -------------- | -------- |
| 2.22 | Add progress indicators         | Medium   | Medium     | 6h             | ✅ v3.2.0 |
| 2.23 | Improve CLI help output         | Medium   | Medium     | 6h             | ✅ v3.2.0 |
| 2.25 | Remove PHP 5.6–7.4 support      | Medium   | Low–Medium | 4h             | ✅ v3.2.0 |
| 2.26 | Update default PHP to 8.4       | Low      | Trivial    | 1h             | ✅ v3.2.0 |
| 2.27 | Update OpenSSL/MariaDB versions | Medium   | Low–Medium | 4h             | Delivered: scoped migration and OpenSSL 3.5.9 LTS |
| 2.28 | Enable Fail2ban by default      | Medium   | Trivial    | 1h             | ✅ v3.2.0 |
| 2.24 | Add interactive TUI mode        | Low      | High       | 20h            | ✅ v3.3.0 |


**Total estimated time:** ~42 hours (completed in this phase)

---

### Phase 5: Security Infrastructure (v3.4.0) — ✅ Complete


| #    | Task                                          | Priority | Effort  | Estimated Time | Status   |
| ---- | --------------------------------------------- | -------- | ------- | -------------- | -------- |
| 2.10 | Enable encrypted config at rest (AES-256-CBC) | High     | High    | 20h            | ✅ v3.4.0 |
| 2.29 | Modernize WAF (ModSecurity v3 + OWASP CRS)    | Medium   | High    | 16h            | ✅ v3.4.0 |
| 2.30 | Fix certbot renewal cron                      | Low      | Trivial | 1h             | ✅ v2.8.0 |


**Total estimated time:** ~37 hours (completed across Phases 1 + 5)

---

### Phase 6: Architecture Debt Resolution &amp; Portability (v3.5.0)  ✅ Complete

**Focus:** Address remaining security vulnerabilities, resolve portability issues,
complete CI/CD hardening, and add mock-based tests. **All Phase 6 tasks implemented.**

#### 2.31 Remove NOPASSWD:ALL for `lemper` User (Security — Critical)  ✅**COMPLETE**

**Issue:** The `lemper` system account had unrestricted sudo access.

**Fix:** ✅ Implemented
- `scripts/utils.sh` `create_account()`: Replaced `usermod -aG sudo` with restricted
  sudoers file at `/etc/sudoers.d/90-lemper` (mode 0440) allowing only specific
  `systemctl` operations for nginx, php, redis, mariadb, mysql
- `lib/lemper-adduser.sh`: Same restricted sudoers approach

**Effort:** ✅ Done

---

#### 2.32 Suppress Credential Display (Security — High)  ✅**COMPLETE**

**Issue:** Installation recap displayed all passwords to stdout.

**Fix:** ✅ Implemented — Removed 560+ lines of dead `CREDENTIALS` variable building
in `lib/core/lemper-stacks.sh`. Replaced with safe summary (hostname, IP, port,
service URLs only — no passwords).

**Effort:** ✅ Done

---

#### 2.33 Replace `eval`-Based Config Loading with Safe Parser (Security — High)  ✅**COMPLETE**

**Issue:** Config loading used `eval`-based `source <(grep ... | sed ...)`.

**Fix:** ✅ Implemented
- `scripts/utils.sh`: Added `safe_parse_dotenv()` — IFS-based parser with key validation
- `lib/lemper-encrypt.sh` `load_config()`: Now uses `safe_parse_dotenv()`
- `bin/lemper-cli.sh`: Config loading replaced with safe IFS='=' parser
- All `unset $(grep ... | xargs)` replaced with safe loop

**Effort:** ✅ Done

---

#### 2.34 Remove Stale EOL PHP Config Templates (Stack Currency — Low)  ✅**COMPLETE**

**Issue:** `etc/php/{5.6,7.0,7.1,7.2,7.3,7.4,8.0}/` directories remained.

**Fix:** ✅ Implemented — Deleted the PHP 5.6–8.0 template directories.
The installer floor is now 8.2. Shipped templates are 8.2–8.5. `update php --migrate-to=VERSION` moves vhosts that still use an EOL PHP.

**Effort:** ✅ Done

---

#### 2.35 Make `sed -i` Portable (Portability — Medium)  ✅**COMPLETE**

**Issue:** 210 `sed -i` usages across 20 files (GNU syntax, breaks on macOS).

**Fix:** ✅ Implemented — Added `sed_inplace()` wrapper in `scripts/utils.sh`
(autodetects Darwin vs Linux, uses correct `sed -i` syntax).

**Effort:** ✅ Done

---

#### 2.36 Replace `grep -oP` (PCRE) with ERE (Portability — Low)  ✅**COMPLETE**

**Issue:** `grep -oP` not available on macOS.

**Fix:** ✅ Already resolved during Phase 2. No `grep -oP` or `grep -P` in codebase.

**Effort:** ✅ Done

---

#### 2.37 Modular Directory Restructuring (Architecture — High) — **Implemented (unreleased)**

**Status:** **Implemented.** A4 completes the service/runtime extraction described
in 2.12. Named component-driver contracts connect standalone scripts, full-stack
recipes and CLI adapters. Import-safety and compatibility behavior have regression
coverage; legacy configuration and execution helpers remain behind their process
boundaries. Further API/state cleanup is optional refinement, separate from this
accepted decomposition scope and final release validation.

**Effort:** Delivered for v4; see [Architecture §4.4](ARCHITECTURE.md#44-module-decomposition-implemented-for-v4-tasks-212237).

---

#### 2.38 Add Mock-Based Unit Tests (Testability — High)  ✅ **COMPLETE**

**Issue:** Tests are structural (grep-based) only.

**Fix:** ✅ Implemented — Added `tests/unit/` with PATH-shadowing mocks. The
verified 9b3963e candidate passed 534 Bats tests; the original 12-case
addition included:

- `validators.bats` — `validate_fqdn()`, `validate_ipv4()`, `sanitize_sed_*`,
  and `validate_nginx_config()` against a mocked nginx binary.
- `php_temp_dirs.bats` — `create_php_temp_dirs()` with mocked `mkdir`/`chmod`/`chown`.
- `db_backup_restore.bats` — extracted `db_backup_database()` /
  `db_restore_database()` driven by mocked `mariadb` / `mariadb-dump`.
- CI and `test_podman.sh` now run `bats tests/ tests/unit/`.

**Execution follow-through:** A2 in the current audit records a reproduced
root/unprivileged fixture mismatch and incomplete Podman dependency preparation.
P1 now delivers shared root Linux setup/runner helpers and per-test locks.

**Effort:** ✅ Done

---

#### 2.39 Add Debian 12 to CI Matrix (CI/CD — Low)  ✅**COMPLETE**

**Fix:** ✅ Implemented — Added `debian-12` job + ShellCheck v0.11.0 in CI.

**Effort:** ✅ Done

---

#### 2.40 Add Bashate Linting to CI (Security — Medium)  ✅**COMPLETE**

**Fix:** ✅ Implemented — Install `bashate` via pip3, added linting step.

**Effort:** ✅ Done

---

### Phase 7: Advanced UX &amp; Automation (v3.6.0) — ✅ Complete

**Focus:** TUI enhancements, ModSecurity auto-tuning, advanced automation.


| #     | Task                              | Priority | Effort     | Estimated Time | Status  |
| ----- | --------------------------------- | -------- | ---------- | -------------- | ------- |
| 2.41  | TUI real-time log streaming       | Low      | High       | 24h            | ✅ Complete |
| 2.42  | Interactive site creation wizard  | Low      | Medium     | 8h             | ✅ Complete |
| 2.43  | ModSecurity auto-tuning           | Medium   | High       | 16h            | ✅ Complete |
| 2.44  | systemd-resolved ACME integration | Medium   | Medium     | 6h             | ✅ Complete |

**Implementation notes:**

- **2.41** — `lib/lemper-tui.sh`: Live Logs menu streams Nginx access/error,
  PHP-FPM, MariaDB, auth, and Fail2ban logs with a one-second refresh loop;
  any key returns to the TUI.
- **2.42** — `lib/lemper-tui.sh`: guided wizard validates the domain, framework,
  PHP version, system user, and web root, then invokes `lemper-site create` with
  SSL, wildcard, FastCGI cache, Fail2ban, and app-install options.
  The runtime wizard and CLI now share an application capability catalog.
  Mautic/Roundcube now offer complete-package installation; Sendy remains a
  manual vhost choice. A3's capability gap is closed; unattended database,
  administrator and mail-endpoint setup remains upstream-managed.
- **2.43** — `lib/lemper-modsec.sh`: new `lemperctl modsec` plugin with
  `status`, `report`, and `tune` commands. `tune --auto --apply` derives CRS
  paranoia/thresholds from the audit log, writes `/etc/modsecurity/lemper-tuning.conf`,
  validates with `nginx -t`, and rolls back on failure. Installer now respects
  `MODSEC_ENGINE`, `MODSEC_PARANOIA_LEVEL`, thresholds, and body-limit config.
- **2.44** — `scripts/install_certbotle.sh`: flushes the systemd-resolved cache
  around DNS-01 issuance and installs a Certbot deploy hook that reloads Nginx
  and flushes cached DNS records after renewal.


---

### Phase 8: Emergency PHP2Shell Remediation (v3.5.1) — ✅ Complete

**Focus:** Give legacy LEMPer installations a supported path to patch
CVE-2026-109618 / CVE-2026-109619 and keep the rest of the stack current.


| #     | Task                                        | Priority | Effort     | Estimated Time | Status  |
| ----- | ------------------------------------------- | -------- | ---------- | -------------- | ------- |
| 2.45  | Standalone `update.sh` bootstrap            | Critical | Medium     | 8h             | ✅ Complete |
| 2.46  | `lemper update` CLI plugin                  | Critical | High       | 16h            | ✅ Complete |
| 2.47  | Updater tests and documentation             | High     | Medium     | 6h             | ✅ Complete |

**Implementation notes:**

- **2.45** — `update.sh` installs the current CLI to `/usr/local/bin`, installs
  `lib/lemper-update.sh` as `/etc/lemper/cli-plugins/lemper-update`, and records
  the checkout in `/etc/lemper/update-source`. Supports `--install-only`,
  `--check`, `--source-dir`, `--post-max-size`, and `--yes`.
- **2.46** — `lib/lemper-update.sh` provides `check`, `php`, `nginx`, `mariadb`,
  `lemper`, and `all`. Supported PHP branches are upgraded from apt and verified
  against 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12. EOL branches are backed up and
  admin-locked with `memory_limit=-1`, `post_max_size=32M`,
  `session.upload_progress.enabled=0` (plus `fatal_error_backtraces=0` on 8.5),
  then reported as requiring migration. Source-built nginx is detected and not
  modified. Runs take a `flock` and log to `/var/log/lemper/`.
- **2.47** — `tests/unit/update_helpers.bats` (10 tests) plus syntax/wiring
  checks; suite is now 107 tests. README, ARCHITECTURE, and DEVELOPER document
  the bootstrap and remediation limits.


---

### Phase 9: Next Major (v4.0) — Accepted scope implemented; production checks and publication remain

GitHub issue [#92](https://github.com/joglomedia/LEMPer/issues/92) and
[Architecture §4](ARCHITECTURE.md#4-target-architecture-v40-cli-alignment-implemented)
describe the command/module alignment. Its accepted CLI/module scope is
implemented; optional extensions and remaining production checks are recorded
separately from the numbered tasks.

**CLI structure (issue #92).** `lemperctl` is the preferred installed command.
Retain `lemper-cli` as a compatibility symlink so existing scripts keep working.
The implementation filename remains `bin/lemper-cli.sh`.

- `lemperctl stack install`, `stack remove`, and `stack update` run one
  service at a time (Nginx, PHP, MariaDB, Redis/Valkey, PostgreSQL, FTP,
  CrowdSec, Fail2ban, and the rest of the installer set).
- `lemperctl stack start|stop|restart|reload|status` controls those
  services. PHP-FPM takes a version option because several branches can be
  installed together.
- `site create`, `site remove`, and `site update` match the issue's verbs.
  The current `add`, `manage`, and `mod` commands stay as aliases.
- A pinned `get-lemper` bootstrap downloads one release tarball, checks its
  checksum, installs the CLI and plugins under `/opt/lemper/<version>`, and
  copies `.env.dist` to `/etc/lemper/lemper.conf` only when that file is
  missing. It does not install the stack. The next instruction is to edit
  that config, then run `lemperctl stack install SERVICE` or opt into the
  shared full recipe with `stack install --all --config FILE`.

**Architecture status.** Schema-validated dotenv, core helper modules, working
runtime/service layers and compatibility adapters, key-only SSH defaults,
host/dependency audit jobs and release automation are implemented. PHP 8.2–8.5,
Bats/ShellCheck/Bashate, Fail2ban/CrowdSec, optional CBC encrypted configuration,
documentation, multi-distro CI and ACME helpers also exist.

Accepted legacy extraction, public parser adoption and native nftables
are implemented, along with managed data backups and monitoring. Public ACME and selected live migrations
need further deployment validation. YAML is optional; AEAD is a separate
encryption-format decision. See [ROADMAP_AUDIT.md](ROADMAP_AUDIT.md) for evidence.
Further request-state/API cleanup is optional. Candidate 9b3963e CI, reproducible
assets and exact-archive validation passed. Any subsequent commit requires its
own asset build and CI review before publication.

---

## 4. Risk Register


| Risk                                                                     | Impact | Likelihood | Mitigation                                                           | Status      |
| ------------------------------------------------------------------------ | ------ | ---------- | -------------------------------------------------------------------- | ----------- |
| Removing NOPASSWD:ALL breaks user scripts that rely on passwordless sudo | High   | Medium     | Document migration, add restricted sudoers config as opt-in          | ✅ Mitigated |
| Replacing `eval` config loader breaks existing `.env` parsing            | Medium | High       | Maintain backward-compatible fallback, test all key types            | ✅ Mitigated |
| Reorganizing directory structure breaks CI and user automation           | High   | Medium     | Preserve wrappers/exports and module import/dispatch contracts (A4) | Implemented; 9b3963e CI passed |
| Test entry points use incompatible users or missing fixture dependencies | High | Previously reproduced | Shared root Linux fixtures/tooling, public help staging and isolated state (A2) | Fixed; 534 Bats tests passed in candidate CI |
| Legacy backup-account credentials are written without private modes or literal serialization | High | Confirmed in isolated probe | Protected provisioning, key reconciliation and inline migration (A1) | Implemented locally |
| Removing PHP 5.6–7.4 breaks existing vhost configs                       | Medium | Medium     | Auto-detect installed PHP, warn on upgrade, provide migration script | ✅ Mitigated |
| Encrypted config breaks non-interactive CLI use                          | High   | Medium     | Add `--password` flag and environment variable fallback              | ✅ Mitigated |
| bats-core migration requires rewriting all tests                         | Medium | High       | Keep shunit2 tests running alongside, migrate gradually              | ✅ Mitigated |


---

## 5. Version Target Map


| Version    | Focus Area               | Key Deliverables                                                                                                                                   |
| ---------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **v2.7.2** | Immediate security fixes | Fix typos, `cgi.fix_pathinfo`, NOPASSWD, CI                                                                                                        |
| **v2.8.0** | Security hardening       | Credential suppression, RSA-4096, keyring, certbot fix                                                                                             |
| **v2.9.0** | EOL cleanup              | Remove PHP &lt;8.0, update defaults                                                                                                                |
| **v3.0.0** | Architecture overhaul    | Modular structure, safe config loading, encrypted secrets, bats-core tests                                                                         |
| **v3.1.0** | CLI enhancement          | `site list`, `site show`, DB backup/restore, Bun.js runtime                                                                                        |
| **v3.2.0** | Integration              | CrowdSec HIPS, Valkey, ACME DNS-01 wildcard                                                                                                        |
| **v3.3.0** | UI/UX                    | Progress indicators, improved help, PHP 8.4 default, Fail2ban default                                                                              |
| **v3.4.0** | Advanced security        | ModSecurity v3 WAF, encrypted config at rest, interactive TUI                                                                                      |
| **v3.5.0** | Architecture debt        | NOPASSWD fix, credential suppression, safe config loader, sed/i portability, restricted sudoers, Debian 12 CI, bashate linting, ShellCheck v0.11.0 |
| **v3.5.1** | PHP2Shell remediation    | Legacy `update.sh` bootstrap, `lemper update` plugin, EOL pool mitigations, apt version verification |
| **v3.5.2** | PHP 8.5 support          | 8.5 FPM templates, 8.5 default, install/remove menus, nginx handlers and phpinfo endpoints |
| **v3.6.0** | Current release          | TUI logs and site wizard, ModSecurity tuning, HTTP/3, CORS, resource profiles, MyGuard nginx, PHP 8.1 removed from defaults, EOL vhost migration (`--migrate-to`), Adminer 6.2.0, config backup, CrowdSec installer, FTP fixes |
| **v4.0.0** | Unreleased candidate | Implemented issue #92 CLI, pinned bootstrap, unified/minimal lifecycle flows, core/runtime/service decomposition, schema, key-only SSH, release automation, mail hosting and PHP/Laravel enhancements; Restic data backups, native nftables and Monit monitoring; release follow-through in ROADMAP_AUDIT.md |


---

## 6. Next Steps

Latest published release is **v3.6.0**. Delivery history below does not imply
every original task's full scope is complete. The unreleased **v4.0** branch
has delivered P1/P2/P3 foundations and prioritized runtime follow-through.
The current audit records the installer, CI and app-capability follow-through;
module decomposition is committed and verified by candidate CI.

A1/A2 are committed in 79d4d40; A3 and additional application deployment are
committed in 87b75b3. Resolute/Sury support is committed in b17b7f7 and the
documentation refresh in 21e27ab. A4 completes the four extraction boundaries
in [the implementation follow-through](ROADMAP_AUDIT.md#a4-module-decomposition-follow-through--2026-11-23).
For release preparation, rebuild assets from
the final clean commit after required fixes, validate that archive and candidate
CI, then tag/publish only when authorized. Keep deferred architecture/product
scope explicit.

Delivery history and unreleased candidate:

- **v3.0.0**: Architecture overhaul — `lemper-stacks.sh` orchestrator, validation functions,
bats-core test suite (107 tests passing)
- **v3.1.0**: `site list`, `site show`, DB backup/restore/schedule, Bun.js runtime
- **v3.2.0**: CrowdSec HIPS (+ WordPress scenarios), Valkey drop-in, ACME DNS-01 wildcard
- **v3.3.0**: Interactive TUI dashboard, progress indicators, improved CLI help,
PHP 8.4 default, Fail2ban enabled by default
- **v3.4.0**: ModSecurity v3 WAF + OWASP CRS, AES-256-CBC encrypted config, TUI
- **v3.5.0**: Restricted sudoers (replaces NOPASSWD:ALL), credential display suppression,
safe config loader (no eval), `sed_inplace()` portable wrapper, removed stale PHP 5.6-8.0
templates, bashate linting, Debian 12 CI matrix, ShellCheck v0.11.0, Ubuntu 24.04 runner
- **v3.5.1**: PHP2Shell remediation — standalone `update.sh` bootstrap, `lemper update`
plugin, EOL pool compensating controls, apt version verification
- **v3.5.2**: PHP 8.5 support — FPM templates, `DEFAULT_PHP_VERSION=8.5`, install/remove
menus, nginx `.php85` handlers, admin phpinfo endpoints
- **v3.6.0**: TUI live logs and site wizard, ModSecurity CRS auto-tuning,
systemd-resolved ACME hooks, opt-in HTTP/3, per-site CORS, resource profiles
and `nginx-lowend.conf`, SEC-20 … SEC-27, MyGuard nginx, PHP 8.1 removed
from the default install, `update php --migrate-to`, Adminer 6.2.0, config
backup, CrowdSec installer, and the Pure-FTPd / VSFTPD fixes
- **v4.0.0 (unreleased)**: issue #92 CLI, shared core/schema and runtime/service
layers, key-only SSH, pinned bootstrap and unified/minimal stack flows, mail
hosting and PHP/Laravel enhancements, expanded application deployments, native
nftables and Resolute/Sury support. A4 decomposition is delivered; final release
validation and optional extensions are detailed in ROADMAP_AUDIT.md.

---

## 7. Appendix: Full Issue Index


| ID       | Title                                               | File(s)                                                       | Phase      |
| -------- | --------------------------------------------------- | ------------------------------------------------------------- | ---------- |
| SEC-01   | `cgi.fix_pathinfo = 1` enables path traversal       | `etc/php/*/fpm/pool.d/*.conf`, `lib/lemper-create.sh`         | Phase 0 ✅  |
| SEC-02   | NOPASSWD:ALL sudo for lemper user                   | `scripts/utils.sh:create_account()`                           | Phase 6 ✅  |
| SEC-03   | Passwords passed as CLI args                        | `lib/lemper-create.sh`, `lib/lemper-db.sh`                    | Phase 1 ✅  |
| SEC-04   | `cgi.fix_pathinfo=1` in [www.conf](http://www.conf) | `etc/php/*/fpm/pool.d/www.conf`                               | Phase 0 ✅  |
| SEC-05   | Self-signed SSL uses RSA-2048                       | `nginx_ssl_cert.sh`, `lemper-selfssl.sh`, `lemper-manage.sh`  | Phase 1 ✅  |
| SEC-06   | `eval`-based config loading                         | `scripts/utils.sh`, `bin/lemper-cli.sh`                       | Phase 6 ✅  |
| SEC-07   | Deprecated `apt-key` usage                          | `scripts/nginx/nginx_repo.sh:45`, `scripts/install_php.sh:62` | Phase 1 ✅  |
| SEC-08   | Credentials printed to stdout                       | `lib/core/lemper-stacks.sh`                                   | Phase 6 ✅  |
| SEC-09   | `fial` typo in error paths                          | `lib/lemper-create.sh:957`, `lib/lemper-db.sh:593`            | Phase 0 ✅  |
| SEC-10   | No input sanitization for domain/IP                 | `lib/lemper-selfssl.sh`, `lib/lemper-create.sh`               | Phase 2 ✅  |
| SEC-11   | Plaintext credential storage                        | `scripts/utils.sh:846-851`                                    | Phase 5 ✅  |
| SEC-12   | Open\_basedir temp dirs under user home             | `lib/lemper-create.sh:615-616`                                | Phase 6 ✅  |
| SEC-13   | Hidden files (`.env`, `.git`, backups) served       | `etc/nginx/includes/rules_restriction.conf`                   | Audit ✅    |
| SEC-14   | `display_errors = on` in all FPM pools              | `etc/php/*/fpm/pool.d/*.conf`, pool generators                | Audit ✅    |
| SEC-15   | FastCGI cache ignored `Set-Cookie`/`Cache-Control`  | `etc/nginx/includes/fastcgi_cache.conf`                       | Audit ✅    |
| SEC-16   | Session cookies missing `HttpOnly`/`SameSite`       | all FPM pools, `install_php.sh`                               | Audit ✅    |
| SEC-17   | FPM status/ping reachable from any client           | vhost generators, `sites-available/default*`                  | Audit ✅    |
| SEC-18   | `/lcp/phpinfo.php84` bypassed basic auth            | `etc/nginx/sites-available/default`, `default-ssl`            | Audit ✅    |
| SEC-19   | HSTS preload/includeSubDomains enabled by default   | `etc/nginx/includes/ssl.conf`                                 | Audit ✅    |
| SEC-20   | Admin vhosts (8082/8083) bypassed restriction rules | `etc/nginx/sites-available/default*`                          | Audit ✅    |
| SEC-21   | `X-Powered-By` advertised the stack                 | `etc/nginx/includes/compression_gzip.conf`                    | Audit ✅    |
| SEC-22   | Static cache dropped inherited security headers     | `etc/nginx/includes/cache_static.conf`                        | Audit ✅    |
| SEC-23   | Backup/dump files served from web roots             | `etc/nginx/includes/rules_restriction.conf`                   | Audit ✅    |
| SEC-24   | SVG served without sandboxing                       | `etc/nginx/includes/rules_staticfiles.conf`                   | Audit ✅    |
| SEC-25   | `session.save_path` app-overridable (doc-root sessions) | `scripts/install_php.sh`, FPM pool templates              | Audit ✅    |
| SEC-26   | `sess_*` session files served if left in web root   | `etc/nginx/includes/rules_restriction.conf`                   | Audit ✅    |
| PERF-01  | Fixed FPM/opcache/nginx/MariaDB sizing on low-end VPSes | `scripts/utils.sh`, `nginx_post_install.sh`, `nginx-lowend.conf`, `install_mariadb.sh` | Audit ✅ |
| FUNC-01  | JavaScript runtime                                   | Bun.js via `scripts/install_bun.sh`; Node.js is not shipped   | Phase 3 ✅  |
| FUNC-02  | No `site list` command                              | CLI missing                                                   | Phase 3 ✅  |
| FUNC-03  | No `site show` command                              | CLI missing                                                   | Phase 3 ✅  |
| FUNC-04  | No DB backup/restore commands                       | `lib/lemper-db.sh`                                            | Phase 3 ✅  |
| FUNC-05  | Certbot renewal cron bug                            | `scripts/install_certbotle.sh:109`                            | Phase 1 ✅  |
| FUNC-06  | No CrowdSec PHP webapp scenarios                    | `scripts/install_crowdsec.sh`                                 | Phase 5 ✅  |
| UX-01    | Poor CLI help text                                  | `bin/lemper-cli.sh:158`                                       | Phase 4 ✅  |
| UX-02    | No progress indicators                              | All install scripts                                           | Phase 4 ✅  |
| UX-03    | No TUI/dashboard mode                               | CLI                                                           | Phase 4 ✅  |
| UX-04    | No TUI site creation wizard                         | `lib/lemper-tui.sh`                                           | Phase 7 ✅  |
| UX-05    | No real-time log streaming in TUI                   | `lib/lemper-tui.sh`                                           | Phase 7 ✅  |
| ARCH-01  | Duplicated install/remove logic                     | `install.sh` vs `lemper.sh`                                   | Phase 2 ✅  |
| ARCH-02  | Flat directory structure                            | Entire codebase                                               | Phase 2 ⚠️ |
| ARCH-03  | No bats-core integration tests                      | `shunit2/run_test.sh`                                         | Phase 2 ✅  |
| ARCH-04  | CI references non-existent vars                     | `.github/workflows/main.yml`                                  | Phase 0 ✅  |
| ARCH-05  | ShellCheck not run on nginx submodules              | `.github/workflows/main.yml`                                  | Phase 0 ✅  |
| ARCH-06  | No mock-based unit tests                            | `tests/`                                                      | Phase 6 ✅  |
| PERF-01  | FastCGI buffers/timeouts oversized (16MB/300s)      | `etc/nginx/includes/fastcgi.conf`                             | Audit ✅    |
| PERF-02  | Opcache never enabled for PHP 8.4 (static php.ini)  | `scripts/install_php.sh`                                      | Audit ✅    |
| PERF-03  | 30 FPM children per pool on 1GB servers             | pool templates                                                | Audit ✅    |
| STACK-01 | PHP 5.6–7.4 templates still in etc/                 | `etc/php/{5.6,...,7.4}/`                                      | Phase 6 ✅  |
| STACK-02 | Default PHP version outdated (8.2)                  | `.env.dist`                                                   | Phase 4 ✅  |
| STACK-03 | MariaDB default version old (11.1)                  | `.env.dist`                                                   | Phase 4 ✅  |
| STACK-04 | Old OpenSSL reference in config                     | `.env.dist`                                                   | Phase 4 ✅  |
| STACK-05 | Fail2ban off by default                             | `.env.dist`                                                   | Phase 4 ✅  |
| STACK-06 | NAXSI WAF is legacy                                 | `etc/nginx/includes/*.rules`                                  | Phase 5 ✅  |
| STACK-07 | No CrowdSec integration                             | TODO in README                                                | Phase 3 ✅  |
| STACK-08 | sed -i not macOS-portable                           | 20 files, 210 usages                                          | Phase 6 ✅  |
| STACK-09 | grep -oP (PCRE) not macOS-portable                  | `scripts/lemper_stacks.sh:50`                                 | Phase 6 ✅  |
| DOC-01   | No architecture documentation                       | Project root                                                  | ✅ Complete |
| DOC-02   | No developer guide                                  | Project root                                                  | ✅ Complete |
| DOC-03   | No agentic guide                                    | Project root                                                  | ✅ Complete |
| DOC-04   | No roadmap document                                 | Project root                                                  | ✅ Complete |
| DOC-05   | Stale PHP 5.6-8.0 docs in README                    | `README.md`                                                   | Phase 6 ✅  |

## v4 release preparation status

The v4 entry points now share profile validation and full-stack lifecycle
orchestration. Bootstrap defaults to CLI-only; an explicit `--install --config`
selects full installation. A minimal service profile skips optional services
and panels. The version/tag workflow produces both archive and bootstrap
checksums. Accepted legacy driver decomposition is implemented; optional
request-state/API refinements and production deployment checks remain separate.

Validation and publication steps are recorded in [RELEASE_V4.md](RELEASE_V4.md).
