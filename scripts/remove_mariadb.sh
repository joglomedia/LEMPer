#!/usr/bin/env bash

# MariaDB (MySQL) Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 31/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function mariadb_remove_conf() {
    # Remove MariaDB (MySQL) config files.
    warning "!! This action is not reversible !!"
    if "${AUTO_REMOVE}"; then
        REMOVE_MYSQLCONFIG="y"
    else
        while [[ "${REMOVE_MYSQLCONFIG}" != "y" && "${REMOVE_MYSQLCONFIG}" != "n" ]]; do
            read -rp "Remove MariaDB (MySQL) database and configuration files? [y/n]: " -e REMOVE_MYSQLCONFIG
        done
    fi

    if [[ "${REMOVE_MYSQLCONFIG}" == Y* || "${REMOVE_MYSQLCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [ -d /etc/mysql ]; then
            run rm -fr /etc/mysql
        fi

        if [ -d /var/lib/mysql ]; then
            run rm -fr /var/lib/mysql
        fi

        echo "All your SQL database and configuration files deleted permanently."
    fi
}

function init_mariadb_removal() {
    MYSQL_VERSION=${MYSQL_VERSION:-"10.4"}

    # Stop MariaDB mysql server process.
    if [[ $(pgrep -c mysqld) -gt 0 ]]; then
        run systemctl stop mysql
    fi

    if dpkg-query -l | awk '/mariadb/ { print $2 }' | grep -qwE "^mariadb-server-${MYSQL_VERSION}"; then
        echo "Found MariaDB package installation, removing..."

        # Remove MariaDB server.
        run apt remove --purge -qq -y libmariadb3 libmariadbclient18 "mariadb-client-${MYSQL_VERSION}" \
            "mariadb-client-core-${MYSQL_VERSION}" mariadb-common mariadb-server "mariadb-server-${MYSQL_VERSION}" \
            "mariadb-server-core-${MYSQL_VERSION}" mariadb-backup

        # shellcheck disable=SC2046
        #run apt remove --purge -qq -y $(dpkg-query -l | awk '/mariadb/ { print $2 }')

        # Remove config.
        mariadb_remove_conf

        # Remove repository.
        if "${FORCE_REMOVE}"; then
            #run rm -f /etc/apt/sources.list.d/mariadb-*.list
            run rm -f /etc/apt/sources.list.d/mariadb.list
        fi
    elif dpkg-query -l | awk '/mysql/ { print $2 }' | grep -qwE "^mysql"; then
        echo "Found MySQL package installation, removing..."

        # Remove MySQL server.
        run apt remove --purge -qq -y mysql-client mysql-common mysql-server
        
        # shellcheck disable=SC2046
        #run apt remove --purge -qq -y $(dpkg-query -l | awk '/mysql/ { print $2 }' | grep -wE "^mysql")

        # Remove config.
        mariadb_remove_conf
    else
        echo "No installed Mariadb package found, possibly installed from source."
        echo "Remove it manually!!"

        MYSQL_BIN=$(command -v mysql)
        MYSQLD_BIN=$(command -v mysqld)

        echo "Mysql binary executable: ${MYSQL_BIN}"
        echo "Mysqld binary executable: ${MYSQLD_BIN}"
    fi

    # Final test.
    if "${DRYRUN}"; then
        info "MariaDB (MySQL) server removed in dryrun mode."
    else
        if [[ -z $(command -v mysqld) ]]; then
            success "MariaDB (MySQL) server removed."
        else
            info "MariaDB (MySQL) server not removed."
        fi
    fi
}

echo "Uninstalling MariaDB (MySQL) server..."
if [[ -n $(command -v mysql) || -n $(command -v mysqld) ]]; then
    if "${AUTO_REMOVE}"; then
        REMOVE_MARIADB="y"
    else
        while [[ "${REMOVE_MARIADB}" != "y" && "${REMOVE_MARIADB}" != "n" ]]; do
            read -rp "Are you sure to remove MariaDB (MySQL)? [y/n]: " -e REMOVE_MARIADB
        done
    fi

    if [[ "${REMOVE_MARIADB}" == Y* || "${REMOVE_MARIADB}" == y* ]]; then
        init_mariadb_removal "$@"
    else
        echo "Found MariaDB (MySQL), but not removed."
    fi
else
    info "Oops, MariaDB (MySQL) installation not found."
fi
