#!/usr/bin/env bash

# NGiNX uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 10/12/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Remove nginx.
function init_nginx_removal() {
    # Stop nginx HTTP server process.
    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        #run service nginx stop
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
        run apt-get remove --purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run add-apt-repository -y --remove ppa:nginx/stable
        fi
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx-custom"; then
        echo "Found nginx-custom package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get remove --purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run add-apt-repository -y --remove ppa:rtcamp/nginx
        fi
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx"; then
        echo "Found nginx package installation, removing..."

        # shellcheck disable=SC2046
        run apt-get remove --purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx") $(dpkg-query -l | awk '/libnginx/ { print $2 }' | grep -wE "^libnginx")
        if [[ "${FORCE_REMOVE}" == true ]]; then
            run add-apt-repository -y --remove "ppa:ondrej/${NGINX_REPO}"
        fi
    else
        info "NGiNX package not found, possibly installed from source."
        echo "Remove it manually!!"

        NGINX_BIN=$(command -v nginx)

        if [[ -n "${NGINX_BIN}" ]]; then
            echo "NGiNX binary executable: ${NGINX_BIN}"

            # Disable systemctl.
            echo "Disable NGiNX service."
            [ -f /etc/systemd/system/multi-user.target.wants/nginx.service ] && run systemctl disable nginx
            [ -f /etc/systemd/system/multi-user.target.wants/nginx.service ] && \
            run unlink /etc/systemd/system/multi-user.target.wants/nginx.service
            [ -f /lib/systemd/system/nginx.service ] && run rm -f /lib/systemd/system/nginx.service

            # Remove Nginx files.
            [ -f /etc/init.d/nginx ] && run rm -f /etc/init.d/nginx
            [ -d /usr/lib/nginx ] && run rm -fr /usr/lib/nginx
            [ -d /etc/nginx/modules-enabled ] && run rm -fr /etc/nginx/modules-enabled
            [ -d /etc/nginx/modules-available ] && run rm -fr /etc/nginx/modules-available

            # Remove binary executable file.
            if [[ -x "${NGINX_BIN}" ]]; then
                echo "Remove NGiNX binary executable file."
                run rm -f "${NGINX_BIN}"
            fi

            # Delete default account credential from server .htpasswd.
            if [ -f /srv/.htpasswd ]; then
                local USERNAME=${LEMPER_USERNAME:-"lemper"}
                run sed -i "/^${USERNAME}:/d" /srv/.htpasswd
            fi
        else
            error "Sorry, we couldn't find any NGiNX binary executable file."
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
            read -rp "Remove all NGiNX configuration files? [y/n]: " -e REMOVE_NGX_CONFIG
        done
    fi

    if [[ "${REMOVE_NGX_CONFIG}" == Y* || "${REMOVE_NGX_CONFIG}" == y* ]]; then
        run rm -fr /etc/nginx
        run rm -fr /var/cache/nginx
        run rm -fr /usr/share/nginx

        echo "All your NGiNX configuration files deleted permanently."
    fi
    
    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        if [[ -z $(command -v nginx) ]]; then
            success "NGiNX HTTP server removed succesfully."
        else
            info "Unable to remove NGiNX HTTP server."
        fi        
    else
        info "NGiNX HTTP server removed in dry run mode."
    fi
}

echo "Uninstalling NGiNX HTTP server..."

if [[ -n $(command -v nginx) || -x /usr/sbin/nginx ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_NGINX="y"
    else
        while [[ "${REMOVE_NGINX}" != "y" && "${REMOVE_NGINX}" != "n" ]]; do
            read -rp "Are you sure to remove NGiNX HTTP server? [y/n]: " -e REMOVE_NGINX
        done
    fi

    if [[ "${REMOVE_NGINX}" == Y* || "${REMOVE_NGINX}" == y* ]]; then
        init_nginx_removal "$@"
    else
        echo "Found NGiNX HTTP server, but not removed."
    fi
else
    info "Oops, NGiNX installation not found."
fi
