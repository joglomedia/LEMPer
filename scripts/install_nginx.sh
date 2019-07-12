#!/usr/bin/env bash

# Nginx installer
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

function nginx_install_menu() {
    echo ""
    echo "Available Nginx installer to use:"
    echo "  1). Install from Repository"
    echo "  2). Compile from Source"
    echo "----------------------------------"
    while [[ $NGINX_INSTALLER != "1" && $NGINX_INSTALLER != "2" ]]; do
        read -p "Select an option [1-2]: " NGINX_INSTALLER
	done

    case $NGINX_INSTALLER in
        1)
            echo -e "\nInstalling Nginx from package repository..."
            run apt-get install -y --allow-unauthenticated ${NGX_PACKAGE} >> lemper.log 2>&1
        ;;
        2)
            echo -e "\nInstalling Nginx from source..."
            run ${BASEDIR}/install_nginx_from_source.sh -v latest-stable -n latest \
                --dynamic-module --extra-modules -y
        ;;
        *)
            warning "No installer found."
            continue_or_exit "Retry Nginx installation?"
            nginx_install_menu
        ;;
    esac

    if [ ! -d /etc/nginx/modules-available ]; then
        run mkdir /etc/nginx/modules-available
    fi

    if [ ! -d /etc/nginx/modules-enabled ]; then
        run mkdir /etc/nginx/modules-enabled
    fi

    if [ ! -d /etc/nginx/sites-available ]; then
        run mkdir /etc/nginx/sites-available
    fi

    if [ ! -d /etc/nginx/sites-enabled ]; then
        run mkdir /etc/nginx/sites-enabled
    fi

    # Custom Nginx dynamic modules configuration
    if [[ "$NGINX_INSTALLER" == "2" ]]; then

        if [[ -f /usr/lib/nginx/modules/ngx_pagespeed.so && ! -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_pagespeed.so\";" > \
                /etc/nginx/modules-available/mod-pagespeed.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_http_geoip_module.so && ! -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_geoip_module.so\";" > \
                /etc/nginx/modules-available/mod-http-geoip.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_http_image_filter_module.so && ! -f /etc/nginx/modules-available/mod-http-image-filter.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_image_filter_module.so\";" > \
                /etc/nginx/modules-available/mod-http-image-filter.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_http_xslt_filter_module.so && ! -f /etc/nginx/modules-available/mod-http-xslt-filter.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_xslt_filter_module.so\";" > \
                /etc/nginx/modules-available/mod-http-xslt-filter.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_mail_module.so && ! -f /etc/nginx/modules-available/mod-mail.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_mail_module.so\";" > \
                /etc/nginx/modules-available/mod-mail.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so && ! -f /etc/nginx/modules-available/mod-stream.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_stream_module.so\";" > \
                /etc/nginx/modules-available/mod-stream.conf'
        fi

        # Enable Nginx Dynamic Module
        echo ""
        while [[ $ENABLE_NGXDM != "y" && $ENABLE_NGXDM != "n" ]]; do
            read -p "Enable Nginx dynamic modules? [y/n]: " -e ENABLE_NGXDM
		done
        if [[ "$ENABLE_NGXDM" == Y* || "$ENABLE_NGXDM" == y* ]]; then

            if [[ -f /etc/nginx/modules-available/mod-pagespeed.conf && \
                ! -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
                run ln -s /etc/nginx/modules-available/mod-pagespeed.conf /etc/nginx/modules-enabled/50-mod-pagespeed.conf
            fi

            #run ln -s /etc/nginx/modules-available/mod-http-geoip.conf /etc/nginx/modules-enabled/50-mod-http-geoip.conf
        fi

        # Nginx init script
        if [ ! -f /etc/init.d/nginx ]; then
            run cp nginx/init.d/nginx /etc/init.d/
            run chmod ugo+x /etc/init.d/nginx
        fi

        # Nginx systemd script
        if [ ! -f /lib/systemd/system/nginx.service ]; then
            run cp nginx/systemd/nginx.service /lib/systemd/system/
        fi
    fi

    #run chown -hR www-data:root /etc/nginx/modules-available
}

function init_nginx_install() {
    echo ""
    echo "Welcome to Nginx installation script"

    # Install Nginx custom
    nginx_install_menu

    # Copy custom Nginx Config
    if [ -f /etc/nginx/nginx.conf ]; then
        run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old
    fi

    run cp -f nginx/charset /etc/nginx/
    run cp -f nginx/comp_brotli /etc/nginx/
    run cp -f nginx/comp_gzip /etc/nginx/
    run cp -f nginx/fastcgi_cache /etc/nginx/
    run cp -f nginx/fastcgi_https_map /etc/nginx/
    run cp -f nginx/fastcgi_params /etc/nginx/
    run cp -f nginx/http_cloudflare_ips /etc/nginx/
    run cp -f nginx/http_proxy_ips /etc/nginx/
    run cp -f nginx/nginx.conf /etc/nginx/
    run cp -f nginx/proxy_cache /etc/nginx/
    run cp -f nginx/proxy_params /etc/nginx/
    run cp -f nginx/upstream /etc/nginx/
    run cp -fr nginx/includes/ /etc/nginx/
    run cp -fr nginx/vhost/ /etc/nginx/
    run cp -fr nginx/ssl/ /etc/nginx/

    if [ -f /etc/nginx/sites-available/default ]; then
        run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old
    fi

    run cp -f nginx/sites-available/default /etc/nginx/sites-available/

    if [ -f /etc/nginx/sites-enabled/default ]; then
        run unlink /etc/nginx/sites-enabled/default
    fi

    if [ -f /etc/nginx/sites-enabled/01-default ]; then
        run unlink /etc/nginx/sites-enabled/01-default
    fi

    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

    if [ -d /usr/share/nginx/html ]; then
        run chown -hR www-data:root /usr/share/nginx/html
    fi

    # Nginx cache directory
    if [ ! -d /var/cache/nginx ]; then
        run mkdir /var/cache/nginx
        run chown -hR www-data:root /var/cache/nginx
    fi

    if [ ! -d /var/cache/nginx/fastcgi_cache ]; then
        run mkdir /var/cache/nginx/fastcgi_cache
        run chown -hR www-data:root /var/cache/nginx/fastcgi_cache
    fi

    if [ ! -d /var/cache/nginx/proxy_cache ]; then
        run mkdir /var/cache/nginx/proxy_cache
        run chown -hR www-data:root /var/cache/nginx/proxy_cache
    fi

    # Check IP Address
    #IPAddr=$(curl -s http://ipecho.net/plain)
    IPAddr=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

    # Make default server accessible from IP address
    run sed -i "s|localhost.localdomain|${IPAddr}|g" /etc/nginx/sites-available/default

    # Restart Nginx server
    if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
        run service nginx restart
        status -e "\nNginx web server restarted successfully."
    elif [[ -n $(which nginx) ]]; then
        run service nginx start

        if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
            status -e "\nNginx web server started successfully."
        else
            warning -e "\nSomething went wrong with Nginx installation."
        fi
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which nginx) && -d /etc/nginx/sites-available ]]; then
    warning -e "\nNginx web server already exists. Installation skipped..."
else
    init_nginx_install "$@"
fi
