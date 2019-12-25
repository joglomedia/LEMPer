# [L]inux [E]ngine-X [M]ariaDB [P]HP Install[ER]

LEMPer stands for Linux, Engine-X (Nginx), MariaDB and PHP installer written in Bash script. This is just a small tool set (a bunch collection of scripts) that usually I use to deploy and manage Debian-based/Ubuntu LEMP stack. LEMPer is _ServerPilot_, _CloudWays_, _RunCloud_, _WordOps_, and _EasyEngine_ alternative crafted to support wide-range PHP framework (not only WordPress).

[![Build Status](https://travis-ci.org/joglomedia/LEMPer.svg?branch=1.3.0)](https://travis-ci.org/joglomedia/LEMPer)

## Features

* Nginx from [Ondrej's repository](https://launchpad.net/~ondrej/+archive/ubuntu/nginx)
* Nginx build from [source](https://github.com/nginx/nginx) with [Mod PageSpeed](https://github.com/apache/incubator-pagespeed-ngx) module.
* Nginx with FastCGI cache enable & disable feature (via LEMPer CLI).
* Nginx pre-configured optimization for low-end VPS/cloud server. Need reliable VPS/cloud server? Get one  [here](https://eslabs.id/upcloud/) or [here](https://eslabs.id/digitalocean/).
* Nginx virtual host (vhost) configuration optimized for WordPress, and several PHP Framework.
* Supported PHP Framework and CMS: default (vanilla PHP), framework (codeigniter, laravel, lumen, phalcon, symfony), CMS (drupal, mautic, roundcube, sendy, wordpress, wordpress-ms), and more coming soon.
* Multiple PHP version 5.6 [EOL], 7.0 [EOL], 7.1, 7.2, 7.3, 7.4 from [Ondrej's repository](https://launchpad.net/~ondrej/+archive/ubuntu/php).
* PHP sets as user running the PHP script (via FPM's pool). Feel the faster Nginx with secure multi-user environment like a top-notch shared hosting.
* PHP Zend OPcache.
* PHP Loader (ionCube & SourceGuardian).
* SQL database with MariaDB 10 (MySQL drop-in replacement).
* In-memory database with Redis.
* Memory cache with Memcached.
* NoSQL database with MongoDB *NEW*.
* [Adminer](https://www.adminer.org/) web-based MySQL database administration (PhpMyAdmin replacement).
* [TinyFileManager](https://github.com/prasathmani/tinyfilemanager) alternative web-based filemanager (Experimental).

## Setting Up

* Ensure that you have git installed.
* Make a copy of .env.dist to .env in the LEMPer base directory and replace the values.
* Enter LEMPer directory.
* Execute lemper.sh file, ```sudo ./lemper.sh --install```.

### Installing LEMP stack

```bash
sudo apt-get install git && git clone -q https://github.com/joglomedia/LEMPer.git && cd LEMPer && cp -f .env.dist .env && sudo ./lemper.sh --install
```

### Removing LEMP stack

```bash
sudo ./lemper.sh --remove
```

## LEMPer Command Line Administration Tool

LEMPer comes with friendly command line tool which will make your LEMP stack administration much easier. These command line tool called Lemper CLI (lemper-cli) for creating new virtual host and managing existing LEMP stack.

### lemper-cli Usage

Add/create new virtual host

```bash
sudo lemper-cli create -u username -d example.app -f default -w /home/username/Webs/example.app
```

Manage/update existing virtual host

```bash
sudo lemper-cli manage --enable-fastcgi-cache example.app
```

for more help

```bash
sudo lemper-cli --help
```

Note: Lemper CLI will automagically add a new PHP-FPM user's pool configuration if it doesn't exists. You must add the user account first.

## Web-based Administration

You can access pre-installed web-based administration tools here

```bash
http://YOUR_IP_ADDRESS:8082/lcp/
```

Adminer (Web-based SQL database managemer)

```bash
http://YOUR_DOMAIN_NAME:8082/lcp/dbadmin
```

TinyFilemanage (Web-based file managemer)

```bash
http://YOUR_DOMAIN_NAME:8082/lcp/filemanager
```

## TODO

* ~~Custom build latest [Nginx](https://nginx.org/en/) from source~~
* ~~Add [Let's Encrypt SSL](https://letsencrypt.org/)~~
* ~~Add network security (iptable rules, firewall configurator, else?)~~
* Add enhanced security (AppArmor, cgroups, jailkit (chrooted/jail users), fail2ban, else?)
* Add file backup tool (Borg, Restic, Rclone, Rsnapshot, else?)
* ~~Add database backup tool (Mariabackup, Percona Xtrabackup, else?)~~
* Add server monitoring (Amplify, Monit, Nagios, else?)
* Add user account & hosting package management.
* Add your feature [request here](https://github.com/joglomedia/LEMPer/issues/new).

## Contribution

Please send your PR on the Github repository to help improve this script.

## TL;DR

If you're looking for mature, feature rich, advanced, and 24/7 premium service, please don't use this script.

## DONATION

**[Buy Me a Bottle of Milk](https://paypal.me/masedi) !!**

## SPONSORSHIP

Be the first one!

## Copyright

(c) 2014-2019
