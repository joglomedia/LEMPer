#!/usr/bin/env bash

# PHP Loader Installer
# Min. Requirement  : GNU/Linux Ubuntu 16.04 & 16.04
# Last Build        : 03/04/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.3.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

##
# Install ionCube Loader.
#
function install_ioncube() {
    echo "Installing ionCube PHP loader..."

    # Delete old loaders file.
    if [ -d /usr/lib/php/loaders/ioncube ]; then
        echo "Removing old/existing ionCube PHP loader..."
        run rm -fr /usr/lib/php/loaders/ioncube
    fi

    local CURRENT_DIR && CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}"

    echo "Download latest ionCube PHP loader..."

    ARCH=${ARCH:-$(uname -p)}
    if [[ "${ARCH}" == "x86_64" ]]; then
        run wget -q "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86-64.tar.gz
        run rm -f ioncube_loaders_lin_x86-64.tar.gz
    else
        run wget -q "http://downloads2.ioncube.com/loader_downloads/ioncube_loaders_lin_x86.tar.gz"
        run tar -xzf ioncube_loaders_lin_x86.tar.gz
        run rm -f ioncube_loaders_lin_x86.tar.gz
    fi

    run mv -f ioncube /usr/lib/php/loaders/
    run cd "${CURRENT_DIR}"
}

##
# Enable ionCube Loader.
#
function enable_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Enable ionCube PHP ${PHPv} loader"

    if "${DRYRUN}"; then
        info "ionCube PHP ${PHPv} enabled in dryrun mode."
    else
        if [[ -f "/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so" && -n $(command -v "php${PHPv}") ]]; then
            cat > "/etc/php/${PHPv}/mods-available/ioncube.ini" <<EOL
[ioncube]
zend_extension=/usr/lib/php/loaders/ioncube/ioncube_loader_lin_${PHPv}.so
EOL

            if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/ioncube.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini"
            fi
            if [ ! -f "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/ioncube.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini"
            fi

            # Restart PHP-fpm server.
            if "${DRYRUN}"; then
                info "php${PHPv}-fpm reloaded in dry run mode."
            else
                if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                    run systemctl reload "php${PHPv}-fpm"
                    success "php${PHPv}-fpm reloaded successfully."
                elif [[ -n $(command -v "php${PHPv}") ]]; then
                    run systemctl start "php${PHPv}-fpm"

                    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                        success "php${PHPv}-fpm started successfully."
                    else
                        error "Something goes wrong with PHP ${PHPv} & FPM installation."
                    fi
                fi
            fi
        else
            error "PHP ${PHPv} or ionCube loader not found."
        fi
    fi
}

##
# Disable ionCube Loader.
#
function disable_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Disabling ionCube PHP ${PHPv} loader"

    run unlink "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini"
    run unlink "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini"
}

##
# Remove ionCube Loader.
#
function remove_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Uninstalling ionCube PHP ${PHPv} loader..."

    if [[ -f "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini" || \
        -f "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini" ]]; then
        disable_ioncube "${PHPv}"
    fi

    if [ -d /usr/lib/php/loaders/ioncube ]; then
        run rm -fr /usr/lib/php/loaders/ioncube
        success "ionCube PHP ${PHPv} loader has been removed."
    else
        info "ionCube PHP ${PHPv} loader couldn't be found."
    fi
}

##
# Install SourceGuardian Loader.
#
function install_sourceguardian() {
    echo "Installing SourceGuardian PHP loader..."

    # Delete old loaders file.
    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        echo "Remove old/existing loader..."
        run rm -fr /usr/lib/php/loaders/sourceguardian
    fi

    if [ ! -d "${BUILD_DIR}/sourceguardian" ]; then
        run mkdir -p "${BUILD_DIR}/sourceguardian"
    fi

    local CURRENT_DIR && CURRENT_DIR=$(pwd)
    run cd "${BUILD_DIR}/sourceguardian"

    echo "Download latest SourceGuardian PHP loader..."

    ARCH=${ARCH:-$(uname -p)}
    if [[ "${ARCH}" == "x86_64" ]]; then
        run wget -q "http://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz"
        run tar -xzf loaders.linux-x86_64.tar.gz
        run rm -f loaders.linux-x86_64.tar.gz
    else
        run wget -q "http://www.sourceguardian.com/loaders/download/loaders.linux-x86.tar.gz"
        run tar -xzf loaders.linux-x86.tar.gz
        run rm -f loaders.linux-x86.tar.gz
    fi

    run cd "${CURRENT_DIR}"
    run mv -f "${BUILD_DIR}/sourceguardian" /usr/lib/php/loaders/
}

