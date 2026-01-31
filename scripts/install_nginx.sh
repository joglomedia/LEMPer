#!/usr/bin/env bash

# Nginx HTTP Server Installer
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 1.0.0
# Refactored: 2.x.x - Modular architecture

# Include helper functions
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck source=./utils.sh
    . "${BASE_DIR}/utils.sh"
fi

# Must be root to run this script
requires_root "$@"

# Ensure we're running from the project directory
CURRENT_DIR=$(pwd)

# Include nginx modules
. "${BASE_DIR}/nginx/nginx_common.sh"
. "${BASE_DIR}/nginx/nginx_repo.sh"
. "${BASE_DIR}/nginx/nginx_ssl_builders.sh"
. "${BASE_DIR}/nginx/nginx_extra_modules.sh"
. "${BASE_DIR}/nginx/nginx_module_config.sh"
. "${BASE_DIR}/nginx/nginx_post_install.sh"
. "${BASE_DIR}/nginx/nginx_ssl_cert.sh"
. "${BASE_DIR}/nginx/nginx_build.sh"

##
# Select installer method (interactive or automatic)
##
function select_install_method() {
    local SELECTED_INSTALLER=${NGINX_INSTALLER:-"source"}
    local SELECTED_REPO="ondrej"

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ -z "${NGINX_INSTALLER}" || "${NGINX_INSTALLER}" == "none" ]]; then
            DO_INSTALL_NGINX="n"
        else
            DO_INSTALL_NGINX="y"
        fi
    else
        while [[ ${DO_INSTALL_NGINX} != "y" && ${DO_INSTALL_NGINX} != "n" ]]; do
            read -rp "Do you want to install Nginx HTTP server? [y/n]: " -i y -e DO_INSTALL_NGINX
        done
    fi

    if [[ ${DO_INSTALL_NGINX} != y* ]]; then
        return 1
    fi

    # Interactive installer selection
    if [[ "${AUTO_INSTALL}" != true ]]; then
        echo "Available Nginx installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" && \
                 ${SELECTED_INSTALLER} != "none" && ${SELECTED_INSTALLER} != "repo" && \
                 ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done
    fi

    # Normalize selection
    case "${SELECTED_INSTALLER}" in
        1|"repo") NGINX_INSTALL_METHOD="repo" ;;
        2|"source"|*) NGINX_INSTALL_METHOD="source" ;;
    esac

    NGINX_REPO_SOURCE="${SELECTED_REPO}"
    return 0
}

##
# Determine Nginx version to install
##
function determine_nginx_version() {
    local NGINX_VERSION="${NGINX_VERSION:-stable}"
    local VERSION=""

    # Get latest version from nginx.org
    case "${NGINX_VERSION}" in
        mainline|latest)
            VERSION=$(curl -sL https://nginx.org/en/download.html 2>&1 | \
                grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d'-' -f2)
            ;;
        stable|*)
            VERSION=$(curl -sL https://nginx.org/en/download.html 2>&1 | \
                grep -oE 'Stable version.*nginx-[0-9]+\.[0-9]+\.[0-9]+' | \
                grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
            ;;
    esac

    # Fallback
    [[ -z "${VERSION}" ]] && VERSION="1.24.0"
    echo "${VERSION}"
}

##
# Main nginx installation function
##
function init_nginx_install() {
    # Check if we should install
    if ! select_install_method; then
        info "Nginx HTTP (web) server installation skipped."
        return 0
    fi

    # Proceed with installation
    if [[ ${DO_INSTALL_NGINX} == y* && ${INSTALL_NGINX:-true} == true ]]; then
        case "${NGINX_INSTALL_METHOD}" in
            repo)
                # Add repository
                if [[ "${NGINX_REPO_SOURCE}" == "ondrej" ]]; then
                    add_nginx_repo_ondrej
                else
                    add_nginx_repo_myguard
                fi

                # Install from repo
                install_nginx_from_repo "${NGINX_REPO_SOURCE}"
                ;;

            source)
                # Build from source (function from nginx_build.sh)
                build_nginx_from_source
                ;;

            *)
                fail "Unsupported installation method: ${NGINX_INSTALL_METHOD}"
                ;;
        esac

        # Generate hostname certificate
        generate_hostname_cert

        # Post-installation configuration
        configure_nginx_post_install "${PWD}" "${HOSTNAME_CERT_PATH:-}"
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

echo "[Nginx HTTP (Web) Server Installation]"

if [[ -n $(command -v nginx) && -d /etc/nginx/sites-available && "${FORCE_INSTALL}" != true ]]; then
    info "Nginx web server already exists, installation skipped."
else
    init_nginx_install "$@"
fi
