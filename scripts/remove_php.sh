#!/usr/bin/env bash

# PHP & FPM Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script
requires_root

function remove_php_fpm() {
    # PHP version.
    local PHPv=${1:-"${PHP_VERSION}"}

    # Related PHP packages to be removed.
    local PHP_PKGS=()

    # Stop default PHP FPM process.
    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
        run service "php${PHPv}-fpm" stop
    fi

    if [[ -n $(command -v "php${PHPv}") ]]; then
        # Installed PHP Packages.
        PHP_PKGS=("php${PHPv} php${PHPv}-bcmath php${PHPv}-cli php${PHPv}-common \
            php${PHPv}-curl php${PHPv}-dev php${PHPv}-fpm php${PHPv}-mysql php${PHPv}-gd \
            php${PHPv}-gmp php${PHPv}-imap php${PHPv}-intl php${PHPv}-json php${PHPv}-ldap \
            php${PHPv}-mbstring php${PHPv}-opcache php${PHPv}-pspell php${PHPv}-readline \
            php${PHPv}-recode php${PHPv}-snmp php${PHPv}-soap php${PHPv}-sqlite3 \
            php${PHPv}-tidy php${PHPv}-xml php${PHPv}-xmlrpc php${PHPv}-xsl php${PHPv}-zip" "${PHP_PKGS[@]}")

        isMcrypt=$("/usr/bin/php${PHPv}" -m | grep mcrypt)
        if [ "${PHPv//.}" -lt "72" ]; then
            if [[ "${isMcrypt}" == "mcrypt" ]]; then
                #run apt-get --purge remove -y php${PHPv}-mcrypt >> lemper.log 2>&1
                PHP_PKGS=("php${PHPv}-mcrypt" "${PHP_PKGS[@]}")
            fi
        elif [ "${PHPv}" == "7.2" ]; then
            if [[ "${isMcrypt}" == "mcrypt" ]]; then
                # Uninstall mcrypt pecl.
                run pecl uninstall mcrypt-1.0.1 >> lemper.log 2>&1

                # Unlink eabled module.
                if [ -f "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini" ]; then
                    run unlink "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini"
                fi

                if [ -f "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini" ]; then
                    run unlink "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini"
                fi

                # Remove module.
                run rm -f "/etc/php/${PHPv}/mods-available/mcrypt.ini"
            fi
        else
            #if [[ -n $(dpkg-query -l | grep dh-php | awk ' { print $2 }') ]]; then
            #    #run apt-get --purge remove -y dh-php >> lemper.log 2>&1
            #    PHP_PKGS=("dh-php" "${PHP_PKGS[@]}")
            #fi

            # Use libsodium? remove separately.
            warning "If you're installing Libsodium extension, then remove it separately."
        fi

        # Additional packages.
        #if [[ -n $(dpkg-query -l | grep fcgiwrap | awk ' { print $2 }') ]]; then
        #    PHP_PKGS=("fcgiwrap" "${PHP_PKGS[@]}")
        #fi

        #if [[ -n $(dpkg-query -l | grep geoip-database | awk ' { print $2 }') ]]; then
        #    PHP_PKGS=("geoip-database" "${PHP_PKGS[@]}")
        #fi

        #if [[ -n $(dpkg-query -l | grep php-geoip | awk ' { print $2 }') ]]; then
        #    PHP_PKGS=("php-geoip" "${PHP_PKGS[@]}")
        #fi

        #if [[ -n $(dpkg-query -l | grep php-pear | awk ' { print $2 }') ]]; then
        #    PHP_PKGS=("php-pear" "${PHP_PKGS[@]}")
        #fi

        #if [[ -n $(dpkg-query -l | grep pkg-php-tools | awk ' { print $2 }') ]]; then
        #    PHP_PKGS=("pkg-php-tools" "${PHP_PKGS[@]}")
        #fi

        #if [[ -n $(dpkg-query -l | grep spawn-fcgi | awk ' { print $2 }') ]]; then
        #    PHP_PKGS=("spawn-fcgi" "${PHP_PKGS[@]}")
        #fi
    
        if [[ "${#PHP_PKGS[@]}" -gt 0 ]]; then
            echo "Removing PHP ${PHPv} packages..."
            run apt-get --purge remove -y "${PHP_PKGS[@]}" >> lemper.log 2>&1
        fi

        # Remove PHP & FPM config files.
        warning "!! This action is not reversible !!"

        while [[ "${REMOVE_PHPCONFIG}" != "y" && "${REMOVE_PHPCONFIG}" != "n" && "${AUTO_REMOVE}" != true ]]
        do
            read -rp "Remove PHP & FPM ${PHPv} configuration files? [y/n]: " -e REMOVE_PHPCONFIG
        done
        if [[ "${REMOVE_PHPCONFIG}" == Y* || "${REMOVE_PHPCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
            echo "All your configuration files deleted permanently..."
            if [[ -d "/etc/php/${PHPv}" ]]; then
                run rm -fr "/etc/php/${PHPv}"
            fi
        fi

        status "PHP & FPM ${PHPv} installation removed."
    else
        warning "PHP & FPM ${PHPv} installation not found."
    fi   
}

# Remove PHP & FPM.
function init_php_fpm_removal() {
    # PHP version.
    #local PHPv="${1}"
    #if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    #fi

    case "${PHPv}" in
        "5.6")
            remove_php_fpm "5.6"
        ;;
        "7.0")
            remove_php_fpm "7.0"
        ;;
        "7.1")
            remove_php_fpm "7.1"
        ;;
        "7.2")
            remove_php_fpm "7.2"
        ;;
        "7.3")
            remove_php_fpm "7.3"
        ;;
        "all")
            remove_php_fpm "5.6"
            remove_php_fpm "7.0"
            remove_php_fpm "7.1"
            remove_php_fpm "7.2"
            remove_php_fpm "7.3"
        ;;
        *)
            fail "Invalid argument: ${PHPv}"
            exit 1
        ;;
    esac

    # Final clean up.
    if "${DRYRUN}"; then
        warning "PHP & FPM ${PHPv} removed in dryrun mode."
    else
        if [[ -z $(command -v php5.6) && \
            -z $(command -v php7.0) && \
            -z $(command -v php7.1) && \
            -z $(command -v php7.2) && \
            -z $(command -v php7.3) ]]; then

            # Remove PHP repository.
            run add-apt-repository -y --remove ppa:ondrej/php >> lemper.log 2>&1

            # Remove PHP loaders.
            if [[ -d /usr/lib/php/loaders ]]; then
                run rm -fr /usr/lib/php/loaders
            fi
        fi
    fi
}

echo -e "\nUninstalling PHP & FPM..."
if [[ -n $(command -v php5.6) || \
    -n $(command -v php7.0) || \
    -n $(command -v php7.1) || \
    -n $(command -v php7.2) || \
    -n $(command -v php7.3) ]]; then

    while [[ "${REMOVE_PHP}" != "y" && "${REMOVE_PHP}" != "n" && "${AUTO_REMOVE}" == true ]]; do
        read -rp "Are you sure to remove PHP & FPM? [y/n]: " -i y -e REMOVE_PHP
    done
    if [[ "${REMOVE_PHP}" == Y* || "${REMOVE_PHP}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_php_fpm_removal "$@"
    else
        echo "Found PHP & FPM, but not removed."
    fi
else
    warning "PHP installation not found."
fi
