#!/usr/bin/env bash

# PHP & FPM Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 12/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Remove PHP & FPM installation from system.
##
function remove_php_fpm() {
    # PHP version.
    local PHPv="${1}"
    local REMOVED_PHP_LOADER="${2}"

    if [ -z "${PHPv}" ]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.2"}
    fi

    # Stop default PHP FPM process.
    if [[ $(pgrep -c "php-fpm${PHPv}") -gt 0 ]]; then
        echo "Stopping php${PHPv}-fpm..."
        run systemctl stop "php${PHPv}-fpm"
        run systemctl disable "php${PHPv}-fpm"
    fi

    if dpkg-query -l | awk '/php/ { print $2 }' | grep -qwE "^php${PHPv}"; then
        echo "Removing PHP ${PHPv} packages installation..."

        if [[ -n $(command -v "php${PHPv}") ]]; then
            # Remove geoip extension.
            if "php${PHPv}" -m | grep -qw geoip; then
                # Uninstall geoip pecl.
                #run pecl uninstall geoip

                # Unlink enabled extension.
                [ -f "/etc/php/${PHPv}/cli/conf.d/20-geoip.ini" ] && \
                run unlink "/etc/php/${PHPv}/cli/conf.d/20-geoip.ini"

                [ -f "/etc/php/${PHPv}/fpm/conf.d/20-geoip.ini" ] && \
                run unlink "/etc/php/${PHPv}/fpm/conf.d/20-geoip.ini"

                # Remove extension.
                run rm -f "/etc/php/${PHPv}/mods-available/geoip.ini"
            fi
        fi

        # Remove PHP packages.
        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/php/ { print $2 }' | grep -wE "^php${PHPv}")

        # Remove PHP loaders.
        remove_php_loader "${PHPv}" "${REMOVED_PHP_LOADER}"

        # Remove PHP & FPM config files.
        warning "!! This action is not reversible !!"

        if [[ "${AUTO_REMOVE}" == true ]]; then
            if [[ "${FORCE_REMOVE}" == true ]]; then
                REMOVE_PHP_CONFIG="y"
            else
                REMOVE_PHP_CONFIG="n"
            fi
        else
            while [[ "${REMOVE_PHP_CONFIG}" != "y" && "${REMOVE_PHP_CONFIG}" != "n" ]]; do
                read -rp "Remove PHP ${PHPv} & FPM configuration files? [y/n]: " -e REMOVE_PHP_CONFIG
            done
        fi

        if [[ ${REMOVE_PHP_CONFIG} == Y* || ${REMOVE_PHP_CONFIG} == y* ]]; then
            [ -d "/etc/php/${PHPv}" ] && run rm -fr "/etc/php/${PHPv}"

            echo "All your configuration files deleted permanently."
        fi

        if [[ -z $(command -v "php${PHPv}") ]]; then
            success "PHP ${PHPv} package and it's extensions successfuly removed."
        else
            info "Unable to remove PHP ${PHPv} installation."
        fi
    else
        info "PHP ${PHPv} package and it's extensions not found."
    fi   
}

##
# Disable ionCube Loader.
##
function disable_ioncube_loader() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.2"}
    fi

    echo "Disable ionCube loader for PHP ${PHPv}."

    if [[ -f "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini" ]]; then
        run unlink "/etc/php/${PHPv}/fpm/conf.d/05-ioncube.ini"
    fi

    if [[ -f "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini" ]]; then
        run unlink "/etc/php/${PHPv}/cli/conf.d/05-ioncube.ini"
    fi
}

##
# Remove ionCube Loader.
##
function remove_ioncube_loader() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.2"}
    fi

    echo "Uninstalling ionCube loader for PHP ${PHPv}..."

    disable_ioncube_loader "${PHPv}"

    if [[ -d /usr/lib/php/loaders/ioncube ]]; then
        run rm -fr /usr/lib/php/loaders/ioncube
        success "ionCube loader for PHP ${PHPv} has been removed."
    else
        info "ionCube loader for PHP ${PHPv} couldn't be found."
    fi
}

