# LEMPer Roadmap Implementation Audit

Date: 2026-11-20. Baseline: the current working tree, with the prior `AGENTIC.md`
to `AGENTS.md` documentation change still uncommitted.

The statement that Phases 0–8 are complete is inaccurate. Most capabilities are
present, but the module migration remains deferred and several completed tasks
have unfinished acceptance criteria. Phase 9 is largely unimplemented. Its site
creation and update foundations already exist and should be extended.

This audit covers all 48 unique numbered tasks in `ROADMAP.md`, Phase 9, the
architecture work it incorporates, and additional plans in `README.md` and
`DEVELOPER.md`. It checks implementation in local source, mappings, and tests;
it does not establish that released packages or live servers behave identically.
GitHub issue #92 was evaluated through the specification reproduced in the
roadmap; the current remote issue was not fetched.

Priority is based on existing operational impact, then dependencies needed for
v4.0, then optional product and developer improvements. P1 means high priority;
P2 means follow after the foundations; P3 means optional or separately scoped.
These are delivery priorities, not vulnerability severity ratings.

## Implementation follow-through (2026-11-20)

P1 ranks 1–12 below now have working-tree implementations and regression tests.
The findings table is retained as the pre-implementation audit snapshot.
Current source adds shared core/schema/argument modules, safe credential and
site/account boundaries, provider DNS-01, SSH policy/rollback, stack/site commands,
pinned bootstrap, and release/host-audit workflows. Review CHANGELOG.md
Unreleased and ROADMAP.md Current P1 implementation for the resulting behavior.

Local verification (2026-11-20): all 262 Bats tests passed in a disposable
Ubuntu 24.04 container. ShellCheck 0.11.0, repository-configured Bashate, workflow
YAML parsing, and whitespace/diff checks passed. A fixture release was installed
inside that container; CLI help, per-service dry-run, and strict config check
succeeded. The security re-review found no remaining confirmed issues within
the reviewed boundaries. Live production installation, real DNS challenges,
SSH/firewall transitions, and GitHub publication were not performed.

P2/P3 work and the authenticated-encryption design decision remain open.
Deployment-level service, DNS, and publication validation has not been performed.

## Remaining work in priority order

