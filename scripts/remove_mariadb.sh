#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | MariaDB Server Uninstaller                                              |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || { echo "Cannot enter ${BASE_DIR}."; exit 1; }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

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
    if [[ $(pgrep -c mariadb) -gt 0 ]]; then
        echo "Stopping mariadb..."
        run systemctl stop mariadb.service
        run systemctl disable mariadb.service
    fi

    if dpkg-query -l | awk '/mariadb/ { print $2 }' | grep -qwE "^mariadb-server-${MYSQL_VERSION}"; then
        echo "Found MariaDB ${MYSQL_VERSION} packages installation, removing..."

        # Remove MariaDB server.
        run apt-get purge -q -y libmariadb-dev libmariadb3 libmariadbclient18 mariadb-client mariadb-client-core \
            mariadb-common mariadb-server mariadb-server-core mariadb-backup

        # Remove config.
        mariadb_remove_config

        # Remove repository.
        if [[ "${FORCE_REMOVE}" == true ]]; then
            [ -f /etc/apt/preferences.d/mariadb-enterprise.pref ] && \
                run rm -f /etc/apt/preferences.d/mariadb-enterprise.pref
            [ -f /etc/apt/sources.list.d/mariadb.list ] && \
                run rm -f /etc/apt/sources.list.d/mariadb.list
        fi
    elif dpkg-query -l | awk '/mysql/ { print $2 }' | grep -qwE "^mysql"; then
        echo "Found MySQL packages installation, removing..."

        # Remove MySQL server.
        run apt-get purge -q -y mysql-server mysql-client mysql-common mysql-server-core* mysql-client-core*

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

if [[ -n $(command -v mariadb) || -n $(command -v mariadbd) ]]; then
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
