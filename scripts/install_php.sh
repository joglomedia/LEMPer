#!/usr/bin/env bash

# PHP Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 13/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Add PHP repository.
##
function add_php_repo() {
    echo "Add Ondrej's PHP repository..."

    DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
    RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

    case "${DISTRIB_NAME}" in
        debian)
            if [[ ! -f "/etc/apt/sources.list.d/ondrej-php-${RELEASE_NAME}.list" ]]; then
                run touch "/etc/apt/sources.list.d/ondrej-php-${RELEASE_NAME}.list"
                run bash -c "echo 'deb https://packages.sury.org/php/ ${RELEASE_NAME} main' > /etc/apt/sources.list.d/ondrej-php-${RELEASE_NAME}.list"
                run wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

                # Add openswoole official repository.
                if echo "${PHP_EXTENSIONS}" | grep -qwE "openswoole"; then
                    run add-apt-repository -y ppa:openswoole/ppa
                fi
            else
                info "PHP package repository already exists."
            fi
        ;;
        ubuntu)
            if [[ ! -f "/etc/apt/sources.list.d/ondrej-php-${RELEASE_NAME}.list" ]]; then
                run apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C
                run add-apt-repository -y ppa:ondrej/php

                # Add openswoole official repository.
                if echo "${PHP_EXTENSIONS}" | grep -qwE "openswoole"; then
                    run add-apt-repository -y ppa:openswoole/ppa
                fi
            else
                info "PHP package repository already exists."
            fi
        ;;
        *)
            fail "Unable to install PHP, this GNU/Linux distribution is not supported."
        ;;
    esac

    info "Updating repository, please wait..."
    run apt-get update -q -y && \
    run apt-get install -q -y geoip-bin geoip-database gettext libgd-dev libgeoip-dev libsodium-dev \
        libxml2-dev libxslt1-dev

}

