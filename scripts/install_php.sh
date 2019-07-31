#!/usr/bin/env bash

# PHP Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
if [ "$(id -u)" -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

# Install PHP.
function install_php() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        # Default PHP is 7.3 (latest stable recommendation).
        PHPv="7.3"
    fi

    # Checking if php already installed.
    if [[ -n $(command -v "php${PHPv}") ]]; then
        warning "PHP${PHPv} & FPM package already installed..."
    else
        echo "Installing PHP${PHPv} & FPM..."

        run apt-get install -y php${PHPv} php${PHPv}-bcmath php${PHPv}-cli php${PHPv}-common \
            php${PHPv}-curl php${PHPv}-dev php${PHPv}-fpm php${PHPv}-mysql php${PHPv}-gd \
            php${PHPv}-gmp php${PHPv}-imap php${PHPv}-intl php${PHPv}-json php${PHPv}-ldap \
            php${PHPv}-mbstring php${PHPv}-opcache php${PHPv}-pspell php${PHPv}-readline \
            php${PHPv}-recode php${PHPv}-snmp php${PHPv}-soap php${PHPv}-sqlite3 \
            php${PHPv}-tidy php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-zip \
            php-geoip php-pear pkg-php-tools spawn-fcgi fcgiwrap geoip-database >> lemper.log 2>&1

        if [[ -n $(command -v php${PHPv}) ]]; then
            status "PHP${PHPv} & FPM package installed."
        fi

        # Install php mcrypt?
        echo ""
        while [[ $INSTALL_PHPMCRYPT != "y" && $INSTALL_PHPMCRYPT != "n" ]]; do
            read -p "Do you want to install PHP Mcrypt for encryption/decryption? [y/n]: " -e INSTALL_PHPMCRYPT
        done
        echo ""

        if [[ "$INSTALL_PHPMCRYPT" == Y* || "$INSTALL_PHPMCRYPT" == y* ]]; then
            if [ "${PHPv//.}" -lt "72" ]; then
                run apt-get install -y php${PHPv}-mcrypt
            elif [ "${PHPv}" == "7.2" ]; then
                run apt-get -y install gcc make autoconf libc-dev pkg-config \
                    libmcrypt-dev libreadline-dev && \
                    pecl install mcrypt-1.0.1 >> lemper.log 2>&1

                # Enable Mcrypt module.
                echo "Update PHP ini file with Mcrypt module..."
                run bash -c "echo extension=mcrypt.so > /etc/php/${PHPv}/mods-available/mcrypt.ini"

                if [ ! -f /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini ]; then
                    run ln -s /etc/php/${PHPv}/mods-available/mcrypt.ini /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini
                fi

                if [ ! -f /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini ]; then
                    run ln -s /etc/php/${PHPv}/mods-available/mcrypt.ini /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini
                fi
            else
                run apt-get install -y dh-php >> lemper.log 2>&1

                # use libsodium instead
                warning "Mcrypt is deprecated for PHP version ${PHPv} or greater, you should using Libsodium or OpenSSL."
            fi
        fi
    fi
}

