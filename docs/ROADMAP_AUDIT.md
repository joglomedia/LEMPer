# LEMPer roadmap implementation audit

Date: **2026-11-23**. Current baseline: **79d4d40**,
`release/v4.0.0`, plus the A3 implementation working tree. The initial audit
used **9b7511b383e6dbcb5cd3da2424b604016134c379** and
began from a clean checkout. Earlier
cross-checks and implementation validation are preserved below as history.
Latest GitHub release checked: **v3.6.0**. v4.0.0 is not published.

This report supersedes the earlier 2026-11-20 audit; that snapshot remains in
Git history. It compares all **48 unique numbered roadmap IDs**, Architecture
§4, README plans, and developer-workflow proposals with current source and test
wiring. It identifies implementation gaps and release gates, rather than treating
historical problem descriptions or old file layouts as current bugs.

Priorities below are suggested delivery priorities, not vulnerability severity
ratings. Source presence does not prove every platform or live upgrade works.
This audit does not constitute a new security scan or upstream dependency audit.

## Remaining work at 9b7511b

The previously reported runtime validation, curated repository/custom-TLS,
diagnostic parity and domain-DB gaps are delivered in **9b7511b**. This pass found
additional installer and test-environment scope; it does not reopen the working
SQL backup/restore engine or treat every historical TODO as an absent feature.

| Order | Priority / scope | Confirmed remaining work | Recommended completion |
|---|---|---|---|
| A1 | **P1 — legacy MariaDB backup provisioning; 2.9 and credential-file guardrails** | [enable_mariabackup](../scripts/install_mariadb.sh) inserts configured names/passwords directly into SQL and a generated shell program. With umask `022`, its synthetic credential drop-in was **0644**; a quoted password failed configuration generation. It saves `MARIABACKUP_USERNAME`/`MARIABACKUP_PASSWORD`, while installation reads `MARIABACKUP_USER`/`MARIABACKUP_PASS`. An existing account skips configuration repair. The schema accepts all four names but does not reconcile them. | Extract a backup-account driver using validated identifiers, literal credential serialization and protected atomic mode-0600 configuration. Reconcile canonical/legacy keys and existing-account state without silently resetting credentials. Cover quoted inputs, failures, private modes and repeat installation. |
| A2 | **P1 — reproducible CI/release checks; 2.15/2.38 and release validation** | [Primary CI](../.github/workflows/main.yml) and [release CI](../.github/workflows/release.yml) run the full Bats suite unprivileged. The DB fixture suite had **6 failures out of 18** as an ordinary Linux user, versus **18/18 passing** as root with isolated locks/temp directories. Directory trust checks reject root-owned ancestors for an unprivileged caller. Some [core tests](../tests/unit/core_contracts.bats) also require `visudo`, `sshd` and `/run/sshd`; the [Podman helper](../scripts/test_podman.sh) installs only ShellCheck/Bats. | Align these entry points with a designated root Linux fixture, declare complete dependencies and the intended lint version, and isolate test locks/state. Preserve runtime ownership checks. Then validate the exact candidate's jobs; the formatting/coverage job already uses root and a fuller dependency list. |
| A3 | **P2 — application capability contract; README and 2.42** | [Site normalization](../lib/runtime/site/commands.sh) accepts Mautic/Roundcube/Sendy with `--install-skeleton`, and the [TUI wizard](../lib/runtime/tui/commands.sh) offers installation by default. Their [creation branch](../lib/runtime/site/create.sh) only writes an index placeholder and generic vhost, even when installation was requested. | Distinguish vhost support from application installation. Reject unsupported installation requests before mutations, or implement verified application drivers and a user-supplied artifact path where licensing requires it. Have CLI/TUI share the capability list and verify actual application entry files in acceptance checks. |
| A4 | **P2 — deeper decomposition; 2.12/2.37, Architecture §4.4** | Business logic remains in [management](../lib/lemper-manage.sh), [updater](../lib/lemper-update.sh), [site creation](../lib/runtime/site/create.sh) and older component installers. Site creation still combines orchestration, configuration rendering and application installation. [Compatibility adapters](../lib/compat/components.sh) isolate legacy execution but do not extract those bodies. | Move one cohesive use case at a time behind existing runtime/service contracts, starting with A1/A3, then site rendering and manager/updater/component internals. Preserve wrappers, registries, installed exports, locking, dry-run behavior and returned failures. |

Publication gates are listed separately below. Finish A1/A2 before relying on
release readiness; deeper decomposition remains incremental release follow-up.
The app contract needs an explicit supported-capability boundary even if full
Mautic/Roundcube/Sendy deployment is deferred.

**Optional extensions, not unfinished required implementations:** authenticated
configuration encryption, YAML, additional quota filesystems and CPU/RAM/bandwidth
limits. MariaDB installation already includes `mariadb-backup`; the managed DB
commands implement logical SQL dumps. A managed physical backup/prepare/restore
workflow would be an additional capability, not evidence that SQL backups are
missing. OCSP directives already exist in the SSL include; operational stapling
depends on the certificate/issuer and is not an absent-template finding.

## Current P1 follow-through

**A1 and A2 are committed in 79d4d40. A3 is implemented in the working tree.**
A4 remains the next implementation priority; release validation/publication
gates remain separate. The table above preserves the original findings at
9b7511b; delivery below supersedes their remaining-work status.

| Finding | Delivered behavior | Source / qualification |
|---|---|---|
| A1 | Dedicated function-only backup-account driver; literal SQL/options/dotenv credentials; private atomic drop-in/profile updates; encryption-preserving canonical key reconciliation; existing-account authentication and configuration repair without password resets; protected recovery copies and known inline `my.cnf` migration | [driver](../lib/services/mariadb/backup.sh), [installer](../scripts/install_mariadb.sh), [regressions](../tests/unit/mariadb_backup_account.bats). Credentials are durable before account/grant mutations so partial SQL failures can be retried. Ambiguous/untrusted configuration is rejected; custom inline tuning requires reconciliation. Root credentials are saved before bootstrap SQL; write/RNG failures abort. The private inline include preserves option precedence and is synchronized with canonical credentials. [Native option preflight](../lib/services/mariadb/option_guard.sh) rejects control escapes and untrusted include graphs before recovery. |
| A2 | Shared root Linux dependency setup and native ShellCheck 0.11.0; isolated Bats/coverage runner and per-unit operation locks; primary Ubuntu CI, Debian CI, coverage, release and Podman entry points use these contracts | [setup](../scripts/prepare_tests.sh), [runner](../scripts/run_tests.sh), [Podman](../scripts/test_podman.sh), [fixture](../tests/unit/env_helper.bash), [CI](../.github/workflows/main.yml), [release](../.github/workflows/release.yml). No runtime ownership check was relaxed. Remote Actions results still require the final committed candidate. |

