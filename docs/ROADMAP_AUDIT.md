# LEMPer roadmap implementation audit

Date: **2026-11-21**. Code baseline: **363945d** plus the P2 implementation
working tree, `release/v4.0.0`.
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

## Remaining implementation work, in priority order

Ranks retain their audit IDs. R8's next step is further legacy management and
installer extraction; it is an incremental architecture workstream. Remaining
product/tooling proposals are:

| Rank | Priority | Plan / current status | Evidence and next deliverable |
|---|---|---|---|
| R10 | P3 | Hosting packages, per-user quotas and provisioning — README plan, unimplemented | Account roles and per-user FPM isolation are present; no hosting-plan schema, quota enforcement or package-provisioning lifecycle is implemented. Define limits and ownership first, then enforcement, upgrade and teardown behavior. Server-wide resource profiles do not implement tenant quotas. |
| R11 | P3 | Formatting/coverage tooling — developer §8.2, unfinished optional proposals | Bashate and ShellCheck are in CI. No tracked `.editorconfig`, `shfmt` enforcement or code-coverage publishing is present. Choose consistent tooling and add it without an unrelated mass-format change. The developer table's proposed `bandit`/`shellspec` examples need clarification: current host audit and dependency review are implemented, while a separate source-security workflow needs an explicit definition if desired. |
| R12 | P3 | Rich progress feedback — optional remainder of 2.22 | [utils.sh](../scripts/utils.sh), `run_spinner` and step progress are implemented. Integrated ETA and the suggested `pv` transfer progress are not. These are optional enhancements; the basic progress feature should remain marked delivered. |

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
- **TLS pins:** 2.27 proposed OpenSSL 3.3/3.4; the opt-in custom TLS pin is still
  `openssl-3.2.4-quic1`, and custom TLS defaults off. Resolve the maintained
  TLS/QUIC-library policy before treating a literal historical version as the
  next target. Upstream currency/advisories were not checked in this audit.
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
| 2.8 | Implemented | Deprecated calls removed and scoped PHP/MariaDB migration delivered in R3; shared legacy keyrings require review. |
| 2.9 | Implemented for audited boundaries | Site/account/SSH/domain validators and DB validation/execution follow-through R1 are delivered. |
| 2.10 | Implemented | Optional CBC/PBKDF2 encrypted config; AEAD is a separate decision. |
| 2.11 | Implemented | Four compatibility entrypoints share `runtime/stack/entry.sh` and recipe logic. |
| 2.12 | Partial | Working runtime/services layers; deeper extraction is R8. |
| 2.13 | Implemented | CI lints Nginx modules. |
| 2.14 | Implemented | Obsolete CI variable references removed. |
| 2.15 | Implemented | Bats behavior/fixture tests and Linux CI; directory-name deviation is intentional. |
| 2.16 | Implemented | Site-list plugin and registry/export wiring. |
| 2.17 | Implemented | Views, JSON flag/object output and diagnostic credential redaction are delivered in R2. |
| 2.18 | Implemented | Protected SQL backup/restore/import/export/scheduling and verified per-database retention are delivered. |
| 2.19 | Implemented | Bun installer/remover, options and recipe wiring. |
| 2.19B | Implemented | Valkey repo/source branches and shared removal; separate filenames are unnecessary. |
| 2.20 | Implemented | CrowdSec lifecycle, options and collections. |
| 2.21 | Implemented in source | Protected provider DNS-01 wiring; public issuance/renewal validation is a release gate. |
| 2.22 | Basic feature implemented | Spinners/counters delivered; optional ETA/transfer enhancement is R12. |
| 2.23 | Implemented, consistency follow-through remains | Expanded/public help and common parser; site-show flag fixed in R2; public-path parser adoption is delivered in R7; compatibility adapters retain their grammar. |
| 2.24 | Implemented | TUI dashboard/logs/wizard; current command is `tui`. |
| 2.25 | Implemented and superseded | Shipped install templates now PHP 8.2–8.5. |
| 2.26 | Implemented and superseded | Default is 8.5; supported defaults can now be configured. |
| 2.27 | Partial policy | MariaDB 11.4 and scoped keys are delivered; the custom-TLS target decision remains. |
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