##
# Enable SourceGuardian Loader.
#
function enable_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Enable SourceGuardian PHP ${PHPv} loader..."

    if "${DRYRUN}"; then
        info "SourceGuardian PHP ${PHPv} enabled in dryrun mode."
    else
        if [[ -f "/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin" && -n $(command -v "php${PHPv}") ]]; then
            cat > "/etc/php/${PHPv}/mods-available/sourceguardian.ini" <<EOL
[sourceguardian]
zend_extension=/usr/lib/php/loaders/sourceguardian/ixed.${PHPv}.lin
EOL

            if [ ! -f "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/sourceguardian.ini" \
                    "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini"
            fi

            if [ ! -f "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini" ]; then
                run ln -s "/etc/php/${PHPv}/mods-available/sourceguardian.ini" \
                    "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini"
            fi

            # Restart PHP-fpm server.
            if "${DRYRUN}"; then
                info "php${PHPv}-fpm reloaded in dry run mode."
            else
                if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                    run systemctl reload "php${PHPv}-fpm"
                    success "php${PHPv}-fpm reloaded successfully."
                elif [[ -n $(command -v "php${PHPv}") ]]; then
                    run systemctl start "php${PHPv}-fpm"

                    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
                        success "php${PHPv}-fpm started successfully."
                    else
                        error "Something goes wrong with PHP ${PHPv} & FPM installation."
                    fi
                fi
            fi
        else
            error "PHP ${PHPv} or SourceGuardian loader not found."
        fi
    fi
}

##
# Disable SourceGuardian Loader.
#
function disable_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Disabling SourceGuardian PHP ${PHPv} loader"

    run unlink "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini"
    run unlink "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini"
}

##
# Remove SourceGuardian Loader.
#
function remove_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.4"}
    fi

    echo "Uninstalling SourceGuardian PHP ${PHPv} loader..."

    if [[ -f "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini" || \
        -f "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini" ]]; then
        disable_sourceguardian "${PHPv}"
    fi

    if [ -d /usr/lib/php/loaders/sourceguardian ]; then
        run rm -fr /usr/lib/php/loaders/sourceguardian
        success "SourceGuardian PHP ${PHPv} loader has been removed."
    else
        info "SourceGuardian PHP ${PHPv} loader couldn't be found."
    fi
}


