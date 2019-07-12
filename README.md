# [L]inux [E]ngine-X [M]ariaDB [P]HP Install[ER]
LEMPer stands for Linux, Engine-X (Nginx), MariaDB and PHP installer written in Bash script. This is just a small tool set (a bunch collection of scripts) that usually I use to deploy and manage Ubuntu-LEMP stack. LEMPer is _ServerPilot_, _RunCloud_, and _EasyEngine_ alternative for wide range PHP framework.

## Features
* Nginx from custom repository & build from source.
* Nginx with FastCGI cache enable & disable feature.
* Nginx pre-configured optimization for low-end VPS/cloud server. Need reliable VPS/cloud server? Get one [here](https://eslabs.id/digitalocean/) or [here](https://eslabs.id/upcloud/).
* Nginx virtual host (vhost) configuration optimized for WordPress, and several PHP Framework (CodeIgniter, Symfony, Laravel, Phalcon).
* MariaDB 10 (MySQL drop-in replacement).
* In-memory database with Redis.
* Memory cache with Memcached.
* PHP 5.6, 7.0, 7.1, 7.2, 7.3 from [Ondrej's repository](https://launchpad.net/~ondrej/+archive/ubuntu/php).
* PHP-FPM sets as user running the PHP script (pool), Feel the faster Nginx with multi-user like a top-notch shared hosting.
* Zend OPcache.
* ionCube PHP Loader.
* SourceGuardian PHP Loader.
* [Adminer](https://www.adminer.org/) (PhpMyAdmin replacement)

## Usage

### Install Nginx, PHP &amp; MariaDB
```bash
sudo apt-get install git
git -q clone https://github.com/joglomedia/LEMPer.git; cd LEMPer; sudo ./lemper.sh --install
```

### Uninstall Nginx, PHP &amp; MariaDB
```bash
sudo ./lemper.sh --uninstall
```

## Nginx vHost Configuration Tool (ngxvhost)
This script also include Nginx Virtual Host (vHost) configuration tool helping you add new website (domain) easily.
The ngxvhost must be run as root (recommended using sudo).

### Ngxvhost Usage
```bash
sudo ngxvhost -u username -d example.com -f default -w /home/username/Webs/example.com
```
Ngxvhost Parameters:

* -u username, system user name (DO NOT use root login)
* -d domain name, your website domain or sub-domain name
* -f framework type, available options: default, codeigniter, laravel, phalcon, wordpress, wordpress-ms (multisite)
* -w web root, absolute path to your website directory containing the index file (we recommend you to use user home directory)

for more info
```bash
sudo ngxvhost --help
```

Note: ngxvhost will automagically add new FPM user's pool configuration file if it doesn't exists.

## Web-based Administration
You can access pre-installed web-based administration tools here
```bash
http://YOUR_IP_ADDRESS/tools/
```
Adminer (SQL database management tool)
```bash
http://YOUR_DOMAIN_NAME:8082/
```
FileRun (File management tool)
```bash
http://YOUR_DOMAIN_NAME:8083/
```

## TODO
* ~~Custom build latest [Nginx](https://nginx.org/en/) from source.~~
* Add [Let's Encrypt SSL](https://letsencrypt.org/).
* Add security hardening (iptable rules, firewall, else?).
* Add server monitoring (Nagios, Monit, else?).
* Add your feature [request here](https://github.com/joglomedia/LEMPer/issues/new).

## Contribution
Please send your PR on the Github repository to help improve this script.

## TLDR;
Do not use this script if you're looking for feature rich and advanced tool like premium service.

## DONATION
**[Buy Me a Bottle of Milk](https://paypal.me/masedi) !!**

## Copyright
(c) 2014-2019
