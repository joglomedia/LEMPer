#!/usr/bin/env bash

echo "Installing Nginx webserver..."

# Install Nginx custom
apt-get install -y --allow-unauthenticated nginx-stable

# Copy custom Nginx Config
mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old
cp -f nginx/nginx.conf /etc/nginx/
cp -f nginx/fastcgi_cache /etc/nginx/
cp -f nginx/fastcgi_https_map /etc/nginx/
cp -f nginx/fastcgi_params /etc/nginx/
cp -f nginx/http_cloudflare_ips /etc/nginx/
cp -f nginx/http_proxy_ips /etc/nginx/
cp -f nginx/proxy_cache /etc/nginx/
cp -f nginx/proxy_params /etc/nginx/
cp -f nginx/upstream.conf /etc/nginx/
cp -fr nginx/conf.vhost/ /etc/nginx/
cp -fr nginx/ssl/ /etc/nginx/
mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old
cp -f nginx/sites-available/default /etc/nginx/sites-available/
cp -f nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-available/
cp -f nginx/sites-available/sample-wordpress.dev.conf /etc/nginx/sites-available/
cp -f nginx/sites-available/sample-wordpress-ms.dev.conf /etc/nginx/sites-available/
cp -f nginx/sites-available/ssl.sample-site.dev.conf /etc/nginx/sites-available/
unlink /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

# Nginx cache directory
if [ ! -d "/var/cache/nginx/" ]; then
    mkdir /var/cache/nginx
    chown -hR www-data: /var/cache/nginx
fi
if [ ! -d "/var/cache/nginx/fastcgi_cache" ]; then
    mkdir /var/cache/nginx/fastcgi_cache
    chown -hR www-data: /var/cache/nginx/fastcgi_cache
fi
if [ ! -d "/var/cache/nginx/proxy_cache" ]; then
    mkdir /var/cache/nginx/proxy_cache
    chown -hR www-data: /var/cache/nginx/proxy_cache
fi

# Check IP Address
IPAddr=$(curl -s http://ipecho.net/plain)
# Make default server accessible from IP address
sed -i "s@localhost.localdomain@$IPAddr@g" /etc/nginx/sites-available/default

# Restart Nginx server
if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
    service nginx restart
fi

