#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Shared Security Helpers                                          |
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

        while [[ ${SELECTED_INSTALLER} != "1" && ${SELECTED_INSTALLER} != "2" &&
            ${SELECTED_INSTALLER} != "none" && ${SELECTED_INSTALLER} != "repo" &&
            ${SELECTED_INSTALLER} != "source" ]]; do
            read -rp "Select an option [1-2]: " -e SELECTED_INSTALLER
        done
    fi

    # Normalize selection
    case "${SELECTED_INSTALLER}" in
        1 | "repo") NGINX_INSTALL_METHOD="repo" ;;
        2 | "source" | *) NGINX_INSTALL_METHOD="source" ;;
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
    local requested="${NGINX_VERSION:-stable}" version
    if [[ "$requested" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s\n' "$requested"
        return 0
    fi
    case "$requested" in stable | lts | mainline | latest) ;; *)
        error "Invalid Nginx version."
        return 1
        ;;
    esac
    # Official GitHub tags avoid depending on the formatting of nginx.org HTML.
    version=$(curl -fsSL --connect-timeout 10 --max-time 30 \
        'https://api.github.com/repos/nginx/nginx/tags?per_page=100' \
        | grep -oE '"name"[[:space:]]*:[[:space:]]*"release-[0-9]+\.[0-9]+\.[0-9]+"' \
        | sed -E 's/.*release-([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' \
        | awk -v selected="$requested" '
            { split($0, parts, /[.]/) }
            selected == "latest" || selected == "mainline" || parts[2] % 2 == 0 { print }
        ' | sort -Vu | tail -n 1)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || {
            error "Unable to resolve Nginx source version; set an explicit NGINX_VERSION."
            return 1
        }
    printf '%s\n' "$version"
}

##
# Main nginx installation function
##
function init_nginx_install() {
    local preexisting_nginx=false
    command -v nginx >/dev/null 2>&1 && preexisting_nginx=true
    # Check if we should install
    if ! select_install_method; then
        info "Nginx HTTP (web) server installation skipped."
        return 0
    fi

    # Proceed with installation
    if [[ ${DO_INSTALL_NGINX} == y* && ${INSTALL_NGINX:-true} == true ]]; then
        case "${NGINX_INSTALL_METHOD}" in
            repo)
                add_nginx_repo_myguard || return 1
                install_nginx_from_repo "${NGINX_REPO_SOURCE}"
                ;;

            source)
                # Build from source (function from nginx_build.sh)
                lemper_build_workspace "$NGINX_BUILD_DIR" || return 1
                build_nginx_from_source || return 1
                ;;

            *)
                fail "Unsupported installation method: ${NGINX_INSTALL_METHOD}"
                ;;
        esac

        # Generate hostname certificate
        generate_hostname_cert

        # Post-installation configuration
        configure_nginx_post_install "${PWD}" "${HOSTNAME_CERT_PATH:-}" || return 1

        # Remember that LEMPer installed Nginx so uninstall does not remove
        # a server that was already present beforehand.
        [[ "$preexisting_nginx" == true ]] || mark_lemper_provisioned nginx
    fi
}

function lemper_nginx_install_entry() {
    requires_root "$@"
    export CURRENT_DIR
    CURRENT_DIR=$(pwd)
    lemper_load_module services/nginx/build_common || return 1
    nginx_build_initialize
    lemper_load_module services/nginx/package_repository || return 1
    lemper_load_module services/nginx/ssl_builders || return 1
    lemper_load_module services/nginx/modules_build || return 1
    lemper_load_module services/nginx/module_config || return 1
    lemper_load_module services/nginx/configure || return 1
    lemper_load_module services/nginx/tls || return 1
    lemper_load_module services/nginx/build || return 1
    echo "[Nginx HTTP (Web) Server Installation]"
    if [[ -n $(command -v nginx) && -d /etc/nginx/sites-available && "${FORCE_INSTALL}" != true ]]; then
        info "Nginx web server already exists, installation skipped."
    else
        init_nginx_install "$@"
    fi
}
