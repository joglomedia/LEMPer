#!/usr/bin/env bash

# Memcached Uninstaller
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

function init_memcached_removal() {
    # Stop Memcached server process.
    if [[ $(pgrep -c memcached) -gt 0 ]]; then
        #run service memcached@memcache stop
        #run service memcached@www-data stop
        # shellcheck disable=SC2046
        run kill -9 $(pidof memcached)
    fi

    if dpkg-query -l | awk '/memcached/ { print $2 }' | grep -qwE "^memcached$"; then
        echo "Found Memcached package installation. Removing..."

        # Remove Memcached server.
        run apt-get purge -qq -y libmemcached11 memcached php-igbinary \
            php-memcache php-memcached php-msgpack
    else
        echo "Memcached package not found, possibly installed from source."
        echo "Remove it manually."

        MEMCACHED_BIN=$(command -v memcached)

        echo "Memcached binary executable: ${MEMCACHED_BIN}"

        if [[ -n $(command -v memcached) ]]; then
            # Disable systemctl.
            if [ -f /etc/systemd/system/multi-user.target.wants/memcached.service ]; then
                echo "Disabling Memcached service..."
                run systemctl disable memcached@memcache.service
                run systemctl disable memcached@www-data.service
            fi

            [ -f /etc/systemd/system/multi-user.target.wants/memcached.service ] && \
            run unlink /etc/systemd/system/multi-user.target.wants/memcached.service

            [ -f /lib/systemd/system/memcached.service ] && run rm -f /lib/systemd/system/memcached.service

            # Memcached systemd script (multi user instance).
            [ -f /etc/systemd/system/multi-user.target.wants/memcached@.service ] && \
            run unlink /etc/systemd/system/multi-user.target.wants/memcached@.service

            [ -f /lib/systemd/system/memcached@.service ] && \
            run rm -f /lib/systemd/system/memcached@.service

            [ -d /usr/share/memcached ] && run rm -fr /usr/share/memcached

            # Remove binary executable file.
            if [ -f "${MEMCACHED_BIN}" ]; then
                echo "Removing Memcached binary executable file..."
                run rm -f "${MEMCACHED_BIN}"
            fi

            # Remove init file.
            [ -f /etc/init.d/memcached ] && run rm -f /etc/init.d/memcached

            # Remove Libevent.
            [ -d /usr/local/libevent ] && run rm -fr /usr/local/libevent
        fi
    fi

    # Remove Memcached config files.
    echo "Removing memcached configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_MEMCACHED_CONFIG="y"
        else
            REMOVE_MEMCACHED_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_MEMCACHED_CONFIG}" != "y" && "${REMOVE_MEMCACHED_CONFIG}" != "n" ]]; do
            read -rp "Remove Memcached configuration files? [y/n]: " -e REMOVE_MEMCACHED_CONFIG
        done
    fi

    if [[ "${REMOVE_MEMCACHED_CONFIG}" == Y* || "${REMOVE_MEMCACHED_CONFIG}" == y* ]]; then
        [ -f /etc/memcached.conf ] && run rm -f /etc/memcached.conf

        echo "All your Memcached configuration files deleted permanently."
    fi

    # Delete memcache user.
    if [[ -n $(getent passwd memcache) ]]; then
        if [[ "${DRYRUN}" != true ]]; then
            run userdel -r memcache
            #run groupdel memcache
        else
            echo "Memcache user deleted in dry run mode."   
        fi
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v memcached) ]]; then
            success "Memcached server removed succesfully."
        else
            info "Unable to remove Memcached server."
        fi
    else
        info "Memcached server removed in dry run mode."
    fi
}

echo "Uninstalling Memcached server..."

if [[ -n $(command -v memcached) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_MEMCACHED="y"
    else
        while [[ "${REMOVE_MEMCACHED}" != "y" && "${REMOVE_MEMCACHED}" != "n" ]]; do
            read -rp "Are you sure to remove Memcached? [y/n]: " -e REMOVE_MEMCACHED
        done
    fi

    if [[ "${REMOVE_MEMCACHED}" == Y* || "${REMOVE_MEMCACHED}" == y* ]]; then
        init_memcached_removal "$@"
    else
        echo "Found Memcached server, but not removed."
    fi
else
    info "Oops, Memcached installation not found."
fi
