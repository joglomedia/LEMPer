#!/usr/bin/env bash

# Memcached Installer
# Min. Requirement  : GNU/Linux Ubuntu 16.04 & 16.04
# Last Build        : 31/08/2019
# Author            : MasEDI.Net (me@masedi.net)
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

##
# Memcached install
#
# Usage: install_memcached [VERSION] [INSTALLER]
#
function install_memcached() {
    local SELECTED_INSTALLER=""

    if "${AUTO_INSTALL}"; then
        if [[ ${INSTALL_MEMCACHED} == true ]]; then
            DO_INSTALL_MEMCACHED="y"
            SELECTED_INSTALLER=${MEMCACHED_INSTALLER:-"repo"}
        else
            DO_INSTALL_MEMCACHED="n"
        fi
    else
        while [[ "${DO_INSTALL_MEMCACHED}" != "y" && "${DO_INSTALL_MEMCACHED}" != "n" ]]; do
            read -rp "Do you want to install Memcached server? [y/n]: " -i y -e DO_INSTALL_MEMCACHED
        done
    fi

    if [[ ${DO_INSTALL_MEMCACHED} == y* || ${DO_INSTALL_MEMCACHED} == Y* ]]; then
        # Install menu.
        if ! "${AUTO_INSTALL}"; then
            echo "Available Memcached installation method:"
            echo "  1). Install from Repository (repo)"
            echo "  2). Compile from Source (source)"
            echo "-------------------------------------"

            while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
                ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
                read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
            done
        fi

        case "${SELECTED_INSTALLER}" in
            1|"repo")
                echo "Installing Memcached server from repository..."

                if hash apt 2>/dev/null; then
                    run apt install -qq -y \
                        libevent-dev libsasl2-dev libmemcached-tools libmemcached11 libmemcachedutil2 memcached
                else
                    fail "Unable to install Memcached, this GNU/Linux distribution is not supported."
                fi
            ;;
            2|"source")
                echo "Installing Memcached server from source..."

                if hash apt 2>/dev/null; then
                    run apt install -qq -y \
                        libevent-dev libsasl2-dev libmemcached-tools libmemcached11 libmemcachedutil2
                else
                    fail "Unable to install Memcached, this GNU/Linux distribution is not supported."
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}"

                # Install Libevent from source.
                #LIBEVENT_DOWNLOAD_URL="https://github.com/libevent/libevent/releases/download/release-2.1.11-stable/libevent-2.1.11-stable.tar.gz"
                #if curl -sLI "${LIBEVENT_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                #    run wget -q -O libevent.tar.gz "${LIBEVENT_DOWNLOAD_URL}"
                #    run tar -zxf libevent.tar.gz
                #    run cd libevent-*
                #    run ./configure --prefix=/usr/local/libevent
                #    run make
                #    run make install
                #    run cd "${BUILD_DIR}"
                #fi

                # Memcached source.
                if [[ ${MEMCACHED_VERSION} == "latest" ]]; then
                    MEMCACHED_DOWNLOAD_URL="http://memcached.org/latest"
                else
                    MEMCACHED_DOWNLOAD_URL="https://memcached.org/files/memcached-${MEMCACHED_VERSION}.tar.gz"
                fi

                if curl -sLI "${MEMCACHED_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
                    run wget -q -O memcached.tar.gz "${MEMCACHED_DOWNLOAD_URL}" && \
                    run tar -zxf memcached.tar.gz && \
                    run cd memcached-* && \

                    if [[ ${MEMCACHED_SASL} == "enable" || ${MEMCACHED_SASL} == true ]]; then
                        #run ./configure --enable-sasl --bindir=/usr/bin --with-libevent=/usr/local/libevent
                        run ./configure --enable-sasl --bindir=/usr/bin
                    else
                        #run ./configure --bindir=/usr/bin --with-libevent=/usr/local/libevent
                        run ./configure --bindir=/usr/bin
                    fi

                    run make && \
                    run make install

                    # Create memcache user. 
                    # TODO: not realy used, due to LEMPer will run memcached as www-data for Nginx PageSpeed module.
                    if [[ -z $(getent passwd memcache) ]]; then
                        if "${DRYRUN}"; then
                            echo "Create memcache user in dryrun mode."
                        else
                            run groupadd -r memcache
                            run useradd -r -M -g memcache memcache
                        fi
                    fi
                else
                    error "An error occured while downloading Memcached source."
                fi

                run cd "${CURRENT_DIR}"
            ;;
            *)
                # Skip installation.
                error "Installer method not supported. Memcached installation skipped."
            ;;
        esac

        if [[ -n $(command -v memcached) ]]; then
            echo "Configuring Memcached server..."

            # Remove existing Memcached config.
            [ -f /etc/memcached.conf ] && run mv /etc/memcached.conf /etc/memcached.conf~

            # Copy multi user instance config.
            run cp -fr etc/memcached/memcache.conf /etc/memcached_memcache.conf
            run cp -fr etc/memcached/www-data.conf /etc/memcached_www-data.conf

            # Memcached init script.
            [ -f /etc/init.d/memcached ] && run mv /etc/init.d/memcached /etc/init.d/memcached~
            run cp -f etc/init.d/memcached /etc/init.d/
            run chmod ugo+x /etc/init.d/memcached

            # Memcached systemd script (multi user instance).
            [ -f /lib/systemd/system/memcached.service ] && \
            run mv /lib/systemd/system/memcached.service /lib/systemd/system/memcached.service~

            [ ! -f /lib/systemd/system/memcached@.service ] && \
            run cp etc/systemd/memcached@.service /lib/systemd/system/

            [ -f /etc/systemd/system/multi-user.target.wants/memcached@.service ] && \
            run mv /etc/systemd/system/multi-user.target.wants/memcached@.service \
                /etc/systemd/system/multi-user.target.wants/memcached@.service~

            [ ! -f /etc/systemd/system/multi-user.target.wants/memcached@.service ] && \
            run ln -s /lib/systemd/system/memcached@.service \
                /etc/systemd/system/multi-user.target.wants/memcached@.service

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

            # Enabled SASL auth?
            if [[ ${MEMCACHED_SASL} == "enable" || ${MEMCACHED_SASL} == true ]]; then
                echo "Memcached SASL auth option is enabled..."

                if "${DRYRUN}"; then
                    info "Memcahed SASL-auth configured in dry run mode."
                else
                    MEMCACHED_USERNAME=${MEMCACHED_USERNAME:-"lempermc"}
                    MEMCACHED_PASSWORD=${MEMCACHED_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

                    run mkdir -p /etc/sasl2 && run touch /etc/sasl2/memcached_memcache.conf
                    cat > /etc/sasl2/memcached_memcache.conf <<EOL
mech_list: plain
log_level: 5
sasldb_path: /etc/sasl2/memcached-sasldb2
EOL

                    # Add new sasl auth for memcached.
                    run saslpasswd2 -p -a memcached -f /etc/sasl2/memcached-sasldb2 -c "${MEMCACHED_USERNAME}" <<<"${MEMCACHED_PASSWORD}"
                    run chown memcache:memcache /etc/sasl2/memcached-sasldb2
                    run echo -e "\n# Enable SASL auth\n-S" >> /etc/memcached_memcache.conf
                    run sed -i "/#\ -vv/a -vv" /etc/memcached_memcache.conf

                    # Save config.
                    save_config -e "MEMCACHED_SASL=enabled\nMEMCACHED_USERNAME=${MEMCACHED_USERNAME}\nMEMCACHED_PASSWORD=${MEMCACHED_PASSWORD}\nMEMCACHED_INSTANCE=memcache"

                    # Save log.
                    save_log -e "Memcached SASL auth is enabled, below is your default auth credential.\nUsername: ${MEMCACHED_USERNAME}, password: ${MEMCACHED_PASSWORD}\nSave this credential and use it to authenticate your Memcached connection."
                fi
            fi

            # Optimizing Memcached conf.
            local RAM_SIZE && \
            RAM_SIZE=$(get_ram_size)
            if [[ ${RAM_SIZE} -le 2048 ]]; then
                # If machine RAM less than / equal 2GiB, set Memcached to 1/16 of RAM size.
                local MEMCACHED_SIZE=$((RAM_SIZE / 16))
            elif [[ ${RAM_SIZE} -gt 2049 && ${RAM_SIZE} -le 8192 ]]; then
                # If machine RAM less than / equal 8GiB and greater than 2GiB, set Memcached to 1/8 of RAM size.
                local MEMCACHED_SIZE=$((RAM_SIZE / 8))
            else
                # Otherwise, set Memcached to max of 2GiB.
                local MEMCACHED_SIZE=2048
            fi
            run sed -i "s/-m 64/-m ${MEMCACHED_SIZE}/g" /etc/memcached_memcache.conf
            run sed -i "s/-m 64/-m ${MEMCACHED_SIZE}/g" /etc/memcached_www-data.conf
        fi

        # Installation status.
        if "${DRYRUN}"; then
            info "Memcached server installed in dryrun mode."
        else
            if [[ $(pgrep -c memcached) -gt 0 ]]; then
                #run systemctl restart memcached@memcache
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_memcache.conf /var/run/memcached_memcache.pid
                #run systemctl restart memcached@www-data
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_www-data.conf /var/run/memcached_www-data.pid

                success "Memcached server restarted successfully."
            elif [[ -n $(command -v memcached) ]]; then
                #run systemctl start memcached@memcache
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_memcache.conf /var/run/memcached_memcache.pid
                #run systemctl start memcached@www-data
                run /usr/share/memcached/scripts/start-memcached \
                    /etc/memcached_www-data.conf /var/run/memcached_www-data.pid

                if [[ $(pgrep -c memcached) -gt 0 ]]; then
                    success "Memcached server started successfully."
                else
                    info "Something went wrong with Memcached installation."
                fi
            fi
        fi
    else
        info "Memcached server installation skipped."
    fi
}

