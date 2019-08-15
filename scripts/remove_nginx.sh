#!/usr/bin/env bash

# Nginx uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 31/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
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
        run service nginx stop
    fi

    # Remove nginx installation.
    if [[ -n $(dpkg-query -l | grep nginx-common | awk '/nginx-common/ { print $2 }') ]]; then
        echo "Nginx-common package found. Removing..."
        {
            run apt-get --purge remove -y nginx-common
            run add-apt-repository -y --remove ppa:nginx/stable
        }
    elif [[ -n $(dpkg-query -l | grep nginx-custom | awk '/nginx-custom/ { print $2 }') ]]; then
        echo "Nginx-custom package found. Removing..."
        {
            run apt-get --purge remove -y nginx-custom
            run add-apt-repository -y --remove ppa:rtcamp/nginx
            run rm -f /etc/apt/sources.list.d/nginx-*.list
        }
    elif [[ -n $(dpkg-query -l | grep nginx-full | awk '/nginx-full/ { print $2 }') ]]; then
        echo "Nginx-full package found. Removing..."
        {
            run apt-get --purge remove -y nginx-full
            run add-apt-repository -y --remove ppa:nginx/stable
        }
    elif [[ -n $(dpkg-query -l | grep nginx-stable | awk '/nginx-stable/ { print $2 }') ]]; then
        echo "Nginx-stable package found. Removing..."
        {
            run apt-get --purge remove -y nginx-stable
            run add-apt-repository -y --remove ppa:nginx/stable
        }
    else
        echo "Nginx package not found. Possibly installed from source."

        if [[ -n $(command -v nginx) ]]; then
            # Disable systemctl.
            if [ -f /etc/systemd/system/multi-user.target.wants/nginx.service ]; then
                run systemctl disable nginx.service
            fi

            # Only if nginx package not installed / nginx installed from source.
            if [ -f /usr/sbin/nginx ]; then
                run rm -f /usr/sbin/nginx
            fi

            if [ -f /etc/init.d/nginx ]; then
                run rm -f /etc/init.d/nginx
            fi

            if [ -f /lib/systemd/system/nginx.service ]; then
                run rm -f /lib/systemd/system/nginx.service
            fi

            if [ -d /usr/lib/nginx/ ]; then
                run rm -fr /usr/lib/nginx/
            fi

            if [ -d /etc/nginx/modules-available ]; then
                run rm -fr /etc/nginx/modules-available
            fi

            if [ -d /etc/nginx/modules-enabled ]; then
                run rm -fr /etc/nginx/modules-enabled
            fi

            # Delete lemper account from PageSpeed admin.
            if [ -f /srv/.htpasswd ]; then
                #run rm -f /srv/.htpasswd'
                run sed -i "/^lemper:/d" /srv/.htpasswd
            fi
        fi
    fi

    # Remove nginx config files.
    warning "!! This action is not reversible !!"
    while [[ "${REMOVE_NGXCONFIG}" != "y" && "${REMOVE_NGXCONFIG}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Remove Nginx configuration files? [y/n]: " \
            -i y -e REMOVE_NGXCONFIG
    done
    if [[ "${REMOVE_NGXCONFIG}" == Y* || "${REMOVE_NGXCONFIG}" == y* || "${FORCE_REMOVE}" == true ]]; then
        echo "All your Nginx configuration files deleted permanently..."
        run rm -fr /etc/nginx
        # Remove nginx-cache.
        run rm -fr /var/cache/nginx
        # Remove nginx html.
        run rm -fr /usr/share/nginx
    fi

    if [[ -z $(command -v nginx) ]]; then
        status "Nginx HTTP server removed."
    else
        warning "Nginx HTTP server not removed."
    fi
}

echo "Uninstalling Nginx HTTP server..."
if [[ -n $(command -v nginx) || -x /usr/sbin/nginx ]]; then
    while [[ "${REMOVE_NGINX}" != "y" && "${REMOVE_NGINX}" != "n" && "${AUTO_REMOVE}" != true ]]; do
        read -rp "Are you sure to remove Nginx HTTP server? [y/n]: " -e REMOVE_NGINX
    done
    if [[ "${REMOVE_NGINX}" == Y* || "${REMOVE_NGINX}" == y* || "${AUTO_REMOVE}" == true ]]; then
        init_nginx_removal "$@"
    else
        echo "Found NGiNX HTTP server, but not removed."
    fi
else
    warning "Oops, NGiNX installation not found."
fi
