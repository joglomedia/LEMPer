#!/usr/bin/env bash

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . "${BASEDIR}/helper.sh"
fi

echo -e "\nCleaning up machine..."

# Remove Apache2 service if exist
if [[ -n $(which apache2) ]]; then
    warning -e "\nIt seems Apache web server installed on this machine."
    echo "Any other HTTP web server will be removed, otherwise they will conflict."
    read -t 15 -rp "Press [Enter] to continue..." </dev/tty
    echo -e "\nUninstall existing Apache web server..."

    if "${DRYRUN}"; then
        echo "Removing Apache2 installation in dryrun mode."
    else
        run service apache2 stop
        run apt-get --purge remove -y apache2 apache2-doc apache2-utils \
            apache2.2-common apache2.2-bin apache2-mpm-prefork \
            apache2-doc apache2-mpm-worker >> lemper.log 2>&1
    fi
fi

# Remove Mysql service if exist
if [[ -n $(which mysql) ]]; then
    warning -e "\nMySQL database server already installed on this machine. Should we remove it?"
    echo -e "Backup your database before continue!\n"

    while [[ ${REMOVE_MYSQL} != "y" && ${REMOVE_MYSQL} != "n" ]]; do
        read -rp "Surely, remove existing MySQL database server? [y/n]: " -i y -e REMOVE_MYSQL
    done

    if [[ "${REMOVE_MYSQL}" == Y* || "${REMOVE_MYSQL}" == y* ]]; then
        echo "Uninstall existing MySQL database server..."

        if "${DRYRUN}"; then
            echo "Removing MySQL server installation in dryrun mode."
        else
            run service mysqld stop
            run apt-get --purge remove -y mysql-client mysql-server \
                mysql-common >> lemper.log 2>&1
        fi
    else
        echo "Found MySQL server, but not removed."
    fi
fi

if [[ -z $(which apache2) && -z $(which mysql) ]]; then
    status -e "\nMachine cleaned up."
else
    warning -e "\nMachine cleaned up, but some installation not removed."
fi
