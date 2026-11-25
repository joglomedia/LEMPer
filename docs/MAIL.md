# Mail hosting and administration

LEMPer hosts mail with distro Postfix and Dovecot 2.3/2.4 packages, Dovecot LMTP
mail delivery, and optional OpenDKIM/SPF policy checking. Mailbox identities are
full email addresses; a dedicated `vmail` service account owns Maildir storage.
There is no Linux login account per mailbox and no dependency on a database or
webmail panel.

Ubuntu 26.04 selects a dedicated Dovecot 2.4 template; existing supported releases
continue to use their installed Dovecot version. See [the Resolute guide](UBUNTU_26_04.md)
for template changes and the distinction between configuration backup and storage migration.

For production, use a dedicated mail hostname and preferably a separate mail
server/VM. Confirm that the provider permits incoming and outgoing TCP port 25,
allows a matching reverse DNS/PTR record, and gives the server a stable public
IP. A working local SMTP/IMAP installation does not establish Internet
reputation or delivery to Gmail/Outlook. An authenticated external relay can
improve outbound deliverability; that provider integration is separate work.

An administrator-configured relay must use protected SASL credential maps and
verified TLS to the provider. Mail reinstall/reconciliation retains stronger
`smtp_tls_security_level` policies (including `verify`); fresh installations
default to opportunistic outbound TLS (`may`). The installer does not provision
relay credentials or change an existing `relayhost`.

## Installation

Set these values in the installation profile. For an installed stack, use its
protected `/etc/lemper/lemper.conf` configuration; encrypted configuration must
be edited through the existing decryption/re-encryption workflow.

```ini
INSTALL_MAILER=true
INSTALL_SPFDKIM=true
MAILER_HOSTNAME="mail.example.com"
SENDER_DOMAIN="example.com"
MAILER_CERT_PATH="/etc/letsencrypt/live/mail.example.com"
```

`MAILER_HOSTNAME` and the first hosted `SENDER_DOMAIN` default to
`SERVER_HOSTNAME`. Prepare a certificate whose SAN covers the **mail hostname**,
with `fullchain.pem` and `privkey.pem` in `MAILER_CERT_PATH`. The installer checks
its expiry, hostname, and matching key. With an empty certificate path in
production, it checks `/etc/letsencrypt/live/<mail-hostname>` first. Development
can generate a self-signed certificate when no certificate directory is given.
Keep private keys protected and renew certificates using your existing ACME
workflow; run `sudo lemperctl stack reload mailer` after renewal. The mailer does
not stop Nginx or perform its own ACME challenge.

Install from the configured stack:

```bash
sudo lemperctl stack install mailer
sudo lemperctl mail check
sudo lemperctl mail status
```

The full-stack installer also installs mail when `INSTALL_MAILER=true`; minimal
installation skips it. No mailbox password is derived from a server account
password. The initial domain is created, and mailbox creation is explicit.

Existing unmanaged Postfix/Dovecot installations are preserved. Taking one over
requires an explicit `FORCE_INSTALL=true` profile, configuration backups, and a
mail migration plan. This replaces authentication and routing with virtual
mailboxes; existing Unix accounts and old catch-all mappings are **not** imported.
Back up existing mail before takeover, create corresponding virtual accounts,
and copy/import mail with Dovecot tools while services are stopped or otherwise
quiesced. Keep the old mail until the migrated accounts have been verified.

## Domains, accounts, and addresses

```bash
# Add the first mailbox; password entry is hidden and confirmed.
sudo lemperctl mail account add admin@example.com
sudo lemperctl mail alias add postmaster@example.com admin@example.com
sudo lemperctl mail alias add abuse@example.com admin@example.com

# A second domain has its own accounts and DKIM key.
sudo lemperctl mail domain add example.net
sudo lemperctl mail account add sales@example.net
sudo lemperctl mail alias add support@example.net sales@example.net

# An alias can route to a mailbox in another hosted domain.
sudo lemperctl mail alias add team@example.com sales@example.net
sudo lemperctl mail alias edit team@example.com admin@example.com

sudo lemperctl mail domain list
sudo lemperctl mail account list example.net
sudo lemperctl mail alias list
```

Use lowercase ASCII addresses. Supported local parts contain letters, digits,
`.`, `_`, `+`, and `-`; quoted/Unicode local parts, catch-alls, and alias chains
are not supported. Aliases target a managed mailbox, which avoids forwarding
loops. Authenticate with the full mailbox address. A mailbox may send as its
own address or an alias targeting it; another account cannot impersonate it.

