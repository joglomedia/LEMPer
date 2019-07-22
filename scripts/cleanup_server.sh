#!/usr/bin/env bash

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

echo -e "\nCleaning up machine..."

# Remove Apache2 service if exist
if [[ -n $(which apache2) ]]; then
    warning -e "\nIt seems Apache web server installed on this machine. We should remove it!"
    read -t 10 -p "Press [Enter] to continue..." </dev/tty
    echo "Uninstall existing Apache web server..."
    run service apache2 stop
    #killall -9 apache2
    run apt-get --purge remove -y apache2 apache2-doc apache2-utils \
        apache2.2-common apache2.2-bin apache2-mpm-prefork \
        apache2-doc apache2-mpm-worker >> lemper.log 2>&1
fi

# Remove Mysql service if exist
if [[ -n $(which mysql) ]]; then
    warning -e "\nIt seems Mysql database server installed on this machine. We should remove it!"
    echo "Backup your database before continue!"

    echo -n "Surely, remove existing MySQL database server? [y/n]: "
    read rmMysql

    if [[ "$rmMysql" == Y* || "$rmMysql" == y* ]]; then
        echo "Uninstall existing MySQL database server..."
        run service mysqld stop

        #killall -9 mysql
        run apt-get --purge remove -y mysql-client mysql-server mysql-common >> lemper.log 2>&1
    fi
fi

status "Machine cleaned up..."