# Remove PHP
function remove_php() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        # Default PHP is 7.3 (latest stable recommendation).
        PHPv="7.3"
    fi

    echo "Uninstalling PHP ${PHPv}..."

    if [[ -n $(command -v php-fpm${PHPv}) ]]; then
        run apt-get --purge remove -y php${PHPv} php${PHPv}-bcmath php${PHPv}-cli php${PHPv}-common \
            php${PHPv}-curl php${PHPv}-dev php${PHPv}-fpm php${PHPv}-mysql php${PHPv}-gd \
            php${PHPv}-gmp php${PHPv}-imap php${PHPv}-intl php${PHPv}-json php${PHPv}-ldap \
            php${PHPv}-mbstring php${PHPv}-opcache php${PHPv}-pspell php${PHPv}-readline \
            php${PHPv}-recode php${PHPv}-snmp php${PHPv}-soap php${PHPv}-sqlite3 \
            php${PHPv}-tidy php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-zip \
            php-geoip php-pear pkg-php-tools spawn-fcgi fcgiwrap geoip-database >> lemper.log 2>&1

        isMcrypt=$(/usr/bin/php${PHPv} -m | grep mcrypt)
        if [[ "_$isMcrypt" == "_mcrypt" ]]; then
            if [ "${PHPv//.}" -lt "72" ]; then
                run apt-get --purge remove -y php${PHPv}-mcrypt >> lemper.log 2>&1
            elif [ "${PHPv}" == "7.2" ]; then
                # uninstall
                run pecl uninstall mcrypt-1.0.1 >> lemper.log 2>&1

                # remove module
                run rm /etc/php/${PHPv}/mods-available/mcrypt.ini

                if [ -f /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini ]; then
                    run rm /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini
                fi

                if [ -f /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini ]; then
                    run rm /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini
                fi
            else
                run apt-get --purge remove -y dh-php >> lemper.log 2>&1

                # use libsodium instead
                warning "If you're installing Libsodium extension, then remove it separately."
            fi
        fi

        status -e "PHP ${PHPv} installation has been removed."
    else
        warning "PHP ${PHPv} installation couldn't be found."
    fi
}

# Install ionCube Loader
function install_ic() {
    echo "Installing IonCube PHP loader..."

    ARCH=$(uname -p)
    if [[ "${ARCH}" == "x86_64" ]]; then
        run wget -q "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86-64.tar.gz
        run rm -f ioncube_loaders_lin_x86-64.tar.gz
    else
        run wget -q "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86.tar.gz
        run rm -f ioncube_loaders_lin_x86.tar.gz
    fi

    # Delete old loaders file
    if [ -d /usr/lib/php/loaders/ioncube ]; then
        echo "Removing old/existing IonCube PHP loader..."
        run rm -fr /usr/lib/php/loaders/ioncube
    fi

    echo "Installing latest IonCube PHP loader..."
    run mv -f ioncube /usr/lib/php/loaders/
}

# Enable ionCube Loader
function enable_ic() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Enabling IonCube PHP ${PHPv} loader"

if [ -f /usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so ]; then
    cat > /etc/php/${PHPv}/mods-available/ioncube.ini <<EOL
[ioncube]
zend_extension=/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so
EOL

    if [ ! -f /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini ]; then
        run ln -s /etc/php/${PHPv}/mods-available/ioncube.ini /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini
    fi

    if [ ! -f /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini ]; then
        run ln -s /etc/php/${PHPv}/mods-available/ioncube.ini /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini
    fi
    else
        warning "Sorry, no IonCube loader found for PHP ${PHPv}"
    fi
}

# Disable ionCube Loader
function disable_ic() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Disabling IonCube PHP ${PHPv} loader"

    run unlink /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini
    run unlink /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini
}

# Remove ionCube Loader
function remove_ic() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Uninstalling IonCube PHP ${PHPv} loader..."

    if [[ -f /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini || -f /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini ]]; then
        disable_ic ${PHPv}
    fi

    if [ -d /usr/lib/php/loaders/ioncube ]; then
        echo "Removing IonCube PHP ${PHPv} loader installation"
        run rm -fr /usr/lib/php/loaders/ioncube
        removed="has been"
    else
        echo "IonCube PHP ${PHPv} loader installation couldn't be found"
        removed="may be"
    fi

    status "IonCube PHP ${PHPv} loader ${removed} removed"
}

# Install SourceGuardian
function install_sg() {
    echo "Installing SourceGuardian PHP loader..."

    if [ ! -d sourceguardian ]; then
        run mkdir sourceguardian
    fi

    run cd sourceguardian

    ARCH=$(uname -p)
    if [[ "${ARCH}" == "x86_64" ]]; then
        run wget -q "http://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz"
        run tar -xzf loaders.linux-x86_64.tar.gz
        run rm -f loaders.linux-x86_64.tar.gz
    else
        run wget -q "http://www.sourceguardian.com/loaders/download/loaders.linux-x86.tar.gz"
        run tar -xzf loaders.linux-x86.tar.gz
        run rm -f loaders.linux-x86.tar.gz
    fi

    run cd ../

    # Delete old loaders file
    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Removing old/existing loaders..."
        run rm -fr /usr/lib/php/loaders/sourceguardian
    fi

    echo "Installing latest SourceGuardian PHP loaders..."
    run mv -f sourceguardian /usr/lib/php/loaders/
}

