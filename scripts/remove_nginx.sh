#!/usr/bin/env bash

# NGiNX uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 16.04
# Last Build        : 31/07/2019
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
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
        run apt remove --purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        if "${FORCE_REMOVE}"; then
            run add-apt-repository -y --remove ppa:nginx/stable
        fi
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx-custom"; then
        echo "Found nginx-custom package installation, removing..."

        # shellcheck disable=SC2046
        run apt remove --purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx")
        if "${FORCE_REMOVE}"; then
            run add-apt-repository -y --remove ppa:rtcamp/nginx
        fi
    elif dpkg-query -l | awk '/nginx/ { print $2 }' | grep -qwE "^nginx"; then
        echo "Found nginx package installation, removing..."

        # shellcheck disable=SC2046
        run apt remove --purge -qq -y $(dpkg-query -l | awk '/nginx/ { print $2 }' | grep -wE "^nginx") $(dpkg-query -l | awk '/libnginx/ { print $2 }' | grep -wE "^libnginx")
        if "${FORCE_REMOVE}"; then
            run add-apt-repository -y --remove "ppa:ondrej/${NGINX_REPO}"
        fi
    else
        echo "No installed nginx package found, possibly installed from source."

        NGINX_BIN=$(command -v nginx)

        if [[ -n "${NGINX_BIN}" ]]; then
            echo "NGiNX binary executable: ${NGINX_BIN}"

            # Disable systemctl.
            echo "Disable NGiNX service..."
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
            if [ -x "${NGINX_BIN}" ]; then
                echo "Remove NGiNX binary executable file..."
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
    if "${AUTO_REMOVE}"; then
        REMOVE_NGXCONFIG="y"
    else
        while [[ "${REMOVE_NGXCONFIG}" != "y" && "${REMOVE_NGXCONFIG}" != "n" ]]; do
            read -rp "Remove all NGiNX configuration files? [y/n]: " -e REMOVE_NGXCONFIG
        done
    fi

    if [[ "${REMOVE_NGXCONFIG}" == Y* || "${REMOVE_NGXCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
        run rm -fr /etc/nginx
        run rm -fr /var/cache/nginx
        run rm -fr /usr/share/nginx

        echo "All your NGiNX configuration files deleted permanently."
    fi
    
    # Final test.
    if "${DRYRUN}"; then
        info "NGiNX HTTP server removed in dryrun mode."
    else
        if [[ -z $(command -v nginx) ]]; then
            success "NGiNX HTTP server removed succesfully."
        else
            info "Unable to remove NGiNX HTTP server."
        fi
    fi
}

echo "Uninstalling NGiNX HTTP server..."

if [[ -n $(command -v nginx) || -x /usr/sbin/nginx ]]; then
    if "${AUTO_REMOVE}"; then
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
