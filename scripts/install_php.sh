#!/usr/bin/env bash

# Install PHP
function install_php {
    if [[ -n $1 ]]; then
        phpv=$1
    else
        phpv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Installing PHP $phpv..."

    apt-get install -y php${phpv} php${phpv}-common php${phpv}-fpm php${phpv}-cli php${phpv}-mysql php${phpv}-curl php${phpv}-gd php${phpv}-intl php${phpv}-json php${phpv}-mcrypt php${phpv}-mbstring php${phpv}-imap php${phpv}-pspell php${phpv}-pspell php${phpv}-recode php${phpv}-snmp php${phpv}-sqlite3 php${phpv}-tidy php${phpv}-readline php${phpv}-xml php${phpv}-xmlrpc php${phpv}-xsl php${phpv}-gmp php${phpv}-opcache php${phpv}-soap php${phpv}-zip php-geoip php-pear pkg-php-tools php-phalcon
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
    phpv=$1
else
    phpv="7.0" # default php install 7.0 (latest stable recommendation)
fi

echo "Enabling IonCube PHP ${phpv} loader..."

cat > /etc/php/${phpv}/mods-available/ioncube.ini <<EOL
[ioncube]
zend_extension=/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${phpv}.so
EOL

ln -s /etc/php/${phpv}/mods-available/ioncube.ini /etc/php/${phpv}/fpm/conf.d/05-ioncube.ini
ln -s /etc/php/${phpv}/mods-available/ioncube.ini /etc/php/${phpv}/cli/conf.d/05-ioncube.ini
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
    phpv=$1
else
    phpv="7.0" # default php install 7.0 (latest stable recommendation)
fi

echo "Enabling SourceGuardian PHP ${phpv} loader..."

cat > /etc/php/${phpv}/mods-available/sourceguardian.ini <<EOL
[sourceguardian]
zend_extension=/usr/lib/php/loaders/sourceguardian/ixed.${phpv}.lin
EOL

ln -s /etc/php/${phpv}/mods-available/sourceguardian.ini /etc/php/${phpv}/fpm/conf.d/05-sourceguardian.ini
ln -s /etc/php/${phpv}/mods-available/sourceguardian.ini /etc/php/${phpv}/cli/conf.d/05-sourceguardian.ini
}

# PHP Setting + Optimization
function optimize_php {
    if [[ -n $1 ]]; then
        phpv=$1
    else
        phpv="7.0" # default php install 7.0 (latest stable recommendation)
    fi

    echo "Optimizing PHP ${phpv} configuration..."

    # Copy custom php.ini
    mv /etc/php/${phpv}/fpm/php.ini /etc/php/${phpv}/fpm/php.ini~
    cp php/${phpv}/fpm/php.ini /etc/php/${phpv}/fpm/

    # Copy the optimized-version of php fpm config file
    mv /etc/php/${phpv}/fpm/php-fpm.conf /etc/php/${phpv}/fpm/php-fpm.conf~
    cp php/${phpv}/fpm/php-fpm.conf /etc/php/${phpv}/fpm/

    # Copy the optimized-version of php fpm default pool
    mv /etc/php/${phpv}/fpm/pool.d/www.conf /etc/php/${phpv}/fpm/pool.d/www.conf~
    cp php/${phpv}/fpm/pool.d/www.conf /etc/php/${phpv}/fpm/pool.d/

    # Fix cgi.fix_pathinfo
    sed -i "s/cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php/${phpv}/fpm/php.ini

    # Restart Php-fpm server
    service php${phpv}-fpm restart
}

# Start PHP Installation #

echo "Installing PHP..."

# Install PHP, fpm, and modules
echo "Which version of PHP you want to install? (default is all)
Supported PHP version:
1). PHP 7.1 (latest stable)
2). PHP 7.0 (latest stable)
3). PHP 5.6 (old stable)
4). All versions (PHP 5.6, 7.0, 7.1)
-------------------------------------"
echo -n "Select your option [1/2/3/4]: "
read phpveropt

case $phpveropt in
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

# Install PHP loader
echo -n "Do you want to install PHP loader? [Y/n]: "
read plinstall

if [[ "$plinstall" == "Y" || "$plinstall" == "y" || "$plinstall" == "yes" ]]; then
    echo "Available PHP loaders:
    1). IonCube Loader (latest stable)
    2). SourceGuardian (latest stable)
    3). All loaders (IonCube, SourceGuardian)
    ------------------------------------------"
    echo -n "Select your loader [1/2/3]: "
    read plopt

    mkdir /usr/lib/php/loaders

    case $plopt in
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

# Optimizing PHP
if [ "$PHPver" != "all" ]; then
    optimize_php $PHPver
else
    optimize_php "7.1"
    optimize_php "7.0"
    optimize_php "5.6"
fi
