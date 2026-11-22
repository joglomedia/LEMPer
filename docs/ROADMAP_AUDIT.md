# LEMPer roadmap implementation audit

Date: **2026-11-22**. Code baseline: **14377b0** plus the prioritized
implementation working tree, `release/v4.0.0`. The cross-check at 753c846 is
preserved below; the follow-through section records the resulting implementation.
Latest GitHub release checked: **v3.6.0**. v4.0.0 is not published.

This report supersedes the earlier 2026-11-20 audit; that snapshot remains in
Git history. It compares all **48 unique numbered roadmap IDs**, Architecture
§4, README plans, and developer-workflow proposals with current source and test
wiring. It identifies implementation gaps and release gates, rather than treating
historical problem descriptions or old file layouts as current bugs.

Priorities below are suggested delivery priorities, not vulnerability severity
ratings. Source presence does not prove every platform or live upgrade works.
This audit does not constitute a new security scan or upstream dependency audit.

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

The three P1 findings below are implemented in the current working tree:

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

P1 is committed as `363945d`. The current P2 working tree delivers:

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

| Tasks | Delivered follow-through | Limits / source |
|---|---|---|
| 2.9 | Whole-value shared FQDN/IPv4/username validation, semantic IPv6 compression/IPv4-tail checks, legacy wrappers using the same core, validation before site/SSL mutations, typed TLS source tags | [core predicates](../lib/core/validation.sh), [regressions](../tests/unit/validators.bats). Legacy text-result APIs and stricter status APIs retain their caller contracts. This is closure of the identified input boundaries, not a whole-repository security certification. |
| 2.8 / 2.27 | Shared backed-up repository reconciliation for PGDG/Redis/MongoDB/deadsnakes/MaxMind/Go PPAs, pinned published key identities, preflight of mixed stanzas/signature-bypass options, preservation of unrelated/shared trust; corrected custom TLS enablement and verified OpenSSL 3.5.9 LTS source integration | [catalog](../lib/services/apt/catalog.sh), [migration](../lib/services/apt/repositories.sh), [TLS builder](../scripts/nginx/nginx_ssl_builders.sh). MongoDB major changes require explicit reconciliation; unowned/shared keyrings are retained. The former Bun APT endpoint returns 404: its lifecycle now uses [checksummed official release binaries](../lib/services/bun/binary.sh) with native architecture selection and ownership checks. |
| 2.12 / 2.37 | Diagnostics extracted into a function-only runtime adapter and the existing Python JSON reader exported as a service helper; shared staged certificate issuance replaces CLI/manager duplication; repository and Bun lifecycle logic moved into service drivers | [show runtime](../lib/runtime/site/show.sh), [inspection](../lib/services/site/inspect.py), [certificate driver](../lib/services/ssl/certificates.sh). Installed exports include these helpers. Deeper extraction of legacy application rendering and older installer/manager bodies remains; decomposition stays partial. |
| 2.17 | Text/JSON views share Nginx/FPM content, certificate path/SAN/expiry/hostname details, legacy metadata, ownership state and nested application mounts; secret-bearing fields are redacted; Python import-path isolation and recovery views are preserved | [inspection driver](../lib/services/site/inspect.py), [diagnostic tests](../tests/unit/site_diagnostics.bats). Certificate trust-chain verification is not implied by a readable certificate; variable paths and indirect upstreams can remain unresolved. |
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
| CI for the candidate commit | GitHub Actions API returned **0 runs for 523d686**; successful runs on other commits are not candidate validation. | Run/review the candidate's jobs, including new mail and PHP/Laravel acceptance jobs. This audit does not authorize a push. |
| Final release assets | [RELEASE_V4.md](RELEASE_V4.md) records locally reproducible assets from an earlier temporary source snapshot. The mail/runtime commits came afterward. | Build from the final clean committed candidate, verify all four assets and their contents/checksums, then validate that exact archive/bootstrap. |
| Publication | Exact `gh release view v4.0.0` returned `release not found`; no local `v4*` tag was found. Latest published release is v3.6.0. | Set the release date, review/tag/publish after authorization, and verify published downloads and README one-liners. |
| Remaining deployment validation | Recorded native full-bootstrap UAT used Ubuntu 24.04 ARM64 with a source Nginx profile. Public DNS/ACME, broader architecture/distribution installation coverage, and some live legacy transitions remain unverified. | Test representative supported profiles and upgrades, real issuance/renewal with controlled domains, and SSH/firewall recovery in designated disposable environments. These are validation gates, not absent schema/bootstrap/SSH implementations. |

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
| 2.9 | Identified boundaries implemented | Shared whole-value validation and semantic IPv6 checks replace the reported legacy bypasses; valid legacy API behavior is preserved. |
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
| 2.38 | Implemented | Current tree has 32 Bats files and 394 `@test` declarations; original audit baseline was 29/358. |
| 2.39 | Implemented | Debian 12 CI exists; its distro ShellCheck version need not match the explicitly pinned Ubuntu/release tool. |
| 2.40 | Implemented | Bashate in CI/release checks. |
| 2.41 | Implemented | TUI log streaming and refresh controls. |
| 2.42 | Implemented | TUI site wizard delegates to public CLI. |
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
  coverage: **54/62 (87.1%)**. This does not measure Python line/branch coverage.
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