# Install PHP Memcached extension.
function install_php_memcached() {
    # Selected PHP version.
    local SELECTED_PHP="${1}"

    # Install PHP memcached module.
    echo "Installing PHP ${SELECTED_PHP} memcached module..."

    if hash apt 2>/dev/null; then
        #PHPVERS=$(sed "s/,/ /g" <<<"${SELECTED_PHP}")
        for PHPv in ${SELECTED_PHP//,/ } 
        do
            run apt install -qq -y \
                "php${PHPv}-igbinary" "php${PHPv}-memcache" "php${PHPv}-memcached" "php${PHPv}-msgpack"
            enable_php_memcached "${PHPv}"
        done

        # Default PHP 7.4 for LEMPer.
        if [ "${PHPv}" != "7.4" ]; then
            run apt install -qq -y \
                "php7.4-igbinary" "php7.4-memcache" "php7.4-memcached" "php7.4-msgpack"
            enable_php_memcached "7.4"
        fi
    else
        fail "Unable to install PHP Memcached, this GNU/Linux distribution is not supported."
    fi
}

function enable_php_memcached() {
    # PHP version.
    local PHPv="${1}"

    echo "Enabling PHP ${PHPv} memcached module..."

    if "${DRYRUN}"; then
        echo "PHP ${PHPv} Memcache module enabled in dryrun mode."
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

                success "PHP ${PHPv} Memcache module enabled."
            fi

            # Reload PHP-FPM service.
            echo "Restarting php${PHPv}-fpm to apply Memcached module."

            if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                run systemctl reload "php${PHPv}-fpm"
                success "php${PHPv}-fpm restarted successfully."
            elif [[ -n $(command -v "php${PHPv}") ]]; then
                run systemctl start "php${PHPv}-fpm"

                if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                    success "php${PHPv}-fpm started successfully."
                else
                    info "Something went wrong with php${PHPv}-fpm installation."
                fi
            fi

        else
            info "It seems that PHP ${PHPv} not yet installed. Please install it before!"
        fi
    fi
}

function init_memcached_install() {
    install_memcached "${MEMC_VERSION}" "${MEMC_INSTALLER}"

    if [[ -z "${SELECTED_PHP}" ]]; then
        SELECTED_PHP=${PHP_VERSION:-"7.4"}
    elif [[ "${SELECTED_PHP}" == "all" ]]; then
        SELECTED_PHP="5.6,7.0,7.1,7.2,7.3,7.4,8.0"
    fi

    install_php_memcached "${PHP_VERSION}"
}

echo "[Memcached Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v memcached) ]]; then
    info "Memcached server already exists, installation skipped..."
else
    init_memcached_install "$@"
fi