# Enable SourceGuardian
function enable_sg() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Enabling SourceGuardian PHP ${PHPv} loader..."

if [ -f /usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin ]; then
    cat > /etc/php/${PHPv}/mods-available/sourceguardian.ini <<EOL
[sourceguardian]
zend_extension=/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin
EOL

    if [ ! -f /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini ]; then
        run ln -s /etc/php/${PHPv}/mods-available/sourceguardian.ini /etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini
    fi

    if [ ! -f /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini ]; then
        run ln -s /etc/php/${PHPv}/mods-available/sourceguardian.ini /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini
    fi
else
    warning "Sorry, no SourceGuardian loader found for PHP ${PHPv}"
fi
}

# Disable SourceGuardian Loader
function disable_sg() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Disabling SourceGuardian PHP ${PHPv} loader"

    run unlink /etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini
    run unlink /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini
}

# Remove SourceGuardian Loader
function remove_sg() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Uninstalling SourceGuardian PHP ${PHPv} loader..."

    if [[ -f /etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini || -f /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini ]]; then
        disable_sg ${PHPv}
    fi

    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Removing SourceGuardian PHP ${PHPv} loader installation"
        run rm -fr /usr/lib/php/loaders/sourceguardian
        removed='has been'
    else
        echo "SourceGuardian PHP ${PHPv} loader installation couldn't be found"
        removed='may be'
    fi

    status "SourceGuardian PHP ${PHPv} loader ${removed} removed"
}

# PHP Setting + Optimization
function optimize_php() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Optimizing PHP${PHPv} & FPM configuration..."

    if [ ! -d /etc/php/${PHPv}/fpm ]; then
        run mkdir /etc/php/${PHPv}/fpm
    fi

    # Copy the optimized-version of php.ini
    if [ -f etc/php/${PHPv}/fpm/php.ini ]; then
        run mv /etc/php/${PHPv}/fpm/php.ini /etc/php/${PHPv}/fpm/php.ini.old
        run cp -f etc/php/${PHPv}/fpm/php.ini /etc/php/${PHPv}/fpm/
    else
        cat >> /etc/php/${PHPv}/fpm/php.ini <<EOL

[opcache]
opcache.enable=1;
opcache.enable_cli=0;
opcache.memory_consumption=128 # MB, adjust to your needs
opcache.interned_strings_buffer=8 # Adjust to your needs
opcache.max_accelerated_files=10000 # Adjust to your needs
opcache.max_wasted_percentage=5 # Adjust to your needs
opcache.validate_timestamps=1
opcache.revalidate_freq=1
opcache.save_comments=1
EOL
    fi

    # Copy the optimized-version of php-fpm config file
    if [ -f etc/php/${PHPv}/fpm/php-fpm.conf ]; then
        run mv /etc/php/${PHPv}/fpm/php-fpm.conf /etc/php/${PHPv}/fpm/php-fpm.conf.old
        run cp -f etc/php/${PHPv}/fpm/php-fpm.conf /etc/php/${PHPv}/fpm/
    else
        cat >> /etc/php/${PHPv}/fpm/php.ini <<EOL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Custom Optimization by LEMPer ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Adjust to meet your needs.
