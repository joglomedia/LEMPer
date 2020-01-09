#!/usr/bin/env bash

# Phalcon & Zephir Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 02/11/2019
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
    local PHALCON_VERSION=${1}
    local PHPv=${2}

    PHP_BIN=$(command -v "php${PHPv}")
    PHPIZE_BIN=$(command -v "phpize${PHPv}")
    PHPCONFIG_BIN=$(command -v "php-config${PHPv}")
    PHPCOMPOSER_BIN=$(command -v composer)
    PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)

    local CURRENT_DIR && \
    CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}"

    # Install Zephir from source.
    if "${AUTO_INSTALL}"; then
        if [[ ${PHP_ZEPHIR_INSTALL} == y* || ${PHP_ZEPHIR_INSTALL} == true ]]; then
            INSTALL_ZEPHIR="y"
        else
            INSTALL_ZEPHIR="n"
        fi
    else
        while [[ ${INSTALL_ZEPHIR} != "y" && ${INSTALL_ZEPHIR} != "n" ]]; do
            read -rp "Install Zephir interpreter? [y/n]: " -i n -e INSTALL_ZEPHIR
        done
    fi

    if [[ "${INSTALL_ZEPHIR}" == Y* || "${INSTALL_ZEPHIR}" == y* ]]; then
        # Install Zephir parser.
        echo "Installing Zephir parser..."

        ZEPHIR_PARSER_BRANCH=$(git ls-remote https://github.com/phalcon/php-zephir-parser v1.* | sort -t/ -k3 -Vr | head -n1 | awk -F/ '{ print $NF }')
        run git clone --depth=1 --branch="${ZEPHIR_PARSER_BRANCH}" -q https://github.com/phalcon/php-zephir-parser.git && \
        run cd php-zephir-parser

        if [ -n "${PHPv}" ]; then
            run "${PHPIZE_BIN}" && \
            run ./configure --with-php-config="${PHPCONFIG_BIN}"
        else
            run /usr/bin/phpize && \
            run ./configure
        fi

        run make && \
        run make install && \
        run cd ../

        # Install Zephir.
        echo "Installing Zephir lang..."

        if [ -n "${PHPCOMPOSER_BIN}" ]; then
            run "${PHP_BIN}" "${PHPCOMPOSER_BIN}" global require phalcon/zephir
        else
            ZEPHIR_BRANCH=${PHP_ZEPHIR_VERSION:-$(git ls-remote https://github.com/phalcon/zephir 0.12.* | sort -t/ -k3 -Vr | head -n1 | awk -F/ '{ print $NF }')}
            run git clone --depth=1 --branch="${ZEPHIR_BRANCH}" -q https://github.com/phalcon/zephir.git && \
            run cd zephir && \
            run "${PHP_BIN}" "${PHPCOMPOSER_BIN}" install && \
            run cd ../
        fi
    fi

    # Install PSR extension.
    echo "PSR extension is required by Phalcon, install it first."

    if [ ! -d php-psr ]; then
        run git clone https://github.com/jbboehr/php-psr.git && \
        run cd php-psr
    else
        run cd php-psr && \
        run git pull
    fi
    run "${PHPIZE_BIN}" && \
    run ./configure --with-php-config="${PHPCONFIG_BIN}" && \
    run make && \
    #run make test && \
    run make install && \
    run cd ../

    if [ -f "${PHPLIB_DIR}/psr.so" ]; then
        success "PSR extension sucessfully installed."
        run chmod 0644 "${PHPLIB_DIR}/psr.so"
    else
        error "PSR extension installation failed."
    fi

    # Download cPhalcon source.
    echo -e "\nInstalling cPhalcon extension."

    if [[ "${PHALCON_VERSION}" == "latest" ]]; then
        PHALCON_VERSION="master"
    fi

    CPHALCON_DOWNLOAD_URL="https://github.com/phalcon/cphalcon/archive/v${PHALCON_VERSION}.tar.gz"

    if curl -sL --head "${CPHALCON_DOWNLOAD_URL}" | grep -q "HTTP/[.12]* [2].."; then
        run wget -q -O "cphalcon-${PHALCON_VERSION}.tar.gz" "${CPHALCON_DOWNLOAD_URL}" && \
        run tar -zxf "cphalcon-${PHALCON_VERSION}.tar.gz" && \
        #run rm -f "cphalcon-${PHALCON_VERSION}.tar.gz" && \
        run cd "cphalcon-${PHALCON_VERSION}/build"
    elif curl -s --head "https://raw.githubusercontent.com/phalcon/cphalcon/${PHALCON_VERSION}/README.md" \
        | grep -q "HTTP/[.12]* [2].."; then

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
            run ./install --phpize "${PHPIZE_BIN}" --php-config "${PHPCONFIG_BIN}"
        else
            run ./install
        fi
    fi

    if [ -f "${PHPLIB_DIR}/phalcon.so" ]; then
        success "Phalcon extension sucessfully installed."
        run chmod 0644 "${PHPLIB_DIR}/phalcon.so"

        # Install Phalcon Devtools
        PHALCON_DIR="/home/${LEMPER_USERNAME}/.phalcon"
        run mkdir -p "${PHALCON_DIR}"

        if version_older_than "${PHALCON_VERSION}" "3.9.9"; then
            [ ! -d "${PHALCON_DIR}/devtools-3.x" ] && \
            run "${PHP_BIN}" "${PHPCOMPOSER_BIN}" create-project --prefer-dist phalcon/devtools:~3.4 "${PHALCON_DIR}/devtools-3.x"
            local PDEVTOOLSPATH="${PHALCON_DIR}/devtools-3.x"
        else
            [ ! -d "${PHALCON_DIR}/devtools-4.x" ] && \
            run "${PHP_BIN}" "${PHPCOMPOSER_BIN}" create-project --prefer-dist phalcon/devtools:~4.0 "${PHALCON_DIR}/devtools-4.x"
            local PDEVTOOLSPATH="${PHALCON_DIR}/devtools-4.x"
        fi

        local LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
        for xFILE in "/home/${LEMPER_USERNAME}/.bashrc" "/home/${LEMPER_USERNAME}/.bash_profile" "/home/${LEMPER_USERNAME}/.profile"; do
            cat >> "${xFILE}" <<EOL

if [ -d "${PDEVTOOLSPATH}" ]; then
    export PTOOLSPATH="${PDEVTOOLSPATH}"
    export PATH="\$PATH:${PDEVTOOLSPATH}"
fi
EOL
        done
    else
        error "Phalcon framework installation failed."
    fi

    #run service "php${PHPv}-fpm" restart
    run systemctl restart "php${PHPv}-fpm"

    run cd "${CURRENT_DIR}"
}

# Enable Phalcon extension.
function enable_phalcon() {
    # PHP version.
    local PHPv=${1}

    if "${DRYRUN}"; then
        echo "Enabling Phalcon PHP${PHPv} extension in dryrun mode."
    else
        # Optimize Phalcon PHP extension.
        if [ -d "/etc/php/${PHPv}/mods-available/" ]; then
            # Add the extension to php.ini.
            local PHPLIB_DIR && \
                PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
            if [[ -f "${PHPLIB_DIR}/phalcon.so" && ! -f "/etc/php/${PHPv}/mods-available/phalcon.ini" ]]; then
                echo "Enabling Phalcon extension for PHP${PHPv}..."

                # Phalcon requires PSR extension, enable first.
                run bash -c "echo 'extension=psr.so' > /etc/php/${PHPv}/mods-available/psr.ini"

                if [ ! -s "/etc/php/${PHPv}/fpm/conf.d/20-psr.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/psr.ini" "/etc/php/${PHPv}/fpm/conf.d/20-psr.ini"
                fi

                if [ ! -s "/etc/php/${PHPv}/cli/conf.d/20-psr.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/psr.ini" "/etc/php/${PHPv}/cli/conf.d/20-psr.ini"
                fi

                # Enable Phalcon extension.
                run bash -c "echo 'extension=phalcon.so' > /etc/php/${PHPv}/mods-available/phalcon.ini"

                if [ ! -s "/etc/php/${PHPv}/fpm/conf.d/50-phalcon.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/phalcon.ini" "/etc/php/${PHPv}/fpm/conf.d/50-phalcon.ini"
                fi

                if [ ! -s "/etc/php/${PHPv}/cli/conf.d/50-phalcon.ini" ]; then
                    run ln -s "/etc/php/${PHPv}/mods-available/phalcon.ini" "/etc/php/${PHPv}/cli/conf.d/50-phalcon.ini"
                fi
            fi

            # Reload PHP-FPM service.
            if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                run systemctl reload "php${PHPv}-fpm"
                success "PHP${PHPv}-FPM restarted successfully."
            elif [[ -n $(command -v "php${PHPv}") ]]; then
                run systemctl start "php${PHPv}-fpm"

                if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                    success "PHP${PHPv}-FPM started successfully."
                else
                    error "Something wrong with PHP${PHPv} & FPM installation."
                fi
            fi

        else
            info "It seems that PHP${PHPv} not yet installed. Please install it before!"
        fi
    fi
}

# Init Phalcon installer.
function init_phalcon_install() {
    local PHPv=""
    local PHALCON_VERSION=""

    OPTS=$(getopt -o p:v: \
      -l php-version:,version: \
      -n "install_phalcon" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -p|--php-version) shift
                PHPv="${1}"
                shift
            ;;
            -v|--version) shift
                PHALCON_VERSION="${1}"
                shift
            ;;
            --) shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    # PHP version.
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
    fi

    # Phalcon version.
    if [ -z "${PHALCON_VERSION}" ]; then
        PHALCON_VERSION=${PHP_PHALCON_VERSION:-"3.4.5"}
    fi

    local SELECTED_INSTALLER=""

    if "${AUTO_INSTALL}"; then
        if [[ -z "${PHP_PHALCON_INSTALLER}" || "${PHP_PHALCON_INSTALLER}" == "none" ]]; then
            INSTALL_PHALCON="n"
        else
            INSTALL_PHALCON="y"
            SELECTED_INSTALLER=${PHP_PHALCON_INSTALLER}
        fi
    else
        while [[ "${INSTALL_PHALCON}" != "y" && "${INSTALL_PHALCON}" != "n" ]]; do
            read -rp "Do you want to install Phalcon PHP framework? [y/n]: " -e INSTALL_PHALCON
        done
        echo ""
    fi

    # Check PHP.
    if [[ -z $(command -v "php${PHPv}") ]]; then
        error "PHP${PHPv} & FPM could not be found."
        INSTALL_PHALCON="n"
    fi

    if [[ ${INSTALL_PHALCON} == Y* || ${INSTALL_PHALCON} == y* ]]; then
        echo "Available Phalcon installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "--------------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
            ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done

        PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
        if [ ! -f "${PHPLIB_DIR}/phalcon.so" ]; then
            case ${SELECTED_INSTALLER} in
                1|"repo")
                    echo "Installing Phalcon framework from repository..."

                    if hash apt 2>/dev/null; then
                        run apt install -qq -y "php${PHPv}-psr" "php${PHPv}-phalcon"
                    else
                        fail "Unable to install Phalcon extension, this GNU/Linux distribution is not supported."
                    fi
                ;;
                2|"source")
                    echo "Installing Phalcon framework from source..."
                    install_phalcon "${PHALCON_VERSION}" "${PHPv}"
                ;;
                *)
                    # Skip installation.
                    error "Installer method not supported. Phalcon installation skipped."
                ;;
            esac

            # Enable Phalcon extension.
            if [ "${PHPv}" != "all" ]; then
                enable_phalcon "${PHPv}"
            else
                enable_phalcon "5.6"
                enable_phalcon "7.0"
                enable_phalcon "7.1"
                enable_phalcon "7.2"
                enable_phalcon "7.3"
                enable_phalcon "7.4"
            fi
        else
            info "Phalcon extension already installed here ${PHPLIB_DIR}/phalcon.so. Installation skipped..."
        fi
    else
        info "Phalcon PHP framework installation skipped..."
    fi
}

echo "[Phalcon Framework (PHP Extension) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_phalcon_install "$@"
