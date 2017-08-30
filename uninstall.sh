#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# |            LEMPer uninstaller.sh is a Simple LNMP Uninstaller           |
# |-------------------------------------------------------------------------+
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
    echo "This script must be run as root..." >&2
    exit 1
fi

clear

# Variables
arch=$(uname -p)

# Stop Nginx web server
service nginx stop

# Stop php5-fpm server
service php5.6-fpm stop
service php7.0-fpm stop
service php7.1-fpm stop

# Stop MariaDB mysql server
service mysql stop

# Stop Memcached server
service memcached stop

# Remove Nginx - PHP5 - MariaDB - PhpMyAdmin
apt-get remove -y nginx-custom

echo ""
echo -n "Completely remove Nginx configuration files (This action is not reversible)? [Y/n]: "
read rmngxconf
if [ "$rmngxconf" = "Y" ]; then
	echo "All your Nginx configuration files deleted..."
	sleep 2
	#rm -fr /etc/nginx
	# rm nginx-cache
	#rm -fr /var/run/nginx-cache
	# rm nginx html
	#rm -fr /usr/share/nginx
fi

apt-get --purge remove -y php* php*-* spawn-fcgi geoip-database snmp memcached

echo ""
echo -n "Completely remove PHP-FPM configuration files (This action is not reversible)? (y/n): "
read rmfpmconf
if [ "${rmfpmconf}" = "y" ]; then
	echo "All your PHP-FPM configuration files deleted..."
	sleep 2
	#rm -fr /etc/php/
fi

apt-get remove -y mariadb-server-10.1 mariadb-client-10.1 mariadb-server-core-10.1 mariadb-common mariadb-server libmariadbclient18 mariadb-client-core-10.1

echo ""
echo -n "Completely remove MariaDB SQL database and configuration files (This action is not reversible)? (y/n): "
read rmsqlconf
if [ "${rmsqlconf}" = "y" ]; then
	echo "All your SQL database and configuration files deleted..."
	sleep 2
	#rm -fr /etc/mysql
	#rm -fr /var/lib/mysql
fi

#apt-get remove phpmyadmin
apt-get autoremove -y

# Remove ioncube
rm -fr /usr/lib/php/loaders/

clear
echo "#==========================================================================#"
echo "# Thanks for trying SimpleLNMPInstaller... Sad to see you Go ;(            #"
echo "# Found any bugs / errors / suggestions? please let me know....            #"
echo "# If this script useful, don't forget to buy me a coffee or milk... :D     #"
echo "# My PayPal is always open for donation, send your tips here hi@masedi.net #"
echo "#                                                                          #"
echo "# (c) 2015 - MasEDI.Net - http://masedi.net ;)                             #"
echo "===========================================================================#"