emergency_restart_threshold 10
emergency_restart_interval 1m
process_control_timeout 10s
EOL
    fi

    if [ ! -d /etc/php/${PHPv}/fpm/pool.d ]; then
        run mkdir /etc/php/${PHPv}/fpm/pool.d
    fi

    # Copy the optimized-version of php fpm default pool
    if [ -f etc/php/${PHPv}/fpm/pool.d/www.conf ]; then
        run mv /etc/php/${PHPv}/fpm/pool.d/www.conf /etc/php/${PHPv}/fpm/pool.d/www.conf.old
        run cp -f etc/php/${PHPv}/fpm/pool.d/www.conf /etc/php/${PHPv}/fpm/pool.d/
    fi

    # Copy the optimized-version of php fpm lemper pool
    if [ -f etc/php/${PHPv}/fpm/pool.d/lemper.conf ]; then
        run mv /etc/php/${PHPv}/fpm/pool.d/lemper.conf /etc/php/${PHPv}/fpm/pool.d/lemper.conf.old
        run cp -f etc/php/${PHPv}/fpm/pool.d/lemper.conf /etc/php/${PHPv}/fpm/pool.d/
    else
        cat >> /etc/php/${PHPv}/fpm/pool.d/lemper.conf <<EOL
[lemper]
user = lemper
group = lemper

listen = /run/php/php7.3-fpm.$pool.sock
listen.owner = lemper
listen.group = lemper
listen.mode = 0666
;listen.allowed_clients = 127.1.0.1

; Custom PHP-FPM optimization here
; adjust to meet your needs.
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.process_idle_timeout = 30s
pm.max_requests = 500

pm.status_path = /status
ping.path = /ping

request_slowlog_timeout = 6s
slowlog = /var/log/php7.3-fpm_slow.$pool.log

chdir = /

security.limit_extensions = .php .php3 .php4 .php5 .php${PHPv//./}

;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f you@yourmail.com
php_flag[display_errors] = on
php_admin_value[error_log] = /var/log/php7.3-fpm.$pool.log
php_admin_flag[log_errors] = on
;php_admin_value[memory_limit] = 32M
EOL
    fi

    # Fix cgi.fix_pathinfo (for PHP older than 5.3)
    #sed -i "s/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${PHPv}/fpm/php.ini

    # Add custom php extension (ex .php70, .php71)
    PHPExt=".php${PHPv//.}"
    run sed -i "s/;\(security\.limit_extensions\s*=\s*\).*$/\1\.php\ $PHPExt/" \
        "/etc/php/${PHPv}/fpm/pool.d/www.conf"

    # Enable FPM ping service
    run sed -i "/^;ping.path\ =.*/a ping.path\ =\ \/ping" "/etc/php/${PHPv}/fpm/pool.d/www.conf"

    # Enable FPM status
    run sed -i "/^;pm.status_path\ =.*/a pm.status_path\ =\ \/status" \
        "/etc/php/${PHPv}/fpm/pool.d/www.conf"

    # Restart PHP-fpm server
    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
        run service "php${PHPv}-fpm" reload
        status "PHP${PHPv}-FPM restarted successfully."
    elif [[ -n $(command -v "php${PHPv}") ]]; then
        run service "php${PHPv}-fpm" start

        if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
            status "PHP${PHPv}-FPM started successfully."
        else
            warning "Something wrong with PHP installation."
        fi
    fi
}

