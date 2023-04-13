#!/usr/bin/env bash

# MariaDB server Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

function mariadb_remove_config() {
    # Remove MariaDB server config files.
    echo "Removing MariaDB (MySQL) configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_MYSQL_CONFIG="y"
        else
            REMOVE_MYSQL_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_MYSQL_CONFIG}" != "y" && "${REMOVE_MYSQL_CONFIG}" != "n" ]]; do
            read -rp "Remove MariaDB database and configuration files? [y/n]: " -e REMOVE_MYSQL_CONFIG
        done
    fi

    if [[ "${REMOVE_MYSQL_CONFIG}" == y* || "${REMOVE_MYSQL_CONFIG}" == Y* ]]; then
        [ -d /etc/mysql ] && run rm -fr /etc/mysql
        [ -d /var/lib/mysql ] && run rm -fr /var/lib/mysql

        echo "All database and configuration files deleted permanently."
    fi
}

function init_mariadb_removal() {
    MYSQL_VERSION=${MYSQL_VERSION:-"10.5"}

    # Stop MariaDB mysql server process.
    if [[ $(pgrep -c mysqld) -gt 0 ]]; then
        echo "Stopping mariadb..."
        run systemctl stop mysql
        run systemctl disable mysql
    fi

    if dpkg-query -l | awk '/mariadb/ { print $2 }' | grep -qwE "^mariadb-server-${MYSQL_VERSION}"; then
        echo "Found MariaDB ${MYSQL_VERSION} packages installation, removing..."

        # Remove MariaDB server.
        run apt-get purge -q -y libmariadb3 libmariadbclient18 "mariadb-client-${MYSQL_VERSION}" \
            "mariadb-client-core-${MYSQL_VERSION}" mariadb-common mariadb-server "mariadb-server-${MYSQL_VERSION}" \
            "mariadb-server-core-${MYSQL_VERSION}" mariadb-backup

        # Remove config.
        mariadb_remove_config

        # Remove repository.
        if [[ "${FORCE_REMOVE}" == true ]]; then
            #run rm -f /etc/apt/sources.list.d/mariadb-*.list
            run rm -f /etc/apt/sources.list.d/mariadb.list
        fi
    elif dpkg-query -l | awk '/mysql/ { print $2 }' | grep -qwE "^mysql"; then
        echo "Found MySQL packages installation, removing..."

        # Remove MySQL server.
        run apt-get purge -q -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*

        # Remove config.
        mariadb_remove_config
    else
        echo "No installed MariaDB ${MYSQL_VERSION} or MySQL packages found."
        echo "Possibly installed from source? Remove it manually!"

        MYSQL_BIN=$(command -v mysql)
        MYSQLD_BIN=$(command -v mysqld)

        echo "MySQL binary executable: ${MYSQL_BIN}"
        echo "MySQL daemon binary executable: ${MYSQLD_BIN}"
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v mysqld) ]]; then
            success "MariaDB (MySQL) server removed."
        else
            info "MariaDB (MySQL) server not removed."
        fi
    else
        info "MariaDB (MySQL) server removed in dry run mode."
    fi
}

echo "Uninstalling MariaDB server..."

if [[ -n $(command -v mysql) || -n $(command -v mysqld) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_MARIADB="y"
    else
        while [[ "${REMOVE_MARIADB}" != "y" && "${REMOVE_MARIADB}" != "n" ]]; do
            read -rp "Are you sure to remove MariaDB server? [y/n]: " -e REMOVE_MARIADB
        done
    fi

    if [[ "${REMOVE_MARIADB}" == y* || "${REMOVE_MARIADB}" == Y* ]]; then
        init_mariadb_removal "$@"
    else
        echo "Found MariaDB server, but not removed."
    fi
else
    info "Oops, MariaDB server installation not found."
fi
