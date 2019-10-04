#!/usr/bin/env bash

# Memcached Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 31/08/2019
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

function init_memcached_install() {
    if "${AUTO_INSTALL}"; then
        DO_INSTALL_MEMCACHED="y"
    else
        while [[ "${DO_INSTALL_MEMCACHED}" != "y" && "${DO_INSTALL_MEMCACHED}" != "n" ]]; do
            read -rp "Do you want to install Memcached server? [y/n]: " -i y -e DO_INSTALL_MEMCACHED
        done
    fi

    if [[ ${DO_INSTALL_MEMCACHED} == y* && ${INSTALL_MEMCACHED} == true ]]; then
        local SELECTED_MEMCACHED_INSTALLER=${MEMCACHED_INSTALLER:-"repo"}
        case "${SELECTED_MEMCACHED_INSTALLER}" in
            1|"repo")
                echo "Installing Memcached server from repository..."
                run apt-get -qq install -y libmemcached11 libmemcachedutil2 libmemcached-tools memcached
            ;;

            2|"source"|*)
                echo "Installing Memcached server from source..."

                run apt-get -qq install -y libevent-dev libmemcached-tools libmemcached11 libmemcachedutil2
                
                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}"

                if [[ ${MEMCACHED_VERSION} == "latest" ]]; then
                    memcached_download_url="http://memcached.org/latest"
                else
                    memcached_download_url="https://memcached.org/files/memcached-${MEMCACHED_VERSION}.tar.gz"
                fi

                if wget -q -O "memcached.tar.gz" "${memcached_download_url}"; then
                    run tar -zxf "memcached.tar.gz"
                    run cd memcached-*

                    if [[ ${MEMCACHED_SASL} == "enable" || ${MEMCACHED_SASL} == true ]]; then
                        run ./configure --bindir=/usr/bin --enable-sasl
                    else
                        run ./configure --bindir=/usr/bin
                    fi

                    run make && \
                    run make install

                    # Create memcache user. 
                    # TODO: not realy used, due to LEMPer will run memcached as www-data to comply Nginx PageSpeed module.
                    if [[ -z $(getent passwd memcache) ]]; then
                        if "${DRYRUN}"; then
                            echo "Create memcache user in dryrun mode."
                        else
                            run groupadd -r memcache
                            run useradd -r -M -g memcache memcache
                        fi
                    fi
                else
                    warning "An error occured when downloading Memcached source."
                fi

                run cd "${CURRENT_DIR}"
            ;;
        esac

        if [[ -n $(command -v memcached) ]]; then
            echo "Configuring Memcached server..."

            # SASL auth enabled.
            if "${DRYRUN}"; then
                warning "Memcahed SASL-auth configured in dry run mode."
            else
                if [[ ${MEMCACHED_SASL} == "enable" || ${MEMCACHED_SASL} == true ]]; then
                    run mkdir -p /etc/sasl2 && run touch /etc/sasl2/memcached.conf
                    cat >> /etc/sasl2/memcached.conf <<EOL
