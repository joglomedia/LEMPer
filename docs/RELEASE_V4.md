# v4.0.0 release preparation

Status: prepared locally; publication is a separate authorized step.

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

Validated on 2026-11-20 against the v4 working tree.

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

MyGuard currently provides no compatible ARM64 Nginx binary, so native ARM64
validation uses the source profile. Public ACME HTTP/DNS challenges require
routable domains and provider credentials and are outside the local fixture.
Other distributions/architectures and interactive legacy installer flags were
not exercised by the final native UAT. Deep driver extraction and an nftables
backend remain future work. The previous broader service UAT is recorded
separately in [UAT_REPORT.md](UAT_REPORT.md).

After reviewing and committing the changes, set the changelog release date,
create the annotated `v4.0.0` tag, and push it only when publication is
authorized. The tag workflow runs checks and publishes all four assets.
Then verify the download/checksum and README commands against the published
release on a disposable server.
