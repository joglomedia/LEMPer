# v4.0.0 release preparation

Status checked 2026-11-24: v4.0.0 is unpublished; latest GitHub release is
v3.6.0. The verified candidate is `9b3963e` on the pushed `release/v4.0.0`
branch. Accepted module decomposition (2.12/2.37) is implemented. Candidate CI,
reproducible assets and exact-archive acceptance passed; publication and the
selected production checks below remain separate steps.

## Verified candidate 9b3963e

[GitHub Actions run 45318207064](https://github.com/joglomedia/LEMPer/actions/runs/45318207064)
passed **24/24 jobs** for commit
**9b3963e34fa144bcf67d8aa69439675bddfb16ea**. This is committed-candidate evidence;
it supersedes older statements about missing remote CI or native AMD64 coverage.

| Gate | Verified result |
|---|---|
| Bash validation | **534 Bats tests**; Bash syntax, sourced ShellCheck 0.11.0 and Bashate passed |
| Formatting and coverage | Scoped shfmt passed; function-entry coverage **86/94 (91.5%)** |
| Exact archive on native AMD64 | **13/13** bootstrap/install/HTTP/SSH/repeat/remove checks on each of Ubuntu 24.04, Ubuntu 26.04 and Debian 12 |
| PHP/Laravel | **11/11** runtime/default/routing/authentication checks |
| Other native matrices | Maintained PHP archives, mail hosting, FTP source builds, hosting quotas, and priority lifecycle/TLS jobs passed |
| Full legacy installation | shunit2 installation, FTP service verification and provisioned-host audit/artifact upload passed inside a disposable systemd container |

Two fresh Linux builds of this clean commit produced byte-identical copies of
all four assets. Both checksum files verify. Local copies are retained under
`dist/v4.0.0/9b3963e/{first,second}/` (ignored by Git):

| Asset | SHA-256 |
|---|---|
| `lemper-v4.0.0.tar.gz` | `88e77d257d3cbab745af46d46cadda582de03fb7daffc507784b26a1d4461a40` |
| `get-lemper` | `775f1a528f5c6578e2f021368d45dec90f90f7bdf4c6c82938ad5fce3ed8e2b6` |

The downloaded CI coverage artifact is retained under `coverage/9b3963e-ci/`.
Coverage measures entry into the declared functions during synthetic tests;
it is not line/branch coverage or proof of every live transition.

The CI fixes stage public help code without exposing private profiles, wait for
systemd before fixture initialization, keep synthetic SSH keys under `/run`,
select the Composer PHP runtime and its extensions explicitly, isolate legacy
installation tests, and preserve audit-file ownership for uploads. Bootstrap
diagnostics emit code locations/status only and tolerate package child shells
that close the diagnostic descriptor. Nginx source resolution fails before build
mutations when discovery fails; CI resolves the current stable version through
authenticated GitHub metadata without passing a token into the installer.

See [production UAT](PRODUCTION_UAT.md) for protocol checks and external target
requirements. Public ACME, external mail/alerts and selected live migrations
are not established by container acceptance. Further commits change the archive
hash: build and validate the final committed candidate before tagging it.

Follow-through on this runtime baseline passed **537/537 local Bats tests**, **16
local protocol checks**, **19 local remote-backup/alert checks**, **13 VPS SFTP
checks over verified SSH access**, and **6 VPS-native QUIC/TLS checks**. The new
HTTP/3 CI job makes the protocol suite repeatable for subsequent candidates.
These checks preserve disabled early-data defaults and existing VPS services;
Internet port mapping, public ACME credentials and controlled external mail
targets remain pending as recorded in the production checklist.

## Remaining release steps

1. Complete the selected production UAT cases and record their targets/results.
2. Commit the reviewed documentation/test changes, rebuild the resulting assets
   and review that exact commit's candidate CI.
3. Set the changelog release date and create/push the annotated `v4.0.0` tag
   when publication is authorized; tagged CI builds and publishes the assets.
4. Verify published checksums, downloads and README installation commands on a
   fresh disposable server.

## Historical candidate evidence

The sections below retain earlier implementation/validation results. Their
commit-specific CI and platform limits describe those snapshots, not the current
verified candidate above.

## Fixed release candidate d21b293

Commit **d21b29317f816e592bf8f76892a5759199de9afa** includes the shared release
acceptance gate and the Debian Fail2ban journal fix. Two clean Linux builds
produced identical archives, bootstraps and checksum files; both checksums verify,
and the archived Fail2ban driver matches the committed implementation.

Artifacts are retained under `dist/v4.0.0/d21b293/` (ignored by Git):

| Asset | SHA-256 |
|---|---|
| `lemper-v4.0.0.tar.gz` | `a113015032db9247600dbc467556d84a358292e5ca8054402071e116180fc446` |
| `get-lemper` | `775f1a528f5c6578e2f021368d45dec90f90f7bdf4c6c82938ad5fce3ed8e2b6` |

The full Ubuntu 24.04 ARM64 CI-instrumented run passed **524/524 tests**, with
**86/94 (91.5%)** scoped function-entry coverage. Coverage JSON/Markdown is retained
under `coverage/d21b293/`. Sourced ShellCheck, Bashate, scoped shfmt, workflow YAML
and embedded Bash checks pass; the affected installer/module/structural suite
passed **111/111**.

| Fresh archive acceptance | Result |
|---|---|
| Debian 12 ARM64/systemd | **13/13 passed**, including the running journal SSH jail and full removal |
| Ubuntu 26.04 ARM64/systemd | **13/13 passed**, including the running journal SSH jail and full removal |

The stopped fixture names are `lemper-release-d21-debian12` and
`lemper-release-d21-resolute`; private case logs remain under
`/var/log/lemper-uat/v4/`. Only public source/artifacts are mounted read-only.
Native acceptance uses source Nginx, PHP 8.5, native/scoped MariaDB selection and
package-only Certbot. The source Fail2ban installer retains its file backend;
new or forced repository installs select the journal backend.

GitHub returned no Actions runs for this full SHA; the release branch has not
been pushed. The committed gate runs Ubuntu 24.04/26.04 and Debian 12 on native
GitHub runners before tagged publication. Local acceptance is ARM64; native AMD64,
public ACME, remote integrations and live migrations remain separate validation.
No push, tag or publication occurred. These final verification notes are later
than the tested commit; after committing notes or other changes, rebuild/review
the final candidate through the archive gate before authorized publication.

## Committed candidate follow-through

This section records `a39e5f9` before the Fail2ban correction; use the fixed
candidate above for current release evidence.

Two Linux builds from the clean **a39e5f9b85f5dd78956b4b458fb87b1e6d9ae2f9**
checkout produced byte-identical archives, bootstraps and checksum files. Both
checksums verify, the bootstrap matches the committed source, and the archive
contains the extracted modules/docs without local profiles or keys.

Artifacts are retained under `dist/v4.0.0/a39e5f9/` (ignored by Git):

| Asset | SHA-256 |
|---|---|
| `lemper-v4.0.0.tar.gz` | `4356c086b861b2249da7f04ec4934b98009b3b52511be333aca8181e6d638ff7` |
| `get-lemper` | `775f1a528f5c6578e2f021368d45dec90f90f7bdf4c6c82938ad5fce3ed8e2b6` |

Release-command ShellCheck with sourced analysis, Bashate and scoped shfmt pass.
The original committed runtime passed **518/518** full Bats tests and **112/112**
bootstrap/structural regressions. The Fail2ban follow-up passed **524/524** with
CI instrumentation and **86/94 (91.5%)** scoped function-entry coverage, plus
**111/111** affected installer/module/structural regressions. Workflow YAML and
embedded Bash syntax/ShellCheck also pass.
Fresh Ubuntu 26.04 ARM64 exact-archive acceptance passed **13/13** checks,
including real installation, HTTP/SSH, repeat preservation and full removal.
The fixture `lemper-candidate-a39-resolute` is stopped; private case logs remain
under `/var/log/lemper-uat/v4/`. Debian 12 passed **12/13**: the SSH Fail2ban jail
failed because the journal-only image has no `/var/log/auth.log`. Package, PHP,
MariaDB, HTTP/SSH, preservation and full removal checks passed. A focused repair
with native journal bindings passed configuration validation, live SSH-jail
status and repeat restart while the auth log remained absent.

The follow-up service driver uses `backend = systemd` and `python3-systemd` for
repository installs, validates configuration before restart, and requires a live
client response before success. Source installs retain the file backend. The
archive suite now checks the running SSH jail and journal match. Six isolated
regressions cover configuration validation, dry-run dependencies and daemon
readiness; full-archive acceptance of the fixed candidate passed as recorded above.

Read-only GitHub checks found no Actions runs for the full candidate SHA and no
remote `release/v4.0.0` branch. `main.yml` already supports `release/**`; remote
CI requires pushing the reviewed commit/branch. This work did not push or trigger
a workflow.

The new reusable [release acceptance workflow](../.github/workflows/release-acceptance.yml)
builds twice, verifies both checksums, and runs the existing Bash archive suite
in disposable Ubuntu 24.04, Ubuntu 26.04 and Debian 12 systemd environments.
Candidate CI calls it; tagged publication depends on it passing. The suite and
bootstrap are taken from the tested archive/assets. Source and artifact mounts
are read-only; only case summaries enter Actions output, while private installer
logs remain in the fixture. The native profile uses source Nginx and package-only
Certbot. Public ACME, remote integrations and live migration remain separate.

The hashes above identify `a39e5f9` before the Fail2ban fix. Build and test the
fixed follow-up from a clean commit, then review that exact commit's CI before
authorized publication. Further documentation commits also require an asset
rebuild; the archive gate enforces that final source/asset relationship.

## Release contract

The candidate now includes Ubuntu 26.04, the maintained Sury PHP archive,
native Resolute MariaDB 11.8 and a Dovecot 2.4 template. See
[the platform choices and native checks](UBUNTU_26_04.md); historical baselines
below are not evidence of an in-place OS/database migration.

- `lemperctl` is the public CLI; `lemper-cli` and legacy command aliases remain.
- `get-lemper --version 4.0.0` installs only the CLI and preserves configuration.
- `--install --config FILE [--minimal] [--yes]` selects full installation.
- `lemperctl stack install|remove|update --all` and the four compatibility
  scripts use the same profile/lifecycle adapter.
- Minimal installs select Nginx, PHP, MariaDB, Certbot, Fail2ban, and CLI tools;
  disabled services and web panels are skipped. SSH/firewall settings stay explicit.
- Dry runs validate without changing services, configuration, or CLI activation.
- Explicit full installs preserve generated credentials when template values are
  empty, back up existing configuration, and store the effective profile.

## Artifacts

`scripts/build_release.sh 4.0.0 OUTPUT_DIRECTORY` requires a clean committed
checkout with matching CLI/changelog versions and produces:

```text
lemper-v4.0.0.tar.gz
lemper-v4.0.0.tar.gz.sha256
get-lemper
get-lemper.sha256
```

The verified candidate artifacts are under `dist/v4.0.0/9b3963e/` (ignored by
Git). Older preparation assets under `dist/v4.0.0/` came from earlier commits or temporary snapshots.
Use the assets for the exact reviewed commit and rebuild after further commits.

## Validation

The results below were recorded on 2026-11-20 against the earlier v4 working
tree and its temporary public-source archive. They are historical preparation
results, not a rerun against the latest candidate.

| Check | Result |
|---|---|
| Full Bats suite | 329/329 passed |
| Fresh Podman archive bootstrap/service UAT | 13/13 passed |
| ShellCheck 0.11.0 with sourced-file analysis | Passed |
| Bashate with CI options | Passed |
| Bash syntax | 112 shell files passed |
| Workflow YAML | 2 workflows parsed |
| Local Markdown links | 39 links resolve |
| Whitespace/diff checks | Passed |
| Archive and bootstrap integrity/reproducibility | SHA256 verified; repeated builds match |

Subsequent mail and PHP/Laravel commits advanced the source to 523d686.
Separate records cover 358 Bats tests, 55 mail acceptance checks and 11
PHP/Laravel checks; see [MAIL.md](MAIL.md) and
[PHP_RUNTIME_LARAVEL.md](PHP_RUNTIME_LARAVEL.md). Rebuild all four assets from
the final clean committed candidate and test that exact archive before
publication. GitHub Actions returned no runs for 523d686 on 2026-11-21.
The [current roadmap audit](ROADMAP_AUDIT.md) separates remaining implementation
scope from release/deployment validation. Podman was unreachable during that
documentation audit, so no runtime checks were rerun then.

The final UAT used `lemper-v4-release-uat`, Ubuntu 24.04 ARM64 with systemd
PID 1, 2 CPU quota and 3 GiB memory, on the existing running Podman machine.
The source checkout was mounted read-only. It built Nginx natively and installed
PHP 8.5, MariaDB, Certbot, Fail2ban and the CLI from the local release archive.

The 13 real cases covered invalid-profile rejection before activation, full
bootstrap installation, strict encrypted configuration, active core services,
disabled optional services/panels, PHP HTTP, pinned release selection, repeat
bootstrap/config preservation, both command aliases, strict SSH key login,
legacy update checks, site purge, and complete owned-stack removal.
No PHP 8.4 packages were introduced during the PHP 8.5 install, and no PHP 8.5
packages or CLI aliases remained after teardown.

Earlier native attempts exposed the archive guard's rejection of systemd
`@` filenames, generic PHP/XML metapackages selecting another branch, and
retained Nginx configuration blocking full teardown after the server stopped.
These were fixed and verified; teardown ownership is retained across failures
so a partial removal can be resumed. Regression tests also cover custom
encryption and atomic profile replacement failure.

Final logs remain inside the stopped task containers:

```text
lemper-v4-release-uat:/var/log/lemper-uat/v4-summary.log
lemper-v4-release-uat:/var/log/lemper-uat/v4/*.log
lemper-alignment-tests:/tmp/lemper-v4-complete-bats.log
lemper-alignment-tests:/tmp/lemper-v4-complete-shellcheck.log
```

All task containers were stopped after capturing results. Other containers and
Podman machine settings were preserved. Installer logs can contain synthetic
credentials; do not publish raw logs or backup contents.

Use the isolated Linux Bats/lint container for unit checks. Use a fresh,
explicitly designated systemd/Podman container for real service installation,
with a read-only source mount and synthetic credentials. Never run this full
installation/removal on the developer workstation.

The fresh bootstrap test uses the generated archive and its checksum with
`get-lemper --version 4.0.0 --archive FILE --sha256 DIGEST --install --config
FILE --minimal --yes`. It checks active core services, CLI version/aliases,
encrypted effective configuration, disabled optional services/web panels, HTTP,
repeat bootstrap, update checks, and full-stack removal.

## Limits and publication

P1 follow-through now has a separate component UAT suite in
`tests/uat/p1_acceptance.sh`. On 2026-11-21 its final source snapshot passed
30 checks on Ubuntu 24.04 ARM64, covering real SQL restoration, scheduled
execution, protected credentials, site diagnostics/JSON and scoped signing-key
migration. Debian 12's PHP package validation was blocked by upstream signed
package-index checksum mismatches; verification remained enabled. The retained
bundled helper renders scoped Debian 12 sources but retains its older distro
table; current MariaDB installation uses the new direct APT driver.
Validation also includes 385/385 full Bats cases followed by nine final key-scope
regressions, CI-pinned ShellCheck 0.11.0, Bashate and Bash syntax checks.
See [DATABASE.md](DATABASE.md) and [ROADMAP_AUDIT.md](ROADMAP_AUDIT.md).
These checks validate components from the working tree; the final release
archive still needs rebuilding and its own bootstrap UAT after commit.

MyGuard currently provides no compatible ARM64 Nginx binary, so native ARM64
validation uses the source profile. Public ACME HTTP/DNS challenges require
routable domains and provider credentials and are outside the local fixture.
Other distributions/architectures and interactive legacy installer flags were
not exercised by that historical native UAT. A4 module decomposition and native
nftables are now implemented with separate acceptance evidence. The previous broader service UAT is recorded
separately in [UAT_REPORT.md](UAT_REPORT.md).

After reviewing and committing the changes, set the changelog release date,
create the annotated `v4.0.0` tag, and push it only when publication is
authorized. The tag workflow runs checks and publishes all four assets.
Then verify the download/checksum and README commands against the published
release on a disposable server.

## P2 validation follow-through

The P2 component suite `tests/uat/p2_acceptance.sh` passed 51 checks on a fresh
Ubuntu 24.04 ARM64 Podman/systemd container. It exercised Restic data restoration,
SQL/data retention, scheduled jobs, Monit health/authentication and alert syntax,
real SSH key login, IPv4/IPv6 filtering, explicit UFW migration and independent
recovery during a held backup lock. Configuration/repositories remained after
component removal. These results do not replace final archive/bootstrap testing.
Remote backup destinations and external SMTP delivery remain separately scoped.
The final full Bats suite passed 394 cases, with ShellCheck 0.11.0, Bashate,
Bash syntax and documentation/diff checks passing.
See [ROADMAP_AUDIT.md](ROADMAP_AUDIT.md) for current checks and further extraction.

## P3 candidate additions (unreleased)

The candidate adds hosting disk/inode plans for administrator-enabled ext4 quotas
(issue #39), guarded quota/account provisioning and recovery, scoped formatting
and function-entry coverage artifacts, and interactive ETA/pv restore feedback.
See [HOSTING.md](HOSTING.md) for the enforced scope and filesystem prerequisites.
These changes require a fresh final committed-candidate asset build and exact
archive/bootstrap verification before release; no publication is implied.

Local P3 verification passed 418 Bats tests, the declared function-entry coverage
report (33/35), ShellCheck 0.11/Bashate/syntax/shfmt checks, and 41 real quota UAT
checks on each of Ubuntu 24.04 and Debian 12 ARM64. Project mounts stayed read-only;
quota test volumes were released afterward. These results cover the working tree,
not a published v4 archive or remote GitHub Actions run.

## Prioritized follow-through (2026-11-22, working tree)

The earlier partial scope for 2.8/2.9/2.17/2.18/2.27 now has shared validation,
curated repository migration, maintained/checksummed TLS builds, diagnostic view
parity and owned domain DB shortcuts. At this historical snapshot, older
installer/manager internals remained partial; accepted 2.12/2.37 extraction was
subsequently completed in `a39e5f9`.

Verification passed 437 Bats tests, ShellCheck/Bashate/syntax/shfmt checks, 47 real
Ubuntu 24.04 ARM64 UAT checks and 37 Debian 12 ARM64 checks. Ubuntu compiled and
ran Nginx 1.30.7 with OpenSSL 3.5.9, verified HTTPS and QUIC configuration. Client
HTTP/3/0-RTT and native amd64 execution remain unverified locally. These results
cover the reviewed working tree, not an immutable release archive or remote CI.
