#!/usr/bin/env bash

# Memcached Uninstaller
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

function init_memcached_removal() {
    # Stop Memcached server process.
    if [[ $(pgrep -c memcached) -gt 0 ]]; then
        run service memcached stop
    fi

    if dpkg-query -l | awk '/memcached/ { print $2 }' | grep -qwE "^memcached$"; then
        echo "Found Memcached package installation. Removing..."

        # Remove Memcached server.
        run apt-get -qq --purge remove -y libmemcached11 memcached php-igbinary \
            php-memcache php-memcached php-msgpack
    else
        echo "Memcached package not found, possibly installed from source."
        echo "Remove it manually."

        MEMCACHED_BIN=$(command -v memcached)

        echo "Memcached binary executable: ${MEMCACHED_BIN}"

        if [[ -n "${MEMCACHED_BIN}" ]]; then
            # Disable systemctl.
            if [ -f /etc/systemd/system/multi-user.target.wants/memcached.service ]; then
                echo "Disable Memcached service..."
                run systemctl disable memcached.service
            fi

            if [ -f /etc/systemd/system/multi-user.target.wants/memcached.service ]; then
                run unlink /etc/systemd/system/multi-user.target.wants/memcached.service
            fi

            if [ -f /lib/systemd/system/memcached.service ]; then
                run rm -f /lib/systemd/system/memcached.service
            fi

            if [ -d /usr/share/memcached ]; then
                run rm -fr /usr/share/memcached
            fi

            # Remove binary executable file.
            if [ -f "${MEMCACHED_BIN}" ]; then
                echo "Remove Memcached binary executable file..."
                run rm -f "${MEMCACHED_BIN}"
            fi

            # Remove init file.
            if [ -f /etc/init.d/memcached ]; then
                run rm -f /etc/init.d/memcached
            fi
        fi
    fi

    # Remove Redis config files.
    warning "!! This action is not reversible !!"
    while [[ "${REMOVE_MEMCACHEDCONFIG}" != "y" && "${REMOVE_MEMCACHEDCONFIG}" != "n" && \
            "${AUTO_REMOVE}" != true ]]; do
        read -rp "Remove Memcached configuration files? [y/n]: " -i n -e REMOVE_MEMCACHEDCONFIG
    done
    if [[ "${REMOVE_MEMCACHEDCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
        if [ -f /etc/memcached.conf ]; then
            run rm -f /etc/memcached.conf
        fi

        echo "All your Memcached configuration files deleted permanently."
    fi

    # Final test.
    if "${DRYRUN}"; then
        warning "Memcached server removed in dryrun mode."
    else
        if [[ -z $(command -v memcached) ]]; then
            status "Memcached server removed succesfully."
        else
            warning "Unable to remove Memcached server."
        fi
    fi
}

echo "Uninstalling Memcached server..."
if [[ -n $(command -v memcached) ]]; then
    while [[ "${REMOVE_MEMCACHED}" != "y" && "${REMOVE_MEMCACHED}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Are you sure to remove Memcached? [y/n]: " -e REMOVE_MEMCACHED
    done
    if [[ "${REMOVE_MEMCACHED}" == Y* || "${REMOVE_MEMCACHED}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_memcached_removal "$@"
    else
        echo "Found Memcached server, but not removed."
    fi
else
    warning "Oops, Memcached installation not found."
fi
