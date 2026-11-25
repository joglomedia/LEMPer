# Production UAT for v4

Validated runtime baseline: **56e0d8593108f6a089d083f3f026fcfa2a2e58f7**, 2026-11-25.
The [candidate CI](https://github.com/joglomedia/LEMPer/actions/runs/45559066353)
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
| External outbound SMTP relay | **Passed: recipient-confirmed Inbox, SPF/DKIM/DMARC** | Verified STARTTLS to Brevo on TCP 587, authentication 235, submission 250, and DKIM signing for lemper.eu.org; direct Bash relay client with production mail configuration preserved |
| Managed mailbox outbound/inbound and public IMAP | **Passed**, with production Postfix repair | Managed SMTP authentication → native OpenDKIM/Postfix → Brevo → recipient-confirmed Gmail receipt; external Brevo → public MX/SMTP → native LMTP → public IMAP; rejection checks passed |
| External monitoring alerts | Pending designated alert recipient/transport | Mailbox delivery does not prove monitoring alert dispatch |
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

### Brevo outbound relay follow-through

On 2026-11-25, the production host's UFW and IPv4/IPv6 OUTPUT policies allowed
outgoing traffic, but two Gmail MX IPv4 probes on TCP 25 still failed. Public
TCP 25 connected to the VPS; its existing Postfix worker could not give a
greeting because Dovecot's `private/auth` socket was missing. Read-only logs
confirmed `no SASL authentication mechanisms` and worker startup failure.
That production configuration was preserved.

The operator supplied a protected Brevo SMTP login/key and confirmed domain
authentication. Public DNS showed the Brevo verification code, both DKIM
CNAMEs and DMARC. A direct Bash client using the `905963f` checkout's
function-only dotenv parser and SMTP helpers connected from the VPS to
`smtp-relay.brevo.com:587`. STARTTLS verified the certificate and hostname;
SMTP authentication returned **235** and one authorized message returned **250**
after DATA.

The recipient confirmed **Inbox delivery** and reported these Gmail
**Show original** results:

| Authentication | Recipient-confirmed result |
|---|---|
| SPF | **PASS**, sending IP `77.32.148.8` |
| DKIM | **PASS**, signing domain `lemper.eu.org` |
| DMARC | **PASS** |

This establishes outbound delivery through the authenticated Brevo relay for
that sender/message. It does not establish direct port-25 delivery, persistent
Postfix relay configuration, incoming mail, IMAP retrieval or monitoring alerts.
The relay's shared-IP domain authentication uses Brevo code, DKIM and DMARC;
SPF/MX changes are not required solely for that authentication, per
[Brevo's domain guide](https://help.brevo.com/hc/en-us/articles/12163873383186-Authenticate-your-domain-with-Brevo-Brevo-code-DKIM-DMARC).
Existing DNS records and production mail settings were not changed by the test.

Credential values stayed in protected files/shell memory and SMTP input; they
were not displayed, sourced as code or placed in external process arguments.
The remote credential copy and private staging were removed after retaining
non-secret submission evidence. Production service PID/startup baselines matched.
The operator's original local credentials file is retained outside version control.

### Managed mailbox and production Postfix repair

On 2026-11-25, a disposable Ubuntu 24.04/systemd container on the local Podman
machine (`aarch64`) installed the actual mail component from `905963f`, then
exercised the current outbound-TLS reconciliation fix. Native versions were Postfix **3.8.6**,
Dovecot **2.3.21** and OpenDKIM **2.11.0**. It created the synthetic managed
`no-reply@lemper.eu.org` mailbox, used a trusted DNS-01 certificate, and configured
a protected, authenticated Brevo relay with verified TLS. SSH tunnels carried
bytes between the fixture and VPS; certificate verification remained enabled.

| Path/check | Observed result |
|---|---|
| Mailbox submission | Plaintext submission rejected; TLS/password authentication and native Postfix acceptance passed |
| Native signing/storage | Mailbox copy delivered by LMTP, retrieved over IMAP; native OpenDKIM signature independently verified against published DNS |
| External outbound | Native Postfix recorded successful Brevo relay delivery and an empty queue; recipient confirmed the managed-mailbox message arrived at Gmail |
| External inbound | Brevo resolved the temporary public MX, delivered to the VPS on TCP 25, and the scoped route delivered to fixture Postfix/LMTP; the distinct incoming message was retrieved over public IMAP on TCP 18443 |
| Public rejection checks | Wrong IMAP password, wrong TLS hostname, unrelated CA, unknown recipient and anonymous relay all rejected |
| Repeat installation | Initially downgraded verified outbound TLS to `may`; source fix retained `verify` during a real repeat install and refreshed CLI snapshot |

The missing production Dovecot SASL listener was repaired with a restricted
`0660 postfix:postfix` socket and an include that preserved existing passdb,
userdb, accounts and storage. Postfix now requires TLS before authentication.
Both configurations were validated before reload, and public SMTP greeting and
STARTTLS certificate/hostname verification passed. The protected rollback
backup is `/var/backups/lemper-mail-repair.J4KsuCMS`.
The production SMTP front remained Ubuntu 22.04/AMD64, Postfix **3.6.4** and
Dovecot **2.3.16**; no mail package/version upgrade was performed there.

The first incoming probe was permanently rejected because legacy unqualified
Spamhaus DNSBL rules treated **127.255.255.254**, an unsupported-resolver error,
as a spam listing. The repair kept both existing DNSBLs and restricted rejection
to **127.0.0.[2..11]**; error-range replies now produce warning-only diagnostics.
Other recipient/SPF/authentication restrictions were retained. The retry logged
those warnings and delivered successfully. The protected repair backup is
`/var/backups/lemper-mail-rbl-repair.fRCVhOey`.

This follows [Spamhaus's Postfix return-code guidance](https://docs.spamhaus.com/datasets/docs/source/40-real-world-usage/PublicMirrors/MTAs/020-Postfix.html).
The shared resolver still cannot obtain Spamhaus reputation data: use supported
DQS or a suitable dedicated recursive resolver to restore it. Genuine positive
listing rejection remains configured; a controlled positive-listing probe was
not run. The current v4 installer does not configure these legacy DNSBL rules.

The Gmail SPF/DKIM/DMARC passes reported above belong to the earlier direct
Brevo message. The managed-mailbox message's recipient-side authentication
results and Inbox/Spam placement have not yet been confirmed; native DKIM was
verified independently. Persistent production relay setup, direct outbound
TCP 25, monitoring alerts and full legacy mail-storage migration remain separate
work. The production server hosted only the temporary scoped test route; the
managed mailbox/services and relay credentials stayed in the disposable fixture.

Cleanup restored the exact pre-test UFW rule files/status and removed the scoped
Postfix route and socket-proxy units while retaining both permanent repairs.
Only the three owned A/DKIM/MX records were deleted; all six original DNS record
objects matched the baseline afterward. The test certificate was revoked, both
task mail/ACME containers and SSH tunnels were removed, and task credential/key
copies were deleted. The existing preview container and production containers
were preserved. Original operator credential files remain protected and ignored.

Linux regression verification passed **16/16 focused mail tests**, including
stronger TLS preservation, fresh defaults and failed/invalid policy reads, then
**549/549 full Bats tests** in an isolated Debian 12 container. Changed runtime
Bash syntax, sourced ShellCheck **0.11.0**, Bashate, local document link targets
and `git diff --check` passed. The first full run had one ShellCheck-source test
failure because the harness ran from the container root; the complete repeat
from the checkout directory passed without changing or suppressing that check.

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
