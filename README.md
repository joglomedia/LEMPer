# [L]inux [E]ngine-X [M]ariaDB [P]HP Install[ER]
LEMPer stands for Linux, Engine-X (Nginx), MariaDB and PHP installer written in Bash script. This is just a small tool set (a bunch collection of scripts) that usually I use to deploy and manage Debian-based/Ubuntu LEMP stack. LEMPer is _ServerPilot_, _CloudWays_, _RunCloud_, and _EasyEngine_ alternative for wide range PHP framework.


[![Build Status](https://travis-ci.org/joglomedia/LEMPer.svg?branch=1.2.0)](https://travis-ci.org/joglomedia/LEMPer)


## Features
* Nginx from custom repository & build from source.
* Nginx with FastCGI cache enable & disable feature.
* Nginx pre-configured optimization for low-end VPS/cloud server. Need reliable VPS/cloud server? Get one [here](https://eslabs.id/digitalocean/) or [here](https://eslabs.id/upcloud/).
* Nginx virtual host (vhost) configuration optimized for WordPress, and several PHP Framework (CodeIgniter, Symfony, Laravel, Phalcon).
* MariaDB 10 (MySQL drop-in replacement).
* In-memory database with Redis.
* Memory cache with Memcached.
* PHP 5.6, 7.0, 7.1, 7.2, 7.3 from [Ondrej's repository](https://launchpad.net/~ondrej/+archive/ubuntu/php).
* PHP-FPM sets as user running the PHP script (pool), Feel the faster Nginx with multi-user FPM like a top-notch shared hosting.
* Zend OPcache.
* ionCube PHP Loader.
* SourceGuardian PHP Loader.
* [Adminer](https://www.adminer.org/) for MySQL database administration (PhpMyAdmin replacement).

## Setting Up

* Ensure you have git installed.
* Make a copy of .env.dist to .env in the LEMPer base directory and replace the values.
* Enter LEMPer directory.
* Execute lemper.sh file.

### Install Nginx, PHP &amp; MariaDB
```bash
sudo apt-get install git
git clone -q https://github.com/joglomedia/LEMPer.git; cd LEMPer; cp .env-sample .env; sudo ./lemper.sh --install
```

### Uninstall Nginx, PHP &amp; MariaDB
```bash
sudo ./lemper.sh --remove
```

## LEMPer Command Line Administration Tool
LEMPer comes with friendly command line tool which will make your LEMP stack administration much more easier. These command line tool called Lemper CLI (lemper-cli) for creating new virtual host and managing existing LEMP stack.

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

Note: Lemper CLI will automagically add new PHP-FPM user's pool configuration if it doesn't exists.

## Web-based Administration
You can access pre-installed web-based administration tools here
```bash
http://YOUR_IP_ADDRESS:8082/lcp/
```
Adminer (SQL database management tool)
```bash
http://YOUR_DOMAIN_NAME:8082/lcp/dbadminer
```
FileRun (File management tool)
```bash
http://YOUR_DOMAIN_NAME:8082/lcp/filemanager
```

## TODO
* ~~Custom build latest [Nginx](https://nginx.org/en/) from source~~
* ~~Add [Let's Encrypt SSL](https://letsencrypt.org/)~~
* ~~Add network security (iptable rules, firewall configurator, else?)~~
* Add enhanced security (AppArmor, cgroups, jailkit (chrooted/jail users), else?)
* Add file backup tool (Restic, Borg, Rsnapshot, else?)
* ~~Add database backup tool (Mariabackup, Percona Xtrabackup, else?)~~
* Add server monitoring (Amplify, Monit, Nagios, else?)
* Add your feature [request here](https://github.com/joglomedia/LEMPer/issues/new).

## Contribution
Please send your PR on the Github repository to help improve this script.

## TLDR;
Do not use this script if you're looking for feature rich and advanced tool like premium service.

## DONATION
**[Buy Me a Bottle of Milk](https://paypal.me/masedi) !!**

## Copyright
(c) 2014-2019
