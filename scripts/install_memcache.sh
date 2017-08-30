#!/usr/bin/env bash

echo "Installing Memcached and Php memcached module..."

# Install memcached?
apt-get install -y memcached php-memcached php-memcache

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

# Restart memcached daemon
service memcached restart
