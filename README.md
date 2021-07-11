# [L]inux [E]ngine-X [M]ariaDB [P]HP Install[ER]

<p align="center">
<pre><!--
Served by
 _     _____ __  __ ____           
| |   | ____|  \/  |  _ \ ___ _ __ 
| |   |  _| | |\/| | |_) / _ \ '__|
| |___| |___| |  | |  __/  __/ |   
|_____|_____|_|  |_|_|   \___|_|      
--></pre>
</p>

<p align="center">
<a href="https://github.com/joglomedia/LEMPer/releases"><img src="https://img.shields.io/github/v/tag/joglomedia/LEMPer?label=version" alt="LEMPer version"></a>
<a href="https://github.com/joglomedia/LEMPer/network"><img src="https://img.shields.io/github/forks/joglomedia/LEMPer.svg" alt="GitHub forks"></a>
<a href="https://github.com/joglomedia/LEMPer/issues"><img src="https://img.shields.io/github/issues/joglomedia/LEMPer.svg" alt="GitHub issues"></a>
<a href="https://github.com/joglomedia/LEMPer/stargazers"><img src="https://img.shields.io/github/stars/joglomedia/LEMPer.svg" alt="GitHub stars"></a>
<a href="https://github.com/joglomedia/LEMPer/actions/workflows/main.yml"><img src="https://github.com/joglomedia/LEMPer/actions/workflows/main.yml/badge.svg" alt="GitHub CI"></a>
<a href="https://raw.githubusercontent.com/joglomedia/LEMPer/master/LICENSE.md"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="GitHub license"></a>
</p>

<p align="center">
LEMPer stands for Linux, Engine-X (Nginx), MariaDB and PHP installer written in Bash script. This is just a small tool set (a bunch collection of scripts) that usually I use to deploy and manage LEMP stack on Debian/Ubuntu. LEMPer is _CloudWays_, _Ploi_, _RunCloud_, and _ServerPilot_ free alternative crafted to support wide-range PHP framework (not only WordPress).
</p>

## Features

* Nginx from [Ondrej's](https://launchpad.net/~ondrej/+archive/ubuntu/nginx) repository.
* Nginx build from [source](https://github.com/nginx/nginx) with [Mod PageSpeed](https://github.com/apache/incubator-pagespeed-ngx) module.
* Nginx with FastCGI cache enable & disable feature (via LEMPer CLI).
* Nginx pre-configured optimization for low-end VPS/cloud server. Need reliable VPS/cloud server? Get one from [UpCloud](https://masedi.net/upcloud/) or [DigitalOcean](https://masedi.net/digitalocean/).
* Nginx virtual host (vhost) configuration optimized for WordPress, and several PHP Frameworks.
* Support HTTP/2 natively for your secure website.
* Free SSL certificates from [Let's Encrypt](https://letsencrypt.org/).
* Get an A+ grade on several SSL Security Test ([Qualys SSL Labs](https://www.ssllabs.com/ssltest/analyze.html?d=masedi.net), [ImmuniWeb](https://www.immuniweb.com/ssl/?id=bVrykFnK), and Wormly).
* Multiple PHP versions 5.6 [EOL], 7.0 [EOL], 7.1 [EOL], 7.2 [EOL], 7.3 [SFO], 7.4, 8.0 from [Ondrej's repository](https://launchpad.net/~ondrej/+archive/ubuntu/php).
* Run PHP as user who own the file (Multi-user isolation via FPM pool). Feel the faster Nginx with secure multi-user environment like a top-notch shared hosting.
* Supported PHP Framework and CMS:
  * Vanilla PHP: default,
  * Framework: codeigniter, laravel, lumen, phalcon, symfony,
  * CMS: drupal, mautic, roundcube, sendy, wordpress, wordpress-ms (multi-site), and
  * more coming soon.
* PHP Zend OPcache.
* PHP Loader, ionCube & SourceGuardian.
* SQL database with MariaDB 10 (MySQL drop-in replacement).
* NoSQL database with MongoDB.
* In-memory database with Redis.
* Memory cache with Memcached.
* [Adminer](https://www.adminer.org/) web-based SQL & MongoDB database manager (PhpMyAdmin replacement).
* [phpRedisAdmin](https://github.com/erikdubbelboer/phpRedisAdmin) web-based Redis database manager.
* [phpMemcachedAdmin](https://github.com/elijaa/phpmemcachedadmin) web-based Memcached manager.
* [TinyFileManager](https://github.com/prasathmani/tinyfilemanager) alternative web-based filemanager (Experimental).

## Setting Up

* Ensure that you have git installed.
* Clone LEMPer Git repositroy, ```git clone https://github.com/joglomedia/LEMPer.git```.
* Enter LEMPer directory.
* Make a copy of .env.dist to .env ```cp .env.dist .env``` and replace the values.
* Execute install.sh file, ```sudo ./install.sh```.

### Install LEMPer Stack

```bash
sudo apt install git && git clone -q https://github.com/joglomedia/LEMPer.git && cd LEMPer && cp -f .env.dist .env && sudo ./install.sh
```

### Remove LEMPer Stack

```bash
sudo ./remove.sh
```

### LEMPer Command Line Administration Tool

LEMPer comes with friendly command line tool which will make your LEMP stack administration much easier. These command line tool called Lemper CLI (lemper-cli) for creating new virtual host and managing existing LEMP stack.

#### LEMPer CLI Usage

Here are some examples of using LEMPer CLI.

##### LEMPer CLI add new vhost / website

```bash
sudo lemper-cli create -u username -d example.app -f default -w /home/username/Webs/example.app
```

##### LEMPer CLI manage vhost / website

Example, enable SSL

```bash
sudo lemper-cli manage --enable-ssl example.app
```

Example, enable FastCGI cache

```bash
sudo lemper-cli manage --enable-fastcgi-cache example.app
```

##### for more help

```bash
sudo lemper-cli --help
```

Note: Lemper CLI will automagically add a new PHP-FPM user's pool configuration if it doesn't exists. You must add the user account first.

### Web-based Administration

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

## TODOs

* ~~Custom build latest [Nginx](https://nginx.org/en/) from source~~
* ~~Add [Let's Encrypt SSL](https://letsencrypt.org/)~~
* ~~Add network security (iptable rules, firewall configurator, else?)~~
* Add enhanced security (AppArmor, cgroups, jailkit (chrooted/jail users), fail2ban, else?)
* Add file backup tool (Borg, Duplicati, Rclone, Restic, Rsnapshot, else?)
* ~~Add database backup tool (Mariabackup, Percona Xtrabackup, else?)~~
* Add server monitoring (Amplify, Monit, Nagios, else?)
* Add user account & hosting package management.
* Add your feature [request here](https://github.com/joglomedia/LEMPer/issues/new).

## Security Vulnerabilities and Bugs

If you discover any security vulnerability or any bug within _EasyDock Linux_, please open an issue.

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

You can support us using any of the methods below:

**[Buy Me a Bottle of Milk or a Cup of Coffee](https://paypal.me/masedi) !!**

## Licence

LEMPer stack is open-source project licensed under the GNU GPLv3 license.

## Copyright

(c) 2014-2021 | [MasEDI.Net](https://masedi.net/)

### Enjoy LEMPer stack ;)
