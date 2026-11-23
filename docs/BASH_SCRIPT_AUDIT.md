# Bash script audit

LEMPer-owned runtime, tooling and tests use Bash 5+ and standard Linux tools.
The November 2026 audit replaced all six standalone Python helpers and all
embedded Python in repository-owned orchestration and test drivers. A shebang
scan also found and replaced five extensionless bundled Perl helpers; tracked
SysV launcher templates now use Bash.

| Responsibility | Bash implementation | Native tools |
|---|---|---|
| Stable release selection and package provenance | `lib/services/site/release_metadata.sh` | jq, xmllint for PKP XML |
| Validated staged archive extraction | `lib/services/site/release_archive.sh` | GNU tar, zipinfo, unzip, coreutils |
| OJS initial configuration | `lib/services/site/release_prepare.sh` | awk, cmp, coreutils |
| Redacted site/FPM/app/certificate diagnostics | `lib/services/site/inspect.sh` | jq, awk, OpenSSL, GNU date |
| Trusted MariaDB include graph and control-escape checks | `lib/services/mariadb/option_guard.sh` | stat, realpath, tr, cmp; native my_print_defaults decodes options |
| Scoped function-entry coverage | `tests/report_coverage.sh` | jq, sed, awk, realpath |
| Bun release selection and exact binary extraction | `lib/services/bun/binary.sh` | jq, zipinfo, unzip, sha256sum |
| PHP migration path resolution | `lib/lemper-update.sh` | realpath/readlink |
| HTTP/JSON and profile UAT fixtures | `tests/uat/*.sh`, `helpers.bash` | curl, jq, awk |
| SMTP/IMAP UAT clients | `tests/uat/mail_helpers.bash` | Bash sockets/coprocesses, OpenSSL, base64 |
| IPv4/IPv6 firewall UAT clients/listeners | `tests/uat/p2_acceptance.sh` | socat, timeout, ip netns |
| Release and hostile-archive fixtures | `tests/unit/release_helper.bash` | tar, zip, jq; Bash writes hostile ZIP headers |
| Source-built Pure-FTPd configuration wrapper | `sbin/pure-ftpd-wrapper` | Bash arrays, ordered authentication links |
| Memcached foreground/compatibility launchers | `share/memcached/scripts/*memcached*`, `config.bash` | Bash parser, start-stop-daemon |
| Memcached statistics, binary dump and cluster monitor | `share/memcached/scripts/memcached-tool`, `damemtop`, `client.bash` | Bash sockets, socat, GNU dd, awk |

Release metadata remains constrained to official URLs and latest stable releases.
Full GitHub assets require a published SHA-256; HTTPS-only source releases retain
their distinct integrity receipt. Extraction audits every path, type, duplicate,
ancestor conflict and declared size before writing package data. It rejects special
objects and links, except validated internal Nextcloud file aliases, which become
regular copies. Limits remain 100,000 entries and 2 GiB of expanded package data.
Extraction runs as the hosting account into private staging and preserves existing
installations. No archive can publish into a populated project directory.

MariaDB option syntax remains the responsibility of my_print_defaults. The Bash
preflight checks trusted owners/modes, include cycles and unsafe decoded control
escapes before credentials reach its line-based output. Diagnostic configuration
is parsed as data, filtered/redacted before rendering, and never shell sourced.

Base installation supplies jq, unzip and libxml2-utils. Test setup supplies zip
for fixtures and socat for firewall UAT. Bashate is installed as a distribution
package when available; Resolute uses an isolated environment for this third-party
lint tool. LEMPer does not maintain a Python coverage or test runner.

Python/Perl packages still required by upstream Certbot, Fail2ban, SPF policy
services, CSF, Bashate or distribution tools remain supported. Embedded PHP in application
fixtures and PHP extension/platform checks exercises PHP itself; it is application
data or a native runtime probe. These are external/runtime dependencies, not
LEMPer-owned Python orchestration.

Memcached helpers install under `/usr/local/lib/lemper/memcached`, separate from
distribution-owned scripts. The instance service runs the foreground wrapper;
the legacy launcher uses start-stop-daemon to record its PID before privilege
dropping. Configurations without `-u` now default to the `memcache` service user.
Old LEMPer instance units are backed up before this migration. Existing
custom units and `/etc/damemtop.yaml` are retained. The Bash cluster monitor accepts
the shipped block-style YAML schema, arbitrary stats columns, rates, sorting and
computed hit/fill percentages. Advanced YAML objects/tags are rejected; `--once`
supports noninteractive sampling. Dump streams binary values without storing them
in Bash variables; cachedump remains the upstream protocol's best-effort key list.

Use the Linux checks in [DEVELOPER.md](../DEVELOPER.md). Synthetic Bats tests cover
failure, hostile-input, redaction, literal values and repeat/dry-run behavior;
native deployment, mail and firewall acceptance need their designated disposable
containers. Static checks alone do not prove those services work.

Validation on Ubuntu 24.04 ARM64 through Podman: 493 full Bats tests; 57 application
capability checks; 66 additional-application checks; 19 SMTP/IMAP mail checks;
11 bundled-helper checks; and 51 backup/monitoring/firewall checks, including real
IPv4/IPv6 enforcement and rollback. Latest Bun installation also passed with the
published checksum. A focused 56-test coverage run generated JSON and Markdown
function-entry reports. Pure-FTPd checks cover configuration/argument handling;
they do not establish a fresh source build or authenticated FTP transfer.