| Rank | Priority | Plan / status | Evidence and remaining deliverable |
|---|---|---|---|
| 1 | P1 | Credential confidentiality — 2.4 / 2.32 and architecture §4.1; partial | The final installation recap is safe, but MariaDB writes its root and backup passwords through `save_log` at `scripts/install_mariadb.sh:357`; Redis/Valkey, MongoDB, PostgreSQL, and Memcached have equivalent calls. `save_log` appends plaintext to the installation log (`scripts/utils.sh:1361`). App creation prints admin and DB passwords (`lib/lemper-create.sh:1624`). Remove these exposures, keep protected retrieval, and test with synthetic secrets that neither logs nor default output contains them. |
| 2 | P1 | Complete the input-safety layer — 2.9; partial | Domain/IP validators and escaping helpers exist. However, site removal reads a web-root path and passes it to recursive deletion after checking only that it is a directory (`lib/lemper-manage.sh:184`). Add canonical path/ownership checks that reject system roots and unsafe targets, and apply consistent username/path validation at mutation boundaries. Test CLI paths, not just helper functions. |
| 3 | P1 | Complete restricted account privileges — 2.31 / architecture §4.1; partial | The default installer account and interactive adduser path use restricted sudoers. `lib/lemper-account.sh:96` still unconditionally adds a newly created CLI account to the full `sudo` group. `scripts/utils.sh:1255` skips existing accounts, so it does not migrate legacy privileges. Define explicit admin versus hosting-user privileges, align all account paths, and add a documented, deliberate migration for accounts LEMPer owns. Full sudo-group membership is distinct from the old `NOPASSWD:ALL` rule; do not describe this as the same vulnerability. |
| 4 | P1 | Finish automatic wildcard DNS-01 — 2.21; partial | Installer provider helpers exist (`scripts/install_certbotle.sh:173`), but `enable_ssl` still requests wildcard certs with manual DNS (`lib/lemper-manage.sh:384`), as does renewal (`lib/lemper-manage.sh:610`). The installer helper also requires `LEMPER_DOMAIN`, which is not declared in `.env.dist` or assigned by the normal site flow. Wire site issuance and renewal to protected provider credentials; define supported provider credential formats and remove the undeclared-domain dependency. Verify arguments with a stubbed Certbot and exercise renewal. |
| 5 | P1 | Configuration schema — Phase 9 / architecture §4.3; absent | `safe_parse_dotenv` validates key syntax and preserves literal values (`scripts/utils.sh:29`); it does not validate option names, types, ranges, allowed versions, or cross-option constraints. Add a shared schema for installer and CLI startup, reject invalid configuration before side effects, and retain compatibility with existing `.env` and encrypted config. YAML is optional; this task does not require changing format. |
| 6 | P1 | SSH key-only default and ed25519 — Phase 9; partial | Key authentication supports ed25519 input, but `.env.dist:89` sets `SSH_PASSWORDLESS=false`, `securing_ssh` defaults to false, and its key-generation instructions still use RSA (`scripts/server_security.sh:34`). Implement the intended default and ed25519 guidance/generation policy, with a validated key and a tested recovery path before disabling password access. |
| 7 | P1 | One argument parser — Phase 9 / architecture §4.3; absent | Some plugins use GNU `getopt`, while backup, bench, modsec, and update have separate hand-written loops. Examples: `lib/lemper-create.sh:867`, `lib/lemper-backup.sh:528`, `lib/lemper-update.sh:1819`. Extract a shared parser contract with common error/help handling and compatible existing flags. Add tests for missing values, unknown flags, `--`, and argument forwarding. |
| 8 | P1 | Split shared core helpers — Phase 9 / architecture §4.4; scaffold only | `scripts/utils.sh` remains 1,536 lines. `lib/core/` contains only `.gitkeep` and `lemper-stacks.sh`; there are no `config.sh`, `logging.sh`, `colors.sh`, or `cli.sh` modules. Extract the configuration, logging, colors, distro/network/security helpers and dispatcher with compatibility loaders. Consolidate behavior shared with `bin/lemper-cli.sh` where practical. Preserve sourced-shell and exit/return contracts. |
| 9 | P1 | Service lifecycle CLI — Phase 9; absent | No `lemper-stack` plugin or `stack` dispatcher exists. The shared orchestrator (`lib/core/lemper-stacks.sh:34`) installs/removes the configured set; it is not a per-service command registry. The existing updater covers PHP, Nginx, and MariaDB, not every installer. Add `stack install/remove/update` plus `start/stop/restart/reload/status`, a service allow-list, PHP version selection, and per-service tests. Preserve current commands. |
| 10 | P1 | Complete site verbs and compatibility — Phase 9; partial | `site create` already works. `site update` is installed as the legacy management plugin (`scripts/install_tools.sh:71`), which still expects action flags (`lib/lemper-manage.sh:1080`). Removal exists as `--remove`, but no `site remove` plugin/function is mapped by `lib/lemper-site.sh:46`. Implement the new removal verb and settle/update the documented update syntax, keeping existing `add`, `manage`, and `mod` aliases. Test fresh-install and updater mappings together. |
| 11 | P1 | Pinned CLI-only bootstrap and `lemperctl` — Phase 9; absent | There is no `get-lemper` entry point, release checksum bootstrap, versioned `/opt/lemper/<version>` installation, or `lemperctl` symlink. `update.sh` is a checkout-based updater that also refreshes admin tools; it does not satisfy this plan. Build a CLI-only bootstrap from a pinned release archive, verify checksum before extraction, preserve existing config, and create defaults only if config is missing. Integrate with the CLI's encrypted/plaintext config loading. Add `lemperctl` after the new verbs exist. Requires a release archive/checksum publication contract. |
| 12 | P1 | Security/dependency audit and release automation — Phase 9 / architecture §4.3 / developer §8.2; absent | `.github/workflows/main.yml` has lint, Bats, and installation/FTP jobs, but no host audit, dependency audit, or release publishing job. Add host checks in a disposable provisioned environment, dependency/source-version review appropriate to Bash installers, and tested release archives/checksums with version/tag/changelog consistency. A host audit and a source/dependency scan are separate checks. Prepare minimal release assets for rank 11; full publishing automation can follow. |
| 13 | P2 | Explicit UFW/nftables support — Phase 9; partial | UFW is implemented (`scripts/server_security.sh:180`), but the firewall setup ensures `iptables` is installed (`scripts/server_security.sh:557`) and contains no explicit nftables backend selection or verification. Implement and test the intended backend, migration, rule persistence, and IPv4/IPv6 behavior. Existing distributions may use an iptables-to-nft compatibility layer; absence of LEMPer integration does not prove every installed host uses legacy iptables. |
| 14 | P2 | Runtime/services migration — 2.12 / 2.37 / Phase 9; deferred | `lib/runtime/` and `lib/services/` contain only `.gitkeep`; plugins and installers remain in their old locations. Move them after the core interfaces are stable, updating install/update/CI paths and preserving installed host destinations and old source entry points. This is one shared migration task, not three independent features. Requires compatibility and upgrade tests. |
| 15 | P2 | Application/file backups — README plans; absent | `lib/lemper-backup.sh:40` explicitly excludes web content and database data; the delivered feature backs up configuration. Add one selected backup backend, protected local/remote repositories, scheduling/retention, integrity checks, and a tested restore of site data. Keep it separate from the existing config archive and SQL dumps. |
| 16 | P2 | Database backup rotation — 2.18 problem statement; partial | Timestamped dumps, restore, and cron scheduling exist (`lib/lemper-db.sh:313`, `:595`), but the plugin has no retention/prune implementation. Configuration archive pruning does not rotate SQL backups. Add an explicit retention policy and safe pruning, or revise the original task scope to make rotation a separately tracked follow-up. |
| 17 | P2 | Managed server monitoring — README plans; absent | The TUI and loopback Nginx/PHP status endpoints exist, but there is no Netdata/Monit/Nagios/Zabbix installer or equivalent managed metrics/alerting integration. Choose an appropriate backend, define protected access and alerts, and wire install/update/remove paths. Status endpoints alone do not fulfill this feature. |
| 18 | P3 | Hosting packages, per-user quotas, provisioning — README plans; absent | Account creation and FPM isolation are delivered, but no hosting plan model, quota enforcement, or package provisioning workflow exists. Define limits and persistence first, then implement enforcement and lifecycle tests. Depends on consistent account privileges and site/service contracts. |
| 19 | P3 | Coverage reporting and formatting tooling — developer §8.2; partial | Bashate runs in Ubuntu CI, but no `shfmt` or coverage-reporting step is configured. `.editorconfig` is also still absent despite developer-guide references. Decide formatting and coverage tooling compatible with Bash/sourced functions; add narrow checks without mixing a mass-format rewrite into feature work. These are supplementary plans, not Phase 9 release blockers. |
| 20 | P3 | Rich progress feedback — optional remainder of 2.22; partial | Step counters and `run_spinner` are present. ETA and `pv` download progress suggested in the task are not implemented. Treat these as optional enhancement criteria rather than reopening the delivered basic progress feature. |

