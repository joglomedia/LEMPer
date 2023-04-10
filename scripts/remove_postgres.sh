#!/usr/bin/env bash

# PostgreSQL server uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 08/04/2023
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.6

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

function postgres_remove_config() {
    local POSTGRES_VERSION=${POSTGRES_VERSION:-"15"}
    local PGDATA=${POSTGRES_PGDATA:-"/var/lib/postgresql/data"}

    # Remove PostgreSQL server config files.
    echo "Removing PostgreSQL configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_POSTGRES_CONFIG="y"
        else
            REMOVE_POSTGRES_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_POSTGRES_CONFIG}" != "y" && "${REMOVE_POSTGRES_CONFIG}" != "n" ]]; do
            read -rp "Remove PostgreSQL database and configuration files? [y/n]: " -e REMOVE_POSTGRES_CONFIG
        done
    fi

    if [[ "${REMOVE_POSTGRES_CONFIG}" == y* || "${REMOVE_POSTGRES_CONFIG}" == Y* ]]; then
        [ -d /var/lib/postgresql ] && run rm -fr /var/lib/postgresql
        [ -d /var/run/postgresql ] && run rm -fr /var/run/postgresql
        [ -d "${PGDATA}" ] && run rm -fr "${PGDATA}"
        [ -d "/etc/postgresql/${POSTGRES_VERSION}" ] && run rm -fr "/etc/postgresql/${POSTGRES_VERSION}"

        echo "All database and configuration files deleted permanently."
    fi
}

function init_postgres_removal() {
    local POSTGRES_VERSION=${POSTGRES_VERSION:-"15"}
    local POSTGRES_USER=${POSTGRES_USER:-"postgres"}
    #local POSTGRES_PKGS=()

    # Stop PostgreSQL mysql server process.
    if [[ $(pgrep -c postgres) -gt 0 ]]; then
        echo "Stopping postgres..."
        run systemctl stop "postgresql@${POSTGRES_VERSION}-main.service"
    fi

    #run systemctl disable "postgresql@${POSTGRES_VERSION}-main.service"

    if dpkg-query -l | awk '/postgresql/ { print $2 }' | grep -qwE "^postgresql"; then
        echo "Found PostgreSQL ${POSTGRES_VERSION} packages installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/postgresql/ { print $2 }' | grep -wE "^postgresql")

        # Remove PostgreSQL default user.
        if [[ -n $(getent passwd "${POSTGRES_USER}") ]]; then
            run userdel -r "${POSTGRES_USER}"
        fi

        if [[ -n $(getent group "${POSTGRES_USER}") ]]; then
            run groupdel "${POSTGRES_USER}"
        fi

        # Remove config.
        postgres_remove_config

        # Remove repository.
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run rm -f "/etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list"
        fi
    else
        echo "No installed PostgreSQL ${POSTGRES_VERSION} or MySQL packages found."
        echo "Possibly installed from source? Remove it manually!"
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ $(pgrep -c postgres) -eq 0 ]]; then
            success "PostgreSQL server removed."
        else
            info "PostgreSQL server not removed."
        fi
    else
        info "PostgreSQL server removed in dry run mode."
    fi
}

echo "Uninstalling PostgreSQL server..."

if [[ -n $(command -v psql) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_POSTGRES="y"
    else
        while [[ "${REMOVE_POSTGRES}" != "y" && "${REMOVE_POSTGRES}" != "n" ]]; do
            read -rp "Are you sure to remove PostgreSQL server? [y/n]: " -e REMOVE_POSTGRES
        done
    fi

    if [[ "${REMOVE_POSTGRES}" == y* || "${REMOVE_POSTGRES}" == Y* ]]; then
        init_postgres_removal "$@"
    else
        echo "Found PostgreSQL server, but not removed."
    fi
else
    info "Oops, PostgreSQL server installation not found."
fi
