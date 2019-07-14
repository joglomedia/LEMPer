#!/usr/bin/env bash

# Nginx uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include decorator
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

if [ "$(type -t run)" != "function" ]; then
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

# Remove nginx
function init_nginx_removal() {
    # Stop Nginx web server process
    if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
        run service nginx stop
    fi

    # Remove Nginx
    if [ $(dpkg-query -l | grep nginx-common | awk '/nginx-common/ { print $2 }') ]; then
        echo "Nginx-common package found. Removing..."
        run apt-get --purge remove -y nginx-common >> lemper.log 2>&1
        run add-apt-repository -y --remove ppa:nginx/stable >> lemper.log 2>&1
    elif [ $(dpkg-query -l | grep nginx-custom | awk '/nginx-custom/ { print $2 }') ]; then
        echo "Nginx-custom package found. Removing..."
        run apt-get --purge remove -y nginx-custom >> lemper.log 2>&1
        run add-apt-repository -y --remove ppa:rtcamp/nginx >> lemper.log 2>&1
        run rm -f /etc/apt/sources.list.d/nginx-*.list
    elif [ $(dpkg-query -l | grep nginx-full | awk '/nginx-full/ { print $2 }') ]; then
        echo "Nginx-full package found. Removing..."
        run apt-get --purge remove -y nginx-full >> lemper.log 2>&1
        run add-apt-repository -y --remove ppa:nginx/stable >> lemper.log 2>&1
    elif [ $(dpkg-query -l | grep nginx-stable | awk '/nginx-stable/ { print $2 }') ]; then
        echo "Nginx-stable package found. Removing..."
        run apt-get --purge remove -y nginx-stable >> lemper.log 2>&1
        run add-apt-repository -y --remove ppa:nginx/stable >> lemper.log 2>&1
    else
        echo "Nginx package not found. Possibly installed from source."

        # Only if nginx package not installed / nginx installed from source
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

        # Delete lemper account from PageSpeed admin
        if [ -f /srv/.htpasswd ]; then
            #run rm -f /srv/.htpasswd'
            sed -i "/^lemper:/d" /srv/.htpasswd
        fi
    fi

    # Remove config files
    while [[ $REMOVE_NGXCONFIG != "y" && $REMOVE_NGXCONFIG != "n" ]]; do
        read -p "Remove Nginx configuration files (this action is not reversible)? [y/n]: " -e REMOVE_NGXCONFIG
    done
    if [[ "$REMOVE_NGXCONFIG" == Y* || "$REMOVE_NGXCONFIG" == y* ]]; then
        echo "All your Nginx configuration files deleted permanently..."
        run rm -fr /etc/nginx
        # Remove nginx-cache
        run rm -fr /var/cache/nginx
        # Remove nginx html
        run rm -fr /usr/share/nginx
    fi

    if [[ -z $(which nginx) ]]; then
        status "Nginx web server removed."
    fi
}

echo -e "\nUninstalling Nginx web server..."
if [[ -n $(which nginx) ]]; then
    while [[ $REMOVE_NGINX != "y" && $REMOVE_NGINX != "n" ]]; do
        read -p "Are you sure to remove Nginx web server? [y/n]: " -e REMOVE_NGINX
    done
    if [[ "$REMOVE_NGINX" == Y* || "$REMOVE_NGINX" == y* ]]; then
        init_nginx_removal "$@"
    else
        echo "Nginx uninstall skipped."
    fi
else
    warning "Nginx installation not found."
fi
