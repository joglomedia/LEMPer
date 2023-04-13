#!/usr/bin/env bash

# Redis Uninstaller
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

function init_redis_removal() {
    # Stop Redis server process.
    if [[ $(pgrep -c redis-server) -gt 0 ]]; then
        echo "Stopping redis-server..."
        run systemctl stop redis-server
        run systemctl disable redis-server
    fi

    # Remove Redis server.
    if dpkg-query -l | awk '/redis/ { print $2 }' | grep -qwE "^redis-server"; then
        echo "Found Redis package installation. Removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/redis/ { print $2 }' | grep -wE "^redis")

        if [[ "${FORCE_REMOVE}" == true ]]; then
            #if [[ "${DISTRIB_NAME}" == "ubuntu" ]]; then
            #    run add-apt-repository -y --remove ppa:redislabs/redis
            #else
                run rm -f "/etc/apt/sources.list.d/redis-${DISTRIB_NAME}.list"
            #fi
        fi
    else
        info "Redis package not found, possibly installed from source."
        echo "Remove it manually!!"

        REDIS_BIN=$(command -v redis-server)

        echo "Deleting Redis binary executable: ${REDIS_BIN}"

        [[ -n $(command -v redis-server) ]] && run rm -f "${REDIS_BIN}"
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
            read -rp "Remove Redis database and configuration files? [y/n]: " -e REMOVE_REDIS_CONFIG
        done
    fi

    if [[ "${REMOVE_REDIS_CONFIG}" == Y* || "${REMOVE_REDIS_CONFIG}" == y* ]]; then
        if [ -d /etc/redis ]; then
            run rm -fr /etc/redis
        fi
        if [ -d /var/lib/redis ]; then
            run rm -fr /var/lib/redis
        fi
        echo "All your Redis database and configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v redis-server) ]]; then
            success "Redis server removed succesfully."
        else
            info "Unable to remove Redis server."
        fi
    else
        info "Redis server removed in dry run mode."
    fi
}

echo "Uninstalling Redis server..."

if [[ -n $(command -v redis-server) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_REDIS="y"
    else
        while [[ "${REMOVE_REDIS}" != "y" && "${REMOVE_REDIS}" != "n" ]]; do
            read -rp "Are you sure to remove Redis server? [y/n]: " -e REMOVE_REDIS
        done
    fi

    if [[ "${REMOVE_REDIS}" == Y* || "${REMOVE_REDIS}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_redis_removal "$@"
    else
        echo "Found Redis server, but not removed."
    fi
else
    info "Oops, Redis installation not found."
fi
