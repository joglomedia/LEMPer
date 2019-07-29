#!/usr/bin/env bash

# PHP uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ "$(id -u)" -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

# Remove PHP & FPM
function init_phpfpm_removal() {
    # Related PHP packages to be removed
    DEBPackages=()

    # Stop default PHP FPM process
    if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/5.6" | wc -l) > 0 ]]; then
        run service php5.6-fpm stop
    fi
    if [[ -n $(command -v php-fpm5.6) ]]; then
        DEBPackages=("php5.6 php5.6-bcmath php5.6-cli php5.6-common \
            php5.6-curl php5.6-dev php5.6-fpm php5.6-mysql php5.6-gd \
            php5.6-gmp php5.6-imap php5.6-intl php5.6-json php5.6-ldap \
            php5.6-mbstring php5.6-opcache php5.6-pspell php5.6-readline \
            php5.6-recode php5.6-snmp php5.6-soap php5.6-sqlite3 \
            php5.6-tidy php5.6-xml php5.6-xmlrpc php5.6-xsl php5.6-zip" "${DEBPackages[@]}")
    fi

    if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.0" | wc -l) > 0 ]]; then
        run service php7.0-fpm stop
    fi
    if [[ -n $(command -v php-fpm7.0) ]]; then
        DEBPackages=("php7.0 php7.0-bcmath php7.0-cli php7.0-common \
            php7.0-curl php7.0-dev php7.0-fpm php7.0-mysql php7.0-gd \
            php7.0-gmp php7.0-imap php7.0-intl php7.0-json php7.0-ldap \
            php7.0-mbstring php7.0-opcache php7.0-pspell php7.0-readline \
            php7.0-recode php7.0-snmp php7.0-soap php7.0-sqlite3 \
            php7.0-tidy php7.0-xml php7.0-xmlrpc php7.0-xsl php7.0-zip" "${DEBPackages[@]}")
    fi

    if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.1" | wc -l) > 0 ]]; then
        run service php7.1-fpm stop
    fi
    if [[ -n $(command -v php-fpm7.1) ]]; then
        DEBPackages=("php7.1 php7.1-bcmath php7.1-cli php7.1-common \
            php7.1-curl php7.1-dev php7.1-fpm php7.1-mysql php7.1-gd \
            php7.1-gmp php7.1-imap php7.1-intl php7.1-json php7.1-ldap \
            php7.1-mbstring php7.1-opcache php7.1-pspell php7.1-readline \
            php7.1-recode php7.1-snmp php7.1-soap php7.1-sqlite3 \
            php7.1-tidy php7.1-xml php7.1-xmlrpc php7.1-xsl php7.1-zip" "${DEBPackages[@]}")
    fi

    if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.2" | wc -l) > 0 ]]; then
        run service php7.2-fpm stop
    fi
    if [[ -n $(command -v php-fpm7.2) ]]; then
        DEBPackages=("php7.2 php7.2-bcmath php7.2-cli php7.2-common \
            php7.2-curl php7.2-dev php7.2-fpm php7.2-mysql php7.2-gd \
            php7.2-gmp php7.2-imap php7.2-intl php7.2-json php7.2-ldap \
            php7.2-mbstring php7.2-opcache php7.2-pspell php7.2-readline \
            php7.2-recode php7.2-snmp php7.2-soap php7.2-sqlite3 \
            php7.2-tidy php7.2-xml php7.2-xmlrpc php7.2-xsl php7.2-zip" "${DEBPackages[@]}")
    fi

    if [[ $(ps -ef | grep -v grep | grep php-fpm | grep "php/7.3" | wc -l) > 0 ]]; then
        run service php7.3-fpm stop
    fi
    if [[ -n $(command -v php-fpm7.3) ]]; then
        DEBPackages=("php7.3 php7.3-bcmath php7.3-cli php7.3-common \
            php7.3-curl php7.3-dev php7.3-fpm php7.3-mysql php7.3-gd \
            php7.3-gmp php7.3-imap php7.3-intl php7.3-json php7.3-ldap \
            php7.3-mbstring php7.3-opcache php7.3-pspell php7.3-readline \
            php7.3-recode php7.3-snmp php7.3-soap php7.3-sqlite3 \
            php7.3-tidy php7.3-xml php7.3-xmlrpc php7.3-xsl php7.3-zip" "${DEBPackages[@]}")
    fi

    if [[ -n ${DEBPackages} ]]; then
        run apt-get --purge remove -y ${DEBPackages} \
            fcgiwrap php-geoip php-pear pkg-php-tools spawn-fcgi geoip-database && \
            add-apt-repository -y --remove ppa:ondrej/php >> lemper.log 2>&1
    fi

    # Remoce PHP & FPM config files
    while [[ ${REMOVE_PHPCONFIG} != "y" && ${REMOVE_PHPCONFIG} != "n" ]]; do
        read -p "Remove PHP-FPM configuration files (This action is not reversible)? [y/n]: " -e REMOVE_PHPCONFIG
    done
    if [[ "${REMOVE_PHPCONFIG}" == Y* || "${REMOVE_PHPCONFIG}" == y* ]]; then
        echo "All your PHP-FPM configuration files deleted permanently..."
        if [[ -d /etc/php ]]; then
            run rm -fr /etc/php
        fi
        # Remove ioncube
        if [[ -d /usr/lib/php/loaders ]]; then
            run rm -fr /usr/lib/php/loaders
        fi
    fi

    status "PHP & FPM installation removed."
}

echo -e "\nUninstalling PHP & FPM..."
if [[ -n $(command -v php-fpm5.6) \
    || -n $(command -v php-fpm7.0) \
    || -n $(command -v php-fpm7.1) \
    || -n $(command -v php-fpm7.2) \
    || -n $(command -v php-fpm7.3) ]]; then

    while [[ ${REMOVE_PHP} != "y" && ${REMOVE_PHP} != "n" ]]; do
        read -p "Are you sure to remove PHP & FPM? [y/n]: " -e REMOVE_PHP
    done
    if [[ "${REMOVE_PHP}" == Y* || "${REMOVE_PHP}" == y* ]]; then
        init_phpfpm_removal "$@"
    else
        echo "PHP & FPM uninstall skipped."
    fi
else
    warning "PHP installation not found."
fi