##
# Install PHP and extensions.
##
function install_php() {
    export PHP_IS_INSTALLED="no"

    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    # Checking if PHP already installed.
    if [[ -n $(command -v "php${PHPv}") && -n $(command -v "php-fpm${PHPv}") ]]; then
        PHP_IS_INSTALLED="yes"
        info "PHP ${PHPv} and it's extensions already exists."
    else
        echo "Preparing PHP ${PHPv} installation..."

        local PHP_EXTS=()
        local PHP_REPO_EXTS=()
        local PHP_PECL_EXTS=()
        local PHP_PECL_FLAG=""

        # Include user defined extensions from config file.
        read -r -a PHP_EXTS <<< "${PHP_EXTENSIONS}"

        PHP_EXTS+=("bcmath" "bz2" "cli" "common" "curl" "dev" "fpm" "gd" "gmp" "gnupg" \
            "imap" "intl" "mbstring" "mysql" "opcache" "pcov" "pgsql" "pspell" "readline" \
            "ldap" "snmp" "soap" "sqlite3" "tidy" "tokenizer" "xml" "xmlrpc" "xsl" "yaml" "zip")

        # Add PHP extensions.
        [[ "${INSTALL_MEMCACHED}" == true ]] && PHP_EXTS+=("memcache" "memcached")
        [[ "${INSTALL_MONGODB}" == true ]] && PHP_EXTS+=("mongodb")
        [[ "${INSTALL_REDIS}" == true ]] && PHP_EXTS+=("redis")

        # Sort PHP extensions.
        #shellcheck disable=SC2207
        PHP_EXTS=($(printf "%s\n" "${PHP_EXTS[@]}" | sort -u | tr '\n' ' '))

        # Check additional PHP extensions availability.
        for EXT_NAME in "${PHP_EXTS[@]}"; do
            echo -n "Checking extension ${EXT_NAME}... "

            # Search extension from repository or PECL.
            if apt-cache search "php${PHPv}-${EXT_NAME}" | grep -c "php${PHPv}-${EXT_NAME}" > /dev/null; then
                echo "[php${PHPv}-${EXT_NAME}]"
                PHP_REPO_EXTS+=("php${PHPv}-${EXT_NAME}")
            elif apt-cache search "php-${EXT_NAME}" | grep -c "php-${EXT_NAME}" > /dev/null; then
                echo "[php${PHPv}-${EXT_NAME}]"
                PHP_REPO_EXTS+=("php-${EXT_NAME}")
            else
                # Fix PECL Sodium ext name.
                if [[ "${EXT_NAME}" == "sodium" ]]; then
                    EXT_NAME="libsodium"
                fi

                # Check PECL extension is available.
                if curl -sLI "https://pecl.php.net/rest/r/${EXT_NAME}/allreleases.xml" | grep -q "HTTP/[.12]* [2].."; then
                #if pecl list | grep -c "${EXT_NAME}" > /dev/null; then
                    echo "[pecl-${EXT_NAME}]"
                    PHP_PECL_EXTS+=("${EXT_NAME}")

                    if [[ "${EXT_NAME}" == "openswoole" ]]; then
                        PHP_PECL_FLAG=' -D enable-sockets="no" enable-openssl="yes" enable-http2="yes" enable-mysqlnd="yes" enable-swoole-json="yes" enable-swoole-curl="yes" enable-cares="yes" with-postgres="no"'
                    fi
                else
                    echo "Not found."
                fi
            fi
        done

        # Install PHP and PHP extensions.
        echo "Installing PHP ${PHPv} and it's extensions..."

        if [[ "${#PHP_REPO_EXTS[@]}" -gt 0 ]]; then
            run apt-get install -qq -y "php${PHPv}" "${PHP_REPO_EXTS[@]}" \
                dh-php php-common php-pear php-xml pkg-php-tools fcgiwrap spawn-fcgi
        fi

        # Install PHP extensions from PECL.
        echo "Installing PHP extensions from PECL repo..."

        # Sort PHP extensions.
        #shellcheck disable=SC2207
        PHP_PECL_EXTS=($(printf "%s\n" "${PHP_PECL_EXTS[@]}" | sort -u | tr '\n' ' '))

        # Remove json extension from PHP greater than 7.4. It is now always available.
        if [[ $(bc -l <<< "${PHPv//.} > 74") == 1 ]]; then
            PHP_PECL_EXTS=("${PHP_PECL_EXTS[@]/json/}")
        fi

        run pecl channel-update pear.php.net

        if [[ "${#PHP_PECL_EXTS[@]}" -gt 0 ]]; then
            run pecl -d "php_suffix=${PHPv}" install"${PHP_PECL_FLAG}" "${PHP_PECL_EXTS[@]}"
        fi

        # Install additional PHP extensions.
        [[ "${INSTALL_MEMCACHED}" == true ]] && install_php_memcached "${PHPv}"
        #[[ "${INSTALL_MONGODB}" == true ]] && install_php_mongodb "${PHPv}"

        if [[ -n $(command -v "php${PHPv}") ]]; then
            TOTAL_EXTS=$((${#PHP_EXTS[@]} + ${#PHP_PECL_EXTS[@]}))
            success "PHP ${PHPv} along with ${TOTAL_EXTS} extensions installed."
        fi

        # Unset PHP extensions variables.
        run unset PHP_EXTS PHP_REPO_EXTS PHP_PECL_EXTS PHP_PECL_FLAG

        # Enable GeoIP module.
        if [[ "${PHP_PECL_EXTS[*]}" =~ "geoip" ]]; then
            echo "Updating PHP ini file with GeoIP extension..."

            [[ ! -f "/etc/php/${PHPv}/mods-available/geoip.ini" ]] && \
            run touch "/etc/php/${PHPv}/mods-available/geoip.ini"
            run bash -c "echo extension=geoip.so > /etc/php/${PHPv}/mods-available/geoip.ini"

            if [[ ! -f "/etc/php/${PHPv}/cli/conf.d/20-geoip.ini" ]]; then
                run ln -s "/etc/php/${PHPv}/mods-available/geoip.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/20-geoip.ini"
            fi

            if [[ ! -f "/etc/php/${PHPv}/fpm/conf.d/20-geoip.ini" ]]; then
                run ln -s "/etc/php/${PHPv}/mods-available/geoip.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/20-geoip.ini"
            fi
        fi

        # Enable Mcrypt module.
        if [[ "${PHP_PECL_EXTS[*]}" =~ "mcrypt" ]]; then
            echo "Updating PHP ini file with Mcrypt extension..."

            [[ ! -f "/etc/php/${PHPv}/mods-available/mcrypt.ini" ]] && \
            run touch "/etc/php/${PHPv}/mods-available/mcrypt.ini"
            run bash -c "echo extension=mcrypt.so > /etc/php/${PHPv}/mods-available/mcrypt.ini"

            if [[ ! -f "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini" ]]; then
                run ln -s "/etc/php/${PHPv}/mods-available/mcrypt.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini"
            fi

            if [[ ! -f "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini" ]]; then
                run ln -s "/etc/php/${PHPv}/mods-available/mcrypt.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini"
            fi
        fi

        # Create PHP log dir.
        if [[ ! -d /var/log/php ]]; then
            run mkdir -p /var/log/php
        fi

        if [[ ! -d "/home/${LEMPER_USERNAME}/logs/php" ]]; then
            run mkdir -p "/home/${LEMPER_USERNAME}/logs/php"
        fi

        # Log rotation.
        run cp -f "etc/logrotate.d/php${PHPv}-fpm" /etc/logrotate.d/ && \
        run chmod 0644 "/etc/logrotate.d/php${PHPv}-fpm"

        # Optimize PHP & FPM configuration.
        optimize_php_fpm "${PHPv}"
    fi
}

##
# Restart PHP-FPM service.
##
function restart_php_fpm() {
    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    echo "Restarting PHP-FPM service..."

    # Restart PHP-FPM service.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
            run systemctl reload "php${PHPv}-fpm"
            success "php${PHPv}-fpm reloaded successfully."
        elif [[ -n $(command -v "php-fpm${PHPv}") ]]; then
            run systemctl start "php${PHPv}-fpm"

            if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                success "php${PHPv}-fpm started successfully."
            else
                error "Something goes wrong with PHP ${PHPv} & FPM installation."
            fi
        fi
    else
        info "php${PHPv}-fpm reloaded in dry run mode."
    fi
}

##
# PHP & FPM Optimization.
##
function optimize_php_fpm() {
    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    echo "Optimizing PHP ${PHPv} & FPM configuration..."

    if [[ ! -d "/etc/php/${PHPv}/fpm" ]]; then
        run mkdir -p "/etc/php/${PHPv}/fpm"
    fi

    # Copy the optimized-version of php.ini
    if [[ -f "etc/php/${PHPv}/fpm/php.ini" ]]; then
        run mv "/etc/php/${PHPv}/fpm/php.ini" "/etc/php/${PHPv}/fpm/php.ini~"
        run cp -f "etc/php/${PHPv}/fpm/php.ini" "/etc/php/${PHPv}/fpm/"
    else
        if [[ "${DRYRUN}" != true ]]; then
            if [[ "${ENVIRONMENT}" == prod* ]]; then
                OVT="${OVT:-"0"}"
            else
                OVT="${OVT:-"1"}" # Opcache is revalidated every file changes, good for development.
            fi

            cat >> "/etc/php/${PHPv}/fpm/php.ini" <<EOL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Custom Optimization for LEMPer ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=512
opcache.interned_strings_buffer=64
opcache.max_accelerated_files=32531
opcache.max_wasted_percentage=5
opcache.validate_timestamps=${OVT}
opcache.revalidate_freq=600
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.error_log=/var/log/php/php${PHPv}-opcache_error.log
EOL
        else
            info "PHP opcache optimized in dry run mode."
        fi
    fi

    # Copy the optimized-version of php-fpm config file.
    if [[ -f "etc/php/${PHPv}/fpm/php-fpm.conf" ]]; then
        run mv "/etc/php/${PHPv}/fpm/php-fpm.conf" "/etc/php/${PHPv}/fpm/php-fpm.conf~"
        run cp -f "etc/php/${PHPv}/fpm/php-fpm.conf" "/etc/php/${PHPv}/fpm/"
    else
        if [[ "${DRYRUN}" != true ]]; then
            if grep -qwE "^error_log\ =\ \/var\/log\/php${PHPv}-fpm.log" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
                run sed -i "s|^error_log\ =\ /var/log/php${PHPv}-fpm.log|error_log\ =\ /var/log/php/php${PHPv}-fpm.log/g" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            else
                run sed -i "/^;error_log/a error_log\ =\ \/var\/log\/php\/php${PHPv}-fpm.log" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            fi

            if grep -qwE "^emergency_restart_threshold\ =\ [0-9]*" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
                run sed -i "s/^emergency_restart_threshold\ =\ [0-9]*/emergency_restart_threshold\ =\ 10/g" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            else
                run sed -i "/^;emergency_restart_threshold/a emergency_restart_threshold\ =\ 10" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            fi

            if grep -qwE "^emergency_restart_interval\ =\ [0-9]*" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
                run sed -i "s/^emergency_restart_interval\ =\ [0-9]*/emergency_restart_interval\ =\ 60/g" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            else
                run sed -i "/^;emergency_restart_interval/a emergency_restart_interval\ =\ 60" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            fi

            if grep -qwE "^process_control_timeout\ =\ [0-9]*" "/etc/php/${PHPv}/fpm/php-fpm.conf"; then
                run sed -i "s/^process_control_timeout\ =\ [0-9]*/process_control_timeout\ =\ 10/g" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            else
                run sed -i "/^;process_control_timeout/a process_control_timeout\ =\ 10" \
                    "/etc/php/${PHPv}/fpm/php-fpm.conf"
            fi
        else
            info "PHP FPM optimized in dry run mode."
        fi
    fi

    if [[ ! -d "/etc/php/${PHPv}/fpm/pool.d" ]]; then
        run mkdir -p "/etc/php/${PHPv}/fpm/pool.d"
    fi

    # Copy the optimized-version of php fpm default pool.
    if [[ -f "etc/php/${PHPv}/fpm/pool.d/www.conf" ]]; then
        run mv "/etc/php/${PHPv}/fpm/pool.d/www.conf" "/etc/php/${PHPv}/fpm/pool.d/www.conf~"
        run cp -f "etc/php/${PHPv}/fpm/pool.d/www.conf" "/etc/php/${PHPv}/fpm/pool.d/"

        # Update timezone.
        run run sed -i "s|php_admin_value\[date\.timezone\]\ =\ UTC|php_admin_value\[date\.timezone\]\ =\ ${TIMEZONE}|g" \
            "/etc/php/${PHPv}/fpm/pool.d/www.conf"
    else
        # Enable FPM ping service.
        run sed -i "/^;ping.path\ =.*/a ping.path\ =\ \/ping" "/etc/php/${PHPv}/fpm/pool.d/www.conf"

        # Enable FPM status.
        run sed -i "/^;pm.status_path\ =.*/a pm.status_path\ =\ \/status" "/etc/php/${PHPv}/fpm/pool.d/www.conf"
        
        # Enable chdir.
        run sed -i "/^;chdir\ =.*/a chdir\ =\ \/usr\/share\/nginx\/html" "/etc/php/${PHPv}/fpm/pool.d/www.conf"

        # Add custom php extension (ex .php70, .php71)
        PHPExt=".php${PHPv//.}"
        run sed -i "s/;\(security\.limit_extensions\s*=\s*\).*$/\1\.php\ $PHPExt/g" \
            "/etc/php/${PHPv}/fpm/pool.d/www.conf"

        # Customize php ini settings.
        if [[ "${DRYRUN}" != true ]]; then
            cat >> "/etc/php/${PHPv}/fpm/pool.d/www.conf" <<EOL
; Custom PHP ini settings for LEMPer Stack.
php_admin_value[open_basedir] = /usr/share/nginx/html
;php_admin_value[disable_functions] = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,exec,passthru,popen,proc_open,shell_exec,system
;php_admin_value[disable_classes] = 
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /var/log/php/php${PHPv}-fpm.\$pool.log
php_admin_value[sys_temp_dir] = /usr/share/nginx/html/.lemper/tmp
php_admin_value[upload_tmp_dir] = /usr/share/nginx/html/.lemper/tmp
;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f www@my.domain.com
php_admin_value[opcache.file_cache] = /usr/share/nginx/html/.lemper/tmp/php_opcache
php_admin_value[opcache.error_log] = /var/log/php/php${PHPv}-opcache_error.log

; Configuration below can be overwritten from PHP call 'ini_set'.
php_flag[short_open_tag] = off
php_value[max_execution_time] = 300
php_value[max_input_time] = 60
php_value[memory_limit] = 128M
php_value[post_max_size] = 50M
php_flag[file_uploads] = on
php_value[upload_max_filesize] = 50M
php_value[max_file_uploads] = 20
php_value[default_socket_timeout] = 60
php_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
php_flag[display_errors] = on
php_flag[cgi.fix_pathinfo] = 1
php_value[date.timezone] = UTC
php_value[session.save_path] = /usr/share/nginx/html/.lemper/tmp/php_sessions
EOL
        else
            info "Default FPM pool optimized in dry run mode."
        fi
    fi

    # Copy the optimized-version of php fpm default lemper pool.
    local POOLNAME=${LEMPER_USERNAME:-"lemper"}
    if [[ -f "etc/php/${PHPv}/fpm/pool.d/lemper.conf" && ${POOLNAME} = "lemper" ]]; then
        run cp -f "etc/php/${PHPv}/fpm/pool.d/lemper.conf" "/etc/php/${PHPv}/fpm/pool.d/${POOLNAME}.conf"

        # Update timezone.
        run sed -i "s|php_admin_value\[date\.timezone\]\ =\ UTC|php_admin_value\[date\.timezone\]\ =\ ${TIMEZONE}|g" \
            "/etc/php/${PHPv}/fpm/pool.d/${POOLNAME}.conf"
    else
        if [[ -f "/etc/php/${PHPv}/fpm/pool.d/lemper.conf" && -z $(getent passwd "${POOLNAME}") ]]; then
            run mv "/etc/php/${PHPv}/fpm/pool.d/lemper.conf" "/etc/php/${PHPv}/fpm/pool.d/lemper.conf~"
        fi

        # Create custom pool configuration.
        if [[ "${DRYRUN}" != true ]]; then
            touch "/etc/php/${PHPv}/fpm/pool.d/${POOLNAME}.conf"
            cat > "/etc/php/${PHPv}/fpm/pool.d/${POOLNAME}.conf" <<EOL
[${POOLNAME}]
user = ${POOLNAME}
group = ${POOLNAME}

listen = /run/php/php${PHPv}-fpm.\$pool.sock
listen.owner = ${POOLNAME}
listen.group = ${POOLNAME}
listen.mode = 0660
;listen.allowed_clients = 127.1.0.1

; Custom PHP-FPM optimization, adjust here to meet your specs.
; Default value here is optimized for a single CPU with at least 1GB RAM.
pm = dynamic
pm.max_children = 30
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.process_idle_timeout = 30s
pm.max_requests = 500

pm.status_path = /php-fpm_status
ping.path = /php-fpm_ping

slowlog = /home/${POOLNAME}/logs/php/php${PHPv}-fpm_slow.log
request_slowlog_timeout = 10s

;chroot = /home/${POOLNAME}
chdir = /home/${POOLNAME}

;catch_workers_output = yes
;decorate_workers_output = no

security.limit_extensions = .php .php5 .php7 .php${PHPv//./}

; Custom PHP ini settings for LEMPer Stack.
php_admin_value[open_basedir] = /home/${POOLNAME}
;php_admin_value[disable_functions] = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,exec,passthru,popen,proc_open,shell_exec,system
;php_admin_value[disable_classes] = 
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /home/${POOLNAME}/logs/php/php${PHPv}-fpm.log
php_admin_value[sys_temp_dir] = /home/${POOLNAME}/.lemper/tmp
php_admin_value[upload_tmp_dir] = /home/${POOLNAME}/.lemper/tmp
;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f www@my.domain.com
php_admin_value[opcache.file_cache] = /home/${POOLNAME}/.lemper/tmp/php_opcache

; Configuration below can be overwritten from PHP call 'ini_set'.
php_flag[short_open_tag] = off
php_value[max_execution_time] = 300
php_value[max_input_time] = 60
php_value[memory_limit] = 128M
php_value[post_max_size] = 50M
php_flag[file_uploads] = on
php_value[upload_max_filesize] = 50M
php_value[max_file_uploads] = 20
php_value[default_socket_timeout] = 60
php_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
php_flag[display_errors] = on
php_flag[cgi.fix_pathinfo] = 1
php_value[date.timezone] = UTC
php_value[session.save_path] = /home/${POOLNAME}/.lemper/tmp/php_sessions
EOL
        else
            info "Custom FPM pool '${POOLNAME}' created in dry run mode."
        fi
    fi

    # Create default directories.
    run mkdir -p "/home/${POOLNAME}/.lemper/tmp"
    run mkdir -p "/home/${POOLNAME}/.lemper/tmp/php_opcache"
    run mkdir -p "/home/${POOLNAME}/.lemper/tmp/php_sessions"
    run mkdir -p "/home/${POOLNAME}/cgi-bin"
    run chown -hR "${POOLNAME}:${POOLNAME}" "/home/${POOLNAME}"

    # Fix cgi.fix_pathinfo (for PHP older than 5.3).
    #sed -i "s/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${PHPv}/fpm/php.ini
    #sed -i "s/php_flag[cgi.fix_pathinfo]\ =\ 1/php_flag[cgi.fix_pathinfo]\ =\ 0/g" \
    #    /etc/php/${PHPv}/fpm/pool.d/${POOLNAME}.conf
}

##
# Install PHP MongoDB extension.
##
function install_php_mongodb() {
    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    #echo -e "\nInstalling PHP ${PHPv} MongoDB extension..."

    #run apt-get install -qq -y "php${PHPv}-mongodb"

    #local CURRENT_DIR && \
    #CURRENT_DIR=$(pwd)

    #run cd "${BUILD_DIR}" || return 1

    #if [[ ! -d "${BUILD_DIR}/php-${PHPv}-mongodb" ]]; then
    #    run git clone --depth=1 -q https://github.com/mongodb/mongo-php-driver.git
    #fi

    #run cd mongo-php-driver && \
    #run git submodule update --init

    #if [[ -n $(command -v "php${PHPv}") ]]; then
    #    run "/usr/bin/phpize${PHPv}" && \
    #    run ./configure --with-php-config="/usr/bin/php-config${PHPv}"
    #else
    #    run /usr/bin/phpize && \
    #    run ./configure
    #fi

    #run make all && \
    #run make install

    PHP_LIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)

    if [ -f "${PHP_LIB_DIR}/mongodb.so" ]; then
        success "MongoDB module sucessfully installed at ${PHP_LIB_DIR}/mongodb.so."
        run chmod 0644 "${PHP_LIB_DIR}/mongodb.so"
    fi

    #run cd "${CURRENT_DIR}" || return 1
}

##
# Install PHP Memcached extension.
##
function install_php_memcached() {
    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    # Install PHP memcached module.
#    echo "Installing PHP ${PHPv} memcached extension..."

#    if [[ "${DRYRUN}" != true ]]; then
#        run apt-get install -qq -y "php${PHPv}-memcache" "php${PHPv}-memcached"
#    else
#        info "PHP ${PHPv} Memcached extension installed in dry run mode."
#    fi

    echo "Optimizing PHP ${PHPv} memcached extension..."

    # Optimize PHP memcache extension.
    if [[ "${DRYRUN}" != true ]]; then
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

                success "PHP ${PHPv} Memcached extension enabled."
            fi
        else
            info "It seems that PHP ${PHPv} not yet installed. Please install it before!"
        fi
    else
        info "PHP ${PHPv} Memcached extension optimized in dry run mode."
    fi
}

##
# Install PHP Composer.
##
function install_php_composer() {
    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    # Checking if php composer already installed.
    if [[ -z $(command -v composer) ]]; then
        if [[ ${AUTO_INSTALL} == true ]]; then
            DO_INSTALL_COMPOSER="y"
        else
            while [[ "${DO_INSTALL_COMPOSER}" != "y" && "${DO_INSTALL_COMPOSER}" != "n" ]]; do
                read -rp "Do you want to install PHP Composer? [y/n]: " -i n -e DO_INSTALL_COMPOSER
            done
        fi

        if [[ ${DO_INSTALL_COMPOSER} == y* && ${INSTALL_PHP_COMPOSER} == true ]]; then
            echo "Installing PHP Composer..."

            local CURRENT_DIR && CURRENT_DIR=$(pwd)
            run cd "${BUILD_DIR}" || error "Cannot change directory to ${BUILD_DIR}."

            if [[ -n $(command -v "php${PHPv}") ]]; then
                PHP_BIN=$(command -v "php${PHPv}")
                EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
                run "${PHP_BIN}" -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
                ACTUAL_SIGNATURE="$(${PHP_BIN} -r "echo hash_file('sha384', 'composer-setup.php');")"

                if [[ "${EXPECTED_SIGNATURE}" == "${ACTUAL_SIGNATURE}" ]]; then
                    local LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}

                    run "${PHP_BIN}" composer-setup.php --filename=composer --install-dir=/usr/local/bin --quiet

                    # Fix chmod permission to executable.
                    if [[ -f /usr/local/bin/composer ]]; then
                        run chmod ugo+x /usr/local/bin/composer && \
                        run ln -sf /usr/local/bin/composer /usr/bin/composer
                        run bash -c "echo '[ -d \"\$HOME/.composer/vendor/bin\" ] && export PATH=\"\$PATH:\$HOME/.composer/vendor/bin\"' >> /home/${LEMPER_USERNAME}/.bashrc"
                        run bash -c "echo '[ -d \"\$HOME/.composer/vendor/bin\" ] && export PATH=\"\$PATH:\$HOME/.composer/vendor/bin\"' >> /home/${LEMPER_USERNAME}/.bash_profile"
                        run bash -c "echo '[ -d \"\$HOME/.composer/vendor/bin\" ] && export PATH=\"\$PATH:\$HOME/.composer/vendor/bin\"' >> /home/${LEMPER_USERNAME}/.profile"
                    fi
                else
                    error "Invalid PHP Composer installer signature."
                fi
            fi

            #run rm composer-setup.php
            run cd "${CURRENT_DIR}" || error "Cannot change directory to ${CURRENT_DIR}."
        fi

        if [[ -n $(command -v composer) ]]; then
            success "PHP Composer successfully installed."
        else
            error "Something went wrong with PHP Composer installation."
        fi
    fi
}

##
# Install ionCube Loader.
##
function install_ioncube_loader() {
    echo "Installing ionCube PHP loader..."

    # Delete old loaders file.
    if [ -d /usr/lib/php/loaders/ioncube ]; then
        echo "Remove old/existing ionCube PHP loader."
        run rm -fr /usr/lib/php/loaders/ioncube
    fi

    local CURRENT_DIR && CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}" || return 1

    echo "Downloading latest ionCube PHP loader..."

    IC_ARCH=${ARCH:-$(uname -p)}
    IC_ZIP_FILENAME="ioncube_loaders_linux_${IC_ARCH}.tar.gz"
    IC_ZIP_URL="https://raw.githubusercontent.com/joglomedia/php-loaders/main/${IC_ZIP_FILENAME}"

    if curl -sLI "${IC_ZIP_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run wget "${IC_ZIP_URL}" && \
        run tar -xzf "${IC_ZIP_FILENAME}" && \
        run mv -f ioncube /usr/lib/php/loaders/
    else
        error "Cannot download ionCube PHP loader."
    fi

    run cd "${CURRENT_DIR}" || return 1
}

##
# Enable ionCube Loader.
##
function enable_ioncube_loader() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    echo "Enable ionCube loader for PHP ${PHPv}."

    if [[ "${DRYRUN}" != true ]]; then
        if [[ -f "/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so" && -n $(command -v "php${PHPv}") ]]; then
            cat > "/etc/php/${PHPv}/mods-available/ioncube.ini" <<EOL
[ioncube]
zend_extension=/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so
EOL

            if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/ioncube.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini"
            fi
            if [ ! -f "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/ioncube.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini"
            fi
        else
            info "ionCube loader for PHP ${PHPv} not found."
        fi
    else
        info "ionCube loader for PHP ${PHPv} enabled in dry-run mode."
    fi
}

##
# Install SourceGuardian Loader.
##
function install_sourceguardian_loader() {
    echo "Installing SourceGuardian PHP loader..."

    # Delete old loaders file.
    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Remove old/existing loader."
        run rm -fr /usr/lib/php/loaders/sourceguardian
    fi

    if [ ! -d "${BUILD_DIR}/sourceguardian" ]; then
        run mkdir -p "${BUILD_DIR}/sourceguardian"
    fi

    local CURRENT_DIR && CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}/sourceguardian" || return 1

    echo "Downloading latest SourceGuardian PHP loader..."

    SG_ARCH=${ARCH:-$(uname -p)}
    SG_ZIP_FILENAME="sourceguardian_loaders.linux-${SG_ARCH}.tar.gz"
    SG_ZIP_URL="https://raw.githubusercontent.com/joglomedia/php-loaders/main/${SG_ZIP_FILENAME}"

    if curl -sLI "${SG_ZIP_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run wget "${SG_ZIP_URL}" && \
        run tar -xzf "${SG_ZIP_FILENAME}" && \
        run mv -f "${BUILD_DIR}/sourceguardian" /usr/lib/php/loaders/
    else
        error "Cannot download SourceGuardian PHP loader."
    fi

    run cd "${CURRENT_DIR}" || return 1
}

