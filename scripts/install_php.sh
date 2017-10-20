#!/usr/bin/env bash

# PHP installer
# Min requirement   : GNU/Linux Ubuntu 14.04
# Last Build        : 13/11/2015
# Author            : MasEDI.Net (hi@masedi.net)

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root..."
    exit 1
fi

# Install PHP
function install_php {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Installing PHP $PHPv..."

    apt-get install -y php${PHPv} php${PHPv}-common php${PHPv}-fpm php${PHPv}-cli php${PHPv}-mysql php${PHPv}-curl php${PHPv}-gd php${PHPv}-intl php${PHPv}-json php${PHPv}-mcrypt php${PHPv}-mbstring php${PHPv}-imap php${PHPv}-pspell php${PHPv}-recode php${PHPv}-snmp php${PHPv}-sqlite3 php${PHPv}-tidy php${PHPv}-readline php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-gmp php${PHPv}-opcache php${PHPv}-soap php${PHPv}-zip php${PHPv}-dev php-geoip php-pear pkg-php-tools php-phalcon
}

# Remove PHP
function remove_php {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Uninstalling PHP $PHPv..."

    if [ -n $(which php-fpm${PHPver}) ]; then
        apt-get remove -y php${PHPv} php${PHPv}-common php${PHPv}-fpm php${PHPv}-cli php${PHPv}-mysql php${PHPv}-curl php${PHPv}-gd php${PHPv}-intl php${PHPv}-json php${PHPv}-mcrypt php${PHPv}-mbstring php${PHPv}-imap php${PHPv}-pspell php${PHPv}-recode php${PHPv}-snmp php${PHPv}-sqlite3 php${PHPv}-tidy php${PHPv}-readline php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-gmp php${PHPv}-opcache php${PHPv}-soap php${PHPv}-zip php${PHPv}-dev php-geoip php-pear pkg-php-tools php-phalcon
        echo "PHP $PHPv installation has been removed"
    else
        echo "PHP $PHPv installation couldn't be found"
    fi
}

# Install ionCube Loader
function install_ic {
    echo "Installing IonCube PHP loader..."

    arch=$(uname -p)
    if [[ "$arch" == "x86_64" ]]; then
        wget "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
        tar xzf ioncube_loaders_lin_x86-64.tar.gz
        rm -f ioncube_loaders_lin_x86-64.tar.gz
    else
        wget "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86.tar.gz"
        tar xzf ioncube_loaders_lin_x86.tar.gz
        rm -f ioncube_loaders_lin_x86.tar.gz
    fi

    mv ioncube /usr/lib/php/loaders/
}

# Enable ionCube Loader
function enable_ic {
if [[ -n $1 ]]; then
    PHPv=$1
else
    PHPv="7.0" # default php install 7.0 (latest stable recommendation)
fi

echo "Enabling IonCube PHP ${PHPv} loader"

cat > /etc/php/${PHPv}/mods-available/ioncube.ini <<EOL
[ioncube]
zend_extension=/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so
EOL

ln -s /etc/php/${PHPv}/mods-available/ioncube.ini /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini
ln -s /etc/php/${PHPv}/mods-available/ioncube.ini /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini
}

# Disable ionCube Loader
function disable_ic {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Disabling IonCube PHP ${PHPv} loader"

    unlink /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini
    unlink /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini
}

# Remove ionCube Loader
function remove_ic {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Uninstalling IonCube PHP ${PHPv} loader..."

    if [[ -f /etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini || -f /etc/php/${PHPv}/cli/conf.d/05-ioncube.ini ]]; then
        disable_ic $PHPv
    fi

    if [ -d /usr/lib/php/loaders/ioncube ]; then
        echo "Removing IonCube PHP ${PHPv} loader installation"
        rm -fr /usr/lib/php/loaders/ioncube
        removed="has been"
    elif
        echo "IonCube PHP ${PHPv} loader installation couldn't be found"
        removed="may be"
    fi

    echo "IonCube PHP ${PHPv} loader $removed removed"
}

# Install SourceGuardian
function install_sg {
    echo "Installing SourceGuardian PHP loader..."

    mkdir sourceguardian
    cd sourceguardian

    arch=$(uname -p)
    if [[ "$arch" == "x86_64" ]]; then
        wget "http://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz"
        tar xzf loaders.linux-x86_64.tar.gz
        rm -f loaders.linux-x86_64.tar.gz
    else
        wget "http://www.sourceguardian.com/loaders/download/loaders.linux-x86.tar.gz"
        tar xzf loaders.linux-x86.tar.gz
        rm -f loaders.linux-x86.tar.gz
    fi

    cd ../
    mv sourceguardian /usr/lib/php/loaders/
}

# Enable SourceGuardian
function enable_sg {
if [[ -n $1 ]]; then
    PHPv=$1
else
    PHPv="7.0" # default php install 7.0 (latest stable recommendation)
fi

echo "Enabling SourceGuardian PHP ${PHPv} loader..."

cat > /etc/php/${PHPv}/mods-available/sourceguardian.ini <<EOL
[sourceguardian]
zend_extension=/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin
EOL

ln -s /etc/php/${PHPv}/mods-available/sourceguardian.ini /etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini
ln -s /etc/php/${PHPv}/mods-available/sourceguardian.ini /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini
}

