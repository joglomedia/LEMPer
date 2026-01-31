#!/usr/bin/env bash

# Nginx Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 31/01/2026
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
# Stop and disable Nginx service
##
function stop_nginx_service() {
    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        echo "Stopping nginx..."
        run systemctl stop nginx
        run systemctl disable nginx
    fi
}

##
# Remove Nginx installed from repository
##
function remove_nginx_from_repo() {
    local NGINX_VERSION="${NGINX_VERSION:-stable}"
    local NGINX_REPO

    if [[ "${NGINX_VERSION}" == "mainline" || "${NGINX_VERSION}" == "latest" ]]; then
        NGINX_REPO="nginx-mainline"
    else
        NGINX_REPO="nginx"
    fi

    # Check for nginx-stable package
    if dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx-stable"; then
        echo "Found nginx-stable package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")

        if [[ "${FORCE_REMOVE}" == true ]]; then
            run rm -f "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
            run rm -f "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
            [ -f "/etc/apt/preferences.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.pref" ] && \
                run rm -f "/etc/apt/preferences.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.pref"
        fi
        return 0

    # Check for nginx-custom package (legacy rtcamp - obsolete)
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx-custom"; then
        echo "Found nginx-custom package installation (legacy), removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        return 0

    # Check for generic nginx package
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx"; then
        echo "Found nginx package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -q -y \
            $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx") \
            $(dpkg-query -l | awk '/libnginx/ { print $2 }' | grep -wE "^libnginx")

        if [[ "${FORCE_REMOVE}" == true ]]; then
            run rm -f "/etc/apt/sources.list.d/ondrej-${NGINX_REPO}-${RELEASE_NAME}.list"
            run rm -f "/etc/apt/sources.list.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.list"
            [ -f "/etc/apt/preferences.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.pref" ] && \
                run rm -f "/etc/apt/preferences.d/myguard-${NGINX_REPO}-${RELEASE_NAME}.pref"
        fi
        return 0
    fi

    return 1
}

##
# Remove Nginx installed from source
##
function remove_nginx_from_source() {
    local NGINX_BIN
    NGINX_BIN=$(command -v nginx)

    if [[ -z "${NGINX_BIN}" ]]; then
        error "Sorry, we couldn't find any Nginx binary executable file."
        return 1
    fi

    info "Nginx package not found, possibly installed from source."
    echo "Nginx binary executable: ${NGINX_BIN}"

    # Disable and remove systemd service
    echo "Disabling Nginx service..."
    if [ -f /etc/systemd/system/multi-user.target.wants/nginx.service ]; then
        run systemctl disable nginx
        run unlink /etc/systemd/system/multi-user.target.wants/nginx.service
    fi
    [ -f /lib/systemd/system/nginx.service ] && run rm -f /lib/systemd/system/nginx.service
    [ -f /etc/systemd/system/nginx.service ] && run rm -f /etc/systemd/system/nginx.service

    # Remove Nginx binary and libraries
    echo "Removing Nginx libraries & modules..."
    [ -f /etc/init.d/nginx ] && run rm -f /etc/init.d/nginx
    [ -d /usr/lib/nginx ] && run rm -fr /usr/lib/nginx
    [ -d /usr/local/nginx ] && run rm -fr /usr/local/nginx
    [ -d /etc/nginx/modules-enabled ] && run rm -fr /etc/nginx/modules-enabled
    [ -d /etc/nginx/modules-available ] && run rm -fr /etc/nginx/modules-available

    # Remove binary executable
    if [[ -x "${NGINX_BIN}" ]]; then
        echo "Removing Nginx binary executable..."
        run rm -f "${NGINX_BIN}"
    fi

    # Remove build directory
    local BUILD_DIR="${NGINX_BUILD_DIR:-/tmp/lemper}"
    if [[ -d "${BUILD_DIR}" ]]; then
        echo "Cleaning up build directory: ${BUILD_DIR}"
        run rm -fr "${BUILD_DIR}"
    fi

    # Delete default account credential from server .htpasswd
    if [ -f /srv/.htpasswd ]; then
        local LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
        run sed -i "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
    fi

    return 0
}

##
# Remove Nginx configuration files
##
function remove_nginx_config() {
    warning "!! This action is not reversible !!"

    local REMOVE_NGX_CONFIG
    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_NGX_CONFIG="y"
        else
            REMOVE_NGX_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_NGX_CONFIG}" != "y" && "${REMOVE_NGX_CONFIG}" != "n" ]]; do
            read -rp "Remove all Nginx configuration files? [y/n]: " -e REMOVE_NGX_CONFIG
        done
    fi

    # Always remove these directories
    echo "Removing Nginx cache and temporary files..."
    run rm -fr /var/cache/nginx
    run rm -fr /usr/share/nginx
    run rm -fr /usr/lib/nginx

    if [[ "${REMOVE_NGX_CONFIG}" == Y* || "${REMOVE_NGX_CONFIG}" == y* ]]; then
        echo "Removing all Nginx configuration files..."
        run rm -fr /etc/nginx

        echo "All your Nginx installation and configuration files deleted permanently."
    else
        # Preserve main config but clean modules
        echo "Preserving configuration, cleaning modules..."
        run rm -fr /etc/nginx/modules-enabled/*
        run rm -fr /etc/nginx/modules-available/*

        # Clean stream vhost directories (from modular installer)
        run rm -fr /etc/nginx/stream-sites-enabled/*
        run rm -fr /etc/nginx/stream-sites-available/*

        echo "Nginx installation files deleted, configuration preserved."
    fi
}

##
# Main removal function
##
function init_nginx_removal() {
    # Stop Nginx service
    stop_nginx_service

    # Try to remove from repository first
    if ! remove_nginx_from_repo; then
        # Fall back to source removal
        remove_nginx_from_source
    fi

    # Remove configuration files
    remove_nginx_config

    # Reload systemd
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v nginx) ]]; then
            success "Nginx HTTP server removed successfully."
        else
            info "Unable to completely remove Nginx HTTP server."
        fi
    else
        info "Nginx HTTP server removed in dry run mode."
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

echo "[Nginx HTTP Server Uninstallation]"

if [[ -n $(command -v nginx) || -x /usr/sbin/nginx ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_NGINX="y"
    else
        while [[ "${REMOVE_NGINX}" != "y" && "${REMOVE_NGINX}" != "n" ]]; do
            read -rp "Are you sure to remove Nginx HTTP server? [y/n]: " -e REMOVE_NGINX
        done
    fi

    if [[ "${REMOVE_NGINX}" == Y* || "${REMOVE_NGINX}" == y* ]]; then
        init_nginx_removal "$@"
    else
        echo "Found Nginx HTTP server, but not removed."
    fi
else
    info "Oops, Nginx installation not found."
fi
