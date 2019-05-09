#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Remove Apache2 services if exist
if [[ -n $(which apache2) ]]; then
    warning "It seems Apache web server installed on this machine. We should remove it!"
    read -t 10 -p "Press [Enter] to continue..." </dev/tty
    echo "Uninstall existing Apache web server..."
    run service apache2 stop
    #killall -9 apache2
    run apt-get --purge remove -y apache2 apache2-doc apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker
fi

# Remove Mysql services if exist
if [[ -n $(which mysql) ]]; then
    warning "It seems Mysql database server installed on this machine. We should remove it!"
    echo "Backup your database before continue!"

    echo -n "Surely, remove existing MySQL database server? [Y/n]: "
    read rmMysql

    if [[ "$rmMysql" == Y* || "$rmMysql" == y* ]]; then
        echo "Uninstall existing MySQL database server..."
        run service mysqld stop

        #killall -9 mysql
        run apt-get --purge remove -y mysql-client mysql-server mysql-common
    fi
fi

status -e "\nServer cleaned up..."
