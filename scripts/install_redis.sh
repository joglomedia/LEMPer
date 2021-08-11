#!/usr/bin/env bash

# Redis server installer
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 23/10/2019
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function add_redis_repo() {
    echo "Adding Redis repository..."

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    DISTRIB_REPO=${DISTRIB_REPO:-$(get_release_name)}

    case ${DISTRIB_NAME} in
        debian)
            if [ ! -f "/etc/apt/sources.list.d/dotdeb-stable.list" ]; then
                run touch /etc/apt/sources.list.d/dotdeb-stable.list
                run bash -c "echo -e 'deb http://ftp.utexas.edu/dotdeb/ stable all\ndeb-src http://ftp.utexas.edu/dotdeb/ stable all' > /etc/apt/sources.list.d/dotdeb-stable.list"
                run bash -c "wget -qO - 'https://www.dotdeb.org/dotdeb.gpg' | apt-key add -"
                run apt-get update -qq -y
            else
                info "Dotdeb repository already exists."
            fi
        ;;
        ubuntu)
            run add-apt-repository -y ppa:chris-lea/redis-server && \
            run apt-get update -qq -y
        ;;
        *)
            fail "Unable to add Redis, this GNU/Linux distribution is not supported."
        ;;
    esac
}

# Install redis.
function init_redis_install {
    local SELECTED_INSTALLER=""

    if "${AUTO_INSTALL}"; then
        if [[ -z "${REDIS_INSTALLER}" || "${REDIS_INSTALLER}" == "none" ]]; then
            DO_INSTALL_REDIS="n"
        else
            DO_INSTALL_REDIS="y"
            SELECTED_INSTALLER=${REDIS_INSTALLER:-"repo"}
        fi
    else
        while [[ "${DO_INSTALL_REDIS}" != "y" && "${DO_INSTALL_REDIS}" != "n" ]]; do
            read -rp "Do you want to install Redis server? [y/n]: " -i y -e DO_INSTALL_REDIS
        done
    fi

    if [[ ${DO_INSTALL_REDIS} == y* && "${INSTALL_REDIS}" == true ]]; then
        # Install menu.
        echo "Available Redis server installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1|"repo")
                # Add Redis repos.
                add_redis_repo

                echo "Installing Redis server from repository..."

                # Install Redis.
                if hash apt-get 2>/dev/null; then
                    run apt-get install -qq -y redis-server redis-tools
                else
                    fail "Unable to install Redis, this GNU/Linux distribution is not supported."
                fi
            ;;
            2|"source")
                echo "Installing Redis server from source..."
                
                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}" || error "Cannot change directory to ${BUILD_DIR}"

                if [[ "${REDIS_VERSION}" == "latest" || "${REDIS_VERSION}" == "stable" ]]; then
                    REDIS_DOWNLOAD_URL="http://download.redis.io/redis-stable.tar.gz"
                else
                    REDIS_DOWNLOAD_URL="http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz"
                fi

                if curl -sLI "${REDIS_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                    run wget -q -O "redis.tar.gz" "${REDIS_DOWNLOAD_URL}" && \
                    run tar -zxf "redis.tar.gz" && \
                    run cd redis-* && \
                    run make && \
                    run make install

                    # Create Redis user. 
                    if [[ -z $(getent passwd redis) ]]; then
                        if "${DRYRUN}"; then
                            echo "Create redis user in dryrun mode."
                        else
                            run groupadd -r redis
                            run useradd -r -M -g redis redis
                        fi
                    fi

                    if [ ! -d /etc/redis ]; then
                        run mkdir /etc/redis
                    fi
                    if [ ! -d /run/redis ]; then
                        run mkdir /run/redis
                        run chown redis:redis /run/redis
                        run chmod 770 /run/redis
                    fi
                else
                    error "An error occured while downloading Redis source."
                fi

                run cd "${CURRENT_DIR}" || error "Cannot change directory to ${CURRENT_DIR}"
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. Redis installation skipped."
            ;;
        esac

        # Configure Redis.
        if "${DRYRUN}"; then
            info "Configuring Redis in dryrun mode."
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
            elif [[ ${RAM_SIZE} -gt 1024 && ${RAM_SIZE} -le 8192 ]]; then
                # If machine RAM less than / equal 8GiB and greater than 2GiB, 
                # set Redis max mem to 1/4 of RAM size.
                local REDISMEM_SIZE=$((RAM_SIZE / 4))
            else
                # Otherwise, set Memcached to max of 2048MiB.
                local REDISMEM_SIZE=2048
            fi

            # Optimize Redis config.
            cat >> /etc/redis/redis.conf <<EOL

