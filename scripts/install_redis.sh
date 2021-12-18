#!/usr/bin/env bash

# Redis server installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 11/12/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Make sure only supported distribution can run this installer script.
preflight_system_check

function add_redis_repo() {
    echo "Adding Redis repository..."

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    DISTRIB_REPO=${DISTRIB_REPO:-$(get_release_name)}

    case ${DISTRIB_NAME} in
        debian)
            if [[ ! -f "/etc/apt/sources.list.d/dotdeb-stable.list" ]]; then
                run touch /etc/apt/sources.list.d/dotdeb-stable.list
                run bash -c "echo -e 'deb http://ftp.utexas.edu/dotdeb/ stable all\ndeb-src http://ftp.utexas.edu/dotdeb/ stable all' > /etc/apt/sources.list.d/dotdeb-stable.list"
                run bash -c "wget -qO - 'https://www.dotdeb.org/dotdeb.gpg' | apt-key add -"
                run apt-get update -q -y
            else
                info "Dotdeb repository already exists."
            fi
        ;;
        ubuntu)
            run add-apt-repository -y ppa:chris-lea/redis-server && \
            run apt-get update -q -y
        ;;
        *)
            fail "Unable to add Redis, this GNU/Linux distribution is not supported."
        ;;
    esac
}

# Install redis.
function init_redis_install {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_REDIS}" == true ]]; then
            DO_INSTALL_REDIS="y"
            SELECTED_INSTALLER=${REDIS_INSTALLER:-"repo"}
        else
            DO_INSTALL_REDIS="n"
        fi
    else
        while [[ "${DO_INSTALL_REDIS}" != "y" && "${DO_INSTALL_REDIS}" != "n" ]]; do
            read -rp "Do you want to install Redis server? [y/n]: " -i y -e DO_INSTALL_REDIS
        done
    fi

    if [[ ${DO_INSTALL_REDIS} == y* || ${DO_INSTALL_REDIS} == Y* ]]; then
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
            1 | "repo")
                # Add Redis repos.
                add_redis_repo

                echo "Installing Redis server from repository..."

                # Install Redis.
                run apt-get install -q -y redis-server redis-tools
            ;;
            2 | "source")
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
                        if [[ "${DRYRUN}" != true ]]; then
                            run groupadd -r redis
                            run useradd -r -M -g redis redis
                        else
                            info "Create Redis user in dry run mode."
                        fi
                    fi

                    if [[ ! -d /etc/redis ]]; then
                        run mkdir /etc/redis
                    fi

                    if [[ ! -d /run/redis ]]; then
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
                # Skip unsupported installation mode.
                error "Installer method not supported. Redis installation skipped."
            ;;
        esac

        # Configure Redis.
        if [[ "${DRYRUN}" != true ]]; then
            [[ ! -f /etc/redis/redis.conf ]] && run cp -f etc/redis/redis.conf /etc/redis/

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
            if [[ "${REDIS_REQUIRE_PASSWORD}" == true ]]; then
                echo "Configure Redis requirepass password."

                REDIS_PASSWORD=${REDIS_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

                # Update Redis config.
                cat >> /etc/redis/redis.conf <<EOL
requirepass ${REDIS_PASSWORD}
EOL
                # Save data.
                save_config "REDIS_PASSWORD=${REDIS_PASSWORD}"
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

            if [[ ! -f /etc/rc.local ]]; then
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
        else
            info "Redis configuration skipped in dry run mode."
        fi

        # Init Redis script.
        if [[ ! -f /etc/init.d/redis-server ]]; then
            run cp -f etc/init.d/redis-server /etc/init.d/
            run chmod ugo+x /etc/init.d/redis-server
        fi

        # Setup Systemd service.
        if [[ ! -f /lib/systemd/system/redis-server.service ]]; then
            run cp -f etc/systemd/redis-server.service /lib/systemd/system/

            if [[ ! -f /etc/systemd/system/redis.service ]]; then
                run ln -s /lib/systemd/system/redis-server.service /etc/systemd/system/redis.service
            fi

            # Reloading systemctl daemon.
            run systemctl daemon-reload
        fi

        # Restart and enable Redis on system boot.
        echo "Starting Redis server..."

        if [[ -f /etc/systemd/system/redis.service ]]; then
            run systemctl restart redis-server.service
            run systemctl enable redis-server.service
        else
            run systemctl restart redis-server
        fi

        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c redis-server) -gt 0 ]]; then
                success "Redis server started successfully."
            else
                info "Something went wrong with Redis installation."
            fi
        else
            info "Redis server started successfully in dry run mode."
        fi
    else
        info "Redis server installation skipped."
    fi
}

echo "[Redis (Key-value) Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v redis-server) && "${FORCE_INSTALL}" != true ]]; then
    info "Redis key-value store server already exists, installation skipped."
else
    init_redis_install "$@"
fi
