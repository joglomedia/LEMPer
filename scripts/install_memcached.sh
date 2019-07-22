#!/usr/bin/env bash

# Memcached Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

function enable_memcache {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.0 (latest stable recommendation)
    fi

    if "${DRYRUN}"; then
        echo "Optimizing PHP Memcache module."
    else
        # Custom Memcache setting.
        #sed -i 's/-m 64/-m 128/g' /etc/memcached.conf

        if [ -d /etc/php/${PHPv}/mods-available/ ]; then
            cat >> /etc/php/${PHPv}/mods-available/memcache.ini <<EOL

; Optimized for LEMPer stack
memcache.dbpath="/var/lib/memcache"
memcache.maxreclevel=0
memcache.maxfiles=0
memcache.archivememlim=0
memcache.maxfilesize=0
memcache.maxratio=0
; custom setting for WordPress + W3TC
session.bak_handler = memcache
session.bak_path = "tcp://127.0.0.1:11211"
EOL

            # Reload PHP-FPM service
            if [[ $(ps -ef | grep -v grep | grep php-fpm | wc -l) > 0 ]]; then
                run service php${PHPv}-fpm reload
                status "PHP${PHPv}-FPM restarted successfully."
            fi

        else
            warning "It seems that PHP ${PHPv} not yet installed. Please install it before!"
        fi
    fi
}

function init_memcache_install() {
    while [[ $INSTALL_MEMCACHE != "y" && $INSTALL_MEMCACHE != "n" ]]; do
        read -p "Do you want to install Memcache server? [y/n]: " -e INSTALL_MEMCACHE
    done

    if [[ "$INSTALL_MEMCACHE" == Y* || "$INSTALL_MEMCACHE" == y* ]]; then
        echo -e "\nInstalling Memcache and PHP memcached module..."

        # Install memcached
        run apt-get install -y libmemcached11 memcached php-igbinary \
            php-memcache php-memcached php-msgpack

        # Enable PHP module
        echo "Enabling PHP memcached module..."

        # Set PHP version to install.
        if [ -z "${PHP_VERSION}" ]; then PHP_VERSION="7.3"; fi

        if [ "${PHP_VERSION}" != "all" ]; then
            enable_memcache "${PHP_VERSION}"

            # Default PHP Required for LEMPer
            if [ "${PHP_VERSION}" != "7.3" ]; then
                enable_memcache "7.3"
            fi
        else
            enable_memcache "5.6"
            enable_memcache "7.0"
            enable_memcache "7.1"
            enable_memcache "7.2"
            enable_memcache "7.3"
        fi

        # Installation status.
        if "${DRYRUN}"; then
            status -e "\nMemcache server installed in dryrun mode."
        else
            if [[ $(ps -ef | grep -v grep | grep memcached | wc -l) > 0 ]]; then
                service memcached restart
                status -e "\nMemcache server installed successfully."
            else
                warning -e "\nSomething wrong with Memcache installation."
            fi
        fi
    fi
}

echo ""
echo "Welcome to Memcached Installation..."
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which memcached) ]]; then
    warning "Memcache server already exists. Installation skipped..."
else
    init_memcache_install "$@"
fi
