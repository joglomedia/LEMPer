# [L]inux [E]ngine-X [M]ariaDB [P]HP Install[er]

<p align="center">
  <img src="/.github/assets/lemper-logo.svg?raw=true" alt="Served by LEMPer Stack © @joglomedia"/>
</p>

<p align="center">
<a href="https://github.com/joglomedia/LEMPer/releases"><img src="https://img.shields.io/github/v/tag/joglomedia/LEMPer?label=version" alt="LEMPer version"></a>
<a href="https://github.com/joglomedia/LEMPer/stargazers"><img src="https://img.shields.io/github/stars/joglomedia/LEMPer.svg" alt="GitHub stars"></a>
<a href="https://github.com/joglomedia/LEMPer/network"><img src="https://img.shields.io/github/forks/joglomedia/LEMPer.svg" alt="GitHub forks"></a>
<a href="https://github.com/joglomedia/LEMPer/issues"><img src="https://img.shields.io/github/issues/joglomedia/LEMPer.svg" alt="GitHub issues"></a>
<a href="https://github.com/joglomedia/LEMPer/actions/workflows/main.yml"><img src="https://github.com/joglomedia/LEMPer/actions/workflows/main.yml/badge.svg" alt="GitHub CI"></a>
<a href="https://raw.githubusercontent.com/joglomedia/LEMPer/master/LICENSE.md"><img src="https://img.shields.io/badge/license-GPLv3-blue.svg" alt="GitHub license"></a>
</p>

<p align="center">
LEMPer stands for Linux, Engine-X (Nginx), MariaDB and PHP installer written in Bash script, also known as LEMP / LNMP installer. This is just a small toolset (a bunch collection of scripts) that I use to deploy and manage LEMP stack on Debian and Ubuntu server. LEMPer is crafted to support wide-range PHP framework & CMS. It is available as <em>Free Alternative</em> to the paid control panel such as cPanel, Plesk, CloudWays, Ploi, RunCloud, ServerPilot, etc.
</p>

## Features

