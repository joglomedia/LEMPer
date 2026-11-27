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
# Output Default virtual host directive, fill with user input
# To be outputted into new file
# Work for default and WordPress site.
#
function create_vhost_default() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<-EOL
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    disable_symlinks if_not_owner;
    access_log /var/log/nginx/${SERVERNAME}.access.log lp_cache buffer=32k flush=5s;
    error_log /var/log/nginx/${SERVERNAME}.error.log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}";
    root \$root_path;
    include /etc/nginx/site-apps/${DOMAIN}/*.conf;
    index index.php index.html index.htm;
    client_max_body_size 50m;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    include /etc/nginx/includes/compression_gzip.conf;
    #include /etc/nginx/includes/compression_brotli.conf;

    ## Global directives configuration.
    # Restriction rules must come before the static-file locations so deny
    # rules are not shadowed by the broader static regexes.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_restriction.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;

    ## Naxsi WAF rules.
    #set \$naxsi_json_log 1;
	#include /etc/nginx/includes/naxsi_core.rules;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_${FRAMEWORK}.conf;

    ## Add your custom site directives here.

    ## End of custom site directives.

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php$ {
        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Include FastCGI Configs.
        include /etc/nginx/includes/fastcgi.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;
    }

    ## PHP-FPM status monitoring (local only).
    location ~ ^/php-fpm_(status|ping)$ {
        allow 127.0.0.1;
        allow ::1;
        deny all;

        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Virtual host created in dry run mode, no data written."
    fi
}

##
# Output Drupal virtual host directive, fill with user input
# To be outputted into new file.
#
function create_vhost_drupal() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<-EOL
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    disable_symlinks if_not_owner;
    access_log /var/log/nginx/${SERVERNAME}.access.log lp_cache buffer=32k flush=5s;
    error_log /var/log/nginx/${SERVERNAME}.error.log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}";
    root \$root_path;
    include /etc/nginx/site-apps/${DOMAIN}/*.conf;
    index index.php index.html index.htm;
    client_max_body_size 50m;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    include /etc/nginx/includes/compression_gzip.conf;
    #include /etc/nginx/includes/compression_brotli.conf;

    ## Global directives configuration.
    # Restriction rules must come before the static-file locations so deny
    # rules are not shadowed by the broader static regexes.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_restriction.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;

    ## Naxsi WAF rules.
    #set \$naxsi_json_log 1;
	#include /etc/nginx/includes/naxsi_core.rules;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_drupal.conf;

    ## Add your custom site directives here.

    ## End of custom site directives.

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ '\.php$|^/update.php' {
        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Include FastCGI Configs.
        include /etc/nginx/includes/fastcgi.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;
    }

    ## PHP-FPM status monitoring (local only).
    location ~ ^/php-fpm_(status|ping)$ {
        allow 127.0.0.1;
        allow ::1;
        deny all;

        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Virtual host created in dry run mode, no data written."
    fi
}

##
# Output Laravel virtual host skeleton, fill with user input
# To be outputted into new file.
#
function create_vhost_laravel() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<-EOL
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    disable_symlinks if_not_owner;
    access_log /var/log/nginx/${SERVERNAME}.access.log lp_cache buffer=32k flush=5s;
    error_log /var/log/nginx/${SERVERNAME}.error.log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}/public";
    root \$root_path;
    include /etc/nginx/site-apps/${DOMAIN}/*.conf;
    index index.php index.html index.htm;
    client_max_body_size 50m;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    include /etc/nginx/includes/compression_gzip.conf;
    #include /etc/nginx/includes/compression_brotli.conf;

    ## Global directives configuration.
    # Restriction rules must come before the static-file locations so deny
    # rules are not shadowed by the broader static regexes.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_restriction.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;

    ## Naxsi WAF rules.
    #set \$naxsi_json_log 1;
	#include /etc/nginx/includes/naxsi_core.rules;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_laravel.conf;

    ## Add your custom site directives here.

    ## End of custom site directives.

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location = /index.php {
        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Include FastCGI Configs.
        include /etc/nginx/includes/fastcgi.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;
    }

    # Laravel executes only its public front controller.
    location ~* \.(?:php[0-9]*|phtml|phar)(?:/|$) {
        return 404;
    }

    ## PHP-FPM status monitoring (local only).
    location ~ ^/php-fpm_(status|ping)$ {
        allow 127.0.0.1;
        allow ::1;
        deny all;

        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Virtual host created in dry run mode, no data written."
    fi
}

##
# Output Phalcon virtual host skeleton, fill with user input
# To be outputted into new file.
#
function create_vhost_phalcon() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<-EOL
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    disable_symlinks if_not_owner;
    access_log /var/log/nginx/${SERVERNAME}.access.log lp_cache buffer=32k flush=5s;
    error_log /var/log/nginx/${SERVERNAME}.error.log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}/public";
    root \$root_path;
    include /etc/nginx/site-apps/${DOMAIN}/*.conf;
    index index.php index.html index.htm;
    client_max_body_size 50m;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    include /etc/nginx/includes/compression_gzip.conf;
    #include /etc/nginx/includes/compression_brotli.conf;

    ## Global directives configuration.
    # Restriction rules must come before the static-file locations so deny
    # rules are not shadowed by the broader static regexes.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_restriction.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;

    ## Naxsi WAF rules.
    #set \$naxsi_json_log 1;
	#include /etc/nginx/includes/naxsi_core.rules;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_phalcon.conf;

    ## Add your custom site directives here.

    ## End of custom site directives.

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php$ {
        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Phalcon PHP custom params.
        fastcgi_param APPLICATION_ENV production; # development | production

        # Include FastCGI Configs.
        include /etc/nginx/includes/fastcgi.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;
    }

    ## PHP-FPM status monitoring (local only).
    location ~ ^/php-fpm_(status|ping)$ {
        allow 127.0.0.1;
        allow ::1;
        deny all;

        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Virtual host created in dry run mode, no data written."
    fi
}

##
# Output Wordpress Multisite vHost header.
#
function prepare_vhost_wpms() {
    cat <<-EOL
# Operator-maintained hostname map for legacy WordPress Multisite media.
map \$http_host \$blogid {
    default 0;
    include /etc/nginx/wpms/${SERVERNAME}/*.conf;
}

EOL
}

##
# Output server block for HTTP to HTTPS redirection.
#
function redirect_http_to_https() {
    cat <<-EOL

# HTTP to HTTPS redirection
server {
    listen 80;
    listen [::]:80;

    server_name ${SERVERNAME};

    # Automatically redirect site to HTTPS protocol.
    return 301 https://\$server_name\$request_uri;
}
EOL
}
