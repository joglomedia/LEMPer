#!/usr/bin/env bash

# Nginx uninstaller
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

# Remove nginx.
function init_nginx_removal() {
    # Stop nginx HTTP server process.
    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        run systemctl stop nginx
    fi

    if [[ ${NGX_VERSION} == "mainline" || ${NGX_VERSION} == "latest" ]]; then
        local NGINX_REPO="nginx-mainline"
    else
        local NGINX_REPO="nginx"
    fi

    # Remove nginx installation.
    if dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx-stable"; then
        echo "Found nginx-stable package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run add-apt-repository -y --remove ppa:nginx/stable
        fi
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx-custom"; then
        echo "Found nginx-custom package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run add-apt-repository -y --remove ppa:rtcamp/nginx
        fi
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx"; then
        echo "Found nginx package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx") $(dpkg-query -l | awk '/libnginx/ { print $2 }' | grep -wE "^libnginx")
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run add-apt-repository -y --remove "ppa:ondrej/${NGINX_REPO}"
        fi
    else
        info "Nginx package not found, possibly installed from source."
        echo "Remove it manually!!"

        NGINX_BIN=$(command -v nginx)

        if [[ -n $(command -v nginx) ]]; then
            echo "Nginx binary executable: ${NGINX_BIN}"

            # Disable systemctl.
            echo "Disable Nginx service."
            [ -f /etc/systemd/system/multi-user.target.wants/nginx.service ] && run systemctl disable nginx
            [ -f /etc/systemd/system/multi-user.target.wants/nginx.service ] && \
            run unlink /etc/systemd/system/multi-user.target.wants/nginx.service
            [ -f /lib/systemd/system/nginx.service ] && run rm -f /lib/systemd/system/nginx.service

            # Remove Nginx files.
            echo "Removing Nginx libraries & modules."
            [ -f /etc/init.d/nginx ] && run rm -f /etc/init.d/nginx
            [ -d /usr/lib/nginx ] && run rm -fr /usr/lib/nginx
            [ -d /usr/local/nginx ] && run rm -fr /usr/local/nginx
            [ -d /etc/nginx/modules-enabled ] && run rm -fr /etc/nginx/modules-enabled
            [ -d /etc/nginx/modules-available ] && run rm -fr /etc/nginx/modules-available

            # Remove binary executable file.
            if [[ -x "${NGINX_BIN}" ]]; then
                echo "Remove Nginx binary executable file."
                run rm -f "${NGINX_BIN}"
            fi

            # Delete default account credential from server .htpasswd.
            if [ -f /srv/.htpasswd ]; then
                local USERNAME=${LEMPER_USERNAME:-"lemper"}
                run sed -i "/^${USERNAME}:/d" /srv/.htpasswd
            fi
        else
            error "Sorry, we couldn't find any Nginx binary executable file."
        fi
    fi

    # Remove nginx config files.
    warning "!! This action is not reversible !!"

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

    if [[ "${REMOVE_NGX_CONFIG}" == Y* || "${REMOVE_NGX_CONFIG}" == y* ]]; then
        run rm -fr /etc/nginx
        run rm -fr /var/cache/nginx
        run rm -fr /usr/share/nginx

        echo "All your Nginx configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v nginx) ]]; then
            success "Nginx HTTP server removed succesfully."
        else
            info "Unable to remove Nginx HTTP server."
        fi        
    else
        info "Nginx HTTP server removed in dry run mode."
    fi
}

echo "Uninstalling Nginx HTTP server..."

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
