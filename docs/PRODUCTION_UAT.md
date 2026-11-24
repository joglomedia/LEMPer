# Production UAT for v4

Runtime candidate: **d79e4ec7443e10d4845ab5fc8f2300070e4a78d5**, 2026-11-25.
The [candidate CI](https://github.com/joglomedia/LEMPer/actions/runs/45466706385)
passed all 25 jobs, including committed-archive acceptance, PHP/Laravel, mail,
FTP, hosting quotas and priority lifecycle/TLS. The accepted 48 numbered tasks
are implemented or superseded. This checklist covers selected deployment checks
that exceed those automated results.

## Selected checks and evidence

| Case | Status | Scope |
|---|---|---|
| HTTP/3 negotiation and verified TLS | **16/16 local protocol checks passed** | Ubuntu 26.04 ARM64/systemd; Nginx 1.30.8 linked to verified OpenSSL 3.5.9, curl 8.23.0 with native OpenSSL/ngtcp2/nghttp3 |
| VPS-native protocol path | **6/6 passed on AMD64** | Separate Ubuntu 26.04 client and official Nginx 1.30.8/OpenSSL 3.5.9 server containers; QUIC through the VPS's private-address mapped port 18443, verified body/Alt-Svc and certificate/hostname rejection |
| Early-data default | **Passed locally and on the VPS** | Cached-session requests succeed with zero early-data bytes and the disabled setting. Enabled 0-RTT/application replay handling remains separate policy/validation work. |
| Restic/monitoring integration | **19/19 local checks passed** | Separate key-only SFTP/SMTP fixture, encrypted backup/check/staged restore/retention/scheduling and actual Monit failure/recovery messages captured privately |
| Restic on the public VPS | **13/13 passed over verified SSH access** | A separate PAM-enabled SFTP container reached through the existing encrypted SSH transport; strict host-key checks, scheduled execution, staged app/mail restore and retention passed |
| Internet-facing QUIC | **17/17 public protocol checks passed** | Second VPS, native AMD64 Nginx 1.30.8/OpenSSL 3.5.9; a separate ARM64 curl 8.23.0 client verified HTTPS, HTTP/2, QUIC, TLS 1.2/1.3, hostname/trust rejection and zero early-data bytes over public port 18443 |
| Public ACME DNS-01 issuance/renewal | **23/23 passed**, plus final renewal flag/preservation check | LEMPer CLI/driver, Certbot 5.10.0, staging and production wildcard/base issuance for a reserved subdomain under lemper.eu.org, installed Nginx deploy hook and repeat-install preservation |
| Public DNS operations | **6/6 passed** | Cloudflare TXT create/read/update/delete verified on both authoritative nameservers; complete existing record objects matched after cleanup |
| Public ACME HTTP-01 | **17/17 checks passed**, plus CLI issuance/repeat-enable | Let’s Encrypt staging, the exact v4 archive, an isolated Ubuntu 26.04 fixture, and only temporary public challenge files on the existing production route |
| External SMTP/IMAP and alerts | Pending transport/isolated mail endpoint | Both Gmail MX IPv4 probes failed on outbound TCP 25; Gmail submission on 587 connected, but the VPS has no configured Postfix relay |
| Legacy tooling upgrade | **13/13 checks passed** | Actual v3.6.0 CLI/plugins with distro services and synthetic data, upgraded using the exact v4 archive; full legacy installation/storage migration remains pending |
| Full upstream application setup | Pending selected app targets | Complete database/admin/mail/cron setup and HTTP health checks for selected application releases |

The local project mount is read-only. Package/service changes, generated keys,
private logs and restored data stay in task containers. Candidate archive hashes
and older platform results are in [RELEASE_V4.md](RELEASE_V4.md). Local protocol
checks do not establish provider firewall behavior, public DNS or mail deliverability.

The designated public server was accessed using the operator's recorded SSH key.
Existing rootless application containers were inventoried before testing and
retained their IDs, uptime and healthy status. New rootful UAT containers and a
private network carried the tests, with capped CPU/memory and unused test ports.
Host packages, existing proxy configuration and existing service containers were
preserved. The SFTP fixture kept PAM and key-only authentication; a collected
transient launch avoided inheriting the operator's audit login ID.

The repeatable [protocol preparation](../tests/uat/protocol_prepare.sh) and
[acceptance](../tests/uat/protocol_acceptance.sh) drivers are wired into the
Ubuntu 26.04 `HTTP/3 and TLS policy` CI job. The
[remote integration driver](../tests/uat/remote_integrations_acceptance.sh)
supports fixture-only alerts or `--restic-only` for an explicitly supplied backend.
Preparation and execution instructions are in
[DEVELOPER.md](../DEVELOPER.md#protocol-and-remote-integration-acceptance).

The client build verifies curl's published archive SHA-256 and enables its
experimental session-export facility for this test. [Upstream HTTP/3 build
requirements](https://curl.se/docs/http3.html) require a suitable TLS/QUIC library;
the early-data behavior follows [curl's documented option](https://curl.se/docs/manpage.html#--tls-earlydata).
Client session files, private keys and message captures are not release artifacts.

## Public follow-through, 2026-11-25

The tested source is `a7477b4` plus the hostname preflight correction discovered
during this UAT. Component preflight now skips a matching kernel hostname and
persistent hostname file; requested changes still run and failures return before
hosts updates. Three regression cases and the full **545/545 Linux Bats suite**
passed, together with Bash syntax, sourced ShellCheck and Bashate.

The second server runs production Ubuntu 22.04 services. UAT used separate
rootless containers and temporary, delegated systemd units: 0.5 CPU/512 MiB for
the Ubuntu 24.04 AMD64 ACME fixture and 0.25 CPU/128 MiB for the protocol endpoint.
No host packages were installed or upgraded. The old Podman 3.4 runtime required
the dedicated delegation; existing user/service configuration was preserved.
The final fixture image architecture was verified as AMD64 before launch.

The reserved hostname was `uat-v4-20261125.lemper.eu.org`. DNS-01 issued its base
and wildcard certificates through staging and production, and verified renewal
and the installed deploy hook. The production issuer was Let's Encrypt YE2,
with expiry 2027-02-22. The public protocol endpoint used the tracked SSL template
and shared HTTP/3 configuration driver. Its high-port fixture adjusted Alt-Svc
to 18443. curl 8.23.0 used OpenSSL 3.5.5, nghttp2 1.68.0, ngtcp2 1.16.0 and
nghttp3 1.12.0, with the checksum-verified build and experimental session export.
Enabled 0-RTT/replay handling remains a separate validation scope.

Initial public high-port requests did not reach the host rules. After the
operator opened provider TCP/UDP 18443, the checks passed directly over the
Internet. Temporary UFW rules allowed only the test client's IPv4 address.
Both UFW files and numbered rule output matched their backups after removal.
All existing Cloudflare record objects also matched their original snapshot.
The test certificate was revoked; task containers, private credentials/keys and
server staging were removed. Production service PIDs/startup timestamps and the
original HTTPS response body matched, and production HTTPS remained 200.
The operator-added provider port rule can now be closed.

Repeatable drivers: [public ACME](../tests/uat/public_acme_acceptance.sh),
[protocol server](../tests/uat/public_protocol_server.sh),
[client preparation](../tests/uat/public_protocol_client_prepare.sh) and
[public acceptance](../tests/uat/public_protocol_acceptance.sh).
Renewal UAT disables Certbot's random scheduled delay; production scheduling
defaults retain that delay. Client builds live under `/var/tmp`, so stopping a
container does not discard them through a `/run` tmpfs.

### HTTP-01 and legacy tooling follow-through

The exact `d79e4ec` archive also passed **13/13 legacy tooling checks** in a
disposable Ubuntu 24.04 ARM64/systemd container. The baseline uses the actual
v3.6.0 CLI and plugin mapping from tag commit
`7d531deec3e72ef20b0c43d4e5445cf1b2590092`, with distro Nginx, PHP 8.3 and MariaDB.
This is a representative tooling/layout fixture, not a full v3 installer run.
The PHP endpoint queries synthetic SQL data; configuration, package versions,
running service PIDs/startup timestamps, application data and synthetic Maildir
content remained unchanged after the CLI-only bootstrap and its repeat run.
Checksum rejection preserved v3, both public CLI aliases resolved to v4, and
encrypted configuration plus configuration backup/verification passed.

HTTP-01 issued a staging certificate for `lemper.eu.org` through
`lemperctl site update --ssl-enable` in a separate Ubuntu 26.04 ARM64 fixture
running Certbot 5.10.0 and distro Nginx 1.28.3. Only public challenge files were
copied to the existing production `.well-known/acme-challenge` directory; the
existing HTTP-to-HTTPS redirect served them without a configuration change or
reload. Private ACME accounts, keys and the staging TLS endpoint stayed inside
the disposable container. Staging HTTPS uses explicit certificate trust; the
system trust store correctly rejects it, as does a mismatched hostname.

The **17 checks** cover SAN, expiry, webroot renewal configuration, installed
deploy hook, Nginx validation, HTTPS/body and trust/hostname rejection before
and after a successful renewal dry-run. Repeat SSL enable preserved the
certificate. The renewal ran the installed hook and reloaded only fixture Nginx.
An initial manual renewal failed because `renew` cannot pause interactively;
the test-only file watcher now pauses/resumes the fixture process while the
operator mirrors its public challenge. Scheduled jitter is disabled only for
this test. Production service PIDs/startup timestamps and the homepage body
matched their new pre-test baseline. Temporary challenge files were removed,
the staging certificate was revoked, and the task containers were removed after
retaining protected case logs. No production mail configuration, accounts or
DNS records changed.

The new Bash drivers passed Linux Bash syntax, sourced ShellCheck and Bashate;
all 46 local links in the affected developer/release/UAT documents resolve.

The Bash drivers are [legacy tooling](../tests/uat/legacy_tooling_acceptance.sh),
[HTTP-01 preparation](../tests/uat/public_http01_prepare.sh),
[renewal bridge](../tests/uat/public_http01_renew.sh) and
[HTTP-01 verification](../tests/uat/public_http01_acceptance.sh).
See [developer instructions](../DEVELOPER.md#http-01-and-legacy-tooling-acceptance).

External mail remains pending: IPv4 probes to two Gmail MX endpoints on TCP 25
timed out, while `smtp.gmail.com:587` returned an SMTP 220 greeting. The existing
Postfix relay is unset. No external email was sent. Direct delivery needs
provider port-25 access; submission through a relay needs a separately supplied
authenticated transport. SPF/DKIM/MX changes are deferred until that transport
and an isolated mail endpoint are ready. IMAP/inbound delivery and external
alerts have not been established by this preflight.

Full legacy installation/storage migration and selected application setup
still need disposable targets. A production host is not the legacy
installation/removal fixture; use a disposable snapshot clone for those transitions.

## External target requirements

Provide target names and protected credential-file locations through the normal
operator channel; keep secret values out of chat, commands and logs. Use synthetic
accounts/data and endpoints explicitly reserved for these tests.

| Case | Required setup | Completion evidence |
|---|---|---|
| ACME HTTP-01 | Disposable routable hostname with correct A/AAAA and reachable TCP 80/443 | Issue through the staging directory using the LEMPer path, inspect SAN/expiry, verify HTTPS, and run renewal dry-run with the installed deploy hook |
| ACME DNS-01 | Disposable test zone and a credential restricted to that zone | Issue staging wildcard/base certificates, verify both SANs and renewal using the same protected credentials, then remove only test records |
| Mail hosting | Disposable server/domain with MX/A/PTR, sender policy/DKIM, TCP 25/587/993 and controlled remote test mailbox | External inbound/outbound delivery, TLS/IMAP retrieval, DKIM result and rejection of anonymous relay or unauthorized sender identity |
| Monitoring alerts | Explicit test SMTP sink/recipient and the reviewed transport/authentication configuration | Trigger a fixture-only failure, observe the delivered alert and recovery; retain redacted delivery metadata |
| Remote Restic provider | Dedicated empty repository, protected repository password and authenticated transport | Back up synthetic app/mail data, verify repository integrity, restore to an empty staging path, compare contents and test scoped retention |
| Legacy transition | Disposable v3 installation snapshot, backed-up databases/mail/config and supported destination versions | Check public CLI aliases, configuration/ownership preservation, service/HTTP/SQL/mail health and failed-operation retry/recovery |
| Application setup | Selected latest release, supported PHP/extensions and synthetic database/admin/mail configuration | Complete upstream setup through protected routes; check application health, assets, denied private/PHP paths, scheduled jobs and repeat preservation |

Certificate, database and mail-storage major upgrades require an explicit
transition plan. Configuration/code backups alone do not undo storage written
by a newer database or mail version. See [maintenance](MAINTENANCE.md),
[Ubuntu 26.04](UBUNTU_26_04.md) and the upstream migration guidance.

## Evidence record

For each case record the code commit, fixture/platform, component/client versions,
target, exit status and checked behavior. Publish only case summaries and public
certificate/protocol metadata. Keep configuration, password/session files and
raw installer/mail logs private. Record unavailable targets as pending, rather
than counting syntax checks or loopback delivery as public integration success.

After selected checks are reviewed, build/review the final committed candidate
and its CI. Publication and published-download/one-line installation verification
are separate steps in the [release guide](RELEASE_V4.md#remaining-release-steps).