##
# Disable SourceGuardian Loader.
##
function disable_sourceguardian_loader() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.2"}
    fi

    echo "Disable SourceGuardian loader for PHP ${PHPv}."

    if [[ -f "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini" ]]; then
        run unlink "/etc/php/${PHPv}/fpm/conf.d/05-sourceguardian.ini"
    fi

    if [[ -f "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini" ]]; then
        run unlink "/etc/php/${PHPv}/cli/conf.d/05-sourceguardian.ini"
    fi
}

##
# Remove SourceGuardian Loader.
##
function remove_sourceguardian_loader() {
    # PHP version.
    local PHPv="${1}"
    if [ -z "${PHPv}" ]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.2"}
    fi

    echo "Uninstalling SourceGuardian loader for PHP ${PHPv}..."

    disable_sourceguardian_loader "${PHPv}"

    if [[ -d /usr/lib/php/loaders/sourceguardian ]]; then
        run rm -fr /usr/lib/php/loaders/sourceguardian
        success "SourceGuardian loader for PHP ${PHPv} has been removed."
    else
        info "SourceGuardian loader for PHP ${PHPv} couldn't be found."
    fi
}

##
# Remove PHP Loader.
##
function remove_php_loader() {
    local PHPv="${1}"
    local REMOVED_PHP_LOADER="${2}"

    if [[ -z "${PHPv}" ]]; then
        PHPv=${DEFAULT_PHP_VERSION:-"8.2"}
    fi

    if [[ -z "${REMOVED_PHP_LOADER}" ]]; then
        REMOVED_PHP_LOADER=${PHP_LOADER:-"ioncube"}
    fi

    # Remove PHP loader.
    if [[ "${PHPv}" != "unsupported" && ! $(version_older_than "${PHPv}" "5.6") ]]; then
        if [[ "${AUTO_REMOVE}" == true ]]; then
            if [[ "${FORCE_REMOVE}" == true ]]; then
                DO_REMOVE_PHP_LOADER="y"
            else
                DO_REMOVE_PHP_LOADER="n"
            fi
        else
            while [[ "${DO_REMOVE_PHP_LOADER}" != "y" && "${DO_REMOVE_PHP_LOADER}" != "n" ]]; do
                read -rp "Do you want to remove PHP Loader? [y/n]: : " -e DO_REMOVE_PHP_LOADER
            done
        fi

        if [[ ${DO_REMOVE_PHP_LOADER} == y* || ${DO_REMOVE_PHP_LOADER} == Y* ]]; then
            if [[ "${AUTO_INSTALL}" != true ]]; then
                echo ""
                echo "Available PHP Loaders:"
                echo "  1). ionCube Loader (latest stable)"
                echo "  2). SourceGuardian (latest stable)"
                echo "  3). All loaders (ionCube, SourceGuardian)"
                echo "--------------------------------------------"

                while [[ ${REMOVED_PHP_LOADER} != "1" && ${REMOVED_PHP_LOADER} != "2" && \
                        ${REMOVED_PHP_LOADER} != "3" && ${REMOVED_PHP_LOADER} != "ioncube" && \
                        ${REMOVED_PHP_LOADER} != "sg" && ${REMOVED_PHP_LOADER} != "ic" && \
                        ${REMOVED_PHP_LOADER} != "sourceguardian" && ${REMOVED_PHP_LOADER} != "all" ]]; do
                    read -rp "Select an option [1-3]: " -i "${PHP_LOADER}" -e REMOVED_PHP_LOADER
                done
            fi

            case ${REMOVED_PHP_LOADER} in
                1 | "ic" | "ioncube")
                    disable_ioncube_loader "${PHPv}"
                ;;
                2 | "sg" | "sourceguardian")
                    disable_sourceguardian_loader "${PHPv}"
                ;;
                "all")
                    disable_ioncube_loader "${PHPv}"
                    disable_sourceguardian_loader "${PHPv}"
                ;;
                *)
                    error "Your selected PHP loader ${REMOVED_PHP_LOADER} is not supported yet."
                ;;
            esac
        else
            info "PHP ${PHPv} ${REMOVED_PHP_LOADER} loader removal skipped."
        fi
    fi
}
 
