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

function init_redis_install {
    echo ""
    echo "Welcome to Redis Installation..."
    echo ""

    while [[ $INSTALL_REDIS != "y" && $INSTALL_REDIS != "n" ]]; do
        read -p "Do you want to install Redis server? [y/n]: " -e INSTALL_REDIS
    done

    if [[ "$INSTALL_REDIS" == Y* || "$INSTALL_REDIS" == y* ]]; then
        echo -e "\nInstalling Redis server and Redis PHP module..."

        # Add Redis repos
        run add-apt-repository -y ppa:chris-lea/redis-server >> lemper.log 2>&1
        run apt-get update -y >> lemper.log 2>&1

        # Install Redis
        run apt-get install -y redis-server php-redis >> lemper.log 2>&1

        # Configure Redis
        if [ ! /etc/redis/redis.conf ]; then
            cp -f config/redis/redis.conf /etc/redis/
        fi

        # Custom Redis configuration
        cat >> /etc/redis/redis.conf <<EOL

###################################################################
# Custom configuration by LEMPer
#
maxmemory 128mb
maxmemory-policy allkeys-lru
EOL

        # Custom Optimization
        cat >> /etc/sysctl.conf <<EOL

###################################################################
# Custom optimization by LEMPer
#
net.core.somaxconn=65535
vm.overcommit_memory=1
EOL

        if [ ! -f /etc/rc.local ]; then
            touch /etc/rc.local
        fi

        cat >> /etc/rc.local <<EOL

###################################################################
# Custom optimization by LEMPer
#
sysctl -w net.core.somaxconn=65535
echo never > /sys/kernel/mm/transparent_hugepage/enabled
EOL

        if [ ! -f /lib/systemd/system/redis-server.service ]; then
            cp -f config/redis/systemd/redis-server.service /lib/systemd/system/

            if [ ! -f /etc/systemd/system/redis.service ]; then
                link -s /lib/systemd/system/redis-server.service /etc/systemd/system/redis.service
            fi

            # Reloading daemon
            systemctl daemon-reload
        fi

        if [ ! -f /etc/init.d/redis-server ]; then
            cp -f config/redis/init.d/redis-servr /etc/init.d/
        fi

        # Restart redis daemon
        echo "Starting Redis server..."
        if [ -f /etc/systemd/system/redis.service ]; then
            systemctl restart redis-server.service

            # Enable Redis on system boot
            systemctl enable redis-server.service
        else
            service redis-server restart
        fi

        if [[ $(ps -ef | grep -v grep | grep redis-server | wc -l) > 0 ]]; then
            status "Redis server started successfully."
        else
            warning "Something wrong with Redis installation."
        fi
    fi

}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which redis-server) ]]; then
    warning -e "\nRedis key-value store server already exists. Installation skipped..."
else
    init_redis_install "$@"
fi
