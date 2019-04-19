#!/usr/bin/env bash

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root..."
    exit 1
fi

function enable_redis {
# Custom Redis setting
cat >> /etc/redis/redis.conf <<EOL
# Custom configuration
maxmemory 128mb
maxmemory-policy allkeys-lru
EOL
}

header_msg
echo -n "Do you want to install Redis? [Y/n]: "
read RedisInstall

if [[ "$RedisInstall" == "Y" || "$RedisInstall" == "y" || "$RedisInstall" == "yes" ]]; then
    echo "Installing Redis server and Redis PHP module..."

    # Add Redis repos
    add-apt-repository ppa:chris-lea/redis-server -y
    apt-get update -y

    # Install Redis
    apt-get install -y redis-server php-redis

    # Configure Redis
    enable_redis
    
    # Restart redis daemon
    systemctl restart redis-server.service

    # Enable Redis on system boot
    systemctl enable redis-server.service
fi