The shared literal dotenv parser and schema now strip **one matching outer quote
pair**. The shared writer wraps values when needed to retain actual quote
characters during profile merging. Inner and one-sided quotes remain data; this preserves quoted passwords
on both installer and installed CLI paths. The encrypted-profile format is unchanged.
See [DATABASE.md](DATABASE.md#mariadb-backup-account-provisioning) and
[DEVELOPER.md](../DEVELOPER.md) for operating and test contracts.

## Current A3 follow-through

CLI, legacy creation and TUI share the function-only
[application capability catalog](../lib/core/registry.sh) and
[driver](../lib/services/site/applications.sh). Sendy retains manual PHP vhost
support and rejects `--install-skeleton`, `--install-app` and `-i` before site
mutations. Vanilla PHP has no skeleton and rejects the same
flags. The wizard offers installation only for automatic types. Existing
automatic installers must produce nonempty application marker files before
success and ownership recording; WordPress setup/plugin actions honor the flag.

Mautic and Roundcube now use a function-only [release driver](../lib/services/site/releases.sh)
and [vhost renderer](../lib/services/nginx/release-site.sh), with latest-stable complete
packages, SHA-256 verification, restricted extraction, runtime/target preflight
and idempotent preservation. Roundcube uses `public_html`; both have restricted
PHP entry scripts and loopback-only setup endpoints. No fictitious application
database is recorded as owned. This closes A3's advertised-capability gap and
the 2.42 qualification. Unattended DB/admin/mail configuration and Sendy's
licensed-artifact interface remain outside this scope.
File checks do not establish application health; partial installer
state can remain on failure. See [APPLICATIONS.md](APPLICATIONS.md). Deeper
rendering/installer extraction remains A4 and partial 2.12/2.37.

## Implemented foundations

The previous report's "Phase 9 largely unimplemented" statement is obsolete.
These capabilities are now present:

- Shared core helpers, configuration schema, literal dotenv loading, a widely
  adopted CLI argument parser, operation locking, and compatibility loaders.
- Hosting/admin account roles and explicit privilege migration; validated site
  removal and protected default installer credential handling.
- Key-only SSH defaults and Cloudflare/DigitalOcean DNS-01 issuance/renewal helpers.
- Unified install/remove/update entry adapters, per-component lifecycle commands,
  site verbs/aliases, and minimal installation profiles.
- Pinned `get-lemper`, versioned code exports, reproducible release assets,
  release automation, host/dependency audit jobs, and disposable acceptance tests.
- Mail domains/accounts/aliases with retained data and keys; PHP default selection
  with encrypted-profile persistence; Laravel root and mounted application routing.

The runtime/service directories contain working implementations. Retained entry
filenames and thin wrappers are compatibility contracts, not missing features.
Further extraction of business logic from legacy files is still unfinished.

## P1 implementation follow-through

The three P1 findings below were implemented in **363945d**:

| Rank | Delivered behavior | Source / validation |
|---|---|---|
| R1 | Shared DB identifier/host/port/privilege validation; restricted legacy extra fields; literal SQL password handling; locked, argument-safe backup/restore/import/export; atomic mode-0600 dumps and propagated failures; validated repeatable cron scheduling with protected credentials and rollback | [database driver](../lib/services/mariadb/database.sh), [DB plugin](../lib/lemper-db.sh), [regression tests](../tests/unit/db_backup_restore.bats). Default localhost retains socket auth; the broken `backup-schedule` dispatcher mapping is fixed. SQL retention is delivered in the P2 R4 follow-through. |
| R2 | Text/JSON metadata diagnostics redact passwords and expose only known public fields; `--json`/`-j` emit one JSON object and imply `--all`; parse errors do not disclose metadata values | [site-show plugin](../lib/lemper-site-show.sh), [diagnostic tests](../tests/unit/site_diagnostics.bats). Root-only metadata storage is retained for deliberate private recovery. |
| R3 | PHP/Sury/PPA and MariaDB scoped signing keys; source-file backups and `.list`/deb822 migration; verified selective retirement of dedicated old keys; no downloaded MariaDB shell helper execution | [APT driver](../lib/services/apt/repositories.sh), [PHP installer](../scripts/install_php.sh), [MariaDB installer](../scripts/install_mariadb.sh), [retained bundled helper](../scripts/mariadb_repo_setup), [key-scope tests](../tests/unit/repository_keys.bats). Mixed-URI stanzas/shared keyrings require explicit review. Debian live PHP package validation encountered an upstream signed-index checksum mismatch; verification stayed enabled. |

[DATABASE.md](DATABASE.md) documents the delivered CLI, input/credential limits
and migration behavior. The disposable [P1 UAT suite](../tests/uat/p1_acceptance.sh)
passed 30 checks on Ubuntu 24.04 ARM64, including real MariaDB data restoration,
scheduled execution, quote/backslash passwords and installed CLI diagnostics.
This is scoped component UAT, not a rebuilt final release archive.

## P2 implementation follow-through

P1 is committed as `363945d`. P2 is committed as **736c5e5** and delivers:

| Rank | Status | Delivered behavior / remaining qualification |
|---|---|---|
| R4 | Implemented | Checksummed SQL dumps, per-database `db prune --keep`, optional rotation after successful backups, preservation of corrupt/unmanaged/foreign artifacts. Default `SQL_BACKUP_KEEP=0` keeps automatic pruning opt-in. |
| R5 | Implemented | Registered Restic lifecycle and `data` commands, encrypted local/remote repositories, protected credentials, snapshot integrity, host/path/tag retention, daily systemd scheduling and empty staged restoration of applications/uploads/mail. Local repositories were tested; external destinations need their own validation. |
| R6 | Implemented | Native scoped nftables table, persistence, IPv4/IPv6 filtering, existing/active SSH ports, independent timed recovery, explicit UFW migration and rollback. Foreign tables and CSF/APF remain protected; provider firewalls and other platforms need separate UAT. |
| R7 | Implemented for public paths | Mail and full-stack adapters now use the shared parser with equals-value options and `--`. GNU getopt remains only in intentional compatibility boundaries; historical aliases are preserved. |
| R8 | Advanced; further extraction remains | Account, database, SSL, TUI and vhost creation handlers moved into function-only runtime modules. Account provisioning, backups, monitoring and firewall logic use service drivers. Installed wrappers/exports stay compatible. Legacy site-management and older component installer internals remain candidates for the next extraction. |
| R9 | Implemented | Optional Monit lifecycle, system/filesystem/web checks, authenticated loopback HTTP, CLI status/check/reload/logs and opt-in SMTP alert configuration. Local health/authentication/configuration were tested; external alert delivery was not. |

See [DATA_BACKUP.md](DATA_BACKUP.md), [DATABASE.md](DATABASE.md),
[FIREWALL.md](FIREWALL.md), and [MONITORING.md](MONITORING.md). The first native
P2 UAT passed 37 checks; the extended fresh-container suite passed 51, including
actual SSH login, IPv4/IPv6 enforcement, UFW migration/rollback and recovery while
the shared backup lock is held. Full Bats results are recorded below.

## P3 implementation follow-through

| Rank | Delivered behavior | Source / validation |
|---|---|---|
| R10 | Hosting disk/inode plans; preflighted account provisioning; ext4 user-quota enforcement; assignment/upgrade/downgrade checks; original numeric quota restoration; interrupted-operation recovery and removal guards (issue #39) | [hosting guide](HOSTING.md), [plan driver](../lib/services/hosting/plans.sh), [quota driver](../lib/services/hosting/quota.sh), [runtime commands](../lib/runtime/hosting/commands.sh), [UAT](../tests/uat/p3_acceptance.sh). Requires administrator-enabled ext4 quotas. CPU/RAM/bandwidth and additional filesystem backends are separate enhancements. |
| R11 | EditorConfig and scoped shfmt enforcement without mass-formatting; synthetic Bats function-entry instrumentation and JSON/Markdown coverage publishing | [format gate](../scripts/check_format.sh), [scope](../tools/shfmt-files.txt), [coverage runner](../scripts/test_coverage.sh), [CI](../.github/workflows/main.yml). Function-entry coverage does not claim line/branch coverage or installation correctness. |
| R12 | Component step counters with interactive ETA, spinner elapsed/completion time, and optional pv byte/rate/ETA feedback during configuration archive restore | [progress module](../lib/core/progress.sh), [utils](../scripts/utils.sh), [recipe](../lib/runtime/stack/recipe.sh), [backup](../lib/lemper-backup.sh). TTY-only ETA/transfer feedback; deterministic fallback without pv. |

The P3 disk/inode package contract is implemented. The prioritized follow-through
below closes the identified validation, repository/TLS, diagnostic and domain-DB
scope. R8 remains an incremental architecture workstream; its next service
boundaries are delivered, while older installer/management internals still remain.

## Prioritized implementation follow-through — 2026-11-22

Delivered in **9b7511b**; the recorded implementation checks below preceded that
commit. A1/A2/A3 above are additional scope found by the current audit.

| Tasks | Delivered follow-through | Limits / source |
|---|---|---|
| 2.9 | Whole-value shared FQDN/IPv4/username validation, semantic IPv6 compression/IPv4-tail checks, legacy wrappers using the same core, validation before site/SSL mutations, typed TLS source tags | [core predicates](../lib/core/validation.sh), [regressions](../tests/unit/validators.bats). Legacy text-result APIs and stricter status APIs retain their caller contracts. This is closure of the identified input boundaries, not a whole-repository security certification. |
| 2.8 / 2.27 | Shared backed-up repository reconciliation for PGDG/Redis/MongoDB/deadsnakes/MaxMind/Go PPAs, pinned published key identities, preflight of mixed stanzas/signature-bypass options, preservation of unrelated/shared trust; corrected custom TLS enablement and verified OpenSSL 3.5.9 LTS source integration | [catalog](../lib/services/apt/catalog.sh), [migration](../lib/services/apt/repositories.sh), [TLS builder](../scripts/nginx/nginx_ssl_builders.sh). MongoDB major changes require explicit reconciliation; unowned/shared keyrings are retained. The former Bun APT endpoint returns 404: its lifecycle now uses [checksummed official release binaries](../lib/services/bun/binary.sh) with native architecture selection and ownership checks. |
| 2.12 / 2.37 | Diagnostics extracted into a function-only runtime adapter and a Bash diagnostics driver using jq for structured output; shared staged certificate issuance replaces CLI/manager duplication; repository and Bun lifecycle logic moved into service drivers | [show runtime](../lib/runtime/site/show.sh), [inspection](../lib/services/site/inspect.sh), [certificate driver](../lib/services/ssl/certificates.sh). Installed exports include these helpers. Deeper extraction of legacy application rendering and older installer/manager bodies remains; decomposition stays partial. |
| 2.17 | Text/JSON views share Nginx/FPM content, certificate path/SAN/expiry/hostname details, legacy metadata, ownership state and nested application mounts; secret-bearing fields are redacted; literal metadata parsing and recovery views are preserved | [inspection driver](../lib/services/site/inspect.sh), [diagnostic tests](../tests/unit/site_diagnostics.bats). Certificate trust-chain verification is not implied by a readable certificate; variable paths and indirect upstreams can remain unresolved. |
| 2.18 | Positional `db backup DOMAIN`, `db restore DOMAIN FILE` and `db backup-schedule DOMAIN` resolve an ownership record, reject conflicting legacy state and retain the protected engine and explicit DB flags | [resolver](../lib/services/site/database.sh), [runtime](../lib/runtime/database/commands.sh). Sites without a recorded database require explicit `--dbname` or ownership reconciliation. Mount-specific application databases are not guessed from private `.env` files. |

The custom TLS default uses the **OpenSSL 3.5 LTS** line, supported through April
2030. Nginx recommends OpenSSL 3.5.1+ for QUIC. Release 3.5.9 and its published
SHA-256 artifact were verified through the official OpenSSL release metadata;
explicit legacy QuicTLS pins keep their existing source route. Source builds
omit generation of upstream test executables; application validation remains
separate. Sources: [Nginx QUIC](https://nginx.org/en/docs/quic.html),
[OpenSSL LTS policy](https://openssl-library.org/post/2025-02-20-openssl-3.5-lts/),
[OpenSSL 3.5.9](https://github.com/openssl/openssl/releases/tag/openssl-3.5.9).

## Historical targeted completion cross-check (753c846)

P1/P2 delivered the previously identified database, diagnostic and PHP/MariaDB
repository safeguards. The original tasks also contain broader scope:

| Tasks | Delivered | Unfinished scope and source evidence |
|---|---|---|
| 2.8 | Active installer code no longer invokes deprecated `apt-key`; fresh Nginx/PHP/MariaDB and several optional-service repositories use scoped keys. | Repository convergence is incomplete. The [shared migration driver](../lib/services/apt/repositories.sh) recognizes PHP/OpenSwoole/MariaDB families. [PGDG setup](../scripts/install_postgres.sh) skips an existing `pgdg.list` rather than validating/migrating it; [Python](../scripts/install_dependencies.sh), [Go](../scripts/nginx/nginx_ssl_builders.sh) and [MaxMind](../scripts/nginx/nginx_extra_modules.sh) still delegate PPA setup without the shared scoping/migration contract. Shared legacy keys must be retired only when ownership/reference checks prove it safe. |
| 2.9 | Validators, quoting helpers, protected DB inputs and strict modern site/account paths exist. | Single-line and semantic validation are not consistent across legacy paths. [Shared FQDN/IP validators](../lib/core/validation.sh), [self-SSL](../lib/runtime/ssl/commands.sh), [legacy site creation](../lib/runtime/site/create.sh), [management](../lib/lemper-manage.sh) and [site-show](../lib/lemper-site-show.sh) retain duplicated checks. Linux probes confirmed a multiline FQDN is accepted by shared/self-SSL grep validators while `is_valid_domain` rejects it; self-SSL's IPv6 shape check accepts `:::`. Consolidate strict validation before filesystem, sed and certificate operations; existing valid-input tests do not close this scope. |
| 2.17 | Text views for vhost/FPM/app/SSL, parseable JSON and credential redaction work. | [JSON](../lib/lemper-site-show.sh) returns extracted Nginx attributes, not full config or FPM pool data, and SSL type/path rather than certificate details. Both diagnostics paths use legacy `vhost.d` metadata and miss modern [ownership state](../lib/runtime/site/state.sh) and [mounted-app state](../lib/runtime/site/apps.sh). Complete view parity and certificate discovery using actual vhost directives. Plaintext linked credentials are intentionally excluded; redaction is a deliberate specification adjustment. |
| 2.18 | Explicit `--dbname`/`--dbfile` SQL backup, restore, cron scheduling and checksummed retention are implemented and tested. | The proposed `db backup <domain>`, `db restore <domain> <file>` and `db backup-schedule <domain>` shortcuts are absent. [DB dispatch](../lib/runtime/database/commands.sh) does not resolve domain metadata to a database; dry-run probes reject these forms with `Specify --dbname.` Add an unambiguous ownership-aware mapping over the existing DB driver, or explicitly revise the original requirement to the accepted flag interface. This is a CLI/specification gap; protected backup/rotation is already delivered. |
| 2.27 | MariaDB defaults to 11.4 and scoped repository setup is available. | Shares the remaining repository-convergence work in 2.8. The [source builder](../scripts/nginx/nginx_build.sh) checks `NGINX_CUSTOMSSL`, while public defaults/schema expose `NGINX_WITH_CUSTOMSSL`; no assignment bridging these flags was found. A fully stubbed source-build probe confirmed that the public flag does not invoke `build_custom_ssl`, while the alternate internal flag does. The opt-in [custom TLS pin](../.env.dist) remains `openssl-3.2.4-quic1`; select a maintained TLS/QUIC source and validate its builder/HTTP3 compatibility before changing the pin. No live upstream version/advisory assessment was performed here. |
| 2.12 / 2.37 | Core, runtime, services and compatibility layers contain working code, with shared registries, locking and [installed exports](../lib/core/deployment.sh). Account/database/SSL/TUI handlers have already moved into function-only runtime modules. | Decomposition is partial. [Legacy management](../lib/lemper-manage.sh), diagnostics and older `scripts/install_*.sh` business logic remain; [component adapters](../lib/compat/components.sh) still execute those installers in children. [Site creation](../lib/runtime/site/create.sh) is function-only but still combines orchestration, rendering and application installation. Extract business logic into drivers incrementally while preserving public wrappers and installed paths. Directory presence alone is not completed decomposition. |

Suggested next delivery order (priority reflects the next work, not vulnerability severity):

1. **P1 — 2.9:** Reject control/newline input consistently, use semantic IP checks,
   and remove validator shadowing on all affected legacy/public paths.
2. **P2 — 2.8 / 2.27:** Extend backed-up repository migration to remaining families;
   fix custom-TLS enablement wiring, then resolve and validate the maintained TLS/QUIC policy.
3. **P2 — R8 / 2.12 / 2.37:** Continue targeted service extraction alongside those
   fixes; diagnostics and certificate drivers provide a coherent next boundary.
4. **P3 — 2.17:** Complete text/JSON/FPM/certificate/new-state diagnostic parity.
5. **P3 — 2.18:** Implement domain resolution or explicitly approve the flag-based
   specification. Preserve the working backup/restore/scheduling/retention engine.


Cross-check validation: **59 focused Bats tests passed** (diagnostics, repository
migration, DB backup/restore and alignment contracts). Disposable Linux probes
confirmed validator edge cases, rejected domain shortcuts, missing JSON view/state
fields, and the custom-TLS flag mismatch. Runtime/service modules loaded without
dispatch. No installers, live configuration changes, network downloads or TLS
compilation were performed; source-build commands were stubbed. This update changes
roadmap/architecture documentation only and does not implement the open scope.


## Release gates and validation, not missing code features

| Gate | Current evidence | Required follow-through |
|---|---|---|
| CI for the candidate commit | `gh run list --commit 9b7511b383e6dbcb5cd3da2424b604016134c379` returned **0 runs**. A2 identifies a local reproduction of the test-environment mismatch; this is not a remotely observed Actions failure. | Correct the environment contract, then run/review the exact candidate's jobs, including service acceptance checks. This audit does not authorize a push or workflow trigger. |
| Final release assets | [RELEASE_V4.md](RELEASE_V4.md) records locally reproducible assets from an earlier temporary source snapshot. It does not validate the archive of 9b7511b. | After the required fixes, build from the final clean committed candidate, verify all four assets and their contents/checksums, then validate that exact archive/bootstrap. |
| Publication | Exact `gh release view v4.0.0` returned `release not found`; no local `v4*` tag was found. Latest published release is v3.6.0. | Set the release date, review/tag/publish after authorization, and verify published downloads and README one-liners. |
| Remaining deployment validation | Historical native checks include Ubuntu 24.04/Debian 12 ARM64 service UAT and an Ubuntu source Nginx/OpenSSL build. Public ACME, native AMD64 execution, HTTP/3 client negotiation/0-RTT, remote Restic destinations, external SMTP alerts and selected legacy upgrades remain unverified. | Validate representative supported profiles/upgrades and exact release archives, controlled-domain issuance/renewal, remote integrations and client negotiation. Existing SSH/firewall recovery UAT is recorded above; additional platform/provider checks remain. |

Native nftables is now implemented. Further legacy extraction remains follow-up
work and does not automatically make it a v4 publication blocker. An explicit release-scope decision is needed before claiming all of
Architecture §4 is complete.

## Decisions and specification differences

- **Encryption:** Optional encrypted configuration is implemented with
  AES-256-CBC/PBKDF2. Authenticated encryption/GCM is a deferred format/provider
  decision, not implemented by the current `openssl enc` path. Preserve existing
  reads and add tamper tests if that migration is selected.
- **TLS pins:** Historical 3.3/3.4 proposals are superseded by the verified
  OpenSSL 3.5.9 LTS selection. Custom TLS remains opt-in; explicit older library
  pins retain compatibility routes. This source policy is not an advisory scan
  of every optional TLS library.
- **RSA defaults:** The originally named Nginx/self-SSL paths use configurable
  RSA-4096 defaults/SANs. New mailer development certificates explicitly use
  RSA-2048. Decide whether the generic Architecture §4 SSL target should cover
  that development path; this difference alone is not a vulnerability finding.
- **Layout/naming:** Shared Valkey install/remove branches fulfill the backend
  feature without separate `install_valkey.sh`/`remove_valkey.sh` files. Bats in
  `tests/` and `tests/unit/` fulfill testability without `tests/integration/`.
  The TUI is implemented as `tui`; a literal `dashboard` alias is not required
  for the dashboard capability. YAML configuration is optional; schema-validated
  dotenv is implemented.
- **Informal CLI proposal:** `--default-version=8.4` was recommended in the
  conversation but not approved/implemented. Current code remains
  `--default-runtime=php@8.4`. This is not a numbered roadmap requirement.

## Numbered-task reconciliation

"Implemented" means current source has the capability; it is not an assertion
that every branch, upgrade or security property was exhaustively verified.

| ID | Current status | Qualification / source |
|---|---|---|
| 2.1 | Implemented | Active error paths use `fail`; no active `fial` call found. |
| 2.2 | Implemented | Current pool templates and generated pools disable `cgi.fix_pathinfo`; commented php.ini examples are not active settings. |
| 2.3 | Implemented | Restricted hosting accounts and explicit admin roles/migration in `lib/core/accounts.sh`. |
| 2.4 | Implemented | Default credential suppression and protected storage; site diagnostic redaction now delivered in R2. |
| 2.5 | Implemented | Credential recap email delivery removed; mail hosting is a separate feature. |
| 2.6 | Implemented | Literal dotenv/config loading; legacy `eval set --` parses getopt output, not user configuration. |
| 2.7 | Implemented for named paths | RSA-4096 defaults and SAN support; newer mailer development path is a policy difference above. |
| 2.8 | Implemented for curated sources | Deprecated calls removed; PHP/MariaDB and remaining curated repository families use backed-up scoping. Ambiguous/unsafe/unowned state requires reconciliation. |
| 2.9 | Reviewed runtime/backup boundaries implemented | Shared whole-value and semantic validation plus literal backup-account credential handling close the identified findings. This is not a whole-repository certification. |
| 2.10 | Implemented | Optional CBC/PBKDF2 encrypted config; AEAD is a separate decision. |
| 2.11 | Implemented | Four compatibility entrypoints share `runtime/stack/entry.sh` and recipe logic. |
| 2.12 | Partial | Working runtime/services layers; deeper extraction is R8. |
| 2.13 | Implemented | CI lints Nginx modules. |
| 2.14 | Implemented | Obsolete CI variable references removed. |
| 2.15 | Implemented | Bats behavior/fixture tests and Linux CI; directory-name deviation is intentional. |
| 2.16 | Implemented | Site-list plugin and registry/export wiring. |
| 2.17 | Implemented | Shared text/JSON config/FPM/certificate/modern-state views, credential redaction and recovery behavior. |
| 2.18 | Implemented | Protected SQL operations/scheduling/retention plus ownership-resolved positional domain shortcuts. |
| 2.19 | Implemented | Bun installer/remover, options and recipe wiring. |
| 2.19B | Implemented | Valkey repo/source branches and shared removal; separate filenames are unnecessary. |
| 2.20 | Implemented | CrowdSec lifecycle, options and collections. |
| 2.21 | Implemented in source | Protected provider DNS-01 wiring; public issuance/renewal validation is a release gate. |
| 2.22 | Implemented | Spinners/counters delivered; ETA and optional pv restoration progress delivered with R12. |
| 2.23 | Implemented, consistency follow-through remains | Expanded/public help and common parser; site-show flag fixed in R2; public-path parser adoption is delivered in R7; compatibility adapters retain their grammar. |
| 2.24 | Implemented | TUI dashboard/logs/wizard; current command is `tui`. |
| 2.25 | Implemented and superseded | Shipped install templates now PHP 8.2–8.5. |
| 2.26 | Implemented and superseded | Default is 8.5; supported defaults can now be configured. |
| 2.27 | Implemented selected policy | MariaDB 11.4, curated repository reconciliation, canonical custom-TLS flag and checksummed OpenSSL 3.5.9 LTS source integration. |
| 2.28 | Implemented | Fail2ban enabled by default. |
| 2.29 | Implemented | ModSecurity/CRS present; NAXSI is opt-in/off by default. Public option is `INSTALL_MODSEC`. |
| 2.30 | Implemented | Certbot renewal deploy hook uses systemctl reload. |
| 2.31 | Implemented | Restricted account roles and explicit managed legacy privilege migration. |
| 2.32 | Implemented | Same delivered credential suppression/redaction goal as 2.4 and R2. |
| 2.33 | Implemented | Safe literal configuration loading across installer/CLI/encryption paths. |
| 2.34 | Implemented | EOL templates removed; inventory-based management/migration remains supported. |
| 2.35 | Implemented | Portable host-edit helpers; GNU sed in Linux CI/UAT is appropriate. |
| 2.36 | Implemented | Active shell code no longer depends on grep PCRE as described in the historical task. |
| 2.37 | Partial | Same migration workstream as 2.12 and Phase 9, R8. |
| 2.38 | Implemented with shared Linux test environment | Current tree has **39 Bats files / 482 declarations**. A2 aligns dependency preparation, root fixtures, and test locks; final verification is recorded separately from the initial audit. |
| 2.39 | Implemented | Debian 12 CI exists; its distro ShellCheck version need not match the explicitly pinned Ubuntu/release tool. |
| 2.40 | Implemented | Bashate in CI/release checks. |
| 2.41 | Implemented | TUI log streaming and refresh controls. |
| 2.42 | Implemented, capability gap closed by A3 | TUI delegates to public CLI and shares the application catalog; manual types offer vhost creation without an installation flag. Full deployment for those types remains deferred. |
| 2.43 | Implemented | ModSecurity status/report/tune and validation/rollback. |
| 2.44 | Implemented | systemd-resolved/ACME cache and deploy hooks. |
| 2.45 | Implemented | Shared update compatibility adapter/source bootstrap. |
| 2.46 | Implemented | Service/PHP security updater, EOL mitigation/migration and package checks. |
| 2.47 | Implemented | Updater tests/documentation; old test totals are historical. |

## Original audit verification (before P1 implementation)

- Read roadmap/architecture/README/developer plans, public defaults, entrypoints,
  registries, relevant runtime/service/legacy code, test declarations and CI.
- Checked exact candidate CI/publication state with `gh`; no release or workflow
  was triggered, and no GitHub issue/comment was changed.
- Counted 48 roadmap IDs and 358 test declarations in 29 Bats files. These are
  source counts, not a new test run. Previously recorded results include 358 Bats
  tests, 13 archive-bootstrap cases, 55 mail checks and 11 PHP/Laravel checks;
  see [RELEASE_V4.md](RELEASE_V4.md), [MAIL.md](MAIL.md), and
  [PHP_RUNTIME_LARAVEL.md](PHP_RUNTIME_LARAVEL.md) for their separate baselines.
- Podman connection was unavailable. An attempted isolated site-show parser
  reproduction could not execute; the JSON/metadata findings above are based
  on the inspected parser/dispatch/file-writing paths.
- No installers, package/service/firewall changes, destructive restores, or
  private credential/configuration reads were performed. Only audit/roadmap
  documentation is refreshed; runtime tests are not claimed as rerun.
- `git diff --check` passed. All 45 local Markdown paths/heading references
  across the four updated documents resolve; the final diff was reviewed.

## P1 implementation validation

The implementation used the restarted Podman machine and designated disposable
containers. The source mount stayed read-only, synthetic profiles/passwords were
created inside those containers, and no workstation/live service was changed.

- Focused database/diagnostic/key-scope regression checks: 31 cases passed,
  followed by the final nine-case key-scope suite including the additional
  mixed-primary-key fingerprint regression. A real pinned PPA key download
  also passed the final fingerprint check.
- Real Ubuntu 24.04 ARM64 P1 UAT: 30 checks passed, including repository migration
  and repeat installation, installed PHP 8.4, MariaDB restoration, cron execution,
  protected credentials and JSON/text diagnostics.
- Debian 12 ARM64: PHP/Sury key download and signature processing worked, but
  package indexes disagreed with the signed Release checksums. Default, gzip and
  by-hash/no-cache retries failed; native PHP installation remains unverified.
  No signature, TLS or checksum controls were disabled.
- The retained bundled MariaDB helper rendered scoped Debian 12 source output.
  Its historical distro table still rejects Ubuntu 24.04; normal installation
  now uses the new direct APT driver rather than this helper.
- The generic Podman lint invocation initially failed on a new header formatting
  mistake (corrected), plus existing test-literal/compatibility diagnostics from
  distro ShellCheck 0.9. The CI-pinned ShellCheck 0.11 checks are recorded separately.

- Full Bats suite: **385/385 passed** before the final fingerprint regression
  was added; the final nine-case key suite then passed. Current source declares
  386 tests in 31 Bats files; this does not claim a separate 386-case full run.
- CI-pinned ShellCheck **0.11.0**, with `-s bash -x`, passed across CLI, core,
  runtime/service/compatibility modules and installer/server/Nginx scripts. The
  changed files and P1 UAT fixture passed focused lint as well.
- Changed Bash files passed syntax checks and Bashate with repository CI options.
  The final diff passed `git diff --check`; local documentation paths resolve.
- Test containers were stopped after verification; their private synthetic logs
  remain available. No commit, push, release publication or archive rebuild was
  performed.

## P2 implementation validation

- Existing command, account, TUI, mail, bootstrap and full-stack behavior tests
  passed after wrapper/module migration; source-only modules remain inert.
- Full Bats suite: **394/394 passed** after the final ownership regression and
  recovery changes. Focused migration/entrypoint/lifecycle tests also passed.
- Real UAT passed 51 checks on Ubuntu 24.04 ARM64 in a fresh designated systemd
  Podman container, with a read-only project mount and an internal code snapshot.
  Checks cover restored application/mail bytes, SQL/data retention, real scheduled
  jobs, Monit health/authentication and alert syntax, actual SSH key authentication,
  IPv4/IPv6 allowed/blocked connections, scoped rule reload/removal, UFW migration,
  recovery callbacks during a held shared lock, and preserved data/configuration.
- Remote Restic destination permissions/integrity and external SMTP delivery were
  not exercised. Broader distro/architecture/provider networking remains deployment
  validation. No workstation or live-service changes were made.
- ShellCheck 0.11.0 with sourced-file analysis, Bash syntax checks and Bashate
  with repository CI options passed for changed code and the recovery/UAT scripts.
- `git diff --check` passed; all 68 local Markdown references in changed guides
  resolve. Initial structural test failures were corrected to inspect moved
  implementations; behavior checks still exercise the installed wrappers.
- UAT exposed IPv6 listener readiness and repeat-fixture key setup issues; those
  fixtures were corrected and the extended 51-case suite rerun successfully.
- P1 was committed as `363945d`; this report records the P2 follow-through. No push, release
  publication or final release-archive rebuild was performed.

## P3 validation — 2026-11-21

- Final full synthetic Bats run with coverage instrumentation: **418 tests passed**.
- Scoped function-entry coverage: **33/35 (94.3%)**. This is not line/branch coverage.
- ShellCheck **0.11.0** with sourced-file analysis, Bashate using CI options,
  Bash syntax checks, and the opted-in shfmt **3.8.0** gate passed.
- Real Podman ARM64 UAT: **41 checks on Ubuntu 24.04** and **41 on Debian 12**,
  including kernel disk/inode enforcement, plan upgrades/downgrade rejection,
  locked failed provisioning, interrupted recovery, retained data and pv TTY transfer.
- Project mounts were read-only. Disposable loop-backed ext4 volumes were
  unmounted and both quota UAT containers stopped after validation.
- Workflow YAML, affected documentation references and tracked/new-file whitespace
  were checked. New GitHub Actions jobs are configured but have not been run remotely.
- Validation covered the P3 working tree before commit; final clean-candidate release
  assets and publication still require the release workflow and authorization described above.

## Prioritized follow-through validation — 2026-11-22

- Full synthetic Bats suite: **437 tests passed**; scoped Bash function-entry
  coverage: **54/62 (87.1%)**. This does not measure line/branch coverage.
- ShellCheck **0.11.0** with sourced-file analysis, Bashate using CI options,
  Bash syntax checks and shfmt **3.8.0** checks passed.
- Final real Ubuntu 24.04 ARM64 UAT: **47 checks passed**, including actual
  certificate issuance/verification, preserved templates, HTTPS/FPM, domain DB
  backup/restore/scheduling, signed PGDG/Redis indexes, verified native Bun, and
  Nginx 1.30.7 built against OpenSSL 3.5.9 with live HTTPS and QUIC configuration.
- Fresh Debian 12 ARM64 UAT: **37 service/CLI checks passed**, including real
  SQL recovery, certificates, FPM/diagnostics, signed indexes and native Bun.
- Earlier fixture failures were corrected: distribution-specific PHP-FPM naming,
  frozen script/core logging setup, and `/run` exhaustion from upstream test binary
  builds. Final compilation used `/var/tmp` and omitted those unused executables;
  application tests and live TLS checks were retained. No TLS/signature checks were disabled.
- HTTP/3 module loading/UDP binding were validated; client HTTP/3 negotiation and
  0-RTT were not tested. Native amd64 CI jobs are configured but were not run remotely.
- Source mounts stayed read-only. The audit was committed as **14377b0**;
  implementation validation covered the reviewed working tree before commit. Release-archive
  rebuilding/publication and remaining deep legacy extraction are separate work.

## Current audit verification — 9b7511b, 2026-11-22

- Reconciled **48 unique roadmap IDs** with the audit table, current source,
  public defaults and test/workflow wiring. Source count: **437 test declarations
  in 35 Bats files**; this is not a new full-suite result.
- In the existing designated Ubuntu 24.04 ARM64 Podman container, ran
  `bats --print-output-on-failure tests/unit/db_backup_restore.bats` with separate
  temp directories and `LEMPER_OPERATION_LOCK` paths for each identity:
  **18/18 passed as root; 12/18 passed as nobody**. Unprivileged failures included
  `Unsafe database backup directory.` and the public scheduling dry-run case.
  Initial probe setup/working-directory failures were resolved; a shared lock
  created by the unprivileged probe also interfered with the first root run.
  The final comparisons used isolated locks. No runtime ownership check was relaxed.
- Extracted only the inspected `enable_mariabackup` function into an isolated
  probe. Stubbed the database, logging and configuration persistence, redirected
  all writes into a temporary fixture, and used synthetic credentials. Observed
  **0644** credential configuration under umask `022`, mismatched persisted/read
  key names, quoted-password configuration failure, and no repair when an
  existing account lacked configuration. This did not test physical backup,
  package installation, or actual SQL account provisioning.
- Inspected the CLI/TUI and placeholder application branch; no Mautic/Roundcube/
  Sendy download or application installation was attempted. Existing OCSP
  template directives and the `mariadb-backup` package mapping were cross-checked.
- Queried GitHub with `gh` using the **full candidate SHA**: no Actions runs
  returned. Exact v4.0.0 release lookup returned `release not found`; latest
  published release is **v3.6.0**, published 2026-10-27. No workflow, issue,
  release, tag, push or commit was created.
- This audit changes documentation only. Bash lint/full Bats/UAT/build checks
  from the preceding implementation are historical and were not rerun here.
  Markdown paths/anchors and whitespace were checked; the final diff was reviewed.
  Source mounts stayed read-only, temporary probe state was removed, and the
  container started for the audit was stopped afterward.

## Current P1 implementation verification

- Final shared Podman test entry point: `bash scripts/test_podman.sh --test`,
  **456/456 passed** in a fresh Ubuntu 24.04 ARM64 container with a read-only
  checkout mount and root fixtures. Debian 12 ARM64:
  `bash scripts/run_tests.sh --coverage /var/tmp/lemper-p1-complete-coverage`,
  **456/456 passed**, scoped Bash function-entry coverage **61/68 (89.7%)**.
  This does not measure Python line/branch coverage or prove whole-stack installation.
- **19 new backup-account regressions** cover literal credential/option/profile
  round-trips, canonical/legacy keys, safe account repair, privacy during DB
  failure, inline migration and option precedence, encrypted profiles, read/write
  failures, RNG failures, legacy lock enforcement, unsafe input/include paths and
  escaped controls. The final quoted-include path correction was additionally
  verified by its focused regression and the independent review.
- Native Ubuntu 24.04 and Debian 12 ARM64 UAT each passed **22 checks** through
  [the provisioning acceptance suite](../tests/uat/p1_provisioning_acceptance.sh),
  including SQL authentication, unchanged existing password hashes, missing-file
  repair, credential recovery, standalone installer reconciliation, actual
  `mariadb-backup --backup`/`--prepare`, and inline credential migration.
  These are scoped native component checks, not final release-archive UAT.
- Independent read-only fix review is clean in the P1 scope. Confirmed review
  concerns were fixed and exercised with synthetic fixtures; no real credentials
  or live servers were involved.
- Changed Bash files passed Linux syntax checks, ShellCheck **0.11.0** with
  sourced-file analysis, Bashate with CI options, and the opted-in shfmt **3.8.0**
  gate. Python helper syntax and actual option parsing were checked. Initial
  fixture, structural-lint and test-environment failures were corrected without
  relaxing runtime path, ownership, SSH or credential controls.
- Documentation links/anchors and `git diff --check` passed. Only disposable
  containers were used for system changes; containers started for this work were
  stopped after verification. No commit, push, workflow trigger or publication
  was performed. Candidate CI and final archive validation remain release gates.

## Initial A3 implementation verification — 2026-11-22

- `podman exec -w /source lemper-p1-provision-ubuntu24 bash scripts/run_tests.sh`:
  **465/465 Bats tests passed** on Ubuntu 24.04 ARM64, using the shared root
  fixture and a read-only checkout. Nine capability regressions cover all install
  aliases, rejection before mutations, invalid types, dry runs, placeholders,
  real marker requirements, ownership recording and wizard choices.
- The final frozen copy of
  [application acceptance](../tests/uat/application_capabilities_acceptance.sh)
  passed **29 checks** in the designated Ubuntu 24.04 ARM64 systemd container.
  Unsupported Mautic/Roundcube/Sendy installation produced no vhost/project;
  their manual vhosts served synthetic PHP through real per-user FPM pools.
  CodeIgniter **4.7.6** installed production dependencies as the site user,
  produced project/vendor files and ownership state, passed `nginx -t`, and
  served its actual welcome page. This host used distro Nginx **1.24.0** and PHP
  **8.3.6**; these functional checks do not establish current security-patch
  currency or final release-archive readiness.
- Installed public help also passed as `nobody`. Changed Bash files passed Linux
  syntax checks, ShellCheck **0.11.0** with sourced-file analysis, CI Bashate
  options and the shfmt **3.8.0** gate. Local links in all seven changed Markdown
  files and `git diff --check` passed.
- Initial UAT failures exposed missing distro-host LEMPer Nginx/FastCGI templates
  and a PHP DOM prerequisite for the old development-dependency install. The
  fixture now uses complete tracked templates from its immutable CLI snapshot;
  CodeIgniter's Composer path uses distribution archives and `--no-dev` as the
  runtime user. The slow old source-clone run was stopped before repeating UAT.
- Other automatic installers, Debian A3 native deployment, public ACME and exact
  candidate archives were not validated in this scope. Full manual-app installers
  remain deferred, and A4 decomposition remains partial. P1 is committed in
  **79d4d40**; A3 remains uncommitted. No push or publication was performed.

## Complete Mautic/Roundcube release verification — 2026-11-23

- The shared Ubuntu 24.04 ARM64 runner passed **473/473 Bats tests**. The affected
  release/capability/alignment suites passed **44 checks** after final changes.
  Seven release regressions cover flattened package publication, preservation,
  checksum/download/platform/marker failures, dry runs including direct legacy
  entry, unsafe targets, archive traversal/links/duplicates and literal rendering.
  Wizard and CLI tests cover Mautic/Roundcube installation aliases.
- The final frozen [native acceptance suite](../tests/uat/application_capabilities_acceptance.sh)
  passed **57 checks** in the designated Ubuntu 24.04 ARM64 systemd container.
  Actual pinned Mautic **7.2.2** and Roundcube **1.7.6** packages were downloaded,
  SHA-256 verified and extracted as the hosting user. Their upstream setup pages,
  stylesheets and Mautic favicon served through PHP-FPM/Nginx; private files,
  real unauthorized PHP probes and non-loopback setup requests were blocked.
  Configuration directories/receipts were private, repeated deployments retained
  a custom configuration fixture, and ownership records contained no fictional
  database. Manual vhosts, Sendy rejection and CodeIgniter HTTP remained covered.
- The host used distro Nginx **1.24.0** and PHP **8.3.6**. This is functional
  deployment evidence, not current patch-currency or release-archive certification.
  Unattended database/admin/SMTP/IMAP setup, live mail login/delivery, other PHP
  versions, Debian deployment and final archives were not tested in this scope.
- Changed Bash files passed syntax checks, sourced ShellCheck **0.11.0**, CI
  Bashate options and shfmt **3.8.0**. Python syntax, local documentation references
  and whitespace checks passed. The initial renderer delimiter error was fixed
  and covered by a regression. A narrow bundled-image route resolves Mautic's
  favicon restriction while other `app/` paths remain denied.
- Runtime/service exports include the release driver, renderer and extraction
  helper. Documentation distinguishes complete-file deployment from upstream
  setup and explains protected setup access. A4 decomposition and publication
  gates remain. These changes are uncommitted; no push or publication occurred.

## Latest-stable application release selection — 2026-11-23

New Mautic/Roundcube installs now resolve GitHub's `releases/latest` metadata
at installation time. The [metadata helper](../lib/services/site/release_metadata.sh)
requires a stable release, an unambiguous complete asset, its expected official
GitHub URL and a published SHA-256 digest. Fixed application version/digest pins
are removed; metadata errors never fall back to a previous version. A deployment
uses one resolved metadata snapshot. Dry runs and preservation of an existing
valid installation do not query the API or perform upgrades.

- **46/46 focused Bats tests passed**, including synthetic future Mautic and
  Roundcube versions, optional `v` tags, complete-asset selection, malformed or
  unstable metadata, missing/wrong digests, unsafe URLs and duplicate assets.
  Failure, preservation and direct legacy dry-run regressions remain covered.
- **57/57 native Podman acceptance checks passed** on Ubuntu 24.04 ARM64 through
  the installed CLI, dynamically resolving the current stable Mautic **7.2.2**
  and Roundcube **1.7.6** packages. HTTP/setup/assets, privacy, ownership and repeat
  preservation checks remained unchanged. These are observed versions, not pins.
- Changed Bash syntax, sourced ShellCheck, CI Bashate options, shfmt and Python
  syntax checks passed. Documentation now describes dynamic latest selection.
  The prior 473-test full suite remains historical; the full 475-test suite and
  other distributions/PHP versions were not rerun for this scoped change.
  Changes remain uncommitted; no push or publication occurred.

## Additional application deployment verification — 2026-11-23

- The shared Ubuntu 24.04 ARM64 runner passed **482/482 Bats tests**; final
  affected suites passed **53/53 tests**. New tests cover all app installation
  choices, licensed-download rejection, package/provider selection, exact
  Nextcloud distribution matching, GitHub source/MyBB Upload extraction, bounded
  internal-file alias copying, OJS default configuration/storage and Unix-socket
  rendering. Source-only and CLI compatibility checks remain intact.
- The [additional native suite](../tests/uat/additional_applications_acceptance.sh)
  passed **66 checks** on Ubuntu 24.04 ARM64, PHP **8.3.6**, distro Nginx **1.24.0**.
  It installed SnappyMail **3.1.4**, Nextcloud **35.0.3**, MyBB **1.8.41**, OJS
  **3.5.0-6**, phpList **3.6.17**, and Slim skeleton **4.5.0** with Slim framework
  **4.15.3**. These are observed current releases, not source pins.
- Real setup/login pages, Slim's users API and app stylesheets served through
  per-user Unix FPM sockets. Synthetic probes verified DAV `PROPFIND` method,
  `PATH_INFO`, query and body preservation, MyBB friendly-URL parameters,
  XenForo friendly-URL POST/query handling, and blocking of actual private files.
  The probes backed up/restored MyBB/Nextcloud entry files. XenForo's vendor
  application was not supplied or executed; its licensed manual vhost and
  synthetic PHP routing were validated. No license artifacts are distributed.
- phpList's admin HTTP test used a synthetic database configured with a protected
  password file inside the disposable host. Production deployment does not
  create or record an invented database. OJS generated its staged default with
  an owner-only external submission directory; existing customized configuration
  remains protected. Nextcloud's non-secret publication marker remains readable
  by Nginx while credentials/data stay private.
- Initial UAT exposed internal Nextcloud license-file links and expensive
  backwards tar seeking; aliases are now materialized from bounded cached bytes
  after one extraction pass. OJS's packaged default configuration is accepted
  without overwriting customized files. Fixture resumes refresh owned vhosts as
  one batch, preserving systemd's service limits; required jq is checked early.
  No TLS, authentication, ownership or file-security controls were disabled.
- Bash syntax, sourced ShellCheck **0.11.0**, CI Bashate options, shfmt **3.8.0**,
  Python syntax and documentation/whitespace checks passed. phpList/Slim source
  archives and PKP packages record verified-HTTPS provenance where no published
  asset digest exists; complete GitHub assets retain mandatory SHA-256 checks.
- Authenticated mailbox delivery/login, configured forum/journal/cloud workflows,
  other distributions/PHP versions and final release archives were not validated.
  Nextcloud setup logs warnings when it reapplies session-cookie options locked
  by the existing FPM policy; those security settings remain unchanged. The
  source deployment and HTTP checks do not establish security-patch currency.
  A4 decomposition and release/publication gates remain. Work is uncommitted.