## Specification differences that need decisions

- **2.10: encryption exists, GCM does not.** The implementation uses
  AES-256-CBC with PBKDF2 (`lib/lemper-encrypt.sh:148`, `bin/lemper-cli.sh:125`,
  `scripts/utils.sh:1433`). `lib/lemper-encrypt.sh:33` explicitly explains that
  `openssl enc` rejects AEAD ciphers such as GCM. Correct the roadmap's GCM
  completion claim. If authenticated encryption remains a requirement, track a
  format/provider migration with backward-compatible reads and tamper tests;
  changing the cipher name in the current command is not a solution. Optional
  encryption-at-rest functionality is already delivered and defaults off.
- **2.27: the version target changed.** MariaDB is 11.4 and signed keyrings
  are present. The optional custom TLS default is `openssl-3.2.4-quic1`
  (`.env.dist:118`), not the proposed OpenSSL 3.3/3.4 target. The changelog records
  OpenSSL 3.2 defaults and the HTTP/3 path uses quictls. Reconcile the intended
  version/library policy before assigning a new upgrade task. Upstream currency
  was not checked in this local implementation audit.
- **2.19B: Valkey is implemented in shared files.** Source and repository
  branches are in `scripts/install_redis.sh:134`; removal handles both backends
  in `scripts/remove_redis.sh:42`. The missing separate `install_valkey.sh` is
  a stale proposed file layout, not a missing runtime integration. Live source
  compilation and repository availability were not validated here.