mech_list: plain
log_level: 5
sasldb_path: /etc/sasl2/sasldb2-memcached
EOL
                    run saslpasswd2 -p -a memcached -f /etc/sasl2/sasldb2-memcached -c "${USERNAME}" <<< "${PASSWORD}"
                    run chown memcache:memcache /etc/sasl2/sasldb2-memcached
                fi
            fi

            # Remove existing Memcached config.
            if [ -f /etc/memcached.conf ]; then
                run mv /etc/memcached.conf /etc/memcached.conf~
            fi

            # Copy multi user instance config.
            if [ ! -d /etc/memcached ]; then
                run cp -fr etc/memcached /etc/
            fi

            # Memcached init script.
            if [ ! -f /etc/init.d/memcached ]; then
                run cp -f etc/init.d/memcached /etc/init.d/
                run chmod ugo+x /etc/init.d/memcached
            fi

            # Memcached systemd script (multi user instance).
            if [ -f /lib/systemd/system/memcached.service ]; then
                run mv /lib/systemd/system/memcached.service /lib/systemd/system/memcached.service~
            fi

            if [ ! -f /lib/systemd/system/memcached@.service ]; then
                run cp etc/systemd/memcached@.service /lib/systemd/system/
            fi

            if [ -f /etc/systemd/system/multi-user.target.wants/memcached@.service ]; then
                run mv /etc/systemd/system/multi-user.target.wants/memcached@.service \
                    /etc/systemd/system/multi-user.target.wants/memcached@.service~
            fi

            if [ ! -f /etc/systemd/system/multi-user.target.wants/memcached@.service ]; then
                run ln -s /lib/systemd/system/memcached@.service \
                    /etc/systemd/system/multi-user.target.wants/memcached@.service
            fi

            # Custom memcached scripts.
            if [ ! -f /usr/share/memcached/scripts/systemd-memcached-wrapper ]; then
                run cp -fr share/memcached /usr/share/
                run chmod ugo+x /usr/share/memcached/scripts/systemd-memcached-wrapper
                run chmod ugo+x /usr/share/memcached/scripts/start-memcached
                run chmod ugo+x /usr/share/memcached/scripts/memcached-tool
                run chmod ugo+x /usr/share/memcached/scripts/damemtop
            fi

            # Try reloading daemon.
            run systemctl daemon-reload

            # Enable in start up.
            run systemctl enable memcached@memcache.service
            run systemctl enable memcached@www-data.service

            # Optimizing Memcached conf.
            local RAM_SIZE && \
            RAM_SIZE=$(get_ram_size)
            if [[ ${RAM_SIZE} -le 2048 ]]; then
                # If machine RAM less than / equal 1GiB, set Memcached to 1/16 of RAM size.
                local MEMCACHED_SIZE=$((RAM_SIZE / 16))
            elif [[ ${RAM_SIZE} -gt 2049 && ${RAM_SIZE} -le 8192 ]]; then
                # If machine RAM less than / equal 8GiB and greater than 2GiB, set Memcached to 1/4 of RAM size.
                local MEMCACHED_SIZE=$((RAM_SIZE / 8))
            else
                # Otherwise, set Memcached to max of 2048GiB.
                local MEMCACHED_SIZE=2048
            fi
            run sed -i "s/-m 64/-m ${MEMCACHED_SIZE}/g" /etc/memcached_memcache.conf
            run sed -i "s/-m 64/-m ${MEMCACHED_SIZE}/g" /etc/memcached_www-data.conf
        fi

        # Install PHP memcached module.
        echo "Installing PHP memcached module..."
        run apt-get -qq install -y php-igbinary php-memcache php-memcached php-msgpack

        # Enable PHP module
        echo "Enabling PHP memcached module..."

        # Set PHP version to install.
        PHP_VERSION=${PHP_VERSION:-"7.3"}
        if [ "${PHP_VERSION}" != "all" ]; then
            run enable_memcached "${PHP_VERSION}"

            # Default PHP Required for LEMPer
            if [ "${PHP_VERSION}" != "7.3" ]; then
                run enable_memcached "7.3"
            fi
        else
            run enable_memcached "5.6"
            run enable_memcached "7.0"
            run enable_memcached "7.1"
            run enable_memcached "7.2"
            run enable_memcached "7.3"
        fi

        # Installation status.
        if "${DRYRUN}"; then
            warning "Memcached server installed in dryrun mode."
        else
            if [[ $(pgrep -c memcached) -gt 0 ]]; then
                #run service memcached@memcache restart
                #run service memcached@www-data restart
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_memcache.conf /var/run/memcached_memcache.pid
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_www-data.conf /var/run/memcached_www-data.pid

                status "Memcached server restarted successfully."
            elif [[ -n $(command -v memcached) ]]; then
                #run service memcached@memcache start
                #run service memcached@www-data start
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_memcache.conf /var/run/memcached_memcache.pid
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_www-data.conf /var/run/memcached_www-data.pid

                sleep 1

                if [[ $(pgrep -c memcached) -gt 0 ]]; then
                    status "Memcached server started successfully."
                else
                    warning "Something wrong with Memcached installation."
                fi
            fi
        fi
    fi
}

function enable_memcached {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    if "${DRYRUN}"; then
        echo "Enabling PHP Memcache module in dryrun mode."
    else
        # Optimize PHP memcache module.
        if [ -d "/etc/php/${PHPv}/mods-available/" ]; then
            if [ -f "/etc/php/${PHPv}/mods-available/memcache.ini" ]; then
                cat >> "/etc/php/${PHPv}/mods-available/memcache.ini" <<EOL

; Optimized for LEMPer stack.
memcache.dbpath="/var/lib/memcache"
memcache.maxreclevel=0
memcache.maxfiles=0
memcache.archivememlim=0
memcache.maxfilesize=0
memcache.maxratio=0

; Custom setting for WordPress + W3TC.
session.bak_handler="memcache"
session.bak_path="tcp://127.0.0.1:11211"
EOL
            fi

            # Reload PHP-FPM service.
            if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                run service "php${PHPv}-fpm" reload
                status "PHP${PHPv}-FPM restarted successfully."
            elif [[ -n $(command -v "php${PHPv}") ]]; then
                run service "php${PHPv}-fpm" start

                if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                    status "PHP${PHPv}-FPM started successfully."
                else
                    warning "Something wrong with PHP & FPM ${PHPv} installation."
                fi
            fi

        else
            warning "It seems that PHP ${PHPv} not yet installed. Please install it before!"
        fi
    fi
}

echo "[Memcached Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v memcached) ]]; then
    warning "Memcached server already exists. Installation skipped..."
else
    init_memcached_install "$@"
fi
