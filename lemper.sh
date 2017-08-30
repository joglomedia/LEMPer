#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a Simple LNMP Installer for Ubuntu                         |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx 1.10                                                        |
# |     - PHP 5.6/7.0/7.1                                                   |
# |     - Zend OpCache 7.0.3                                                |
# |     - Memcached 1.4.14                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - Adminer (PhpMyAdmin replacement)                                  |
# | Min requirement   : GNU/Linux Ubuntu 14.04 or Linux Mint 17             |
# | Last Update       : 30/08/2017                                          |
# | Author            : MasEDI.Net (hi@masedi.net)                          |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2017 NgxTools (http://www.ngxtools.cf)               |
# +-------------------------------------------------------------------------+
# | This source file is subject to the New BSD License that is bundled      |
# | with this package in the file docs/LICENSE.txt.                         |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@ngxtools.cf so we can send you a copy immediately.           |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <hi@masedi.net>                                |
# +-------------------------------------------------------------------------+

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root..."
    exit 1
fi

# Make sure this script only run on Ubuntu install
if [ ! -f "/etc/lsb-release" ]; then
    echo "This installer only work on Ubuntu server..."
    exit 1
else
    # Variables
    arch=$(uname -p)
    IPAddr=$(hostname -i)
    . /etc/lsb-release
fi

function header_msg {
clear
cat <<- _EOF_
#========================================================================#
#         LEMPer v1.0.0 for Ubuntu Server, Written by MasEDI.Net         #
#========================================================================#
#     A small tool to install Nginx + MariaDB (MySQL) + PHP on Linux     #
#                                                                        #
#        For more information please visit http://www.ngxtools.cf        #
#========================================================================#
_EOF_
sleep 1
}
header_msg

echo "Starting LEMP installation, ensure that you're on a fresh box install!"
read -t 10 -p "Press Enter to continue..." </dev/tty

### Clean up ###
. scripts/remove_apache.sh

### ADD Repos ###
. scripts/add_repo.sh

### Nginx Installation ###
. scripts/install_nginx.sh

### PHP Installation ###
. scripts/install_php.sh
. scripts/install_memcache.sh

### MySQL Database Installation ###
. scripts/install_mariadb.sh

### Mail Server Installation ###
. scripts/install_postfix.sh

### Addon Installation ###
. scripts/install_tools.sh

### Install Let's Encrypt SSL ###
. scripts/install_letsencrypt.sh

### FINAL STEP ###
# Cleaning up all build dependencies hanging around on production server?
apt-get autoremove -y

clear
echo "#==========================================================================#"
echo "# Thanks for installing LNMP stack using SimpleLNMPInstaller...            #"
echo "# Found any bugs / errors / suggestions? please let me know....            #"
echo "# If this script useful, don't forget to buy me a coffee or milk... :D     #"
echo "# My PayPal is always open for donation, send your tips here hi@masedi.net #"
echo "#                                                                          #"
echo "# (c) 2015-2017 - MasEDI.Net - http://masedi.net ;)                        #"
echo "#==========================================================================#"