##
# Enable SourceGuardian Loader.
##
function enable_sourceguardian_loader() {
    # PHP version.
    local PHPv="${1}"
    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    echo "Enable SourceGuardian loader for PHP ${PHPv}."

    if [[ "${DRYRUN}" != true ]]; then
        if [[ -f "/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin" && -n $(command -v "php${PHPv}") ]]; then
            cat > "/etc/php/${PHPv}/mods-available/sourceguardian.ini" <<EOL
[sourceguardian]
zend_extension=/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin
EOL

            if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/sourceguardian.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini"
            fi

            if [ ! -f "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/sourceguardian.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini"
            fi
        else
            error "SourceGuardian loader for PHP ${PHPv} not found."
        fi
    else
        info "SourceGuardian for PHP ${PHPv} enabled in dry-run mode."
    fi
}

##
# Install PHP Loader.
##
function install_php_loader() {
    local PHPv="${1}"
    local SELECTED_PHP_LOADER="${2}"

    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.0"}
    fi

    if [[ -z "${SELECTED_PHP_LOADER}" ]]; then
        SELECTED_PHP_LOADER=${PHP_LOADER:-"ioncube"}
    fi

    # Install PHP loader.
    if [[ "${PHPv}" != "unsupported" && ! $(version_older_than "${PHPv}" "5.6") ]]; then
        if [[ "${AUTO_INSTALL}" == true ]]; then
            if [[ "${INSTALL_PHP_LOADER}" == true ]]; then
                DO_INSTALL_PHP_LOADER="y"
            else
                DO_INSTALL_PHP_LOADER="n"
            fi
        else
            while [[ "${DO_INSTALL_PHP_LOADER}" != "y" && "${DO_INSTALL_PHP_LOADER}" != "n" ]]; do
                read -rp "Do you want to install PHP Loader? [y/n]: " -i n -e DO_INSTALL_PHP_LOADER
            done
        fi

        if [[ ${DO_INSTALL_PHP_LOADER} == y* || ${DO_INSTALL_PHP_LOADER} == Y* ]]; then
            if [[ "${AUTO_INSTALL}" != true ]]; then
                echo ""
                echo "Available PHP Loaders:"
                echo "  1). ionCube Loader (latest stable)"
                echo "  2). SourceGuardian (latest stable)"
                echo "  3). All loaders (ionCube, SourceGuardian)"
                echo "--------------------------------------------"

                while [[ ${SELECTED_PHP_LOADER} != "1" && ${SELECTED_PHP_LOADER} != "2" && \
                        ${SELECTED_PHP_LOADER} != "3" && ${SELECTED_PHP_LOADER} != "ioncube" && \
                        ${SELECTED_PHP_LOADER} != "sg" && ${SELECTED_PHP_LOADER} != "ic" && \
                        ${SELECTED_PHP_LOADER} != "sourceguardian" && ${SELECTED_PHP_LOADER} != "all" ]]; do
                    read -rp "Select an option [1-3]: " -i "${PHP_LOADER}" -e SELECTED_PHP_LOADER
                done
            fi

            # Create PHP loaders directory.
            if [ ! -d /usr/lib/php/loaders ]; then
                run mkdir -p /usr/lib/php/loaders
            fi

            case ${SELECTED_PHP_LOADER} in
                1 | "ic" | "ioncube")
                    install_ioncube_loader
                    enable_ioncube_loader "${PHPv}"
                ;;
                2 | "sg" | "sourceguardian")
                    install_sourceguardian_loader
                    enable_sourceguardian_loader "${PHPv}"
                ;;
                "all")
                    install_ioncube_loader
                    enable_ioncube_loader "${PHPv}"

                    install_sourceguardian_loader
                    enable_sourceguardian_loader "${PHPv}"
                ;;
                *)
                    error "Your selected PHP loader '${SELECTED_PHP_LOADER}' is not supported yet."
                ;;
            esac
        else
            info "${SELECTED_PHP_LOADER} loader for PHP ${PHPv} installation skipped."
        fi
    fi
}

