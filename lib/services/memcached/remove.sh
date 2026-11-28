#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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

function init_memcached_removal() {
    if [[ -f /etc/systemd/system/memcached@memcache.service.d/10-lemper-endpoints.conf ]]; then
        lemper_exec systemctl disable --now memcached@memcache.service memcached@www-data.service || return 1
        lemper_exec rm -f /etc/systemd/system/memcached@{memcache,www-data}.service.d/10-lemper-endpoints.conf || return 1
        if [[ -f /etc/systemd/system/memcached@.service ]] \
            && grep -Fq 'installed using LEMPer Stack' /etc/systemd/system/memcached@.service; then
            lemper_exec rm -f /etc/systemd/system/memcached@.service || return 1
        fi
        if [[ "$(dpkg-query -W -f='${Status}' memcached 2>/dev/null)" == 'install ok installed' ]]; then
            lemper_exec apt-get remove -q -y memcached || return 1
        elif [[ -x /usr/bin/memcached ]]; then
            lemper_exec rm -f /usr/bin/memcached || return 1
        fi
        lemper_exec systemctl daemon-reload || return 1
        success "Managed Memcached instances removed; endpoint backups and cache configuration retained."
        return 0
    fi
    # Stop Memcached server process.
    if [[ $(pgrep -c memcached) -gt 0 ]]; then
        echo "Stopping memcached..."
        #run service memcached@memcache stop
        #run service memcached@www-data stop
        # shellcheck disable=SC2046
        run kill -9 $(pidof memcached)
    fi

    if dpkg-query -l | awk '/memcached/ { print $2 }' | grep -qwE "^memcached$"; then
        echo "Found Memcached package installation. Removing..."

        # Remove Memcached server.
        if [[ "${DISTRIB_NAME}/${RELEASE_NAME}" == ubuntu/resolute ]]; then
            run apt-get purge -q -y libmemcached11t64 memcached
        else
            run apt-get purge -q -y libmemcached11 memcached
        fi
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

            [ -f /etc/systemd/system/multi-user.target.wants/memcached.service ] \
                && run unlink /etc/systemd/system/multi-user.target.wants/memcached.service

            [ -f /lib/systemd/system/memcached.service ] && run rm -f /lib/systemd/system/memcached.service

            # Memcached systemd script (multi user instance).
            [ -f /etc/systemd/system/multi-user.target.wants/memcached@.service ] \
                && run unlink /etc/systemd/system/multi-user.target.wants/memcached@.service

            [ -f /lib/systemd/system/memcached@.service ] \
                && run rm -f /lib/systemd/system/memcached@.service

            [ -d /usr/share/memcached ] && run rm -fr /usr/share/memcached
            [ ! -L /usr/local/lib/lemper/memcached ] && [ -d /usr/local/lib/lemper/memcached ] \
                && run rm -fr /usr/local/lib/lemper/memcached

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

function lemper_memcached_remove_entry() {
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
}