Change a password with `sudo lemperctl mail account edit sales@example.net`.
For automation, pass `--password-file /root/mail-password` to account add/edit.
The file must be root-owned, regular, mode `0600`, and contain one password line
of at least 12 characters. Create it with your secret manager and remove it
after use. Plaintext passwords are not accepted as command arguments or printed
in previews. Accounts are stored with SHA512-CRYPT password hashes.

```bash
# Disable authentication while continuing to receive mail.
sudo lemperctl mail account edit sales@example.net --disable
sudo lemperctl mail account edit sales@example.net --enable

# Preview and then remove an alias and account; mailbox data is retained.
sudo lemperctl mail account delete sales@example.net --dry-run
sudo lemperctl mail alias delete support@example.net --yes
sudo lemperctl mail account delete sales@example.net --yes
sudo lemperctl mail domain delete example.net --yes
```

Aliases targeting an account must be removed or redirected before deleting that
account. A domain must have no accounts or aliases before deletion. Account
edits and deletion disconnect existing IMAP sessions. Account deletion keeps
`/var/vmail/<domain>/<local-part>/`; re-creating that address resumes access to
its retained mail. `account delete ADDRESS --purge --yes` explicitly deletes
that address's stored mail. Back it up first. Domain deletion retains DKIM keys,
so adding the domain again preserves its published key.

## Clients and DNS

| Purpose | Endpoint | Security |
|---|---|---|
| Receive Internet mail | Mail hostname, TCP 25 | Opportunistic STARTTLS; relay denied to untrusted clients |
| Send as a mailbox | Mail hostname, TCP 587 | Required STARTTLS and authentication |
| Read mailbox | Mail hostname, TCP 993 | IMAP with TLS |
| Optional IMAP STARTTLS | Mail hostname, TCP 143 | TLS required for client authentication |

Port 465 and POP3 are not enabled by this configuration. Open the required
ports in both the host and provider firewalls. Only loopback addresses are
trusted for unauthenticated outbound submission by local applications. Remote
applications must use authenticated TLS submission on port 587.

```bash
sudo lemperctl mail dns example.com
sudo lemperctl mail dns example.net
```

The command prints per-domain MX, SPF, DKIM public records, and an initial
DMARC monitoring policy. Create A/AAAA records for the mail hostname and ask the
provider to set matching PTR. Publish AAAA only when IPv6 mail routing works.
The suggested SPF `v=spf1 mx -all` assumes only this server sends for the domain;
adjust it if another provider sends mail. Collect DMARC reports and confirm
alignment before changing `p=none` to enforcement. Publishing the records is a
DNS administration step, not performed by the CLI.

## Operations, backup, and recovery

Use `lemperctl stack start|stop|restart|reload|status|update mailer` to control services.
`lemperctl mail check` validates Postfix, Dovecot, and enabled DKIM configuration.
Configuration is generated from tracked templates in `etc/mail/`; live map data
lives in `/etc/lemper-mail`. Configuration and password/status maps change under
the shared LEMPer lock. One atomic generation selector publishes the maps;
failed validation or reload restores the previous generation and reports a
failure. Protected previous generations and configuration backups are retained
for administrator recovery. Protect and expire obsolete backups according to
your retention policy because they contain old password hashes.

`lemperctl backup create` includes `/etc/lemper-mail` alongside Postfix, Dovecot,
and DKIM configuration. Back up `/var/vmail` separately with a mail-aware backup
or a consistent filesystem snapshot: the configuration backup does not include
message data. Mail package removal preserves configuration, mail, and DKIM keys
and removes only packages recorded as installed by LEMPer. It does not delete
the `vmail` user.

The file-backed approach suits a small or moderate number of managed mailboxes.
For larger multi-tenant deployments, quotas, spam filtering, webmail, migration,
and delegated administration, use a dedicated mail platform with database-backed
account management rather than expanding the web-stack installer into a mail
control panel. Rspamd/antivirus, quotas, relay-provider credentials, automated
DNS publication, and Dovecot 2.4 configuration migration are future additions.

## Audit findings and verification

The audit compared `scripts/install_mailer.sh` at commit `062b567` with the
installer, runtime, templates, deployment registry, and removal path.

