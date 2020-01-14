#!/usr/bin/env bash

# PHP Loader Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 12/01/2020
# Author            : ESLabs.ID (eslabs.id@gmail.com)
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
# Disable ionCube Loader.
#
function disable_ioncube() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
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
        PHPv=${PHP_VERSION:-"7.3"}
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
# Disable SourceGuardian Loader.
#
function disable_sourceguardian() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${PHP_VERSION:-"7.3"}
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
        PHPv=${PHP_VERSION:-"7.3"}
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
# Initialize PHP Loader removal.
#
function init_phploader_removal() {
    local SELECTED_PHP=""
    local SELECTED_PHPLOADER=""

    OPTS=$(getopt -o p:l:ir \
      -l php-version:,loader:,install,remove \
      -n "init_phploader_install" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -p|--php-version) shift
                SELECTED_PHP="${1}"
                shift
            ;;
            -l|--loader) shift
                SELECTED_PHPLOADER="${1}"
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

    if "${AUTO_INSTALL}"; then
        if [ -z "${SELECTED_PHP}" ]; then
            SELECTED_PHP=${PHP_VERSION:-"7.3"}
        fi
    else
        echo "Which version of PHP to be installed?"
        echo "Supported PHP version:"
        echo "  1). PHP 5.6 (EOL)"
        echo "  2). PHP 7.0 (EOL)"
        echo "  3). PHP 7.1 (SFO)"
        echo "  4). PHP 7.2 (Stable)"
        echo "  5). PHP 7.3 (Latest stable)"
        echo "  6). PHP 7.4 (Beta)"
        echo "  7). All available versions"
        echo "+--------------------------------------+"

        while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" && ${SELECTED_PHP} != "3" && \
            ${SELECTED_PHP} != "4" && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" && \
            ${SELECTED_PHP} != "7" && ${SELECTED_PHP} != "5.6" && ${SELECTED_PHP} != "7.0" && \
            ${SELECTED_PHP} != "7.1" && ${SELECTED_PHP} != "7.2" && ${SELECTED_PHP} != "7.3" && \
            ${SELECTED_PHP} != "7.4" && ${SELECTED_PHP} != "all"
        ]]; do
            read -rp "Select a PHP version or an option [1-7]: " -e SELECTED_PHP
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
                read -rp "Do you want to remove PHP Loaders? [y/n]: " -i n -e INSTALL_PHPLOADER
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
                    ${SELECTED_PHPLOADER} != "sourceguardian" && ${SELECTED_PHPLOADER} != "all"
                ]]; do
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
                        if [[ "${PHPv}" != "7.3" && -n $(command -v "php${DEFAULT_PHP_VERSION}") ]]; then
                            enable_ioncube "7.3"
                        fi
                    else
                        # Install all PHP version (except EOL & Beta).
                        enable_ioncube "5.6"
                        enable_ioncube "7.0"
                        enable_ioncube "7.1"
                        enable_ioncube "7.2"
                        enable_ioncube "7.3"
                        enable_ioncube "7.4"
                    fi
                ;;

                2|"sg"|"sourceguardian")
                    install_sourceguardian

                    if [[ "${PHPv}" != "all" ]]; then
                        enable_sourceguardian "${PHPv}"

                        # Required for LEMPer default PHP.
                        if [[ "${PHPv}" != "7.3" && -n $(command -v php7.3) ]]; then
                            enable_sourceguardian "7.3"
                        fi
                    else
                        # Install all PHP version (except EOL & Beta).
                        enable_sourceguardian "5.6"
                        enable_sourceguardian "7.0"
                        enable_sourceguardian "7.1"
                        enable_sourceguardian "7.2"
                        enable_sourceguardian "7.3"
                        enable_sourceguardian "7.4"
                    fi
                ;;

                "all")
                    install_ioncube
                    install_sourceguardian

                    if [ "${PHPv}" != "all" ]; then
                        enable_ioncube "${PHPv}"
                        enable_sourceguardian "${PHPv}"

                        # Required for LEMPer default PHP
                        if [[ "${PHPv}" != "7.3" && -n $(command -v php7.3) ]]; then
                            enable_ioncube "7.3"
                            enable_sourceguardian "7.3"
                        fi
                    else
                        # Install all PHP version (except EOL & Beta).
                        enable_ioncube "5.6"
                        enable_ioncube "7.0"
                        enable_ioncube "7.1"
                        enable_ioncube "7.2"
                        enable_ioncube "7.3"
                        enable_ioncube "7.4"

                        enable_sourceguardian "5.6"
                        enable_sourceguardian "7.0"
                        enable_sourceguardian "7.1"
                        enable_sourceguardian "7.2"
                        enable_sourceguardian "7.3"
                        enable_sourceguardian "7.4"
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

echo "Uninstalling PHP Loader..."

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_phploader_removal "$@"
