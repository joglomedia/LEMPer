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

echo -e "\nWelcome to Redis installation script"

function enable_redis {
# Custom Redis setting
cat >> /etc/redis/redis.conf <<EOL
# Custom configuration
maxmemory 128mb
maxmemory-policy allkeys-lru
EOL
}

#header_msg
echo -en "\nDo you want to install Redis? [Y/n]: "
read RedisInstall

if [[ "$RedisInstall" == Y* || "$RedisInstall" == y* ]]; then
    echo -e "\nInstalling Redis server and Redis PHP module...\n"

    # Add Redis repos
    run add-apt-repository ppa:chris-lea/redis-server -y
    run apt-get update -y

    # Install Redis
    run apt-get install -y redis-server php-redis

    # Configure Redis
    enable_redis

    # Restart redis daemon
    if [ -f /etc/systemd/system/redis.service ]; then
        run systemctl restart redis-server.service

        # Enable Redis on system boot
        run systemctl enable redis-server.service
    else
        run service redis-server restart
    fi

    if [[ $(ps -ef | grep -v grep | grep redis-server | wc -l) > 0 ]]; then
        status -e "\nRedis server started successfully."
    else
        warning -e "\nSomething wrong with Redis installation."
    fi
fi