* Nginx - A high performance web server and a reverse proxy server.
  * Community packages from @eilandert's [MyGuard repo](https://deb.myguard.nl/nginx-modules/) (default, includes the module packages) or built from source. The Ondřej nginx repository is no longer published.
  * Custom build from [source](https://github.com/nginx/nginx) featured with :
    * [Brotli module](https://github.com/google/ngx_brotli.git) an alternative compression to Gzip
    * [Lua Nginx module](https://github.com/openresty/lua-nginx-module) with LuaJIT 2 library
    * FastCGI [cache purge module](https://github.com/nginx-modules/ngx_cache_purge.git) for atomic cache purging
    * Customizable SSL library: OpenSSL (default), LibreSSL, and BoringSSL
    * and much more useful 3rd-party modules.
  * Pre-configured optimization for low-end VPS/cloud server, auto-tuned at install time from the host's RAM and CPU (`micro`, `small`, `medium`, `large` profiles). Need reliable VPS/cloud server? Get one from [DigitalOcean](https://masedi.net/l/digitalocean/), [UpCloud](https://masedi.net/l/upcloud/), or [Vultr](https://masedi.net/l/vultr/).
  * Nginx virtual host (vhost) configuration optimized for WordPress and several PHP Frameworks.
  * Per-vhost CORS control with `lemper-cli site mod --enable-cors` and `--disable-cors`.
  * HTTP/2 on TLS vhosts, with opt-in HTTP/3 (QUIC) when the Nginx build provides the v3 module.
  * Free SSL certificates from [Let's Encrypt](https://letsencrypt.org/).
  * Get an A+ grade on several SSL Security Test ([Qualys SSL Labs](https://www.ssllabs.com/ssltest/analyze.html?d=masedi.net), [ImmuniWeb](https://www.immuniweb.com/ssl/?id=bVrykFnK), and Wormly).
* PHP - Most used language that [powers 78.9% of all websites](https://w3techs.com/technologies/details/pl-php) around the universe.
  * Community packages from [Ondřej's PHP repository](https://launchpad.net/~ondrej/+archive/ubuntu/php) (Sury on Debian).
  * Multiple PHP versions: 8.1 [EOL], 8.2 [Security], 8.3 [Security], 8.4 [Active], 8.5 [Latest, default].
  * PHP extensions are installed from apt repositories (Ondřej/Sury, plus the OpenSwoole PPA when selected). PECL/PEAR is no longer bundled: `geoip` and `mcrypt` are abandoned and excluded, and extensions with no package are reported so they can be built manually with [PIE](https://github.com/php/pie).
  * In-place security updater (`lemper-cli update`) with compensating controls for EOL branches.
  * Run PHP as user who own the file (Multi-user isolation via FPM pool).
  * Feel the faster Nginx with secure multi-user environment like a top-notch shared hosting.
  * Supported PHP Framework and CMS:
    * Vanilla PHP: default,
    * Framework: codeigniter, laravel, lumen, phalcon, symfony,
    * Content Management: drupal, wordpress, wordpress-ms (multi-site),
    * Web Application: mautic, owncloud, roundcube, sendy, and
    * more coming soon.
  * PHP Zend OPcache (built into the PHP 8.5 binary).
  * PHP Loader, ionCube & SourceGuardian.
* SQL database with MariaDB (MySQL drop-in replacement) or PostgreSQL.
* NoSQL database with MongoDB.
* Key-value store database with Redis or Valkey (`REDIS_BACKEND`).
* In-memory cache with Memcached.
* Modern JavaScript/TypeScript runtime with Bun.js, including an npm-compatible client and bundler (`INSTALL_BUNJS`, enabled by default).
* FTP server with VSFTPD or Pure-FTPd.
* Web-based administration tools:
  * [Adminer](https://github.com/vrana/adminer) web-based SQL database manager (PhpMyAdmin replacement).
  * [phpRedisAdmin](https://github.com/erikdubbelboer/phpRedisAdmin) web-based Redis database manager.
  * [phpMemcachedAdmin](https://github.com/elijaa/phpmemcachedadmin) web-based Memcached manager.
  * phpOpCacheStatus web-based OPcache status panel.
  * [TinyFileManager](https://github.com/joglomedia/tinyfilemanager) alternative web-based filemanager (Experimental).
* Security hardening:
  * Optional CrowdSec host-based intrusion prevention with WordPress and PHP application scenarios (`INSTALL_CROWDSEC`).
  * Optional ModSecurity v3 WAF with the OWASP Core Rule Set, plus `lemper-cli modsec` status, reporting, and auto-tuning (`INSTALL_MODSEC`).
  * Optional config-at-rest encryption (`ENCRYPT_CONFIG_AT_REST`) for LEMPer credentials, keyed by a root-only file (`/etc/lemper/.config_key`).
  * SSL/TLS defaults from the RFC 7919 `ffdhe2048` group, security headers, and optional rate limiting, archive-deny rules, and secure session cookies.
  * Optional HTTP/3 (QUIC) listeners and `Alt-Svc` advertising on TLS vhosts (`NGINX_HTTP3`, requires an Nginx built with `--with-http_v3_module`).
  * Loopback-only Nginx and PHP-FPM status endpoints for local monitoring.

## Setting Up

### Requirements

* Debian 11 (Bullseye) or 12 (Bookworm), or Ubuntu 22.04 or 24.04 (Linux Mint 21–22), on a 64-bit architecture.
* A fresh server with root (sudo) access. LEMPer is designed for a clean install and configures system services directly.
* git, curl, and a working apt repository connection.

### Clone and configure

* Ensure that you have git installed.
* Clone LEMPer Git repository, ```git clone https://github.com/joglomedia/LEMPer.git```
* Enter LEMPer directory
* Checkout to the desired version, ```git checkout 3.x.x```
* Make a copy of .env.dist to .env ```cp .env.dist .env``` and replace the values

### Install LEMPer Stack

```bash
sudo apt-get install git && \
git clone -q https://github.com/joglomedia/LEMPer.git && \
cd LEMPer && \
git checkout 3.x.x && \
cp -f .env.dist .env && \
sudo ./install.sh
```

### Remove LEMPer Stack

```bash
sudo ./remove.sh
```

Uninstall only tears down services that LEMPer provisioned. A service that
already existed before installation (for example, a pre-installed Nginx) is
left in place with its packages and configuration; set `FORCE_REMOVE=true` in
`.env` to remove it anyway.

### Update an Existing Installation

Legacy installations can be patched in place from a current checkout. The bootstrap
installs the latest CLI and updater plugin, records the checkout path, and then patches
the stack through the configured apt repositories.

```bash
sudo ./update.sh                 # install updater + update PHP, nginx, MariaDB, CLI
sudo ./update.sh --check         # install updater, then audit without patching
sudo ./update.sh --install-only  # install the updater, change no packages
```

Once installed:

```bash
sudo lemper-cli update check     # exit 0 only when every PHP branch is patched
sudo lemper-cli update all
sudo lemper-cli update php --post-max-size=8M
```

The updater remediates **PHP2Shell** (CVE-2026-109618 / CVE-2026-109619) by installing
PHP 8.2.35+, 8.3.36+, 8.4.27+, or 8.5.12+ from the configured apt repositories. PHP 8.1
and older branches have no vendor patch: the updater backs up their FPM pools and
admin-locks compensating controls (`memory_limit=-1`, `post_max_size=32M`,
`session.upload_progress.enabled=0`, and `fatal_error_backtraces=0` on PHP 8.5) before
reporting that migration is still required. Source-built nginx is detected and reported
as needing a rebuild.

### LEMPer Command Line Administration Tool

LEMPer packed with friendly command line tool which makes your LEMPer stack administration much easier. These command line tool called Lemper CLI (lemper-cli) for creating new virtual host and managing existing LEMPer stack.

An interactive TUI is available for menu-driven management, live service logs, a guided site-creation wizard, and hardware, disk, and network benchmarks:

```bash
sudo lemper-cli tui
```

#### LEMPer CLI Usage

Here are some examples of using LEMPer CLI.

##### LEMPer CLI add new vhost / website

```bash
lemper-cli site add -u ${USER} -d example.test -f wordpress \
-w ${HOME}/webapps/example.test --install-app
```

:warning: For local/development environment, in order to make the test domain (e.g. example.test) working as expected, you need to do a small workaround by modifying the `/etc/hosts` file. By adding the local domain name to the hosts file and assign it with local/private IP address.

Since version 2.4.0, this workaround could be done via `lemper-cli` by passing `--ipv4` parameter and assign it with private IP address, as below:

```bash
lemper-cli site add -u ${USER} -d example.test -f wordpress \ 
-w ${HOME}/webapps/example.test --ipv4=127.0.10.1 --install-app
```

For more info

```bash
lemper-cli site add --help
```

##### LEMPer CLI manage vhost / website

Example, enable SSL

```bash
sudo lemper-cli site mod --enable-ssl example.test
```

Example, enable FastCGI cache

```bash
sudo lemper-cli site mod --enable-fastcgi-cache example.test
```

Example, enable or disable CORS

```bash
sudo lemper-cli site mod --enable-cors example.test
sudo lemper-cli site mod --disable-cors example.test
```

`--enable-cors` allows every origin by default. To restrict it, edit the
`set $cors` line in `/etc/nginx/includes/cors-example.test.conf` and reload
Nginx (`sudo systemctl reload nginx`).

For more info

```bash
sudo lemper-cli site mod --help
```

##### LEMPer CLI back up and restore configuration

`lemper-cli backup` archives the configuration LEMPer manages — Nginx, PHP,
MySQL/MariaDB, Redis/Valkey, Memcached, Fail2ban, CrowdSec, ModSecurity
tuning, mail, FTP, Let's Encrypt, `/etc/lemper`, and legacy `.env` files — so
a broken change can be rolled back. Web content and database data are not
included.

```bash
sudo lemper-cli backup create          # archive to /var/backups/lemper/config
sudo lemper-cli backup list            # list archives
sudo lemper-cli backup show latest     # print the newest archive manifest
sudo lemper-cli backup restore --latest --reload
sudo lemper-cli backup prune --keep 5
```

`restore` verifies the archive and the member allow-list first, writes a
pre-restore snapshot to the same directory, runs `nginx -t` afterwards, and
rolls back automatically if the test fails. Archives contain credentials and
private keys, so they are created root-only (mode 0600).

##### LEMPer CLI benchmark the server

`lemper-cli bench` reports hardware details, measures disk write/read speed,
and downloads a test file from global endpoints. Downloads use curl's own
speed counter with a per-endpoint timeout, and endpoints that fail are
reported as unavailable instead of printing an empty speed.

```bash
sudo lemper-cli bench                          # hardware, disk, and network
sudo lemper-cli bench --hardware --disk        # no downloads
sudo lemper-cli bench --network --size 100 --timeout 60
sudo lemper-cli bench --disk --disk-size 1024
```

The same tests are available from the TUI under **Benchmark**. Network tests
use bandwidth: each endpoint receives the configured test size (default
32 MB).

##### for more help

```bash
sudo lemper-cli help
```

Note: LEMPer CLI automagically create new PHP-FPM user's pool configuration if it doesn't exists. You must add the user account first.

### Web-based Administration

You can access pre-installed web-based administration tools here.

```bash
http://YOUR_IP_ADDRESS:8082/lcp/
```

Adminer (web-based SQL database manager)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/dbadmin/
```

TinyFileManager (web-based file manager)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/filemanager/
```

phpOpCacheStatus (OPcache status panel)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/opcache.php
```

phpMemcachedAdmin and phpRedisAdmin

```bash
http://YOUR_IP_ADDRESS:8082/lcp/memcadmin/
http://YOUR_IP_ADDRESS:8082/lcp/redisadmin/
```

## TODOs

Implemented:

* [x] Add support for Debian (Bullseye, Bookworm) & Ubuntu (Jammy, Noble) distro
* [x] Add custom build latest [Nginx](https://nginx.org/en/) from source
* [x] Add [Let's Encrypt SSL](https://letsencrypt.org/)
* [x] Add network security (iptable rules, firewall configurator, else?)
* [x] Add database backup tool (Mariabackup, Percona Xtrabackup, else?)
* [x] Add PostgreSQL database (SQL object-relational database system)
* [x] Add Pure-FTPd installation as an alternative option to VSFTPD
* [x] Add enhanced security (firewall, Fail2ban, CrowdSec, ModSecurity WAF)
* [x] Add CrowdSec a modern Host-based Intrusion Prevention System (modern-replacement for Fail2ban)
* [x] Add Bun.js JavaScript/TypeScript runtime (Node.js-compatible npm client and bundler)
* [x] Add in-place security updater (`lemper-cli update`, PHP2Shell remediation)
* [x] Add interactive TUI dashboard and site-creation wizard
* [x] Add user account management (`lemper-cli account`, PHP-FPM pool isolation)

Planned:

* [ ] Add native Node.js installation to support modern web frontend development (Bun.js is available as a Node.js-compatible runtime)
* [ ] Add file backup tool (Borg, Duplicati, Rclone, Restic, Rsnapshot, else?)
* [ ] Add server monitoring (Netdata, Monit, Nagios, Zabbix, else?); loopback Nginx/PHP-FPM status endpoints are already shipped
* [ ] Add hosting package management (per-user quotas and provisioning)

Add your feature [request here](https://github.com/joglomedia/LEMPer/issues/new)!

## Security Vulnerabilities and Bugs

If you discover any security vulnerabilities or any bugs within _LEMPer Stack_, please open an [issue](https://github.com/joglomedia/LEMPer/issues/new).

## Contributing

* Fork it ([https://github.com/joglomedia/LEMPer/fork](https://github.com/joglomedia/LEMPer/fork))
* Create your feature branch (git checkout -b my-new-feature) or fix issue (git checkout -b fix-some-issue)
* Commit your changes (git commit -am 'Add some feature') or (git commit -am 'Fix some issue')
* Push to the branch (git push origin my-new-feature) or (git push origin fix-some-issue)
* Create a new Pull Request
* GitHub Workflows will be run to make sure that your changes does not have errors or warning

## Awesome People

**LEMPer Stack** is an open-source project licensed under the GNU GPLv3 license with its ongoing development made possible entirely by the support of all these smart and generous people, from code contributors to financial contributors. :purple_heart:

Thank you for considering contributing to this project!

### Project Maintainers

<table>
  <tbody>
    <tr>
        <td align="center" valign="top">
            <img width="125" height="125" src="https://github.com/joglomedia.png?s=150">
            <br>
            <strong>Edi Septriyanto</strong>
            <br>
            <a href="https://github.com/joglomedia">@joglomedia</a>
        </td>
     </tr>
  </tbody>
</table>

### Code Contributors

<a href="https://github.com/joglomedia/LEMPer/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=joglomedia/LEMPer" />
</a>

Made with [contributors-img](https://contrib.rocks).

### Financial Contributors

You can support development by using any of the methods below:

**[Buy Me a Bottle of Milk or a Cup of Coffee](https://paypal.me/masedi) !!**

## Licence

LEMPer Stack is open-source project licensed under the GNU GPLv3 license.

## Copyright

(c) 2014-2026 | [MasEDI.Net](https://masedi.net/)

### Enjoy LEMPer Stack ;)
