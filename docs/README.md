# LEMPer documentation

Start with the project [README](../README.md) for the overview and quick start.

## Install and operate

| Guide | Covers |
|---|---|
| [Installation](INSTALLATION.md) | Requirements, release/checkout bootstrap and profiles |
| [CLI](CLI.md) | Accounts, sites, services, TUI, credentials and benchmarks |
| [Features](FEATURES.md) | Nginx, PHP, optional services, security and web panels |
| [Maintenance](MAINTENANCE.md) | Updates, configuration backups, EOL migration and removal |
| [Applications](APPLICATIONS.md) | Grouped deployment capabilities and application setup |
| [PHP and Laravel](PHP_RUNTIME_LARAVEL.md) | Runtime defaults and root/subpath applications |
| [Databases](DATABASE.md) | SQL accounts, backup/restore, scheduling and retention |
| [Mail](MAIL.md) | SMTP/IMAP, domains, accounts, aliases, TLS and DKIM |
| [Authoritative DNS](DNS.md) | External DNS planning, Knot primary setup, zone publication and secondary verification |
| [Hosting](HOSTING.md) | Disk/inode plans, quota requirements and provisioning |
| [Data backups](DATA_BACKUP.md) | Restic repositories, schedules, retention and restore |
| [Firewall](FIREWALL.md) | Native nftables, SSH recovery and UFW migration |
| [Monitoring](MONITORING.md) | Monit health checks and alerts |
| [Ubuntu 26.04](UBUNTU_26_04.md) | Resolute packages, migration boundaries and native checks |

## Develop and release

- [Developer guide](../DEVELOPER.md), [contribution guide](../CONTRIBUTING.md)
  and [agent guidelines](../AGENTS.md).
- [Architecture](ARCHITECTURE.md) and [architecture alignment](ARCHITECTURE_ALIGNMENT.md).
- [Authoritative DNS proposal](AUTHORITATIVE_DNS_PROPOSAL.md) for the optional core service.
- [Roadmap](ROADMAP.md) and [remaining-scope audit](ROADMAP_AUDIT.md).
- [Release preparation](RELEASE_V4.md) and [changelog](../CHANGELOG.md).
- [4.1.0 release notes](RELEASE_NOTES_V4_1.md) cover authoritative DNS and existing-host upgrades.
- [4.0.0 release notes](RELEASE_NOTES_V4.md) cover the previous release.
- [Production UAT](PRODUCTION_UAT.md): protocol checks and external release targets.
- [UAT report](UAT_REPORT.md) and [Bash script audit](BASH_SCRIPT_AUDIT.md).
- [Brand assets](BRAND.md): SVG logos, icons, colors and usage guidance.

Architecture, roadmap and UAT documents include historical records. Read their
implementation/status sections for current behavior and validation limits.
