LEMPer v4.0.0 installs and manages LEMP stacks on Debian and Ubuntu with a shared
Bash service architecture and the `lemperctl` CLI. This release is intended for
fresh deployments; existing v3 servers require a backed-up migration plan.

## Highlights

- Ubuntu 26.04 support, maintained Sury PHP repositories, native MariaDB 11.8 on
  Resolute and a dedicated Dovecot 2.4 template.
- Profile-based minimal/full installation, per-service lifecycle commands,
  protected configuration, dry runs and the retained `lemper-cli` alias.
- Multi-domain virtual mailboxes, aliases, authenticated TLS submission,
  IMAP/LMTP, DKIM, retained mail storage and verified relay TLS preservation.
- Latest-release application skeletons and Unix-socket PHP deployment, including
  Mautic, Roundcube, SnappyMail, Nextcloud, MyBB, phpList, OJS and Slim;
  licensed applications retain their manual package/setup paths.
- Optional hosting quotas, Monit, nftables recovery and encrypted Restic backups.
- Refreshed welcome pages, SVG brand assets and focused documentation.

## Install

Install the CLI:

```bash
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0
```

For a fresh minimal stack, prepare a private `lemper.env` profile with the server
hostname/IP, administrator email and SSH public key, then run:

```bash
curl -fsSL https://github.com/joglomedia/LEMPer/releases/download/v4.0.0/get-lemper -o get-lemper && sudo bash get-lemper --version 4.0.0 --install --config ./lemper.env --minimal --yes
```

See the [installation guide](https://github.com/joglomedia/LEMPer/blob/v4.0.0/docs/INSTALLATION.md)
for requirements, profile preparation and source installation. Both the archive
and bootstrap have SHA256 files attached to this release.

## Upgrade and validation limits

- Back up configuration, databases and mail before adopting v4 on an existing
  server. CLI replacement preserves configuration; full installation and
  database/mail storage major migrations require their own transition plan.
  Full v3 storage migration has not completed UAT.
- Internet mail needs suitable DNS/PTR, provider firewall access and sender
  authentication. An authenticated Brevo relay passed public delivery tests;
  relay credentials and supported Spamhaus DNS/DQS remain operator setup.
  Direct outbound TCP 25 and external monitoring-alert delivery remain unverified.
- Application skeleton deployment still requires each application's upstream
  database/admin/cron/mail setup. Complete setup UAT for selected applications
  remains additional deployment work.

The runtime baseline passed 25 CI jobs and 549 Bats tests, including exact-archive
installation/removal on Ubuntu 24.04, Ubuntu 26.04 and Debian 12. The tagged
publication workflow repeats archive acceptance, lint and tests before uploading
assets. Public ACME, DNS, TLS/HTTP/3 and managed-mailbox tests have also passed.
See [UAT evidence](https://github.com/joglomedia/LEMPer/blob/v4.0.0/docs/PRODUCTION_UAT.md),
[maintenance](https://github.com/joglomedia/LEMPer/blob/v4.0.0/docs/MAINTENANCE.md)
and the [full changelog](https://github.com/joglomedia/LEMPer/blob/v4.0.0/CHANGELOG.md).
