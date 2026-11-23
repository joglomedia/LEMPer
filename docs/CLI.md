# LEMPer command-line guide

`lemperctl` is the public command; `lemper-cli` remains a compatibility alias.
Run administration commands with sudo. Most commands provide `--help`:

```bash
lemperctl --help
lemperctl site --help
lemperctl stack --help
sudo lemperctl tui
```

The TUI provides service management, live logs, guided site creation and
benchmarks. The following examples use the same CLI handlers.

## Accounts and sites

Create a non-root runtime account before deploying its website:

```bash
sudo lemperctl account webowner
sudo lemperctl site create example.com --type=wordpress --runtime=php@8.5 \
  --runtime-user=webowner --install-skeleton
sudo lemperctl site show example.com --all
sudo lemperctl site show example.com --json
sudo lemperctl site update example.com --ssl-enable
sudo lemperctl site enable example.com
sudo lemperctl site disable example.com
```

Application installation is opt-in. Available types, release sources, setup
routes and manual licensed deployments are grouped in
[application capabilities](APPLICATIONS.md). Laravel root/subpath deployments
and runtime switching are covered in [PHP and Laravel](PHP_RUNTIME_LARAVEL.md).
Diagnostics redact credential-bearing fields; `--json` implies `--all`.

`site add` aliases `create`; `manage`/`mod` alias `update`; `delete` aliases
`remove`. Legacy creation flags remain accepted. Batch commands validate domains
and conflicting actions before mutation, return failure if any target fails,
and validate/reload Nginx after the batch.

For a local development domain, pass a private address and arrange the matching
domain/IP entry in the client machine's hosts file:

```bash
sudo lemperctl site create example.test --type=wordpress --runtime=php@8.5 \
  --runtime-user=webowner --ipv4=127.0.10.1 --install-skeleton
```

Use an address reachable from the browser's machine; loopback addresses refer to
that machine itself.

## Site features

```bash
sudo lemperctl site mod --enable-ssl example.com
sudo lemperctl site mod --enable-fastcgi-cache example.com
sudo lemperctl site mod --enable-cors example.com
sudo lemperctl site mod --disable-cors example.com
```

CORS allows every origin by default. To restrict it, edit the generated
`set $cors` line in `/etc/nginx/includes/cors-example.com.conf`, validate Nginx
and reload it. Enable caching only when appropriate for the application's
authentication and session behavior. See [web and security features](FEATURES.md).

## Site ownership and removal

```bash
sudo lemperctl site remove example.com
sudo lemperctl site remove example.com --purge
sudo lemperctl site adopt legacy.example.com --runtime-user=webowner --runtime=php@8.1
```

Removal retains application data by default. `--purge` deletes the recorded
document root and site-owned database only after ownership/reference checks.
Shared accounts, PHP pools, certificates and service packages remain. Private
siblings outside the document root need deliberate cleanup; see
[application removal limits](APPLICATIONS.md).

`--yes` skips confirmation; `--dry-run` makes no changes. Adoption checks the
configured document root and its owner and asks you to assert ownership of the
recorded database. Explicit `--webroot` must match that root. Adoption changes
metadata; it does not install or migrate PHP. Legacy EOL runtimes can be recorded
for management; new PHP installation is restricted to supported versions.

## Service lifecycle

```bash
sudo lemperctl stack status nginx
sudo lemperctl stack install php --php-version 8.5
sudo lemperctl stack restart php
sudo lemperctl stack restart php --php-version 8.5
sudo lemperctl stack update php --php-version 8.4
sudo lemperctl stack remove php --php-version 8.1 --yes
```

PHP installation supports 8.2–8.5. Control/update without a version targets all
installed versions; control acts on FPM instances. Multi-version removal requires
`--php-version` or `--all-versions`, and site references block removal.
EOL migration remains explicit; see [updates and recovery](MAINTENANCE.md).

Lifecycle commands use installed configuration and recorded source. Removal
requires provisioning markers; `--force` permits deliberate removal of a
pre-existing component while retaining site-reference checks. Full-stack
installation uses `stack install --all --config FILE`; see
[installation](INSTALLATION.md).

## Configuration and credentials

```bash
sudo lemperctl config check
sudo lemperctl stack config php --default-runtime=php@8.4
```

Configuration is validated before loading. `config check` also rejects unknown
options and unsupported PHP versions; normal runtime loading preserves unknown
legacy settings for upgrades. PHP default changes preserve profile encryption
and leave existing sites' explicit runtimes intact.

Hosting accounts have no sudo access by default. `account --admin` grants a new
account restricted service administration; `account --restrict-sudo USERNAME`
deliberately migrates a recorded account away from broad sudo permissions.
Account credentials are stored privately in `/etc/lemper/accounts/USERNAME.conf`
and are not printed in installation output. See [hosting plans](HOSTING.md).

## Databases, mail and optional services

| Task | Guide |
|---|---|
| SQL accounts, domain backups, restore and retention | [Database management](DATABASE.md) |
| Multi-domain SMTP/IMAP accounts, aliases and DNS | [Mail hosting](MAIL.md) |
| Disk/inode plans and account quotas | [Hosting](HOSTING.md) |
| Restic application/mail backups | [Data backups](DATA_BACKUP.md) |
| Native nftables and UFW migration | [Firewall](FIREWALL.md) |
| Monit health checks and alerts | [Monitoring](MONITORING.md) |
| Configuration backups and package updates | [Maintenance](MAINTENANCE.md) |

## Benchmarks

```bash
sudo lemperctl bench
sudo lemperctl bench --hardware --disk
sudo lemperctl bench --network --size 100 --timeout 60
sudo lemperctl bench --disk --disk-size 1024
```

Benchmarks report hardware, disk read/write speed and network download speed.
Failed endpoints are reported as unavailable. Network tests download the selected
size from each endpoint (32 MB by default), consuming bandwidth; use
`--hardware --disk` to omit them. The TUI's Benchmark menu exposes the same tests.
