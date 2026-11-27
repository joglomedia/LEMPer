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

### Updating existing managed virtual hosts

Package updates preserve the active Nginx configuration. Back up the current
configuration and merge the following changes from this release into existing
managed sites. Review custom and adopted virtual hosts individually. For sites
with both HTTP and HTTPS configurations, update both variants before reloading.

1. Merge the shipped default or default-SSL template into the active default
   configuration. Preserve the hostname and certificate paths. Deny `/lcp` on
   the public content server and bind the no-certificate fallback to loopback.
   [Enroll each verified administrator](CLI.md#web-administration-accounts)
   before switching the active administration server to
   `/etc/nginx/lemper-admin.htpasswd`. Preserve `/srv/.htpasswd` for unrelated
   hosting authentication and enroll management identities individually.
2. In hosted sites, place access and error logs under the service-controlled
   `/var/log/nginx` directory, using `<domain>.access.log` and
   `<domain>.error.log`. Use `flush=5s` if buffering the access log. Apply
   `disable_symlinks if_not_owner;` to managed site blocks and review deliberate
   symlinks whose owners differ. Merge the shipped logrotate pattern and update
   any log consumers that followed the former per-account paths.
3. For legacy WordPress Multisite media routing, point the hostname map at
   `/etc/nginx/wpms/<domain>/*.conf`. Create that directory under root ownership
   with no tenant write access. If legacy media depends on the map, create a
   root-owned `sites.conf` using one verified hostname and numeric site ID per
   line, such as `site.example.test 2;`. Consult the site's administrator for
   the current mapping and maintain it as sites change. The Nginx Helper plugin's
   tenant-owned uploads output is no longer a live configuration source.
4. For an explicitly enabled reverse-proxy cache, merge both shipped proxy
   cache files. Check any custom bypass rules and disable shared caching on
   routes that use additional kinds of authentication.
5. Run `sudo nginx -t` before reloading. After Nginx has opened the new access
   log, update each existing Fail2ban jail to read the matching daemon-owned
   log and reload Fail2ban. Use `sudo lemperctl site update --enable-fail2ban
   <domain>` for a managed site with a supported filter. A site created with
   an optional jail request stays installed if the jail could not be enabled.

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

LEMPer-managed Memcached installations give the `memcache` and `www-data`
service accounts separate private sockets at
`/run/lemper-memcached-memcache/memcached.sock` and
`/run/lemper-memcached-www-data/memcached.sock`. With `MEMCACHED_SASL=true`,
the `memcache` instance instead accepts authenticated binary-protocol clients
on `127.0.0.1:11211`. Give each hosting tenant its own cache instance and
credentials when tenant applications need cache access.

Existing managed installations retain their listeners during a tooling update.
After preparing each client for the appropriate new endpoint, run
`sudo lemperctl stack install memcached --force`
to switch the two instances. The migration restarts the managed instances,
starts with empty caches, and saves the old configuration next to each instance
file with the suffix `.lemper-before-endpoints`. Existing SASL setups need
`sasl2-bin` and their saved credentials to retain the authenticated listener.

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
them. The administration vhost uses HTTP Basic authentication with a dedicated
administrator verifier at `/etc/nginx/lemper-admin.htpasswd`. Normal hosting
credentials grant access only where hosting authentication is intentionally
configured. Use the configured HTTPS endpoint or a protected SSH tunnel before
entering management credentials.

The fallback listener binds to loopback. Forward port 8082 over SSH and open `http://127.0.0.1:8082/lcp/`. With TLS configured, use the administration hostname on port 8083.

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
