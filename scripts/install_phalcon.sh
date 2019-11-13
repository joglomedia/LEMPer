#!/usr/bin/env bash

# Phalcon & Zephir Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 23/08/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.2.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Install Phalcon from source.
function install_phalcon() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    # Phalcon version.
    local PHALCON_VERSION="${2}"
    if [ -z "${PHALCON_VERSION}" ]; then
        PHALCON_VERSION=${PHP_PHALCON_VERSION:-"3.4.4"}
    fi

    local CURRENT_DIR && \
    CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}"

    # Install prerequisite packages.
    run apt-get -qq install -y autoconf automake gcc libpcre3-dev make re2c

    # Install Zephir from source.
    if "${AUTO_INSTALL}"; then
        if [[ "${PHP_PHALCON_ZEPHIR}" == y* || "${PHP_PHALCON_ZEPHIR}" == true ]]; then
            INSTALL_ZEPHIR="y"
        else
            INSTALL_ZEPHIR="n"
        fi
    else
        while [[ $INSTALL_ZEPHIR != "y" && $INSTALL_ZEPHIR != "n" ]]; do
            read -rp "Install Zephir Interpreter? [y/n]: " -i n -e INSTALL_ZEPHIR
        done
    fi

    if [[ "$INSTALL_ZEPHIR" == Y* || "$INSTALL_ZEPHIR" == y* ]]; then
        # Install Zephir parser.
        run git clone -q git://github.com/phalcon/php-zephir-parser.git
        run cd php-zephir-parser

        if [[ -n "${PHPv}" ]]; then
            run "phpize${PHPv}"
            run ./configure --with-php-config="/usr/bin/php-config${PHPv}"
        else
            run phpize
            run ./configure
        fi

        run make
        run make install
        run cd ../

        # Install Zephir.
        ZEPHIR_BRANCH=$(git ls-remote https://github.com/phalcon/zephir 0.12.* | sort -t/ -k3 -Vr | head -n1 | awk -F/ '{ print $NF }')
        run git clone --depth=1 --branch="${ZEPHIR_BRANCH}" -q https://github.com/phalcon/zephir.git
        run cd zephir
        run composer install
        run cd ../
    fi

    # Download cPhalcon source.
    if [[ "${PHALCON_VERSION}" == "latest" ]]; then
        PHALCON_VERSION="master"
    fi

    if wget -q -O "cphalcon-${PHALCON_VERSION}.tar.gz" \
        "https://github.com/phalcon/cphalcon/archive/v${PHALCON_VERSION}.tar.gz"; then
        run tar -zxf "cphalcon-${PHALCON_VERSION}.tar.gz"
        #run rm -f "cphalcon-${PHALCON_VERSION}.tar.gz"
        run cd "cphalcon-${PHALCON_VERSION}/build"
    elif wget -q -O /dev/null "https://raw.githubusercontent.com/phalcon/cphalcon/${PHALCON_VERSION}/README.md"; then
        # Clone repository.
        if [ ! -d cphalcon ]; then
            run git clone -q https://github.com/phalcon/cphalcon.git && \
            run git checkout "${PHALCON_VERSION}" && \
            run cd cphalcon/build
        else
            run cd cphalcon && \
            run git checkout "${PHALCON_VERSION}" && \
            run git pull -q && \
            run cd build
        fi
    else
        error "cPhalcon ${PHALCON_VERSION} source couldn't be downloaded."
    fi

    # Install cPhalcon.
    if [ -f install ]; then
        if [[ -n "${PHPv}" ]]; then
            run ./install --phpize "/usr/bin/phpize${PHPv}" --php-config "/usr/bin/php-config${PHPv}"
        else
            run ./install
        fi
    fi

    PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
    if [ -f "${PHPLIB_DIR}/phalcon.so" ]; then
        status "Phalcon.so module sucessfully installed."
        run chmod 0644 "${PHPLIB_DIR}/phalcon.so"
    fi

    run cd "${CURRENT_DIR}"
}

