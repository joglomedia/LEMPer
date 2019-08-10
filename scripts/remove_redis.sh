#!/usr/bin/env bash

# Redis Uninstaller
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

function init_redis_removal() {
    # Stop Redis server process.
    if [[ $(pgrep -c redis-server) -gt 0 ]]; then
        run service redis-server stop
    fi

    if [[ -n $(dpkg-query -l | grep redis-server | awk '/redis-server/ { print $2 }') ]]; then
        echo "Found Redis package installation. Removing..."

        # Remove Redis server.
        {
            run apt-get --purge remove -y redis-server php-redis
            run add-apt-repository -y --remove ppa:chris-lea/redis-server
        } >> lemper.log 2>&1
    else
        echo "Redis package not found, possibly installed from source."
        echo "Remove it manually."

        REDIS_BIN=$(command -v redis-server)

        echo "Which redis-server bin: ${REDIS_BIN}"
    fi

    # Remove Redis config files.
    warning "!! This action is not reversible !!"
    while [[ "${REMOVE_REDISCONFIG}" != "y" && "${REMOVE_REDISCONFIG}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Remove Redis database and configuration files? [y/n]: " -e REMOVE_REDISCONFIG
    done
    if [[ "${REMOVE_REDISCONFIG}" == Y* || "${REMOVE_REDISCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [ -d /etc/redis ]; then
            run rm -fr /etc/redis
        fi
        if [ -d /var/lib/redis ]; then
            run rm -fr /var/lib/redis
        fi
        echo "All your Redis database and configuration files deleted permanently."
    fi

    # Final test.
    if "${DRYRUN}"; then
        warning "Redis server removed in dryrun mode."
    else
        if [[ -z $(command -v redis-server) ]]; then
            status "Redis server removed succesfully."
        else
            warning "Unable to remove Redis server."
        fi
    fi
}

echo "Uninstalling Redis server..."
if [[ -n $(command -v redis-server) ]]; then
    while [[ "${REMOVE_REDIS}" != "y" && "${REMOVE_REDIS}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Are you sure to remove Redis server? [y/n]: " -e REMOVE_REDIS
    done
    if [[ "${REMOVE_REDIS}" == Y* || "${REMOVE_REDIS}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_redis_removal "$@"
    else
        echo "Found Redis server, but not removed."
    fi
else
    warning "Oops, Redis installation not found."
fi
