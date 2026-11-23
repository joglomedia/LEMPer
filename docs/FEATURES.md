# Stack features and configuration

Use the [installation guide](INSTALLATION.md) to choose services in a private
profile. The public [.env.dist](../.env.dist) lists configuration keys and
defaults; minimal installation skips optional components.

## Nginx

`NGINX_INSTALLER="repo"` selects MyGuard's community packages and module
packages. The retired Ondřej Nginx archive is no longer used. ARM64 currently
requires `NGINX_INSTALLER="source"`; see [platform choices](UBUNTU_26_04.md).

Source installation supports Brotli, Lua/LuaJIT, FastCGI cache purge and custom
OpenSSL, LibreSSL or BoringSSL builds. Module and TLS choices are configured in
the profile; see the [architecture](ARCHITECTURE.md) for installer boundaries.
The maintained custom OpenSSL baseline is selected by
`NGINX_WITH_CUSTOMSSL` and `NGINX_CUSTOMSSL_VERSION`.

Nginx includes application-specific vhosts, security headers, compression,
FastCGI caching and per-site CORS. HTTP/2 is configured for TLS sites. HTTP/3 is
opt-in through `NGINX_HTTP3` and requires a build with `--with-http_v3_module`;
its UDP listener and `Alt-Svc` header are enabled only when supported.

`SERVER_PROFILE` selects `micro`, `small`, `medium`, `large` or automatic sizing
from RAM. Installation tunes Nginx, PHP-FPM and MariaDB for that profile. See
[resource sizing](ARCHITECTURE.md) and [site feature commands](CLI.md#site-features).

## PHP

LEMPer installs multiple PHP 8.2–8.5 runtimes, with 8.5 as the profile default.
The maintained Sury archive serves supported Debian/Ubuntu releases through its
managed signing-key package. Installation/update share source migration;
[the Resolute guide](UBUNTU_26_04.md) explains trust, backups and rollback.

Each runtime user has isolated FPM pools and Unix sockets. Pool temporary/session
directories remain outside public web roots. PHP 8.5 includes OPcache in its
binary. Optional loaders include ionCube and SourceGuardian.

Extensions use APT packages, with the OpenSwoole PPA when selected. PECL/PEAR is
not bundled; abandoned `geoip` and `mcrypt` extensions are excluded. Missing
extension packages are reported for deliberate upstream installation, such as
through [PIE](https://github.com/php/pie). Enable prerequisites in both CLI and
FPM before deploying an application.

PHP 8.1 is EOL and has no PHP2Shell vendor patch. See
[security updates and EOL migration](MAINTENANCE.md#php-security-updates-and-eol-migration),
[runtime defaults and Laravel](PHP_RUNTIME_LARAVEL.md), and
[application capabilities](APPLICATIONS.md).

## Optional services

| Component | Selection | Further guidance |
|---|---|---|
| MariaDB | `INSTALL_MYSQL`, `MYSQL_VERSION` | [Database accounts and backups](DATABASE.md); [native Resolute 11.8](UBUNTU_26_04.md) |
| PostgreSQL | `INSTALL_POSTGRES` | Profile options in [.env.dist](../.env.dist) |
| MongoDB | `INSTALL_MONGODB` | Profile options in [.env.dist](../.env.dist) |
| Redis/Valkey | `INSTALL_REDIS`, `REDIS_BACKEND` | Choose `redis` or `valkey` |
| Memcached | `INSTALL_MEMCACHED` | Profile options in [.env.dist](../.env.dist) |
| Bun.js | `INSTALL_BUNJS`, `BUNJS_VERSION` | Official amd64/arm64 binaries with published checksums; npm-compatible tooling |
| VSFTPD/Pure-FTPd | `INSTALL_FTP_SERVER`, `FTP_SERVER_NAME` | Select the server and its repository/source installer in the profile |
| Postfix/Dovecot | `INSTALL_MAILER` | [Mail accounts, domains and TLS](MAIL.md) |
| Restic | `INSTALL_RESTIC` | [Encrypted data backups](DATA_BACKUP.md) |
| Monit | `INSTALL_MONITORING` | [Health checks and alerts](MONITORING.md) |
| Filesystem quotas | `INSTALL_QUOTA` | [Hosting plans](HOSTING.md) |

Use [service lifecycle commands](CLI.md#service-lifecycle) to install, update,
control or remove individual components. Bun's `source` installer selects the
official binary path; legacy `repo` selects the same path. It does not compile
Bun from source.

## Security

The stack supports Let's Encrypt certificates, Fail2ban, optional CrowdSec
(`INSTALL_CROWDSEC`) and ModSecurity v3 with OWASP CRS (`INSTALL_MODSEC`).
CrowdSec can enable WordPress/PHP scenarios; `lemperctl modsec` provides status,
reporting and tuning. These choices depend on the installed components and
profile; they do not guarantee an external security-test grade.

TLS uses RFC 7919 `ffdhe2048` defaults. Optional rate limiting, archive-deny rules
and secure session cookies supplement private-file and PHP execution restrictions.
Nginx/FPM status endpoints bind to loopback for local monitoring.

Wildcard certificates support Cloudflare or DigitalOcean DNS-01 for issuance
and renewal. Configure `ACME_DNS_PROVIDER` and `ACME_DNS_API_TOKEN`; unattended
issuance also requires a server hostname. Provider credentials are stored in a
root-only file. Certificate issuance needs a reachable domain/provider setup;
local tests do not validate public ACME challenges.

`ENCRYPT_CONFIG_AT_REST` enables encrypted LEMPer credentials with a root-only
key at `/etc/lemper/.config_key`. The current encryption format uses
AES-256-CBC/PBKDF2; it is not an authenticated-encryption format. Protect both
keys and backups and retain an offline recovery copy.

Accounts use restricted administration and key-only SSH defaults. See
[installation prerequisites](INSTALLATION.md), [account credentials](CLI.md#configuration-and-credentials),
and [native firewall recovery/UFW migration](FIREWALL.md).

## Web administration

`INSTALL_WEB_ADMIN` enables the optional `/lcp/` tools; minimal profiles skip
them. The administration vhost uses HTTP basic authentication. Keep access
restricted and use the configured HTTPS endpoint or a protected SSH tunnel
before entering credentials.

The default HTTP administration endpoint is `http://SERVER_IP:8082/lcp/`:

| Tool | Path |
|---|---|
| Adminer SQL manager | `/lcp/dbadmin/` |
| TinyFileManager (experimental) | `/lcp/filemanager/` |
| OPcache status | `/lcp/opcache.php` |
| phpMemcachedAdmin | `/lcp/memcadmin/` |
| phpRedisAdmin | `/lcp/redisadmin/` |

Available tools also depend on installed services and PHP. The CLI and
[TUI](CLI.md) provide administration without web panels. Credentials remain in
protected local configuration; do not expose raw profiles or backup archives.