####################################
# Custom configuration for LEMPer
#
maxmemory ${REDISMEM_SIZE}mb
maxmemory-policy allkeys-lru
EOL

            # Is Redis password protected enable?
            if "${REDIS_REQUIRE_PASSWORD}"; then
                echo "Redis Requirepass is enabled..."

                REDIS_PASSWORD=${REDIS_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

                # Update Redis config.
                cat >> /etc/redis/redis.conf <<EOL
requirepass ${REDIS_PASSWORD}
EOL
                # Save config.
                save_config "REDIS_PASSWORD=${REDIS_PASSWORD}"

                # Save log.
                save_log -e "Redis server requirepass is enabled, here is your authentication password: ${REDIS_PASSWORD}\nSave this password and use it to authenticate your Redis connection (typically use -a parameter)."
            fi

            # Custom kernel optimization for Redis.
            cat >> /etc/sysctl.conf <<EOL

###################################
# Custom optimization for LEMPer
#
net.core.somaxconn=65535
vm.overcommit_memory=1
EOL

            if [ ! -f /etc/rc.local ]; then
                run touch /etc/rc.local
            fi

            # Make the change persistent.
            cat >> /etc/rc.local <<EOL

###################################################################
# Custom optimization for LEMPer
#
sysctl -w net.core.somaxconn=65535
echo never > /sys/kernel/mm/transparent_hugepage/enabled
EOL
        fi

        # Init Redis script.
        if [ ! -f /etc/init.d/redis-server ]; then
            run cp -f etc/init.d/redis-server /etc/init.d/
            run chmod ugo+x /etc/init.d/redis-server
        fi

        # Systemd Redis service.
        if [ ! -f /lib/systemd/system/redis-server.service ]; then
            run cp -f etc/systemd/redis-server.service /lib/systemd/system/

            if [ ! -f /etc/systemd/system/redis.service ]; then
                run ln -s /lib/systemd/system/redis-server.service /etc/systemd/system/redis.service
            fi

            # Reloading systemctl daemon.
            run systemctl daemon-reload
        fi

        # Restart Redis daemon.
        echo "Starting Redis server..."
        if [ -f /etc/systemd/system/redis.service ]; then
            run systemctl restart redis-server.service

            # Enable Redis on system boot.
            run systemctl enable redis-server.service
        else
            run systemctl restart redis-server
        fi

        if "${DRYRUN}"; then
            info "Redis server installed in dryrun mode."
        else
            if [[ $(pgrep -c redis-server) -gt 0 ]]; then
                success "Redis server started successfully."
            else
                info "Something went wrong with Redis installation."
            fi
        fi

        # PHP version.
        local PHPv="${1}"
        if [ -z "${PHPv}" ]; then
            PHPv=${PHP_VERSION:-"7.4"}
        fi

        # Install PHP Redis extension.
        install_php_redis "$@"
    else
        info "Redis server installation skipped."
    fi
}

# Install PHP Redis extension.
function install_php_redis() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Installing PHP ${PHPv} Redis extensions..."

    if hash apt-get 2>/dev/null; then
        run apt-get install -qq -y "php${PHPv}-redis"
    else
        fail "Unable to install PHP ${PHPv} Redis, this GNU/Linux distribution is not supported."
    fi
}


echo "[Redis (Key-value) Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v redis-server) ]]; then
    info "Redis key-value store server already exists. Installation skipped..."
else
    init_redis_install "$@"
fi
