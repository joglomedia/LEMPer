# v4.0.0 release preparation

Status checked 2026-11-21: v4.0.0 is unpublished; latest GitHub release is
v3.6.0. Local preparation below records an earlier baseline. Current code is
363945d plus P2 working-tree changes on `release/v4.0.0`; final candidate
rebuild/validation remains.

## Release contract

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

The local preparation artifacts are under `dist/v4.0.0/` (ignored by Git).
They are generated from a temporary public-source snapshot; the main working
tree remains available for review. Rebuild from the final reviewed commit
before publishing.

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
not exercised by the final native UAT. Further legacy driver extraction remains future work; native nftables is now
implemented with separate P2 component UAT. The previous broader service UAT is recorded
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