##
# Initialize PHP Loader Installation.
#
function init_phploader_install() {
    local SELECTED_PHP=""
    local SELECTED_PHPLOADER=""

    OPTS=$(getopt -o p:l:ir \
      -l php-version:,php-loader:,install,remove \
      -n "init_phploader_install" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -p|--php-version) shift
                OPT_PHP_VERSION="${1}"
                shift
            ;;
            -l|--php-loader) shift
                OPT_PHP_LOADER="${1}"
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

    if [ -n "${OPT_PHP_VERSION}" ]; then
        PHP_VERSION=${OPT_PHP_VERSION}
    else
        PHP_VERSION=${PHP_VERSION:-"7.4"}
    fi

    if [ -n "${OPT_PHP_LOADER}" ]; then
        PHP_LOADER=${OPT_PHP_LOADER}
    else
        PHP_LOADER=${PHP_LOADER:-""}
    fi

    if "${AUTO_INSTALL}"; then
        # PHP Loader.
        if [[ -z "${PHP_LOADER}" || "${PHP_LOADER}" == "none" ]]; then
            DO_INSTALL_PHPLOADER="n"
        else
            DO_INSTALL_PHPLOADER="y"
            SELECTED_PHPLOADER=${PHP_LOADER}
        fi
    else
        while [[ "${DO_INSTALL_PHPLOADER}" != "y" && "${DO_INSTALL_PHPLOADER}" != "n" ]]; do
            read -rp "Do you want to install PHP Loader? [y/n]: " -e DO_INSTALL_PHPLOADER
        done
    fi

    if [[ ${DO_INSTALL_PHPLOADER} == y* || ${INSTALL_PHPLOADER} == true ]]; then
        # Select loader.
        if ! "${AUTO_INSTALL}"; then
            echo ""
            echo "Available PHP Loaders:"
            echo "  1). ionCube Loader (latest stable)"
            echo "  2). SourceGuardian (latest stable)"
            echo "  3). All loaders (ionCube, SourceGuardian)"
            echo "--------------------------------------------"

            while [[ ${SELECTED_PHPLOADER} != "1" && ${SELECTED_PHPLOADER} != "2" && \
                ${SELECTED_PHPLOADER} != "3" && ${SELECTED_PHPLOADER} != "ioncube" && \
                ${SELECTED_PHPLOADER} != "sg" && ${SELECTED_PHPLOADER} != "ic" && \
                ${SELECTED_PHPLOADER} != "sourceguardian" && ${SELECTED_PHPLOADER} != "all" ]]; do
                    read -rp "Select PHP loader or an option [1-3]: " -i "${PHP_LOADER}" -e SELECTED_PHPLOADER
            done
        fi

        # Select PHP version.
        if "${AUTO_INSTALL}"; then
            if [ -z "${SELECTED_PHP}" ]; then
                SELECTED_PHP=${PHP_VERSION:-"7.3"}
            fi
        else
            echo ""
            echo "Which PHP to install the Loader?"
            echo "Supported PHP versions:"
            echo "  1). PHP 5.6 (EOL)"
            echo "  2). PHP 7.0 (EOL)"
            echo "  3). PHP 7.1 (SFO)"
            echo "  4). PHP 7.2 (Stable)"
            echo "  5). PHP 7.3 (Stable)"
            echo "  6). PHP 7.4 (Latest stable)"
            echo "  7). All available versions"
            echo "+--------------------------------------+"

            while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" && ${SELECTED_PHP} != "3" && \
                    ${SELECTED_PHP} != "4" && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" && \
                    ${SELECTED_PHP} != "7" && ${SELECTED_PHP} != "5.6" && ${SELECTED_PHP} != "7.0" && \
                    ${SELECTED_PHP} != "7.1" && ${SELECTED_PHP} != "7.2" && ${SELECTED_PHP} != "7.3" && \
                    ${SELECTED_PHP} != "7.4" && ${SELECTED_PHP} != "all" ]]; do
                read -rp "Select a PHP version or an option [1-7]: " -i "${PHP_VERSION}" -e SELECTED_PHP
            done
        fi

        local PHPv
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
                # Install all PHP version (except EOL & Beta).
                PHPv="all"
            ;;
            *)
                PHPv="unsupported"
                error "Your selected PHP version ${SELECTED_PHP} is not supported."
            ;;
        esac
    fi

    # NOT COMPLETE

    # Install PHP loader.
    if [[ "${PHPv}" != "unsupported" && ! $(version_older_than "${PHPv}" "5.6") ]]; then
        if "${AUTO_INSTALL}"; then
            # PHP Loader.
            if [ -z "${SELECTED_PHPLOADER}" ]; then
                SELECTED_PHPLOADER=${PHP_LOADER:-""}
            fi

            if [[ -z "${SELECTED_PHPLOADER}" || "${SELECTED_PHPLOADER}" == "none" ]]; then
                INSTALL_PHPLOADER="n"
            else
                INSTALL_PHPLOADER="y"
            fi
        else
            while [[ "${INSTALL_PHPLOADER}" != "y" && "${INSTALL_PHPLOADER}" != "n" ]]; do
                read -rp "Do you want to install PHP Loader? [y/n]: " -i n -e INSTALL_PHPLOADER
            done
        fi

        if [[ ${INSTALL_PHPLOADER} == Y* || ${INSTALL_PHPLOADER} == y* ]]; then
            if ! "${AUTO_INSTALL}"; then
                echo ""
                echo "Available PHP Loaders:"
                echo "  1). ionCube Loader (latest stable)"
                echo "  2). SourceGuardian (latest stable)"
                echo "  3). All loaders (ionCube, SourceGuardian)"
                echo "--------------------------------------------"

                while [[ ${SELECTED_PHPLOADER} != "1" && ${SELECTED_PHPLOADER} != "2" && \
                        ${SELECTED_PHPLOADER} != "3" && ${SELECTED_PHPLOADER} != "ioncube" && \
                        ${SELECTED_PHPLOADER} != "sg" && ${SELECTED_PHPLOADER} != "ic" && \
                        ${SELECTED_PHPLOADER} != "sourceguardian" && ${SELECTED_PHPLOADER} != "all" ]]; do
                    read -rp "Select an option [1-3]: " -i "${PHP_LOADER}" -e SELECTED_PHPLOADER
                done
            fi

            # Create loaders directory
            if [ ! -d /usr/lib/php/loaders ]; then
                run mkdir -p /usr/lib/php/loaders
            fi

            case ${SELECTED_PHPLOADER} in
                1|"ic"|"ioncube")
                    install_ioncube

                    if [ "${PHPv}" != "all" ]; then
                        enable_ioncube "${PHPv}"

                        # Required for LEMPer default PHP.
                        if [[ "${PHPv}" != "7.4" && -n $(command -v php7.4) ]]; then
                            enable_ioncube "7.4"
                        fi
                    else
                        # Install all PHP version (except EOL & Beta).
                        #enable_ioncube "5.6"
                        #enable_ioncube "7.0"
                        #enable_ioncube "7.1"
                        #enable_ioncube "7.2"
                        #enable_ioncube "7.3"
                        #enable_ioncube "7.4"

                        for PHPver in "5.6 7.0 7.1 7.2 7.3 7.4 8.0"; do
                            enable_ioncube "${PHPver}"
                        done
                    fi
                ;;
                2|"sg"|"sourceguardian")
                    install_sourceguardian

                    if [ "${PHPv}" != "all" ]; then
                        enable_sourceguardian "${PHPv}"

                        # Required for LEMPer default PHP.
                        if [[ "${PHPv}" != "7.4" && -n $(command -v php7.4) ]]; then
                            enable_sourceguardian "7.4"
                        fi
                    else
                        # Install all PHP version (except EOL & Beta).
                        #enable_sourceguardian "5.6"
                        #enable_sourceguardian "7.0"
                        #enable_sourceguardian "7.1"
                        #enable_sourceguardian "7.2"
                        #enable_sourceguardian "7.3"
                        #enable_sourceguardian "7.4"

                        for PHPver in "5.6 7.0 7.1 7.2 7.3 7.4 8.0"; do
                            enable_sourceguardian "${PHPver}"
                        done
                    fi
                ;;
                "all")
                    install_ioncube
                    install_sourceguardian

                    if [ "${PHPv}" != "all" ]; then
                        enable_ioncube "${PHPv}"
                        enable_sourceguardian "${PHPv}"

                        # Required for LEMPer default PHP
                        if [[ "${PHPv}" != "7.4" && -n $(command -v php7.4) ]]; then
                            enable_ioncube "7.4"
                            enable_sourceguardian "7.4"
                        fi
                    else
                        # Install all PHP version (except EOL & Beta).
                        #enable_ioncube "5.6"
                        #enable_ioncube "7.0"
                        #enable_ioncube "7.1"
                        #enable_ioncube "7.2"
                        #enable_ioncube "7.3"
                        #enable_ioncube "7.4"
                        #enable_ioncube "8.0"

                        #enable_sourceguardian "5.6"
                        #enable_sourceguardian "7.0"
                        #enable_sourceguardian "7.1"
                        #enable_sourceguardian "7.2"
                        #enable_sourceguardian "7.3"
                        #enable_sourceguardian "7.4"
                        #enable_sourceguardian "8.0"

                        for PHPver in "5.6 7.0 7.1 7.2 7.3 7.4 8.0"; do
                            enable_ioncube "${PHPver}"
                            enable_sourceguardian "${PHPver}"
                        done
                    fi
                ;;
                *)
                    info "Your selected PHP loader ${SELECTED_PHPLOADER} is not supported yet."
                ;;
            esac
        else
            info "${SELECTED_PHPLOADER^} PHP ${PHPv} loader installation skipped."
        fi
    fi
}

echo "[PHP Loaders Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_phploader_install "$@"
