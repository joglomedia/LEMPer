#!/usr/bin/env bash

# Redis server installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 01/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Install redis.
function init_redis_install {
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_REDIS="y"
    else
        while [[ "${DO_INSTALL_REDIS}" != "y" && "${DO_INSTALL_REDIS}" != "n" ]]; do
            read -rp "Do you want to install Redis server? [y/n]: " -i y -e DO_INSTALL_REDIS
        done
    fi

    if [[ "${DO_INSTALL_REDIS}" == y* && "${INSTALL_REDIS}" == true ]]; then
        echo "Installing Redis server and Redis PHP module..."

        {
            # Add Redis repos.
            run add-apt-repository -y ppa:chris-lea/redis-server
            run apt-get update -y

            # Install Redis.
            run apt-get install -y redis-server php-redis
        }

        # Configure Redis.
        if "${DRYRUN}"; then
            warning "Configuring Redis in dryrun mode."
        else
            if [ ! -f /etc/redis/redis.conf ]; then
                run cp -f etc/redis/redis.conf /etc/redis/
            fi

            # Custom Redis configuration.
            local RAM_SIZE && \
            RAM_SIZE=$(get_ram_size)
            if [[ ${RAM_SIZE} -le 1024 ]]; then
                # If machine RAM less than / equal 1GiB, set Redis max mem to 1/8 of RAM size.
                local REDISMEM_SIZE=$((RAM_SIZE / 8))
            elif [[ ${RAM_SIZE} -gt 2048 && ${RAM_SIZE} -le 8192 ]]; then
                # If machine RAM less than / equal 8GiB and greater than 2GiB, 
                # set Redis max mem to 1/4 of RAM size.
                local REDISMEM_SIZE=$((RAM_SIZE / 4))
            else
                # Otherwise, set Memcached to max of 2048MiB.
                local REDISMEM_SIZE=2048
            fi

            cat >> /etc/redis/redis.conf <<EOL

###################################################################
# Custom configuration for LEMPer
#
maxmemory ${REDISMEM_SIZE}mb
maxmemory-policy allkeys-lru
EOL

            # Custom Optimization.
            cat >> /etc/sysctl.conf <<EOL

###################################################################
# Custom optimization for LEMPer
#
net.core.somaxconn=65535
vm.overcommit_memory=1
EOL

            if [ ! -f /etc/rc.local ]; then
                run touch /etc/rc.local
            fi

            cat >> /etc/rc.local <<EOL

###################################################################
# Custom optimization for LEMPer
#
sysctl -w net.core.somaxconn=65535
echo never > /sys/kernel/mm/transparent_hugepage/enabled
EOL
        fi

        # Init script.
        if [ ! -f /etc/init.d/redis-server ]; then
            run cp -f etc/init.d/redis-server /etc/init.d/
            run chmod ugo+x /etc/init.d/redis-server
        fi
        if [ ! -f /lib/systemd/system/redis-server.service ]; then
            run cp -f etc/systemd/redis-server.service /lib/systemd/system/

            if [ ! -f /etc/systemd/system/redis.service ]; then
                run link -s /lib/systemd/system/redis-server.service /etc/systemd/system/redis.service
            fi

            # Reloading daemon.
            run systemctl daemon-reload
        fi

        # Restart redis daemon.
        echo "Starting Redis server..."
        if [ -f /etc/systemd/system/redis.service ]; then
            run systemctl restart redis-server.service

            # Enable Redis on system boot.
            run systemctl enable redis-server.service
        else
            run service redis-server restart
        fi

        if "${DRYRUN}"; then
            warning "Redis server installed in dryrun mode."
        else
            if [[ $(pgrep -c redis-server) -gt 0 ]]; then
                status "Redis server started successfully."
            else
                warning "Something wrong with Redis installation."
            fi
        fi
    else
        echo "Skipping Redis server installation..."
    fi
}

echo "[Welcome to Redis server Installer]"
echo ""

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v redis-server) ]]; then
    warning "Redis key-value store server already exists. Installation skipped..."
else
    init_redis_install "$@"
fi
