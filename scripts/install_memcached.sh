#!/usr/bin/env bash

# Include decorator
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

    # Custom Memcache setting
    #sed -i 's/-m 64/-m 128/g' /etc/memcached.conf

    if [ -d  /etc/php/${PHPv}/mods-available/ ]; then
        cat > /etc/php/${PHPv}/mods-available/memcache.ini <<EOL
; uncomment the next line to enable the module
extension=memcache.so

[memcache]
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
    else
        warning "It seems that PHP ${PHPver} not yet installed. Please install it before!"
    fi
}

function init_memcache_install() {
    echo ""
    while [[ $INSTALL_MEMCACHE != "y" && $INSTALL_MEMCACHE != "n" ]]; do
        read -p "Do you want to install Memcache server? [y/n]: " -e INSTALL_MEMCACHE
    done

    if [[ "$INSTALL_MEMCACHE" == Y* || "$INSTALL_MEMCACHE" == y* ]]; then
        echo -e "\nInstalling Memcache and PHP memcached module..."

        # Install memcached
        run apt-get install -y libmemcached11 memcached php-igbinary \
            php-memcache php-memcached php-msgpack >> lemper.log 2>&1

        # Enable PHP module
        echo "Enabling PHP memcached module..."

        PHPver="7.3"
        if [ "$PHPver" != "all" ]; then
            enable_memcache ${PHPver}

            # Required for LEMPer default PHP
            if [ "$PHPver" != "7.3" ]; then
                enable_memcache "7.3"
            fi
        else
            enable_memcache "5.6"
            enable_memcache "7.0"
            enable_memcache "7.1"
            enable_memcache "7.2"
            enable_memcache "7.3"
        fi

        # Restart Memcached daemon
        if [[ $(ps -ef | grep -v grep | grep memcached | wc -l) > 0 ]]; then
            run service memcached restart
            status "Memcached server installed successfully."
        fi
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which memcached) ]]; then
    warning -e "\nMemcache server already exists. Installation skipped..."
else
    init_memcache_install "$@"
fi
