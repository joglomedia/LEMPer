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
  * Community package from [Ondrej repo](https://launchpad.net/~ondrej/+archive/ubuntu/nginx) or @eilandert's [MyGuard repo](https://deb.myguard.nl/nginx-modules/) with built-in PageSpeed module.
  * Custom build from [source](https://github.com/nginx/nginx) featured with :
    * [Brotli module](https://github.com/google/ngx_brotli.git) an alternative compression to Gzip
    * [Lua Nginx module](https://github.com/openresty/lua-nginx-module) with LuaJIT 2 library
    * [PageSpeed module](https://github.com/apache/incubator-pagespeed-ngx) an automatic PageSpeed optimization
    * FastCGI [cache purge module](https://github.com/nginx-modules/ngx_cache_purge.git) for atomic cache purging
    * Customizable SSL library: OpenSSL (default), LibreSSL, and BoringSSL
    * and much more useful 3rd-party modules.
  * Pre-configured optimization for low-end VPS/cloud server. Need reliable VPS/cloud server? Get one from [UpCloud](https://masedi.net/l/upcloud/) or [DigitalOcean](https://masedi.net/l/digitalocean/).
  * Nginx virtual host (vhost) configuration optimized for WordPress and several PHP Frameworks.
  * Support HTTP/2 natively for your secure website.
  * Free SSL certificates from [Let's Encrypt](https://letsencrypt.org/).
  * Get an A+ grade on several SSL Security Test ([Qualys SSL Labs](https://www.ssllabs.com/ssltest/analyze.html?d=masedi.net), [ImmuniWeb](https://www.immuniweb.com/ssl/?id=bVrykFnK), and Wormly).
* PHP - Most used language that [powers 78.9% of all websites](https://w3techs.com/technologies/details/pl-php) around the universe.
  * Community package from [Ondrej's PHP repository](https://launchpad.net/~ondrej/+archive/ubuntu/php).
  * Multiple PHP versions ~5.6 [EOL]~, ~7.0 [EOL]~, ~7.1 [EOL]~, ~7.2 [EOL]~, ~7.3 [EOL]~, 7.4 [SFO], 8.0, 8.1, 8.2 (Latest).
  * Run PHP as user who own the file (Multi-user isolation via FPM pool).
  * Feel the faster Nginx with secure multi-user environment like a top-notch shared hosting.
  * Supported PHP Framework and CMS:
    * Vanilla PHP: default,
    * Framework: codeigniter, laravel, lumen, phalcon, symfony,
    * CMS: drupal, mautic, roundcube, sendy, wordpress, wordpress-ms (multi-site), and
    * more coming soon.
  * PHP Zend OPcache.
  * PHP Loader, ionCube & SourceGuardian.
* SQL database with MariaDB (MySQL drop-in replacement) or PostgreSQL.
* NoSQL database with MongoDB.
* Key-value store database with Redis.
* In-memory cache with Memcached.
* FTP server with VSFTPD or Pure-FTPd.
* Web-based administration tools:
  * [Adminer](https://www.adminer.org/) web-based SQL & MongoDB database manager (PhpMyAdmin replacement).
  * [phpRedisAdmin](https://github.com/erikdubbelboer/phpRedisAdmin) web-based Redis database manager.
  * [phpMemcachedAdmin](https://github.com/elijaa/phpmemcachedadmin) web-based Memcached manager.
  * [TinyFileManager](https://github.com/joglomedia/tinyfilemanager) alternative web-based filemanager (Experimental).

## Setting Up

* Ensure that you have git installed.
* Clone LEMPer Git repositroy, ```git clone https://github.com/joglomedia/LEMPer.git```
* Enter LEMPer directory
* Checkout to the desired version, ```git checkout 2.x.x```
* Make a copy of .env.dist to .env ```cp .env.dist .env``` and replace the values

### Install LEMPer Stack

```bash
sudo apt-get install git && \
git clone -q https://github.com/joglomedia/LEMPer.git && \
cd LEMPer && \
cp -f .env.dist .env && \
sudo ./install.sh
```

### Remove LEMPer Stack

```bash
sudo ./remove.sh
```

### LEMPer Command Line Administration Tool

LEMPer packed with friendly command line tool which will make your LEMP stack administration much easier. These command line tool called Lemper CLI (lemper-cli) for creating new virtual host and managing existing LEMP stack.

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
sudo lemper-cli manage --enable-ssl example.test
```

Example, enable FastCGI cache

```bash
sudo lemper-cli manage --enable-fastcgi-cache example.test
```

For more info

```bash
sudo lemper-cli manage --help
```

##### for more help

```bash
sudo lemper-cli help
```

Note: LEMPer CLI automagically add a new PHP-FPM user's pool configuration if it doesn't exists. You must add the user account first.

### Web-based Administration

You can access pre-installed web-based administration tools here.

```bash
http://YOUR_IP_ADDRESS:8082/lcp/
```

Adminer (Web-based SQL database manager)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/dbadmin/
```

TinyFileManager (Web-based file manager)

```bash
http://YOUR_IP_ADDRESS:8082/lcp/filemanager/
```

## TODOs

* [x] Custom build latest [Nginx](https://nginx.org/en/) from source
* [x] Add [Let's Encrypt SSL](https://letsencrypt.org/)
* [x] Add network security (iptable rules, firewall configurator, else?)
* [x] Add database backup tool (Mariabackup, Percona Xtrabackup, else?)
* [x] Add PostgreSQL database (SQL object-relational database system)
* [x] Add Pure-FTPd installation as an alternative option to VSFTPD
* [x] Add enhanced security (AppArmor, cgroups, jailkit (chrooted/jail users), fail2ban, else?)
* [ ] Add CrowdSec a modern Host-based Intrusion Prevention System (modern-replacement for Fail2ban)
* [ ] Add NodeJS installation to support modern web frontend development
* [ ] Add file backup tool (Borg, Duplicati, Rclone, Restic, Rsnapshot, else?)
* [ ] Add server monitoring (Amplify, Monit, Nagios, else?)
* [ ] Add user account & hosting package management

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

(c) 2014-2023 | [MasEDI.Net](https://masedi.net/)

### Enjoy LEMPer Stack ;)
