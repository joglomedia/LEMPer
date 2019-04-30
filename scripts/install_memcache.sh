#!/usr/bin/env bash

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root..."
    exit 1
fi

function enable_memcache {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    # Custom Memcache setting
    sed -i 's/-m 64/-m 128/g' /etc/memcached.conf

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
    echo "It seems that PHP ${PHPver} not yet installed. Please install it before!"
fi
}

header_msg
echo -n "Do you want to install Memcache? [Y/n]: "
read MemcachedInstall

if [[ "$MemcachedInstall" == "Y" || "$MemcachedInstall" == "y" || "$MemcachedInstall" == "yes" ]]; then
    echo "Installing Memcache and PHP memcached module..."

    # Install memcached
    apt-get install -y memcached php-memcached php-memcache

    # Enable PHP module
    PHPver="7.0"
    if [ "$PHPver" != "all" ]; then
        enable_memcache ${PHPver}
    else
        enable_memcache "5.6"
        enable_memcache "7.0"
        enable_memcache "7.1"
        enable_memcache "7.2"
        enable_memcache "7.3"
    fi

    # Restart Memcached daemon
    service memcached restart
fi
