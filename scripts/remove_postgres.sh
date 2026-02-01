#!/usr/bin/env bash

# PostgreSQL server uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 20.04
# Last Build        : 02/01/2026
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

##
# PostgreSQL service control helper.
# Tries multiple methods to start/stop/restart PostgreSQL:
# 1. systemctl (for systems with systemd running)
# 2. pg_ctlcluster (Debian/Ubuntu wrapper - works in containers)
# 3. service (legacy SysV init fallback)
##
function postgres_ctl() {
    local action="${1}"  # start, stop, restart, reload, status, enable, disable, daemon-reload
    local version="${2:-${POSTGRES_VERSION:-17}}"
    local cluster="${3:-main}"

    # Handle systemd-specific actions (only work with systemctl)
    case "${action}" in
        daemon-reload)
            if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
                systemctl daemon-reload 2>/dev/null && return 0
            fi
            return 0  # Non-fatal if systemd not available
        ;;
        enable|disable)
            if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
                systemctl "${action}" "postgresql@${version}-${cluster}.service" 2>/dev/null && return 0
            fi
            return 0  # Non-fatal if systemd not available
        ;;
    esac

    # Try systemctl first (for systems with systemd running)
    if command -v systemctl &>/dev/null; then
        if systemctl is-system-running &>/dev/null 2>&1; then
            if systemctl "${action}" "postgresql@${version}-${cluster}.service" 2>/dev/null; then
                return 0
            fi
        fi
    fi

    # Fallback to pg_ctlcluster (Debian/Ubuntu - works in containers!)
    if command -v pg_ctlcluster &>/dev/null; then
        if sudo -u postgres pg_ctlcluster "${version}" "${cluster}" "${action}" 2>/dev/null; then
            return 0
        fi
    fi

    # Fallback to service command (legacy SysV init)
    if command -v service &>/dev/null; then
        if service postgresql "${action}" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

function init_postgres_removal() {
    local POSTGRES_VERSION=${POSTGRES_VERSION:-"17"}
    local POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER:-"postgres"}
    #local POSTGRES_PKGS=()

    # Stop PostgreSQL server process.
    if pg_isready -q 2>/dev/null || [[ $(pgrep -c postgres) -gt 0 ]]; then
        echo "Stopping postgres..."
        postgres_ctl stop "${POSTGRES_VERSION}" main

        # Disable service on startup.
        postgres_ctl disable "${POSTGRES_VERSION}" main
    fi

    if dpkg-query -l | awk '/postgresql/ { print $2 }' | grep -qwE "^postgresql"; then
        echo "Found PostgreSQL ${POSTGRES_VERSION} packages installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/postgresql/ { print $2 }' | grep -wE "^postgresql")

        # Remove PostgreSQL default user.
        if [[ -n $(getent passwd "${POSTGRES_SUPERUSER}") ]]; then
            run userdel -r "${POSTGRES_SUPERUSER}"
        fi

        if [[ -n $(getent group "${POSTGRES_SUPERUSER}") ]]; then
            run groupdel "${POSTGRES_SUPERUSER}"
        fi

        # Remove config.
        postgres_remove_config
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

function postgres_remove_config() {
    local POSTGRES_VERSION=${POSTGRES_VERSION:-"17"}
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

        # Remove repository (legacy and new locations).
        run rm -f "/etc/apt/sources.list.d/postgres-${RELEASE_NAME}.list"
        run rm -f "/usr/share/keyrings/postgres-${RELEASE_NAME}.gpg"
        run rm -f "/etc/apt/sources.list.d/pgdg.list"
        run rm -rf /usr/share/postgresql-common/pgdg

        echo "All database and configuration files deleted permanently."
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
