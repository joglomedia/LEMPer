# Production UAT for v4

Runtime baseline: **9b3963e34fa144bcf67d8aa69439675bddfb16ea**, 2026-11-24.
The [candidate CI](https://github.com/joglomedia/LEMPer/actions/runs/45318207064)
passed all 24 jobs, including committed-archive acceptance, PHP/Laravel, mail,
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
| Internet-facing QUIC | Pending provider port mapping | The VPS has a private interface. Direct high-port requests did not reach its listeners; no provider mapping or existing service/firewall routing was changed. |
| Public ACME issuance/renewal | Pending external target | Routable disposable domain/server and scoped test-zone credentials for DNS-01 |
| External SMTP/IMAP and alerts | Pending external target | Controlled sender/recipient domains/mailboxes, verified TLS and routable mail endpoints |
| Selected legacy upgrades | Pending disposable legacy baseline | A designated old installation/data snapshot and a reviewed recovery path |
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