# Disable SourceGuardian Loader
function disable_sg {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Disabling SourceGuardian PHP ${PHPv} loader"

    unlink /etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini
    unlink /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini
}

# Remove SourceGuardian Loader
function remove_sg {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Uninstalling SourceGuardian PHP ${PHPv} loader..."

    if [[ -f /etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini || -f /etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini ]]; then
        disable_sg $PHPv
    fi

    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Removing SourceGuardian PHP ${PHPv} loader installation"
        rm -fr /usr/lib/php/loaders/sourceguardian
        removed='has been'
    elif
        echo "SourceGuardian PHP ${PHPv} loader installation couldn't be found"
        removed='may be'
    fi

    echo "SourceGuardian PHP ${PHPv} loader $removed removed"
}

# PHP Setting + Optimization
function optimize_php {
    if [[ -n $1 ]]; then
        PHPv=$1
    else
        PHPv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Optimizing PHP ${PHPv} configuration..."

    # Copy custom php.ini
    mv /etc/php/${PHPv}/fpm/php.ini /etc/php/${PHPv}/fpm/php.ini~
    cp php/${PHPv}/fpm/php.ini /etc/php/${PHPv}/fpm/

    # Copy the optimized-version of php fpm config file
    mv /etc/php/${PHPv}/fpm/php-fpm.conf /etc/php/${PHPv}/fpm/php-fpm.conf~
    cp php/${PHPv}/fpm/php-fpm.conf /etc/php/${PHPv}/fpm/

    # Copy the optimized-version of php fpm default pool
    mv /etc/php/${PHPv}/fpm/pool.d/www.conf /etc/php/${PHPv}/fpm/pool.d/www.conf~
    cp php/${PHPv}/fpm/pool.d/www.conf /etc/php/${PHPv}/fpm/pool.d/

    # Fix cgi.fix_pathinfo
    sed -i "s/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${PHPv}/fpm/php.ini

    # Add custom php extension (ex .php70, .php71)
    PHPExt=".php${PHPv//.}"
    sed -i "s/;\(security\.limit_extensions\s*=\s*\).*$/\1\.php\ $PHPExt/" /etc/php/${PHPv}/fpm/pool.d/www.conf

    # Restart Php-fpm server
    service php${PHPv}-fpm restart
}

## Main Function, Start PHP Installation ##
function init_php_install() {
# Menu Install PHP, fpm, and modules
header_msg
echo "Welcome to PHP installation"
sleep 1
echo "Which version of PHP you want to install? (default is all)
Supported PHP version:
1). PHP 7.1 (latest stable)
2). PHP 7.0 (latest stable)
3). PHP 5.6 (old stable)
4). All versions (PHP 5.6, 7.0, 7.1)
-------------------------------------"
echo -n "Select your option [1/2/3/4]: "
read PhpVersionInstall

case $PhpVersionInstall in
    1)
        PHPver="7.1"
        install_php $PHPver
    ;;
    2)
        PHPver="7.0"
        install_php $PHPver
    ;;
    3)
        PHPver="5.6"
        install_php $PHPver
    ;;
    *)
        PHPver="all"
        install_php "7.1"
        install_php "7.0"
        install_php "5.6"
    ;;
esac

# Menu Install PHP loader
header_msg
echo -n "Do you want to install PHP loader? [Y/n]: "
read PhpLoaderInstall

if [[ "$PhpLoaderInstall" == "Y" || "$PhpLoaderInstall" == "y" || "$PhpLoaderInstall" == "yes" ]]; then
    echo "Available PHP loaders:
    1). IonCube Loader (latest stable)
    2). SourceGuardian (latest stable)
    3). All loaders (IonCube, SourceGuardian)
    ------------------------------------------"
    echo -n "Select your loader [1/2/3]: "
    read PhpLoaderOpt

    mkdir /usr/lib/php/loaders

    case $PhpLoaderOpt in
        1)
            install_ic

            if [ "$PHPver" != "all" ]; then
                enable_ic $PHPver
            else
                enable_ic "7.1"
                enable_ic "7.0"
                enable_ic "5.6"
            fi
        ;;
        2)
            install_sg

            if [ "$PHPver" != "all" ]; then
                enable_sg $PHPver
            else
                enable_sg "7.1"
                enable_sg "7.0"
                enable_sg "5.6"
            fi
        ;;
        *)
            install_ic
            install_sg

            if [ "$PHPver" != "all" ]; then
                enable_ic $PHPver
                enable_sg $PHPver
            else
                enable_ic "7.1"
                enable_ic "7.0"
                enable_ic "5.6"
                enable_sg "7.1"
                enable_sg "7.0"
                enable_sg "5.6"
            fi
        ;;
    esac
fi

# Menu Optimizing PHP
if [ "$PHPver" != "all" ]; then
    optimize_php $PHPver
else
    optimize_php "7.1"
    optimize_php "7.0"
    optimize_php "5.6"
fi
}

init_php_install()
