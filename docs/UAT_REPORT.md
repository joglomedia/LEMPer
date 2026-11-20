# Podman UAT report

Date: 2026-11-20. Target: the uncommitted `3.x.x` working tree, based on
`8e52740`. Procedure: [DEVELOPER.md §3.4.4](../DEVELOPER.md#344-real-installation-and-cli-uat).

## Results

The source-profile UAT passed all 23 real-service acceptance cases. The final
legacy installer run passed all 14 tests, and the full isolated Bats suite
passed all 308 tests. UAT-discovered defects were fixed and retested.

| Check | Result |
|---|---|
| Real CLI acceptance, source Nginx profile | 23/23 passed, exit 0 |
| Legacy installer tests, `shunit2/run_test.sh` | 14/14 passed, exit 0 |
| Full Bats suite, `bats tests/ tests/unit/` | 308/308 passed, exit 0 |
| ShellCheck 0.11.0 with sourced-file analysis | Passed |
| Bashate with the CI ignore list, including UAT scripts | Passed |
| Bash syntax | 106 shell files passed |
| Workflow YAML parsing | 2 workflows parsed |
| `git diff --check` | Passed |

An earlier CLI run finished at 21/23. CORS reload readiness and verification of
the custom checkout configuration backup were corrected before the final run.
The final checks require an actual FastCGI cache `HIT` with CORS headers, and
restore a deliberately modified synthetic configuration file before validating
Nginx and PHP HTTP again.

## Environment and provisioning

| Item | Value |
|---|---|
| Podman machine | `podman-machine-default`, running, libkrun, ARM64 |
| Machine resources | 4 CPUs, 3814 MiB memory |
| UAT container | `lemper-uat-ubuntu24`, Ubuntu 24.04 ARM64 |
| Service manager | systemd 255 as PID 1 |
| Container resources | 2 CPU quota, 3 GiB memory |
| Isolation | Privileged systemd container, private cgroup namespace, no published ports |
| Checkout | Project mounted read-only at `/source`; public code copied to `/checkout` |
| Separate unit-test container | `lemper-alignment-tests`; no LEMP provisioning |
| Nginx | 1.30.7, built natively from official source; PAM and cache-purge modules |
| Primary PHP | 8.5.13; PHP 8.4.28 installed and removed during acceptance |
| Database | MariaDB 11.4.14; PostgreSQL also provisioned |
| Certbot | 5.10.0; staging account registration passed |

Provisioning followed the guide's cleanup, dependency installer, and legacy
installer-test path. Initial failures were repaired in the disposable container
and in repository source. The final legacy run tested repeated installation on
that corrected provisioned environment. This was not a separate clean run of
the top-level `install.sh` after every fix. Fresh encrypted-configuration seeding
and preservation were also checked by isolated regression tests.

The synthetic profile uses PHP 8.5, the `small` resource profile, encrypted
installed configuration, key-only SSH on port 2269, PostgreSQL, Memcached,
Valkey, Pure-FTPd, and Fail2ban. It disables swap, firewall installation, MongoDB,
CrowdSec, mail, and public certificate issuance. The source Nginx profile also
disables ModSecurity and optional modules such as Brotli/VTS, keeping PAM and
cache-purge enabled.

## Real acceptance coverage

The acceptance script exercises 23 cases against installed packages and services:

| Cases | Evidence checked |
|---|---|
| Configuration and provisioned services | Strict installed-config schema; active Nginx, PHP-FPM, MariaDB, PostgreSQL, Memcached, Valkey, Pure-FTPd, Fail2ban |
| Database authentication and WordPress | Authenticated SQL query; installed WordPress responds over HTTP |
| PHP 8.4 install and HTTP | Real packages and per-user FPM pool; positional site creation serves PHP 8.4 |
| PHP restart, reload, status, update | All-version control and selected-version control/update |
| Batch CORS/cache and dry run | Both sites updated; PHP response carries CORS headers on a cache hit; OPTIONS returns 204; dry run preserves vhost hash |
| Site state and referenced-PHP guard | Disable/enable and repeated enable work; removal refuses PHP referenced by a managed site |
| TLS and SSH | HTTPS verifies against the generated CA; HTTPS disable returns to HTTP; strict host-key-verified SSH key login succeeds |
| Configuration backup/restore | Archive verifies; changed configuration is restored; Nginx validates and PHP serves HTTP afterward |
| Retained data and purge | Ordinary removal keeps content; explicit purge removes the owned webroot |
| Shared PHP assets and installed EOL branch | PHP 8.4 removal preserves PHP 8.5; new PHP 8.1 install is rejected; externally installed PHP 8.1 remains manageable and requires force to remove |
| WordPress database purge and surviving services | Owned database is deleted; Nginx, PHP 8.5, and MariaDB remain active |

## Fixes identified through UAT

| Observed problem | Repository change |
|---|---|
| Container-mounted `/etc/hosts` could not be replaced with a rename | In-place hosts updates retain the inode and unrelated aliases |
| Certbot could wait interactively or select the wrong account directory | Optional package-only installation; unattended account operations; configured-server account lookup |
| Sourcing installer helpers selected `/checkout/scripts` as the project root | Checkout-root default while preserving explicit overrides |
| Installed CLI configuration lacked installer settings or rejected its metadata | Validated fresh configuration seeding, immediate encryption, accepted hostname/SSH metadata, existing-config preservation |
| Source Nginx release lookup/download failed; cache-purge branch was obsolete | Explicit-version handling, official release-tag lookup and archive fallback, literal configure arguments, current cache-purge branch |
| MyGuard metadata selected incompatible binary/configuration packages | Reject repository installation when its selected Nginx binary is not supplied by MyGuard |
| Repeated site enabling and HTTPS enabling were unreliable | Idempotent site-state driver; existing certificates reused without implicit renewal |
| Ubuntu's socket-activated SSH listener did not follow updated policy | Socket-aware service-policy refresh and rollback reapplication |
| Operation-lock umask made public installer assets unreadable | Restore callback umask; executable public WP CLI asset |
| CORS directives failed at server scope or vanished in cached PHP locations | Valid server-scope snippet and per-site includes after active cache directives, preserving edited origin policy |
| Backup creation accepted a custom checkout `.env` that verification rejected | Permit the exact locally recorded/explicit legacy path after traversal and code exclusions |
| Detailed legacy command help fell back to global help | Command-specific public help before root/private-config loading |

## Limitations

- **Default MyGuard repository installation did not pass on ARM64.** Its
  `nginx-common` candidate was `3:1.31.9-1myguard2~noble`, but the Nginx binary
  candidate was Ubuntu's `1.24.0-2ubuntu7.21`. Source-profile success does not
  establish repository-profile compatibility.
- This run covers Ubuntu 24.04 ARM64. An AMD64 container probe returned
  `Exec format error`; Debian and other Ubuntu releases were not live-tested.
- TLS tests used a generated local CA with certificate verification enabled.
  Let's Encrypt staging account registration succeeded; public HTTP-01/DNS-01
  challenges and production certificates were not exercised.
- Disabled services/modules, interactive TUI flows, and externally reachable
  network/firewall behavior are not established by this run.
- Downloaded package versions reflect repositories on the test date; slow PHP
  PPA downloads affected runtime. The UAT does not pin every dependency.

## Reproduction and retained evidence

Use the container build, source-profile preparation, provisioning, and acceptance
commands in [DEVELOPER.md §3.4.4](../DEVELOPER.md#344-real-installation-and-cli-uat).
The safety guard requires root, Podman's container marker, systemd PID 1, and
`/run/lemper-uat/authorized`. Do not run this script on the workstation or a live
server. Do not run the ordinary Bats suite inside the provisioned container:
isolated unit tests may assume services are absent and remove provisioning.

Final acceptance evidence is retained in the UAT container:

```text
/var/log/lemper-uat/cli-summary-verified.log
/var/log/lemper-uat/cli/*.log
/var/log/lemper-uat/shunit-final.log
```

Unit/lint logs are retained in the separate test container:

```text
/tmp/lemper-final-bats.log
/tmp/lemper-final-shellcheck.log
/tmp/lemper-final-bashate.log
```

Logs and backups remain container-local; raw installer logs and backup archives
may contain synthetic credentials and must not be published. This report includes
no credentials, private keys, decrypted configuration, or backup contents.

After capturing results, both task containers were stopped. Other containers and
the running Podman machine were preserved. No commits or pushes were made during UAT.