##
# Initialize PHP Installation.
##
function init_php_install() {
    local SELECTED_PHP_VERSIONS=()
    local OPT_PHP_VERSIONS=()
    local OPT_PHP_EXTENSIONS=()
    local OPT_PHP_LOADER=${PHP_LOADER:-"ioncube"}

    OPTS=$(getopt -o p:x:l: \
        -l php-version:,php-extensions:,php-loader: \
        -n "init_php_install" -- "$@")

    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            -p | --php-version)
                shift
                OPT_PHP_VERSIONS+=("${1}")
                shift
            ;;
            -x | --php-extensions)
                shift
                OPT_PHP_EXTENSIONS+=("${1}")
                shift
            ;;
            -l | --php-loader)
                shift
                OPT_PHP_LOADER="${1}"
                shift
            ;;
            --)
                shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    # Include versions from config file.
    read -r -a SELECTED_PHP_VERSIONS <<< "${PHP_VERSIONS}"

    if [[ "${#OPT_PHP_VERSIONS[@]}" -gt 0 ]]; then
        SELECTED_PHP_VERSIONS+=("${OPT_PHP_VERSIONS[@]}")
    else
        # Manually select PHP version in interactive mode.
        if [[ "${AUTO_INSTALL}" != true ]]; then
            echo "Which PHP version to be installed?"
            echo "Available PHP versions:"
            echo "  1). PHP 5.6 (EOL)"
            echo "  2). PHP 7.0 (EOL)"
            echo "  3). PHP 7.1 (EOL)"
            echo "  4). PHP 7.2 (EOL)"
            echo "  5). PHP 7.3 (EOL)"
            echo "  6). PHP 7.4 (EOL)"
            echo "  7). PHP 8.0 (SFO)"
            echo "  8). PHP 8.1 (Latest)"
            echo "  9). PHP 8.2 (Latest Stable)"
            echo "  10). All available versions"
            echo "--------------------------------------------"

            [[ -n "${DEFAULT_PHP_VERSION}" ]] && \
            info "Default version is: ${DEFAULT_PHP_VERSION}"

            while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" && ${SELECTED_PHP} != "3" && \
                    ${SELECTED_PHP} != "4" && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" && \
                    ${SELECTED_PHP} != "7" && ${SELECTED_PHP} != "8" && \
                    ${SELECTED_PHP} != "9" && ${SELECTED_PHP} != "10" && \
                    ${SELECTED_PHP} != "5.6" && ${SELECTED_PHP} != "7.0" && ${SELECTED_PHP} != "7.1" && \
                    ${SELECTED_PHP} != "7.2" && ${SELECTED_PHP} != "7.3" && ${SELECTED_PHP} != "7.4" && \
                    ${SELECTED_PHP} != "8.0" &&  ${SELECTED_PHP} != "8.1" && \
                    ${SELECTED_PHP} != "8.2" && ${SELECTED_PHP} != "all" ]]; do
                read -rp "Enter a PHP version from an option above [1-9]: " -i "${DEFAULT_PHP_VERSION}" -e SELECTED_PHP
            done

            case "${SELECTED_PHP}" in
                1 | "5.6")
                    SELECTED_PHP_VERSIONS+=("5.6")
                ;;
                2 | "7.0")
                    SELECTED_PHP_VERSIONS+=("7.0")
                ;;
                3 | "7.1")
                    SELECTED_PHP_VERSIONS+=("7.1")
                ;;
                4 | "7.2")
                    SELECTED_PHP_VERSIONS+=("7.2")
                ;;
                5 | "7.3")
                    SELECTED_PHP_VERSIONS+=("7.3")
                ;;
                6 | "7.4")
                    SELECTED_PHP_VERSIONS+=("7.4")
                ;;
                7 | "8.0")
                    SELECTED_PHP_VERSIONS+=("8.0")
                ;;
                8 | "8.1")
                    SELECTED_PHP_VERSIONS+=("8.1")
                ;;
                9 | "8.2")
                    SELECTED_PHP_VERSIONS+=("8.2")
                ;;
                10 | "all")
                    # Select all PHP versions (except EOL & Beta).
                    SELECTED_PHP_VERSIONS=("5.6" "7.0" "7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2")
                ;;
                *)
                    error "Your selected PHP version ${SELECTED_PHP} is not supported yet."
                ;;
            esac
        fi
    fi

    # Sort PHP versions.
    #shellcheck disable=SC2207
    SELECTED_PHP_VERSIONS=($(printf "%s\n" "${SELECTED_PHP_VERSIONS[@]}" | sort -u | tr '\n' ' '))

    # Add Ondrej's PHP repository.
    add_php_repo

    # Install all selected PHP versions and extensions.
    for PHPV in "${SELECTED_PHP_VERSIONS[@]}"; do
        IS_PKG_AVAIL=$(apt-cache search "php${PHPV}" | grep -c "${PHPV}")

        if [[ "${IS_PKG_AVAIL}" -gt 0 ]]; then
            # Install PHP + default extensions.
            install_php "${PHPV}"
            install_php_loader "${PHPV}" "${OPT_PHP_LOADER}"
            restart_php_fpm "${PHPV}"
        else
            error "PHP ${PHPV} package is not available for your operating system."
        fi
    done

    # Install default PHP version used by LEMPer.
    if [[ -z $(command -v "php${DEFAULT_PHP_VERSION}") ]]; then
        info "LEMPer requires PHP ${DEFAULT_PHP_VERSION} as default to run its administration tool."
        echo "PHP ${DEFAULT_PHP_VERSION} now being installed..."

        install_php "${DEFAULT_PHP_VERSION}"
        install_php_loader "${DEFAULT_PHP_VERSION}" "${OPT_PHP_LOADER}"
        restart_php_fpm "${DEFAULT_PHP_VERSION}"
    fi

    # Install PHP composer.
    install_php_composer "${DEFAULT_PHP_VERSION}"
}

echo "[PHP & Extensions Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v php5.6) && \
    -n $(command -v php7.0) && \
    -n $(command -v php7.1) && \
    -n $(command -v php7.2) && \
    -n $(command -v php7.3) && \
    -n $(command -v php7.4) && \
    -n $(command -v php8.0) && \
    -n $(command -v php8.1) && "${FORCE_INSTALL}" != true ]]; then
    info "All available PHP version already exists, installation skipped."
else
    init_php_install "$@"
fi