- **2.15: test directory placement changed.** CLI/mock tests live in `tests/`
  and `tests/unit/`, not `tests/integration/`. Their location is not an unmet
  feature. Debian 12 and Ubuntu jobs exist; the Debian job runs lint/Bats rather
  than full service installation tests.
- **2.11: orchestration design changed successfully.** `install.sh`,
  `remove.sh`, and `lemper.sh` call one shared `lemper_install`/`lemper_remove`
  implementation. They need not become literal `exec ./lemper.sh` wrappers.

## Numbered-task reconciliation

"Present" below means implementation was found in current source/CI; it does not
mean a live installation was tested. "Partial" identifies remaining scope.
"Deviation" identifies a changed design or a claim requiring reconciliation.
Duplicate historical tasks remain listed so no roadmap ID is lost.

| Task | Audited status | Source / qualification |
|---|---|---|
| 2.1 | Present | No active `fial` call found; error paths use `fail`. |
| 2.2 | Present | Current PHP pool templates and generated pools disable `cgi.fix_pathinfo`; tests expect `off`. |
| 2.3 | Present for fresh installer accounts | `scripts/utils.sh:1260` replaces broad passwordless sudo with restricted service operations; broader account/migration gap is rank 3. |
| 2.4 | Partial | Safe stack recap at `lib/core/lemper-stacks.sh:206`; other default credential output/logging remains, rank 1. The proposed `--show-credentials` opt-in is absent. |
| 2.5 | Present | Old credential recap email delivery is gone from the shared orchestrator. Mail-server installation is unrelated and still supported. |
| 2.6 | Present | Literal dotenv loading in `scripts/utils.sh` and `bin/lemper-cli.sh`; focused tests pass. |
| 2.7 | Present | RSA-4096 certificate generation and SAN configuration in `etc/openssl/cert.conf`. |
| 2.8 | Present | Scoped `signed-by` repository keys; no active `apt-key` invocation found in shell source. |
| 2.9 | Partial | Validators/escaping and domain checks exist; consistent mutation/path validation remains, rank 2. |
| 2.10 | Deviation | Optional encrypted configuration exists, but uses CBC/PBKDF2, not the claimed GCM. |
| 2.11 | Present | One shared implementation in `lib/core/lemper-stacks.sh`; wrappers source it. |
| 2.12 | Deferred | Runtime/services layout migration remains, rank 14. |
| 2.13 | Present | CI runs ShellCheck on `scripts/nginx/*.sh`. |
| 2.14 | Present | Old `NGX_PAGESPEED` and `PHP_LOADER=none` CI toggles are gone. |
| 2.15 | Present with layout deviation | Bats/mock tests in `tests/` and `tests/unit/`; Debian and Ubuntu CI. |
| 2.16 | Present | `lib/lemper-site-list.sh` and installed `lemper-site-list` mapping. |
| 2.17 | Present | `lib/lemper-site-show.sh` and installed `lemper-site-show` mapping. |
| 2.18 | Partial | Dump/restore/schedule commands present; rotation from the problem statement absent, rank 16. CLI uses options rather than the proposed positional domain syntax. |
| 2.19 | Present | Bun installer/remover, defaults, and shared stack wiring. |
| 2.19B | Present with layout deviation | Shared Redis installer/remover handles Valkey; systemd template exists. |
| 2.20 | Present | CrowdSec install/remove, defaults, collections, and stack wiring. |
| 2.21 | Partial | Installer DNS provider helpers exist; site CLI issuance/renewal remains manual, rank 4. |
| 2.22 | Basic feature present | Counters/spinners exist; optional ETA/transfer progress absent, rank 20. |
| 2.23 | Present | Expanded CLI and plugin help; common parser is separate remaining scope. |
| 2.24 | Present with command-name deviation | TUI dashboard exists through `tui`/interactive options; the proposed `dashboard` alias is not registered. |
| 2.25 | Present and superseded | Shipped PHP templates are now 8.2–8.5, stricter than the historical 8.0 floor. |
| 2.26 | Present and superseded | Default PHP is now 8.5, newer than the proposed 8.4. |
| 2.27 | Deviation | MariaDB/keyrings updated; custom TLS version differs from proposed target. |
| 2.28 | Present | Fail2ban enabled by default. |
| 2.29 | Present | ModSecurity v3 and CRS are implemented; NAXSI remains opt-in/off by default. Actual option is `INSTALL_MODSEC`, not proposed `INSTALL_MODSECURITY`. |
| 2.30 | Present | Certbot renewal hook uses `systemctl reload nginx`. |
| 2.31 | Partial | Restricted installer/adduser paths present; full sudo CLI-account route and legacy migration remain, rank 3. |
| 2.32 | Partial beyond final recap | Final stack recap suppression delivered; credential confidentiality remains incomplete, rank 1. |
| 2.33 | Present | Safe literal loading across installer, CLI, and encryption helper; focused tests pass. |
| 2.34 | Present | EOL template removal and supported install floor; EOL vhost migration implemented in updater. |
| 2.35 | Present | `sed_inplace` helpers and migrated host calls. Raw `sed -i` inside Linux CI/container scripts is appropriate to those contexts. |
| 2.36 | Present | No active PCRE `grep -P` / `grep -oP` invocation found in shell source. |
| 2.37 | Deferred | Same runtime/services/core migration as 2.12 and Phase 9; ranks 8 and 14. |
| 2.38 | Present | Mock/fixture tests in `tests/unit/`; source now has 18 Bats files and 229 test declarations overall. |
| 2.39 | Present with version-claim drift | Debian 12 job exists; it installs distro `shellcheck`, not an explicitly pinned v0.11.0 binary. |
| 2.40 | Present | Bashate installed and run in Ubuntu CI. |
| 2.41 | Present | TUI live log menu and one-second refresh loop. |
| 2.42 | Present | TUI site wizard constructs create arguments and validates selections. |
| 2.43 | Present | `lemper-modsec` status/report/tune, audit-log-derived settings, config validation/rollback. |
| 2.44 | Present | systemd-resolved cache helpers and ACME deploy hooks; the separate DNS-01 wiring gap remains rank 4. |
| 2.45 | Present | `update.sh` checkout bootstrap and installation options. It is not the new pinned CLI-only bootstrap. |
| 2.46 | Present | `lemper-update` command, targeted service updates, EOL mitigations/migration, locking/logging. |
| 2.47 | Present with stale counts | Updater helper/migration tests and documentation exist. Historical test totals are stale. |

