#!/usr/bin/env bash

function enable_memcache {
if [[ -n $1 ]]; then
    phpv=$1
else
    phpv="7.0" # default php install 7.0 (latest stable recommendation)
fi

# Custom Memcache setting
sed -i 's/-m 64/-m 128/g' /etc/memcached.conf
cat > /etc/php/${PHPver}/mods-available/memcache.ini <<EOL
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
}

header_msg
echo -n "Do you want to install Memcache? [Y/n]: "
read mcinstall

if [[ "$mcinstall" == "Y" || "$mcinstall" == "y" || "$mcinstall" == "yes" ]]; then
    echo "Installing Memcache and Php memcached module..."

    # Install memcache?
    apt-get install -y memcached php-memcached php-memcache

    if [ "$PHPver" != "all" ]; then
        enable_memcache $PHPver
    else
        enable_memcache "7.1"
        enable_memcache "7.0"
        enable_memcache "5.6"
    fi
    
    # Restart memcached daemon
    service memcached restart
fi