# Enable Phalcon extension.
function enable_phalcon() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    if "${DRYRUN}"; then
        echo "Enabling Phalcon PHP extension in dryrun mode."
    else
        # Optimize Phalcon PHP extension.
        if [ -d "/etc/php/${PHPv}/mods-available/" ]; then
            # Add the extension to php.ini.
            local PHPLIB_DIR && \
                PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
            if [[ -f "${PHPLIB_DIR}/phalcon.so" && ! -f "/etc/php/${PHPv}/mods-available/phalcon.ini" ]]; then
                run echo "Enabling Phalcon extension for PHP${PHPv}..."

                run touch "/etc/php/${PHPv}/mods-available/phalcon.ini"
                run echo "extension=phalcon.so" > "/etc/php/${PHPv}/mods-available/phalcon.ini"

                # Enable extension.
                if [ ! -s "/etc/php/${PHPv}/fpm/conf.d/20-phalcon.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/phalcon.ini" "/etc/php/${PHPv}/fpm/conf.d/20-phalcon.ini"
                fi

                if [ ! -s "/etc/php/${PHPv}/cli/conf.d/20-phalcon.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/phalcon.ini" "/etc/php/${PHPv}/cli/conf.d/20-phalcon.ini"
                fi
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

# Init Phalcon installer.
function init_phalcon_install() {
    # PHP version.
    local PHPv=${PHP_VERSION:-"7.3"}

    if "${AUTO_INSTALL}"; then
        if [[ -z "${PHP_PHALCON_INSTALLER}" || "${PHP_PHALCON_INSTALLER}" == "none" ]]; then
            INSTALL_PHALCON="n"
        else
            INSTALL_PHALCON="y"
            SELECTED_PHALCON=${PHP_PHALCON_INSTALLER}
        fi
    else
        while [[ ${INSTALL_PHALCON} != "y" && ${INSTALL_PHALCON} != "n" ]]; do
            read -rp "Do you want to install Phalcon PHP framework? [y/n]: " -e INSTALL_PHALCON
        done
        echo ""
    fi

    if [[ "${INSTALL_PHALCON}" == Y* || "${INSTALL_PHALCON}" == y* ]]; then
        echo "Available Phalcon framework installer:"
        echo "  1). Repository (repo)"
        echo "  2). Source (source)"
        echo "--------------------------------------------"

        while [[ ${SELECTED_PHALCON} != "1" && ${SELECTED_PHALCON} != "2" && ${SELECTED_PHALCON} != "none" && \
            ${SELECTED_PHALCON} != "repo" && ${SELECTED_PHALCON} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_PHALCON
        done

        echo ""

        case ${SELECTED_PHALCON} in
            1|"source")
                echo "Installing Phalcon extension from source..."
                run install_phalcon "${PHPv}"
            ;;
            2|"repo")
                echo "Installing Phalcon extension from repository..."
                run apt-get -qq install -y php-phalcon
            ;;
            *)
                # Skip installation.
                warning "Phalcon installation skipped."
            ;;
        esac

        # Enable Phalcon extension.
        if [ "${PHPv}" != "all" ]; then
            run enable_phalcon "${PHPv}"

            # Default PHP Required for LEMPer
            if [ "${PHPv}" != "7.3" ]; then
                run enable_phalcon "7.3"
            fi
        else
            run enable_phalcon "5.6"
            run enable_phalcon "7.0"
            run enable_phalcon "7.1"
            run enable_phalcon "7.2"
            run enable_phalcon "7.3"
        fi
    fi
}

echo "[Phalcon Framework (PHP Extension) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
PHP_VERSION=${PHP_VERSION:-"7.3"}
if [[ -n $(command -v "php${PHP_VERSION}") ]]; then
    #if "php${PHP_VERSION}" --ri phalcon | grep -qwE "phalcon => enabled"; then
    PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
    if [ ! -f "${PHPLIB_DIR}/phalcon.so" ]; then
        init_phalcon_install "$@"
    else
        warning "Phalcon extension already installed here ${PHPLIB_DIR}/phalcon.so. Installation skipped..."
    fi
else
    warning "PHP${PHP_VERSION} & FPM not found. Installation skipped..."
fi
