#!/usr/bin/env bash

# Remove Apache2 & mysql services if exist
echo "Uninstall existing Webserver (Apache) and MySQL server..."
killall apache2 && killall mysql
apt-get --purge remove -y apache2 apache2-doc apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker mysql-client mysql-server mysql-common
apt-get autoremove -y
