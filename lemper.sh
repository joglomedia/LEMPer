#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a Simple LNMP Installer for Ubuntu                         |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx 1.10                                                        |
# |     - PHP 5.6/7.0/7.1/7.2/7.3                                           |
# |     - Zend OpCache 7.0.3                                                |
# |     - Memcached 1.4.14                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - Adminer (PhpMyAdmin replacement)                                  |
# | Min requirement   : GNU/Linux Ubuntu 14.04 or Linux Mint 17             |
# | Last Update       : 16/06/2019                                          |
# | Author            : ESLabs.ID (eslabs.id@gmail.com)                     |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 NgxTools (https://eslabs.id/lemper)             |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

set -e  # Work even if somebody does "sh thisscript.sh".

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    . scripts/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

# Make sure this script only run on Ubuntu install
if [ ! -f "/etc/lsb-release" ]; then
    warning -e "\nThis installer only work on Ubuntu server..."
    exit 1
else
    # Variables
    arch=$(uname -p)
    IPAddr=$(hostname -i)

    # export lsb-release vars
    . /etc/lsb-release

    MAJOR_RELEASE_NUMBER=$(echo $DISTRIB_RELEASE | awk -F. '{print $1}')

    if [[ "$DISTRIB_ID" == "LinuxMint" ]]; then
        DISTRIB_RELEASE="LM${MAJOR_RELEASE_NUMBER}"
    fi
fi

header_msg

echo -e "\nStarting LEMP installation...\nPlease ensure that you're on a fresh box install!\n"
read -t 10 -p "Press [Enter] to continue..." </dev/tty

### Clean up ###
. scripts/cleanup_server.sh

### ADD Repos ###
. scripts/add_repo.sh

### Nginx Installation ###
. scripts/install_nginx.sh

### PHP Installation ###
. scripts/install_php.sh
. scripts/install_memcache.sh

### MySQL Database Installation ###
. scripts/install_mariadb.sh

### Redis Database Installation ###
. scripts/install_redis.sh

### Mail Server Installation ###
. scripts/install_postfix.sh

### Install Let's Encrypt SSL ###
. scripts/install_letsencrypt.sh

### Addon Installation ###
. scripts/install_tools.sh

### FINAL STEP ###
# Cleaning up all build dependencies hanging around on production server?
run apt-get autoremove -y

status -e "\nLEMPer installation has been completed."

### Recap ###
if [[ ! -z "$katasandi" ]]; then
    status -e "\nHere is your default system account information:

Username: lemper
Password: ${katasandi}

Please keep it private!
"
fi

echo -e "\nNow, you can reboot your server and enjoy it!\n"

echo "#==========================================================================#"
echo "#         Thank's for installing LNMP stack using LEMPer Installer         #"
echo "#        Found any bugs / errors / suggestions? please let me know         #"
echo "#    If this script useful, don't forget to buy me a coffee or milk :D     #"
echo "#   My PayPal is always open for donation, here https://paypal.me/masedi   #"
echo "#                                                                          #"
echo "#         (c) 2014-2019 - ESLabs.ID - https://eslabs.id/lemper ;)          #"
echo "#==========================================================================#"