##
# Initialize PHP & FPM removal.
##
function init_php_fpm_removal() {
    local REMOVED_PHP_VERSIONS=()
    local OPT_PHP_VERSIONS=()
    local OPT_PHP_LOADER=${PHP_LOADER:-"ioncube"}

    OPTS=$(getopt -o p:l: \
        -l php-version:,php-loader: \
        -n "init_php_fpm_removal" -- "$@")

    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            -p | --php-version) 
                shift
                if [[ "${1}" == "all" ]]; then
                    # Include versions from config file.
                    read -r -a OPT_PHP_VERSIONS <<< "${PHP_VERSIONS}"
                else
                    OPT_PHP_VERSIONS+=("${1}")
                fi
                shift
            ;;
            -l | --php-loader) 
                shift
                OPT_PHP_LOADER="${1}"
                shift
            ;;
            --) 
                shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    # Include versions from config file.
    read -r -a REMOVED_PHP_VERSIONS <<< "${PHP_VERSIONS}"

    if [[ "${#OPT_PHP_VERSIONS[@]}" -gt 0 ]]; then
        REMOVED_PHP_VERSIONS+=("${OPT_PHP_VERSIONS[@]}")
    else
        # Manually select PHP version in interactive mode.
        if [[ "${AUTO_REMOVE}" != true ]]; then
            echo "Which PHP version to be removed?"
            echo "Available PHP versions:"
            echo "  1). PHP 7.1 (EOL)"
            echo "  2). PHP 7.2 (EOL)"
            echo "  3). PHP 7.3 (EOL)"
            echo "  4). PHP 7.4 (EOL)"
            echo "  5). PHP 8.0 (EOL)"
            echo "  6). PHP 8.1 (SFO)"
            echo "  7). PHP 8.2 (Stable)"
            echo "  8). PHP 8.3 (Latest Stable)"
            echo "  9). All installed versions"
            echo "  10). Do not remove!"
            echo "--------------------------------------------"

            [ -n "${DEFAULT_PHP_VERSION}" ] && \
            info "Default version is: ${DEFAULT_PHP_VERSION}"

            while [[ ${SELECTED_PHP} != "1" && ${SELECTED_PHP} != "2" && ${SELECTED_PHP} != "3" && \
                    ${SELECTED_PHP} != "4" && ${SELECTED_PHP} != "5" && ${SELECTED_PHP} != "6" && \
                    ${SELECTED_PHP} != "7" && ${SELECTED_PHP} != "8" && ${SELECTED_PHP} != "9" && \
                    ${SELECTED_PHP} != "10" && \
                    ${SELECTED_PHP} != "7.1" && ${SELECTED_PHP} != "7.2" && ${SELECTED_PHP} != "7.3" && \
                    ${SELECTED_PHP} != "7.4" && ${SELECTED_PHP} != "8.0" && ${SELECTED_PHP} != "8.1" && \
                    ${SELECTED_PHP} != "8.2" && ${SELECTED_PHP} != "8.3" && \
                    ${SELECTED_PHP} != "all" && ${SELECTED_PHP} != "none"
            ]]; do
                read -rp "Enter a PHP version from an option above [1-9]: " -i "${DEFAULT_PHP_VERSION}" -e SELECTED_PHP
            done

            case ${SELECTED_PHP} in
                1 | "7.1")
                    REMOVED_PHP_VERSIONS+=("7.1")
                ;;
                2 | "7.2")
                    REMOVED_PHP_VERSIONS+=("7.2")
                ;;
                3 | "7.3")
                    REMOVED_PHP_VERSIONS+=("7.3")
                ;;
                4 | "7.4")
                    REMOVED_PHP_VERSIONS+=("7.4")
                ;;
                5 | "8.0")
                    REMOVED_PHP_VERSIONS+=("8.0")
                ;;
                6 | "8.1")
                    REMOVED_PHP_VERSIONS+=("8.1")
                ;;
                7 | "8.2")
                    REMOVED_PHP_VERSIONS+=("8.2")
                ;;
                8 | "8.3")
                    REMOVED_PHP_VERSIONS+=("8.3")
                ;;
                9 | "all")
                    # Select all PHP versions (except EOL & Beta).
                    REMOVED_PHP_VERSIONS=("7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2" "8.3")
                ;;
                10 | n*)
                    info "No PHP version will be removed."
                    return
                ;;
                *)
                    error "Your selected PHP version ${SELECTED_PHP} is not supported yet."
                ;;
            esac
        fi
    fi

    # If FORCE_REMOVE, then remove all installed PHP versions include the default.
    if [[ "${FORCE_REMOVE}" == true ]]; then
        # Also remove default LEMPer PHP.
        DEFAULT_PHP_VERSION=${DEFAULT_PHP_VERSION:-"8.2"}
        REMOVED_PHP_VERSIONS+=("${DEFAULT_PHP_VERSION}")
    fi

    # Remove all selected PHP versions.
    if [[ "${#REMOVED_PHP_VERSIONS[@]}" -gt 0 ]]; then
        # Sort PHP versions.
        #shellcheck disable=SC2207
        REMOVED_PHP_VERSIONS=($(printf "%s\n" "${REMOVED_PHP_VERSIONS[@]}" | sort -u | tr '\n' ' '))

        for PHP_VER in "${REMOVED_PHP_VERSIONS[@]}"; do
            remove_php_fpm "${PHP_VER}" "${OPT_PHP_LOADER}"
        done

        # Final clean up (executed only if no PHP version installed).
        if [[ "${DRYRUN}" != true ]]; then
            # New logic for multiple PHP removal in batch.
            PHP_IS_EXISTS=false
            for PHP_VER in "${REMOVED_PHP_VERSIONS[@]}"; do
                [[ -n $(command -v "${PHP_VER}") ]] && PHP_IS_EXISTS=true
            done

            if [[ "${PHP_IS_EXISTS}" == false ]]; then
                echo "Removing additional unused PHP packages..."
                run apt-get purge -q -y dh-php php-common php-pear php-xml pkg-php-tools fcgiwrap spawn-fcgi

                # Remove all the rest of PHP lib files.
                [ -d /usr/lib/php ] && run rm -fr /usr/lib/php
                [ -d /usr/share/php ] && run rm -fr /usr/share/php
                [ -d /var/lib/php ] && run rm -fr /var/lib/php

                # Remove repository.
                case "${DISTRIB_NAME}" in
                    debian)
                        if echo "${PHP_EXTENSIONS}" | grep -qwE "openswoole"; then
                            run rm -f "/etc/apt/sources.list.d/openswoole-ppa-ubuntu-${OPENSWOOLE_RELEASE_NAME}.list"
                            run rm -f "/usr/share/keyrings/openswoole-ppa-ubuntu-${OPENSWOOLE_RELEASE_NAME}.gpg"
                        fi

                        run rm -f "/etc/apt/sources.list.d/ondrej-php-${RELEASE_NAME}.list"
                        run rm -f "/etc/apt/trusted.gpg.d/ondrej-php-${RELEASE_NAME}.gpg"
                    ;;
                    ubuntu)
                        if echo "${PHP_EXTENSIONS}" | grep -qwE "openswoole"; then
                            run add-apt-repository -y --remove ppa:openswoole/ppa
                        fi

                        run add-apt-repository -y --remove ppa:ondrej/php
                    ;;
                esac

                success "All PHP package and it's extensions completely removed."
            fi
        else
            info "PHP package & it's extensions removed in dry run mode."
        fi
    else
        info "No PHP version removed."
    fi
}

echo "Uninstalling PHP packages..."

if [[ -n $(command -v php7.1) || \
    -n $(command -v php7.2) || \
    -n $(command -v php7.3) || \
    -n $(command -v php7.4) || \
    -n $(command -v php8.0) || \
    -n $(command -v php8.1) || \
    -n $(command -v php8.2) || \
    -n $(command -v php8.3) 
]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_PHP="y"
    else
        while [[ "${REMOVE_PHP}" != "y" && "${REMOVE_PHP}" != "n" ]]; do
            read -rp "Are you sure to remove PHP package? [y/n]: " -e REMOVE_PHP
        done
    fi

    if [[ "${REMOVE_PHP}" == Y* || "${REMOVE_PHP}" == y* ]]; then
        init_php_fpm_removal "$@"
    else
        echo "Found PHP packages, but not removed."
    fi
else
    info "Oops, PHP packages installation not found."
fi
