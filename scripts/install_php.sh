#!/usr/bin/env bash

# PHP installer
# Min requirement   : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 17/09/2018
# Author            : ESLabs.id (eslabs.id@gmail.com)

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

# Install PHP
function install_php() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    # Checking if php already installed
    if [[ -n $(which php${PHPv}) ]]; then
        warning -e "\nPHP $PHPv package already installed..."
    else
        echo "Installing PHP $PHPv..."

        run apt-get install -y php${PHPv} php${PHPv}-common php${PHPv}-fpm php${PHPv}-cli php${PHPv}-mysql \
            php${PHPv}-bcmath php${PHPv}-curl php${PHPv}-gd php${PHPv}-intl php${PHPv}-json php${PHPv}-mbstring \
            php${PHPv}-imap php${PHPv}-pspell php${PHPv}-recode php${PHPv}-snmp php${PHPv}-sqlite3 php${PHPv}-tidy \
            php${PHPv}-readline php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-gmp php${PHPv}-opcache \
            php${PHPv}-soap php${PHPv}-zip php${PHPv}-ldap php${PHPv}-dev php-geoip php-pear pkg-php-tools php-phalcon

        # Install php mcrypt?
        echo -en "\nDo you want to install PHP Mcrypt for encryption/decryption? [Y/n]: "
        read PhpMcryptInstall

        if [[ "$PhpMcryptInstall" == "Y" || "$PhpMcryptInstall" == "y" || "$PhpMcryptInstall" == "yes" ]]; then
            if [ "${PHPv//.}" -lt "72" ]; then
                run apt-get install -y php${PHPv}-mcrypt
            elif [ "$PHPv" == "7.2" ]; then
                run apt-get -y install gcc make autoconf libc-dev pkg-config
                run apt-get -y install libmcrypt-dev libreadline-dev
                run pecl install mcrypt-1.0.1

                # enable module
                echo -e "\nCreating config file with new version"
                bash -c "echo extension=mcrypt.so > /etc/php/${PHPv}/mods-available/mcrypt.ini"

                if [ ! -f /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini ]; then
                    run ln -s /etc/php/${PHPv}/mods-available/mcrypt.ini /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini
                fi

                if [ ! -f /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini ]; then
                    run ln -s /etc/php/${PHPv}/mods-available/mcrypt.ini /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini
                fi
            else
                run apt-get install -y dh-php

                # use libsodium instead
                warning -e "\nPHP Mcrypt is deprecated for PHP version $PHPv or greater, you should using Libsodium or OpenSSL."
            fi
        fi
    fi
}

# Remove PHP
function remove_php() {
    if [[ -n $1 ]]; then
        PHPv="$1"
    else
        PHPv="7.3" # default php install 7.3 (latest stable recommendation)
    fi

    echo "Uninstalling PHP $PHPv..."

    if [[ -n $(which php-fpm${PHPv}) ]]; then
        run apt-get remove -y php${PHPv} php${PHPv}-common php${PHPv}-fpm php${PHPv}-cli php${PHPv}-mysql \
            php${PHPv}-bcmath php${PHPv}-curl php${PHPv}-gd php${PHPv}-intl php${PHPv}-json php${PHPv}-mbstring \
            php${PHPv}-imap php${PHPv}-pspell php${PHPv}-recode php${PHPv}-snmp php${PHPv}-sqlite3 php${PHPv}-tidy \
            php${PHPv}-readline php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-gmp php${PHPv}-opcache \
            php${PHPv}-soap php${PHPv}-zip php${PHPv}-ldap php${PHPv}-dev php-geoip php-pear pkg-php-tools php-phalcon

        isMcrypt=$(/usr/bin/php${PHPv} -m | grep mcrypt)
        if [[ "_$isMcrypt" == "_mcrypt" ]]; then
            if [ "${PHPv//.}" -lt "72" ]; then
                run apt-get remove -y php${PHPv}-mcrypt
            elif [ "$PHPv" == "7.2" ]; then
                # uninstall
                run pecl uninstall mcrypt-1.0.1

                # remove module
                run rm /etc/php/${PHPv}/mods-available/mcrypt.ini

                if [ -f /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini ]; then
                    run rm /etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini
                fi

                if [ -f /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini ]; then
                    run rm /etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini
                fi
            else
                run apt-get remove -y dh-php

                # use libsodium instead
                warning -e "\nIf you're installing Libsodium extension, then remove it separately."
            fi
        fi

        status -e "\nPHP $PHPv installation has been removed."
    else
        warning "PHP $PHPv installation couldn't be found."
    fi
}

