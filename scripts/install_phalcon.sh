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
        run git pull -q
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
    echo "Installing cPhalcon extension."

    if [[ "${PHALCON_VERSION}" == "latest" ]]; then
        PHALCON_VERSION="master"
    fi

    CPHALCON_SOURCE="https://github.com/phalcon/cphalcon/archive/v${PHALCON_VERSION}.tar.gz"

    if curl -sLI "${CPHALCON_SOURCE}" | grep -q "HTTP/[.12]* [2].."; then
        run wget -q -O "cphalcon-${PHALCON_VERSION}.tar.gz" "${CPHALCON_SOURCE}" && \
        run tar -zxf "cphalcon-${PHALCON_VERSION}.tar.gz" && \
        #run rm -f "cphalcon-${PHALCON_VERSION}.tar.gz" && \
        run cd "cphalcon-${PHALCON_VERSION}/build"
    elif curl -sLI "https://raw.githubusercontent.com/phalcon/cphalcon/${PHALCON_VERSION}/README.md" \
        | grep -q "HTTP/[.12]* [2].."; then

        # Clone repository.
        if [ ! -d cphalcon ]; then
            run git clone -q https://github.com/phalcon/cphalcon.git && \
            run cd cphalcon && \
            run git checkout "${PHALCON_VERSION}" && \
            run cd build
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

        if version_older_than "${PHALCON_VERSION}" "3.4.9"; then
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

    # Back to the install dir.
    run cd "${CURRENT_DIR}"
}

# Enable Phalcon extension.
function enable_phalcon() {
    # PHP version.
    local PHPv=${1}

    if "${DRYRUN}"; then
        echo "Enabling Phalcon PHP ${PHPv} extension in dryrun mode."
    else
        # Optimize Phalcon PHP extension.
        if [ -d "/etc/php/${PHPv}/mods-available/" ]; then
            # Add the extension to php.ini.
            local PHPLIB_DIR && \
                PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
            if [[ -f "${PHPLIB_DIR}/phalcon.so" && ! -f "/etc/php/${PHPv}/mods-available/phalcon.ini" ]]; then
                echo "Enabling Phalcon extension for PHP ${PHPv}..."

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
                success "php${PHPv}-fpm restarted successfully."
            elif [[ -n $(command -v "php${PHPv}") ]]; then
                run systemctl start "php${PHPv}-fpm"

                if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                    success "php${PHPv}-fpm started successfully."
                else
                    error "Something went wrong with php${PHPv}-fpm installation."
                fi
            fi

        else
            info "It seems that PHP ${PHPv} not yet installed. Please install it before!"
        fi
    fi
}

