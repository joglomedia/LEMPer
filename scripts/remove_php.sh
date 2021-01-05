#!/usr/bin/env bash

# PHP & FPM Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 12/07/2019
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

function remove_php_fpm() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    # Stop default PHP FPM process.
    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
        run systemctl stop "php${PHPv}-fpm"
    fi

    if dpkg-query -l | awk '/php/ { print $2 }' | grep -qwE "^php${PHPv}"; then
        echo "Removing PHP ${PHPv} packages installation..."

        # Remove geoip module.
        if "php${PHPv}" -m | grep -qw geoip; then
            # Uninstall geoip pecl.
            #run pecl uninstall geoip-1.1.1

            # Unlink enabled module.
            [ -f "/etc/php/${PHPv}/cli/conf.d/20-geoip.ini" ] && \
            run unlink "/etc/php/${PHPv}/cli/conf.d/20-geoip.ini"

            [ -f "/etc/php/${PHPv}/fpm/conf.d/20-geoip.ini" ] && \
            run unlink "/etc/php/${PHPv}/fpm/conf.d/20-geoip.ini"

            # Remove module.
            run rm -f "/etc/php/${PHPv}/mods-available/geoip.ini"
        fi

        # Remove mcrypt module.
        if [[ "${PHPv//.}" -lt "72" ]]; then
            if "php${PHPv}" -m | grep -qw mcrypt; then
                run apt-get --purge remove -y "php${PHPv}-mcrypt"
            fi
        elif [[ "${PHPv}" == "7.2" ]]; then
            if "php${PHPv}" -m | grep -qw mcrypt; then
                # Uninstall mcrypt pecl.
                #run pecl uninstall mcrypt-1.0.1

                # Unlink enabled module.
                [ -f "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini" ] && \
                run unlink "/etc/php/${PHPv}/cli/conf.d/20-mcrypt.ini"

                [ -f "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini" ] && \
                run unlink "/etc/php/${PHPv}/fpm/conf.d/20-mcrypt.ini"

                # Remove module.
                run rm -f "/etc/php/${PHPv}/mods-available/mcrypt.ini"
            fi
        else
            # Use libsodium? remove separately.
            info "If you're installing Libsodium extension, then remove it separately."
        fi

        # Remove PHP packages.
        # shellcheck disable=SC2046
        run apt remove --purge -qq -y $(dpkg-query -l | awk '/php/ { print $2 }' | grep -wE "^php${PHPv}")

        # Remove PHP & FPM config files.
        warning "!! This action is not reversible !!"

        if "${AUTO_REMOVE}"; then
            REMOVE_PHPCONFIG="y"
        else
            while [[ "${REMOVE_PHPCONFIG}" != "y" && "${REMOVE_PHPCONFIG}" != "n" ]]; do
                read -rp "Remove PHP ${PHPv} & FPM configuration files? [y/n]: " -e REMOVE_PHPCONFIG
            done
        fi

        if [[ ${REMOVE_PHPCONFIG} == Y* || ${REMOVE_PHPCONFIG} == y* || ${FORCE_REMOVE} == true ]]; then
            [ -d "/etc/php/${PHPv}" ] && run rm -fr "/etc/php/${PHPv}"

            echo "All your configuration files deleted permanently."
        fi

        if [[ -z $(command -v "php${PHPv}") ]]; then
            success "PHP ${PHPv} & FPM installation removed."
        else
            info "Unable to remove PHP ${PHPv} & FPM installation."
        fi
    else
        info "PHP ${PHPv} & FPM installation not found."
    fi   
}

# Remove PHP & FPM.
function init_php_fpm_removal() {
    # PHP version.
    local INSTALLED_PHP="${1}"
    [[ -z "${INSTALLED_PHP}" || "${INSTALLED_PHP}" == *install || "${INSTALLED_PHP}" == *remove ]] && \
    INSTALLED_PHP=${PHP_VERSION:-"7.3"}

    [[ "${INSTALLED_PHP}" == "all" ]] && INSTALLED_PHP="5.6 7.0 7.1 7.2 7.3 7.4"

    # New logic for multiple PHP removal in batch.
    for PHPv in ${INSTALLED_PHP}; do
        remove_php_fpm "${PHPv}"
    done

    # case "${PHPv}" in
    #     "5.6")
    #         remove_php_fpm "5.6"
    #     ;;
    #     "7.0")
    #         remove_php_fpm "7.0"
    #     ;;
    #     "7.1")
    #         remove_php_fpm "7.1"
    #     ;;
    #     "7.2")
    #         remove_php_fpm "7.2"
    #     ;;
    #     "7.3")
    #         remove_php_fpm "7.3"
    #     ;;
    #     "7.4")
    #         remove_php_fpm "7.4"
    #     ;;
    #     "all")
    #         remove_php_fpm "5.6"
    #         remove_php_fpm "7.0"
    #         remove_php_fpm "7.1"
    #         remove_php_fpm "7.2"
    #         remove_php_fpm "7.3"
    #         remove_php_fpm "7.4"
    #     ;;
    #     *)
    #         fail "Invalid argument: ${PHPv}"
    #         exit 1
    #     ;;
    #esac

    # Final clean up (executed only if no PHP version installed).
    if "${DRYRUN}"; then
        info "PHP ${INSTALLED_PHP} & FPM removed in dryrun mode."
    else
        # New logic for multiple PHP removal in batch.
        PHP_IS_EXISTS=false
        for PHPv in ${INSTALLED_PHP}; do
            [[ -n $(command -v "${PHPv}") ]] && PHP_IS_EXISTS=true
        done

        if [[ "${PHP_IS_EXISTS}" == true ]]; then
        # if [[ -z $(command -v php5.6) && \
        #     -z $(command -v php7.0) && \
        #     -z $(command -v php7.1) && \
        #     -z $(command -v php7.2) && \
        #     -z $(command -v php7.3) && \
        #     -z $(command -v php7.4) ]]; then

            echo "Removing additional unused PHP packages..."
            run apt remove --purge -qq -y php-common php-pear php-xml pkg-php-tools spawn-fcgi fcgiwrap

            # Remove PHP repository.
            run add-apt-repository -y --remove ppa:ondrej/php

            # Remove all the rest of PHP lib files.
            [ -d /usr/lib/php ] && run rm -fr /usr/lib/php
            [ -d /usr/share/php ] && run rm -fr /usr/share/php
            [ -d /var/lib/php ] && run rm -fr /var/lib/php

            success "All PHP packages installation completely removed."
        fi
    fi
}

echo "Uninstalling PHP & FPM..."
if [[ -n $(command -v php5.6) || \
    -n $(command -v php7.0) || \
    -n $(command -v php7.1) || \
    -n $(command -v php7.2) || \
    -n $(command -v php7.3) || \
    -n $(command -v php7.4) ]]; then

    if "${AUTO_REMOVE}"; then
        REMOVE_PHP="y"
    else
        while [[ "${REMOVE_PHP}" != "y" && "${REMOVE_PHP}" != "n" ]]; do
            read -rp "Are you sure to remove PHP & FPM? [y/n]: " -e REMOVE_PHP
        done
    fi

    if [[ "${REMOVE_PHP}" == Y* || "${REMOVE_PHP}" == y* ]]; then
        init_php_fpm_removal "$@"
    else
        echo "Found PHP & FPM, but not removed."
    fi
else
    info "Oops, PHP & FPM installation not found."
fi
