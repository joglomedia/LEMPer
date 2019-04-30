#!/usr/bin/env bash

# Remove Apache2 & mysql services if exist

if [[ -n $(which apache2) ]]; then
    echo "Uninstall existing Apache web server..."
    killall -9 apache2
    service apache2 stop
    apt-get --purge remove -y apache2 apache2-doc apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker
fi

if [[ -n $(which mysql) ]]; then
    echo "Uninstall existing MySQL database server..."
    killall -9 mysql
    service mysqld stop
    apt-get --purge remove -y mysql-client mysql-server mysql-common
fi

apt-get autoremove -y