# Install ionCube Loader
function install_ic() {
    echo "Installing IonCube PHP loader..."

    arch=$(uname -p)
    if [[ "$arch" == "x86_64" ]]; then
        run wget "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86-64.tar.gz
        run rm -f ioncube_loaders_lin_x86-64.tar.gz
    else
        run wget "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86.tar.gz"
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
        disable_ic $PHPv
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

    arch=$(uname -p)
    if [[ "$arch" == "x86_64" ]]; then
        run wget "http://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz"
        run tar -xzf loaders.linux-x86_64.tar.gz
        run rm -f loaders.linux-x86_64.tar.gz
    else
        run wget "http://www.sourceguardian.com/loaders/download/loaders.linux-x86.tar.gz"
        run tar -xzf loaders.linux-x86.tar.gz
        run rm -f loaders.linux-x86.tar.gz
    fi

    run cd ../

    # Delete old loaders file
    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Removing old/existing loaders..."
        run rm -fr /usr/lib/php/loaders/sourceguardian
    fi

    echo "Installing latest loaders..."
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

    if [ ! -f /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini]; then
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
        disable_sg $PHPv
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

    echo "Optimizing PHP ${PHPv} configuration..."

    if [ ! -d /etc/php/${PHPv}/fpm ]; then
        run mkdir /etc/php/${PHPv}/fpm
    fi

    # Copy custom php.ini
    if [ -f php/${PHPv}/fpm/php.ini ]; then
        run mv /etc/php/${PHPv}/fpm/php.ini /etc/php/${PHPv}/fpm/php.ini~
        run cp php/${PHPv}/fpm/php.ini /etc/php/${PHPv}/fpm/
    fi

    # Copy the optimized-version of php fpm config file
    if [ -f php/${PHPv}/fpm/php-fpm.conf ]; then
        run mv /etc/php/${PHPv}/fpm/php-fpm.conf /etc/php/${PHPv}/fpm/php-fpm.conf~
        run cp php/${PHPv}/fpm/php-fpm.conf /etc/php/${PHPv}/fpm/
    fi

    if [ ! -d /etc/php/${PHPv}/fpm/pool.d ]; then
        run mkdir /etc/php/${PHPv}/fpm/pool.d
    fi

    # Copy the optimized-version of php fpm default pool
    if [ -f php/${PHPv}/fpm/pool.d/www.conf ]; then
        run mv /etc/php/${PHPv}/fpm/pool.d/www.conf /etc/php/${PHPv}/fpm/pool.d/www.conf~
        run cp php/${PHPv}/fpm/pool.d/www.conf /etc/php/${PHPv}/fpm/pool.d/
    fi

    # Fix cgi.fix_pathinfo
    sed -i "s/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${PHPv}/fpm/php.ini

    # Add custom php extension (ex .php70, .php71)
    PHPExt=".php${PHPv//.}"
    sed -i "s/;\(security\.limit_extensions\s*=\s*\).*$/\1\.php\ $PHPExt/" /etc/php/${PHPv}/fpm/pool.d/www.conf

    # Restart PHP-fpm server
    if [[ $(ps -ef | grep -v grep | grep php-fpm | wc -l) > 0 ]]; then
        run service php${PHPv}-fpm restart
        status "${PHPv} & PHP${PHPv}-FPM restarted successfully."
    elif [[ -n $(which php${PHPv}) ]]; then
        run service php${PHPv}-fpm start

        if [[ $(ps -ef | grep -v grep | grep php-fpm | wc -l) > 0 ]]; then
            status "${PHPv} & PHP${PHPv}-FPM started successfully."
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
    #header_msg
    echo -e "\nWelcome to PHP installation script"

    echo -e "\nWhich version of PHP you want to install? (default is all)
    Supported PHP version:
    1). PHP 5.6 (old stable)
    2). PHP 7.0 (stable)
    3). PHP 7.1 (stable)
    4). PHP 7.2 (stable)
    5). PHP 7.3 (latest stable)
    6). All versions (PHP 5.6, 7.0, 7.1, 7.2, 7.3)
    -------------------------------------"
    echo -n "Select your option [1-6]: "
    read PhpVersionInstall

    case $PhpVersionInstall in
        1)
            PHPver="5.6"
            install_php $PHPver
        ;;
        2)
            PHPver="7.0"
            install_php $PHPver
        ;;
        3)
            PHPver="7.1"
            install_php $PHPver
        ;;
        4)
            PHPver="7.2"
            install_php $PHPver
        ;;
        5)
            PHPver="7.3"
            install_php $PHPver
        ;;
        *)
            PHPver="all"
            install_php "5.6"
            install_php "7.0"
            install_php "7.1"
            install_php "7.2"
            install_php "7.3"
        ;;
    esac

    # Install default PHP version used by LEMPer
    if [[ ! -n $(which php7.3) ]]; then
        warning -e "\nLEMPer requires PHP 7.3 as default to run its administration tools."
        echo "PHP 7.3 now being installed..."
        install_php "7.3"
    fi

    # Menu Install PHP loader
    #header_msg
    echo -en "\nDo you want to install PHP loader? [Y/n]: "
    read PhpLoaderInstall

    if [[ "$PhpLoaderInstall" == "Y" || "$PhpLoaderInstall" == "y" || "$PhpLoaderInstall" == "yes" ]]; then
        echo -e "\nAvailable PHP loaders:
        1). IonCube Loader (latest stable)
        2). SourceGuardian (latest stable)
        3). All loaders (IonCube, SourceGuardian)
        ------------------------------------------"
        echo -en "Select your loader [1-3]: "
        read PhpLoaderOpt

        if [ ! -d /usr/lib/php/loaders ]; then
            run mkdir /usr/lib/php/loaders
        fi

        case $PhpLoaderOpt in
            1)
                install_ic

                if [ "$PHPver" != "all" ]; then
                    enable_ic $PHPver

                    # Required for LEMPer default PHP
                    if [ "$PHPver" != "7.3" ]; then
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

                if [ "$PHPver" != "all" ]; then
                    enable_sg $PHPver
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

                if [ "$PHPver" != "all" ]; then
                    enable_ic $PHPver

                    # Required for LEMPer default PHP
                    if [ "$PHPver" != "7.3" ]; then
                        enable_ic "7.3"
                    fi

                    enable_sg $PHPver
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
    if [ "$PHPver" != "all" ]; then
        optimize_php $PHPver

        # Required for LEMPer default PHP
        if [ "$PHPver" != "7.3" ]; then
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
if [[ -n $(which php) && -n $(which php7.0) && -n $(which php7.1) && -n $(which php7.2) && -n $(which php7.3) ]]; then
    warning "All available PHP version has already been installed. Installation skipped..."
else
    init_php_install "$@"
fi