# Init Phalcon installer.
function init_phalcon_install() {
    local PHPv=""
    local PHALCON_VERSION=""
    local PHALCON_INSTALLER=""

    OPTS=$(getopt -o p:I:P:ir \
      -l php-version:,phalcon-installer:,phalcon-version:,install,remove \
      -n "init_phalcon_install" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -p|--php-version) shift
                OPT_PHP_VERSION="${1}"
                shift
            ;;
            -P|--phalcon-version) shift
                OPT_PHALCON_VERSION="${1}"
                shift
            ;;
            -I|--phalcon-installer) shift
                OPT_PHALCON_INSTALLER="${1}"
                shift
            ;;
            -i|--install) shift
                #ACTION="install"
            ;;
            -r|--remove) shift
                #ACTION="remove"
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

    # Phalcon installer.
    if [ -n "${OPT_PHALCON_INSTALLER}" ]; then
        PHP_PHALCON_INSTALLER=${OPT_PHALCON_INSTALLER}
    else
        PHP_PHALCON_INSTALLER=${PHP_PHALCON_INSTALLER:-"source"}
    fi

    # Phalcon version.
    if [ -n "${OPT_PHALCON_VERSION}" ]; then
        PHP_PHALCON_VERSION=${OPT_PHALCON_VERSION}
    else
        PHP_PHALCON_VERSION=${PHP_PHALCON_VERSION:-"4.0.2"}
    fi

    # PHP version.
    if [ -n "${OPT_PHP_VERSION}" ]; then
        PHP_VERSION=${OPT_PHP_VERSION}
    else
        PHP_VERSION=${PHP_VERSION:-"7.3"}
    fi


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
    fi

    # Check PHP.
    if [[ -z $(command -v "php${PHPv}") ]]; then
        error "PHP ${PHPv} & FPM could not be found."
        INSTALL_PHALCON="n"
    fi

    if [[ ${INSTALL_PHALCON} == Y* || ${INSTALL_PHALCON} == y* ]]; then
        # Select installer.
        if "${AUTO_INSTALL}"; then
            if [ -z "${PHALCON_INSTALLER}" ]; then
                SELECTED_INSTALLER=${PHP_PHALCON_INSTALLER}
            fi
        else
            echo ""
            echo "Available Phalcon installation method:"
            echo "  1). Install from Repository (repo)"
            echo "  2). Compile from Source (source)"
            echo "------------------------------------------------"
            [ -n "${PHP_PHALCON_INSTALLER}" ] && \
            info "Pre-defined selected installer is: ${PHP_PHALCON_INSTALLER}"

            while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && ${SELECTED_INSTALLER} != "none" && \
                ${SELECTED_INSTALLER} != "repo" && ${SELECTED_INSTALLER} != "source" ]]; do
                read -rp "Select [source, repo] or an option [1-2]: " -e SELECTED_INSTALLER
            done
        fi

        # Select Phalcon version.
        if "${AUTO_INSTALL}"; then
            if [ -z "${SELECTED_PHALCON}" ]; then
                SELECTED_PHALCON=${PHP_PHALCON_VERSION}
            fi
        else
            echo ""
            echo "Which version of cPhalcon to be installed?"
            echo "Supported cPhalcon versions:"
            echo "  1). cPhalcon 3.4.x (Supported PHP versions: 5.6, 7.0, 7.1) [EOL]"
            echo "  2). cPhalcon 4.0.x (Supported PHP versions: 7.2, 7.3, 7.4) [Latest]"
            echo "Check the cPhalcon available version from their Github release page!"
            echo "-----------------------------------------------------------------------"
            [ -n "${PHP_PHALCON_VERSION}" ] && \
            info "Pre-defined selected cPhalcon version is: ${PHP_PHALCON_VERSION}"

            while [[ ${SELECTED_PHALCON} != "1" && ${SELECTED_PHALCON} != "2" && \
                ${SELECTED_PHALCON} != "3.4.x" && ${SELECTED_PHALCON} != "4.0.x" && \
                $(curl -sLI "https://github.com/phalcon/cphalcon/archive/v${SELECTED_PHALCON}.tar.gz" | grep "HTTP/[.12]* [2]..") == "" && \
                $(curl -sLI "https://raw.githubusercontent.com/phalcon/cphalcon/${SELECTED_PHALCON}/README.md" | grep "HTTP/[.12]* [2]..") == ""
            ]]; do
                read -rp "Select a cPhalcon version [3.4.x, 4.0.x] or an option [1-2]: " -e SELECTED_PHALCON
            done
        fi

        case "${SELECTED_PHALCON}" in
            1|"3.4.x")
                PHALCON_VERSION="3.4.5" # The latest version from Phalcon 3 branch.
            ;;
            2|"4.0.x")
                PHALCON_VERSION="4.0.6" # The latest version from Phalcon 4 branch.
            ;;
            *)
                PHALCON_VERSION=${SELECTED_PHALCON}
            ;;
        esac

        # Select PHP version.
        if "${AUTO_INSTALL}"; then
            if [ -z "${SELECTED_PHP}" ]; then
                SELECTED_PHP=${PHP_VERSION}
            fi
        else
            echo ""
            echo "Which version of PHP to install Phalcon?"
            echo "Supported PHP versions:"
            echo "  1). PHP 5.6 (EOL)"
            echo "  2). PHP 7.0 (EOL)"
            echo "  3). PHP 7.1 (SFO)"
            echo "  4). PHP 7.2 (Stable)"
            echo "  5). PHP 7.3 (Stable)"
            echo "  6). PHP 7.4 (Latest stable)"
            echo "  7). All available versions"
            echo "--------------------------------------------"
            [ -n "${PHP_VERSION}" ] && \
            info "Pre-defined selected version is: ${PHP_VERSION}"

            while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" && ${SELECTED_PHP} != "3" && \
                    ${SELECTED_PHP} != "4" && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" && \
                    ${SELECTED_PHP} != "7" && ${SELECTED_PHP} != "5.6" && ${SELECTED_PHP} != "7.0" && \
                    ${SELECTED_PHP} != "7.1" && ${SELECTED_PHP} != "7.2" && ${SELECTED_PHP} != "7.3" && \
                    ${SELECTED_PHP} != "7.4" && ${SELECTED_PHP} != "all" ]]; do
                read -rp "Select a PHP version or an option [1-7]: " -e SELECTED_PHP
            done
        fi

        case ${SELECTED_PHP} in
            1|"5.6")
                PHPv="5.6"
            ;;
            2|"7.0")
                PHPv="7.0"
            ;;
            3|"7.1")
                PHPv="7.1"
            ;;
            4|"7.2")
                PHPv="7.2"
            ;;
            5|"7.3")
                PHPv="7.3"
            ;;
            6|"7.4")
                PHPv="7.4"
            ;;
            7|"all")
                PHPv="5.6 7.0 7.1 7.2 7.3 7.4"
            ;;
            *)
                PHPv="unsupported"
            ;;
        esac

        local SUPPORTED_PHP
        local PHP_PHALCON_PKG
        if version_older_than "${PHALCON_VERSION}" "3.4.6"; then
            SUPPORTED_PHP="5.6 7.0 7.1"
            PHP_PHALCON_PKG="php-phalcon3"
        elif version_older_than "3.99.99" "${PHALCON_VERSION}"; then
            SUPPORTED_PHP="7.2 7.3 7.4"
            PHP_PHALCON_PKG="php-phalcon4"
        else
            SUPPORTED_PHP=""
            PHP_PHALCON_PKG=""
        fi

        # Begin install Phalcon.
        if [[ ${PHPv} != "unsupported" && -n "${SUPPORTED_PHP}" ]]; then
            case ${SELECTED_INSTALLER} in
                1|"repo")
                    echo "Installing Phalcon framework from repository..."

                    if hash apt 2>/dev/null; then
                        if [[ "${SELECTED_PHP}" != "all" && "${SELECTED_PHP}" != "7" ]]; then
                            if [[ -n $(command -v "php${PHPv}") ]]; then
                                PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
                                if [[ ! -f "${PHPLIB_DIR}/phalcon.so" ]]; then
                                    run apt install -qq -y "php-psr" "${PHP_PHALCON_PKG}"
                                    enable_phalcon "${PHPv}"
                                else
                                    error "PHP ${PHPv} Phalcon extension already installed here ${PHPLIB_DIR}/phalcon.so."
                                fi
                            else
                                error "PHP ${PHPv} not found, Phalcon installation cancelled."
                            fi
                        else
                            # Install Phalcon on all supported PHP.
                            for PHPv in ${SUPPORTED_PHP}; do
                                if [[ -n $(command -v "php${PHPv}") ]]; then
                                    PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
                                    if [[ ! -f "${PHPLIB_DIR}/phalcon.so" ]]; then
                                        run apt install -qq -y "php${PHPv}-psr" "php${PHPv}-phalcon"
                                        enable_phalcon "${PHPv}"
                                    else
                                        error "PHP ${PHPv} Phalcon extension already installed here ${PHPLIB_DIR}/phalcon.so."
                                    fi
                                else
                                    error "PHP ${PHPv} not found, Phalcon installation cancelled."
                                fi
                            done
                        fi
                    else
                        fail "Unable to install Phalcon extension, this GNU/Linux distribution is not supported."
                    fi
                ;;

                2|"source")
                    echo "Installing Phalcon framework from source..."
    
                    # Install & enable Phalcon extension.
                    if [[ "${SELECTED_PHP}" != "all" && "${SELECTED_PHP}" != "7" ]]; then
                        if [[ -n $(command -v "php${PHPv}") ]]; then
                            PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
                            if [[ ! -f "${PHPLIB_DIR}/phalcon.so" ]]; then
                                install_phalcon "${PHALCON_VERSION}" "${PHPv}"
                                enable_phalcon "${PHPv}"
                            else
                                error "PHP ${PHPv} Phalcon extension already installed here ${PHPLIB_DIR}/phalcon.so."
                            fi
                        else
                            error "PHP ${PHPv} not found, Phalcon installation cancelled."
                        fi
                    else
                        # Install Phalcon on all supported PHP.
                        for PHPv in ${SUPPORTED_PHP}; do
                            if [[ -n $(command -v "php${PHPv}") ]]; then
                                PHPLIB_DIR=$("php-config${PHPv}" | grep -wE "\--extension-dir" | cut -d'[' -f2 | cut -d']' -f1)
                                if [[ ! -f "${PHPLIB_DIR}/phalcon.so" ]]; then
                                    install_phalcon "${PHALCON_VERSION}" "${PHPv}"
                                    enable_phalcon "${PHPv}"
                                else
                                    error "PHP ${PHPv} Phalcon extension already installed here ${PHPLIB_DIR}/phalcon.so."
                                fi
                            else
                                error "PHP ${PHPv} not found, Phalcon installation cancelled."
                            fi
                        done
                    fi
                ;;

                *)
                    # Skip installation.
                    error "Installer method not supported, Phalcon installation skipped."
                ;;
            esac
        else
            error "Your selected Phalcon ${PHALCON_VERSION} for PHP ${PHPv} is not supported."
        fi
    else
        info "Phalcon PHP framework installation skipped."
    fi
}

echo "[Phalcon Framework (PHP Extension) Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_phalcon_install "$@"
