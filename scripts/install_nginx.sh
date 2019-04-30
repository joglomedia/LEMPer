#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

echo "Installing Nginx webserver..."

if [[ -n $(which nginx) && -d /etc/nginx/sites-available ]]; then
    warning "Nginx web server already exists. Installation skipped..."
else
    # Install Nginx custom
    run apt-get install -y --allow-unauthenticated ${NGX_PACKAGE}

    # Copy custom Nginx Config
    run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old
    run cp -f nginx/nginx.conf /etc/nginx/
    run cp -f nginx/fastcgi_cache /etc/nginx/
    run cp -f nginx/fastcgi_https_map /etc/nginx/
    run cp -f nginx/fastcgi_params /etc/nginx/
    run cp -f nginx/http_cloudflare_ips /etc/nginx/
    run cp -f nginx/http_proxy_ips /etc/nginx/
    run cp -f nginx/proxy_cache /etc/nginx/
    run cp -f nginx/proxy_params /etc/nginx/
    run cp -f nginx/upstream.conf /etc/nginx/
    run cp -fr nginx/conf.vhost/ /etc/nginx/
    run cp -fr nginx/ssl/ /etc/nginx/
    run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old
    run cp -f nginx/sites-available/default /etc/nginx/sites-available/
    run cp -f nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-available/
    run cp -f nginx/sites-available/sample-wordpress.dev.conf /etc/nginx/sites-available/
    run cp -f nginx/sites-available/sample-wordpress-ms.dev.conf /etc/nginx/sites-available/
    run cp -f nginx/sites-available/ssl.sample-site.dev.conf /etc/nginx/sites-available/
    run unlink /etc/nginx/sites-enabled/default
    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

    # Nginx cache directory
    if [ ! -d "/var/cache/nginx/" ]; then
        run mkdir /var/cache/nginx
        run chown -hR www-data: /var/cache/nginx
    fi

    if [ ! -d "/var/cache/nginx/fastcgi_cache" ]; then
        run mkdir /var/cache/nginx/fastcgi_cache
        run chown -hR www-data: /var/cache/nginx/fastcgi_cache
    fi

    if [ ! -d "/var/cache/nginx/proxy_cache" ]; then
        run mkdir /var/cache/nginx/proxy_cache
        run chown -hR www-data: /var/cache/nginx/proxy_cache
    fi

    # Check IP Address
    IPAddr=$(curl -s http://ipecho.net/plain)
    # Make default server accessible from IP address
    run sed -i s@localhost.localdomain@$IPAddr@g /etc/nginx/sites-available/default

    # Restart Nginx server
    if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
        run service nginx restart
    fi
fi
