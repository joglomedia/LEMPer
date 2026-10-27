#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Nginx HTTP Server Installer                                             |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2026 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || { echo "Cannot enter ${BASE_DIR}."; exit 1; }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

# Must be root to run this script
requires_root "$@"

# Ensure we're running from the project directory (used by nginx modules)
export CURRENT_DIR
CURRENT_DIR=$(pwd)

# Resolve module paths relative to this script. When sourced from install.sh,
# BASE_DIR points at the project root, not the scripts directory.
NGINX_SCRIPTS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include nginx modules
# shellcheck source=scripts/nginx/nginx_common.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_common.sh"
# shellcheck source=scripts/nginx/nginx_repo.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_repo.sh"
# shellcheck source=scripts/nginx/nginx_ssl_builders.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_ssl_builders.sh"
# shellcheck source=scripts/nginx/nginx_extra_modules.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_extra_modules.sh"
# shellcheck source=scripts/nginx/nginx_module_config.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_module_config.sh"
# shellcheck source=scripts/nginx/nginx_post_install.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_post_install.sh"
# shellcheck source=scripts/nginx/nginx_ssl_cert.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_ssl_cert.sh"
# shellcheck source=scripts/nginx/nginx_build.sh
. "${NGINX_SCRIPTS_DIR}/nginx/nginx_build.sh"

##
# Select installer method (interactive or automatic)
##
function select_install_method() {
    local SELECTED_INSTALLER=${NGINX_INSTALLER:-"source"}
    local SELECTED_REPO="${NGINX_REPO_SRC:-myguard}"

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

    case "${SELECTED_REPO}" in
        myguard) ;;
        ondrej)
            warning "NGINX_REPO_SRC=ondrej is retired. The Ondřej nginx repository is no longer published. Using myguard."
            SELECTED_REPO="myguard"
            ;;
        *)
            warning "Unsupported NGINX_REPO_SRC '${SELECTED_REPO}', falling back to myguard."
            SELECTED_REPO="myguard"
            ;;
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
                add_nginx_repo_myguard
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

        # Remember that LEMPer installed Nginx so uninstall does not remove
        # a server that was already present beforehand.
        mark_lemper_provisioned nginx
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