## Roadmap bookkeeping corrections

1. Change the top-level completion claim to acknowledge deferred 2.12/2.37 and
   partial credential, validation, account, DNS-01, and backup-retention work.
2. Phase 0's rollout table labels the CI-variable fix **2.6**, but that task
   is **2.14**; 2.6 is safe configuration loading.
3. Remove the claim that the directory migration risk is already mitigated
   (`docs/ROADMAP.md:895`). The migration and compatibility layer do not exist yet.
4. Reconcile old version targets and duplicated tasks with actual release
   history; do not count 2.12, 2.37, and Phase 9's layout item separately.
5. Correct GCM claims, Valkey file paths, PHP-version baselines, progress scope,
   and test counts. The current tree declares 229 Bats tests; this audit did not
   run all 229. Documentation totals of 107 or 198 do not prove current results.
6. Rename the architecture's obsolete "Proposed Target Architecture (v3.0)"
   heading to the actual v4.0 target, retaining historical context as needed.
7. Track README backup/monitoring/hosting plans separately and decide whether
   they belong to v4.0 or a later release; they currently have no roadmap task IDs.
8. Give each Phase 9 item an ID, acceptance criteria, dependencies, and a tested
   completion record. Existing helpers and symlinks count as partial foundations,
   not completion of the complete new command contract.

## Verification and limits

- Read current entry points, orchestrator, relevant plugins/installers, public
  defaults, configuration templates, test definitions, and CI workflow.
- Compared all 48 unique task IDs and Phase 9 against source; inspected declared
  modules/mappings and searched for missing schema, bootstrap, parser, audit,
  release, backup, monitoring, and quota integration.
- Ran `bats tests/unit/config_encryption.bats tests/unit/validators.bats
  tests/unit/dotenv.bats`: **16/16 passed** on the local macOS environment, using
  temporary fixtures and stubbed dependencies. These validate those helpers,
  not live Linux service behavior or all CLI paths.
- No installer/remover, account creation, firewall change, live ACME issuance,
  package update, or destructive restore was run. No private config was read.
- Only this audit report was added for this task; implementation and roadmap
  status edits are follow-up work.
