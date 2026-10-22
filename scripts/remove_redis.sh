#!/usr/bin/env bash

# Redis / Valkey Uninstaller
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

function is_pkg_installed() {
    dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -q "install ok installed"
}

function remove_source_bins() {
    local bin
    for bin in "$@"; do
        [[ -x "/usr/local/bin/${bin}" ]] && run rm -f "/usr/local/bin/${bin}"
    done
}

function init_redis_removal() {
    local backend="${REDIS_BACKEND:-redis}"

    # Stop Redis/Valkey server processes.
    if pgrep -x redis-server >/dev/null 2>&1; then
        echo "Stopping redis-server..."
        run systemctl stop redis-server
        run systemctl disable redis-server
    fi

    if pgrep -x valkey-server >/dev/null 2>&1; then
        echo "Stopping valkey-server..."
        run systemctl stop valkey-server
        run systemctl disable valkey-server
    fi

    # Remove package-based installations.
    if is_pkg_installed redis-server || is_pkg_installed redis-tools; then
        echo "Found Redis package installation. Removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/redis/ { print $2 }' | grep -wE "^redis")
    else
        info "Redis package not found, possibly installed from source."
        remove_source_bins redis-server redis-cli redis-sentinel redis-benchmark
    fi

    if is_pkg_installed valkey-server || is_pkg_installed valkey-tools; then
        echo "Found Valkey package installation. Removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/valkey/ { print $2 }' | grep -wE "^valkey")
    else
        info "Valkey package not found, possibly installed from source."
        remove_source_bins valkey-server valkey-cli valkey-sentinel valkey-benchmark

        # Remove source-installed systemd unit (package units are removed by purge).
        if [[ -f /lib/systemd/system/valkey-server.service ]] && \
            ! is_pkg_installed valkey-server; then
            run rm -f /lib/systemd/system/valkey-server.service
        fi
    fi

    # Remove Redis config files.
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_REDIS_CONFIG="y"
        else
            REMOVE_REDIS_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_REDIS_CONFIG}" != "y" && "${REMOVE_REDIS_CONFIG}" != "n" ]]; do
            read -rp "Remove Redis/Valkey database and configuration files? [y/n]: " -e REMOVE_REDIS_CONFIG
        done
    fi

    if [[ "${REMOVE_REDIS_CONFIG}" == Y* || "${REMOVE_REDIS_CONFIG}" == y* ]]; then
        local dir
        for dir in /etc/redis /var/lib/redis /etc/valkey /var/lib/valkey /run/valkey; do
            [[ -d "${dir}" ]] && run rm -fr "${dir}"
        done

        # Remove repositories and keyrings.
        run rm -f "/etc/apt/sources.list.d/redis-${RELEASE_NAME}.list"
        run rm -f "/usr/share/keyrings/redis-${RELEASE_NAME}.gpg"
        run rm -f "/etc/apt/sources.list.d/valkey.list"
        run rm -f "/usr/share/keyrings/valkey-archive-keyring.gpg"

        echo "All your Redis/Valkey database and configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v redis-server) && -z $(command -v valkey-server) ]]; then
            success "Redis/Valkey server removed succesfully."
        else
            info "Unable to remove Redis/Valkey server (backend: ${backend})."
        fi
    else
        info "Redis/Valkey server removed in dry run mode."
    fi
}

echo "Uninstalling Redis/Valkey server..."

if [[ -n $(command -v redis-server) || -n $(command -v valkey-server) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_REDIS="y"
    else
        while [[ "${REMOVE_REDIS}" != "y" && "${REMOVE_REDIS}" != "n" ]]; do
            read -rp "Are you sure to remove Redis/Valkey server? [y/n]: " -e REMOVE_REDIS
        done
    fi

    if [[ "${REMOVE_REDIS}" == Y* || "${REMOVE_REDIS}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_redis_removal "$@"
    else
        echo "Found Redis/Valkey server, but not removed."
    fi
else
    info "Oops, Redis/Valkey installation not found."
fi