#
# Main Function
# Start PHP Installation
#
function init_php_install() {
    # Menu Install PHP, fpm, and modules
    echo ""
    echo "Welcome to PHP installation script"
    echo ""
    echo "Which version of PHP to install?"
    echo "Supported PHP version:"
    echo "  1). PHP 5.6 (old stable)"
    echo "  2). PHP 7.0 (stable)"
    echo "  3). PHP 7.1 (stable)"
    echo "  4). PHP 7.2 (stable)"
    echo "  5). PHP 7.3 (latest stable)"
    echo "  6). All available versions"
    echo "---------------------------------"

    while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" \
            && ${SELECTED_PHP} != "3" && ${SELECTED_PHP} != "4" \
            && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" ]]; do
        read -rp "Select an option [1-6]: " -i 5 -e SELECTED_PHP
    done

    echo ""

    case ${SELECTED_PHP} in
        1)
            PHP_VER="5.6"
            install_php ${PHP_VER}
        ;;
        2)
            PHP_VER="7.0"
            install_php ${PHP_VER}
        ;;
        3)
            PHP_VER="7.1"
            install_php ${PHP_VER}
        ;;
        4)
            PHP_VER="7.2"
            install_php ${PHP_VER}
        ;;
        5)
            PHP_VER="7.3"
            install_php ${PHP_VER}
        ;;
        *)
            PHP_VER="all"
            install_php "5.6"
            install_php "7.0"
            install_php "7.1"
            install_php "7.2"
            install_php "7.3"
        ;;
    esac

    # Install default PHP version used by LEMPer
    if [[ ! -n $(command -v php7.3) ]]; then
        warning -e "\nLEMPer requires PHP 7.3 as default to run its administration tools."
        echo "PHP 7.3 now being installed..."
        install_php "7.3"
    fi

    # Menu Install PHP loader
    echo ""
    while [[ ${INSTALL_PHPLOADER} != "y" && ${INSTALL_PHPLOADER} != "n" ]]; do
        read -rp "Do you want to install PHP Loaders? [y/n]: " -e INSTALL_PHPLOADER
    done

    if [[ "${INSTALL_PHPLOADER}" == Y* || "${INSTALL_PHPLOADER}" == y* ]]; then
        echo ""
        echo "Available PHP Loaders:"
        echo "  1). IonCube Loader (latest stable)"
        echo "  2). SourceGuardian (latest stable)"
        echo "  3). All loaders (IonCube, SourceGuardian)"
        echo "--------------------------------------------"

        while [[ ${SELECTED_PHPLOADER} != "1" && ${SELECTED_PHPLOADER} != "2" \
                && ${SELECTED_PHPLOADER} != "3" ]]; do
            read -rp "Select an option [1-3]: " SELECTED_PHPLOADER
        done

        echo ""

        # Create loaders directory
        if [ ! -d /usr/lib/php/loaders ]; then
            run mkdir /usr/lib/php/loaders
        fi

        case ${SELECTED_PHPLOADER} in
            1)
                install_ic

                if [ "${PHP_VER}" != "all" ]; then
                    enable_ic ${PHP_VER}

                    # Required for LEMPer default PHP
                    if [ "${PHP_VER}" != "7.3" ]; then
                        enable_ic "7.3"
                    fi
                else
                    enable_ic "5.6"
                    enable_ic "7.0"
                    enable_ic "7.1"
                    enable_ic "7.2"
                    enable_ic "7.3"
                fi
            ;;
            2)
                install_sg

                if [ "${PHP_VER}" != "all" ]; then
                    enable_sg ${PHP_VER}
                else
                    enable_sg "5.6"
                    enable_sg "7.0"
                    enable_sg "7.1"
                    enable_sg "7.2"
                    enable_sg "7.3"
                fi
            ;;
            *)
                install_ic
                install_sg

                if [ "${PHP_VER}" != "all" ]; then
                    enable_ic ${PHP_VER}

                    # Required for LEMPer default PHP
                    if [ "${PHP_VER}" != "7.3" ]; then
                        enable_ic "7.3"
                    fi

                    enable_sg ${PHP_VER}
                else
                    enable_ic "5.6"
                    enable_ic "7.0"
                    enable_ic "7.1"
                    enable_ic "7.2"
                    enable_ic "7.3"

                    enable_sg "5.6"
                    enable_sg "7.0"
                    enable_sg "7.1"
                    enable_sg "7.2"
                    enable_sg "7.3"
                fi
            ;;
        esac
    fi

    # Menu Optimizing PHP
    if [ "${PHP_VER}" != "all" ]; then
        optimize_php ${PHP_VER}

        # Required for LEMPer default PHP
        if [ "${PHP_VER}" != "7.3" ]; then
            optimize_php "7.3"
        fi
    else
        optimize_php "5.6"
        optimize_php "7.0"
        optimize_php "7.1"
        optimize_php "7.2"
        optimize_php "7.3"
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v php5.6) && -n $(command -v php7.0) && -n $(command -v php7.1) && -n $(command -v php7.2) && -n $(command -v php7.3) ]]; then
    warning -e "\nAll available PHP version already exists. Installation skipped..."
else
    init_php_install "$@"
fi