| Finding in the previous implementation | Implemented correction |
|---|---|
| `dovecot-common` has no candidate on Ubuntu 24.04 | Install maintained core, IMAP, and LMTP packages |
| Postfix expects `private/auth`, but no corresponding Dovecot listener is created | Explicit restricted SASL and LMTP sockets |
| Dovecot TLS key lacks the required `<` prefix | Render certificate/key references from validated templates |
| No authenticated submission service | Port 587 requires TLS and SASL; port 25 does not advertise authentication |
| Mail maps/catch-alls rely on one Unix account and are overwritten | Independent virtual accounts, domain/alias maps, and generation publication |
| Repeated setup overwrites DKIM tables and regenerates published keys | Retain keys and render tables for every hosted domain |
| SPF includes its own sender domain recursively | Print an explicit MX-based SPF starting point |
| Certificate acquisition stops Nginx and failure paths do not reliably restore it | Require prepared production certificates; keep Nginx running |
| Installed binaries cause configuration repair to be skipped | Reconcile managed installations and recognize interrupted owned installs |
| Errors can leave configuration partially changed | Validate before reload and restore backed-up configuration/maps on failure |
| Package purge can discard configuration regardless of ownership | Remove recorded owned mail packages; preserve mail, account maps, and keys |

### Historical verification, 2026-11-21

On 2026-11-21, disposable Podman/systemd containers on a running Podman machine
validated **18/18 cases on each of Ubuntu 22.04, Ubuntu 24.04, and Debian 12**
(54 cases, native `aarch64`). They exercised installation, real SASL/LMTP sockets,
TLS certificate verification, denial of untrusted relay and sender impersonation,
incoming delivery from a non-loopback client, outbound authenticated delivery
for both domains with their DKIM signatures, IMAP/STARTTLS retrieval, repeated
installation/key retention, password rotation, session revocation, aliases,
package updates, configuration backup/verification, and removal with retained
mail. A separate Ubuntu 24.04 acceptance check verified literal `+` addresses
through SMTP, LMTP, IMAP, and explicit purge, bringing executed live checks to 55.
The automated acceptance script now includes that extra address case.

The full Bats suite passed **341/341**. Focused mail regression checks also
cover invalid input, protected password files, failure/rollback, dry runs,
interrupted-install recovery, and purge boundaries. Changed Bash passed syntax,
ShellCheck 0.11.0, and the repository Bashate rules. Both workflow YAML files
parsed, the parameterized Debian test-image build succeeded, and local Markdown
references and `git diff --check` passed.

These tests use synthetic private domains, passwords, and a test CA. They do
not verify public ACME issuance/renewal, public DNS/PTR, SMTP reputation, provider
port-25 policies, Gmail/Outlook delivery, or a live existing-server migration.
The new GitHub Actions job has been prepared and locally checked; it has not yet
run on GitHub. No live server or workstation mail services were changed.

### Current verification, 2026-11-25

[Candidate CI for 905963f](https://github.com/joglomedia/LEMPer/actions/runs/45473224896)
passed **19/19 real mail cases on each of Ubuntu 22.04, Ubuntu 24.04,
Ubuntu 26.04 and Debian 12** (76 cases). These use actual Postfix, Dovecot and
OpenDKIM services with LEMPer-managed virtual mailboxes, multiple domains and
aliases. Coverage includes authenticated TLS submission, incoming SMTP/LMTP
delivery between fixture mailboxes, IMAP/STARTTLS retrieval, DKIM signatures,
relay/sender rejection, password rotation, disable/delete behavior, repeated
installation, backup and retained-mail removal.

The direct Brevo test reached Gmail Inbox with recipient-confirmed SPF, DKIM
for `lemper.eu.org`, and DMARC passes. A subsequent test used a LEMPer-managed
mailbox, native Postfix/OpenDKIM and the same authenticated relay; the recipient
confirmed receipt. Native DKIM verification and LMTP/IMAP retrieval passed.
An external Brevo message also arrived through public MX/SMTP and was retrieved
over public IMAP with a trusted certificate. Invalid passwords, TLS identities,
unknown recipients and anonymous relaying were rejected.

The legacy production authentication socket and false DNSBL rejections were
repaired separately, preserving existing accounts/storage. Relay credentials
and the new managed mailbox existed only in a disposable fixture; persistent
production relay configuration remains separate work. The new message's Gmail
authentication results have not been confirmed. See
[the public UAT report](PRODUCTION_UAT.md#managed-mailbox-and-production-postfix-repair).
