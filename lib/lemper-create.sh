#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Lemper Create - Simple LEMP Virtual Host Creator                        |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2022 MasEDI.Net (https://masedi.net/lemper)          |
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

# Version control.
PROG_NAME=$(basename "$0")
PROG_VER="2.x.x"
CMD_PARENT="lemper-cli"
CMD_NAME="create"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

# Check pre-requisite packages.
REQUIRED_PACKAGES=("curl" "git" "rsync" "unzip" "wget")
for CMD in "${REQUIRED_PACKAGES[@]}"; do
    if ! [[ -x "$(command -v "${CMD}")" ]]; then
        NO_PACKAGES+=("${CMD}")
    fi
done

if [[ ${#NO_PACKAGES[@]} -gt 0 ]]; then
    printf -v NO_PACKAGES_STR '%s, ' "${NO_PACKAGES[@]}"
    error "${PROG_NAME} ${COMMAND_NAME} requires: ${NO_PACKAGES_STR%, }, please install it first!"
    echo "help: run 'sudo apt-get install ${NO_PACKAGES[*]}'"
    exit 1
fi

##
# Main Functions
#

## 
# Show usage
# output to STDERR.
#
function show_usage {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VER}
Creates Nginx virtual host (vHost) configuration file.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage: ${CMD_PARENT} ${CMD_NAME} [options]...
       ${CMD_PARENT} ${CMD_NAME} -d <domain-name> -f <framework>
       ${CMD_PARENT} ${CMD_NAME} -d <domain-name> -f <framework> -w <webroot-path>

Options:
  -4, --ipv4 <IPv4 address>
      Any valid IPv4 addreess for listening on.
  -6, --ipv6 <IPv6 address>
      Any valid IPv6 addreess for listening on.
  -d, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed, i.e. example.app or sub.example.app.
  -f, --framework <website framework>
      Type of PHP web Framework and CMS, i.e. default.
      Supported PHP Framework and CMS: default (vanilla PHP), framework (codeigniter, laravel,
      lumen, phalcon, symfony), CMS (drupal, mautic, roundcube, sendy, wordpress, wordpress-ms).
      Another framework and cms will be added soon.
  -p, --php-version
      PHP version for selected framework. Latest recommended PHP version is "7.4".
  -u, --username <virtual-host username>
      Use username added from useradd. Default user set as LEMPer's user, Do not use root user!!
  -w, --webroot <web root>
      Web root is an absolute path to the website root directory, i.e. /home/lemper/webapps/example.test.

  -c, --enable-fastcgi-cache
      Enable FastCGI cache module.
  -D, --dryrun
      Dry run mode, only for testing.
  -F, --enable-fail2ban
      Enable fail2ban filter. 
  -i, --install-app
      Auto install application for selected framework.
  -s, --enable-ssl
      Enable HTTPS with Let's Encrypt free SSL certificate.
  -P, --enable-pagespeed
      Enable Nginx mod_pagespeed.
  -W, --wildcard-domain
      Enable wildcard (*) domain.

  -h, --help
      Print this message and exit.
  -v, --version
      Show version number and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} -u lemper -d example.com -f default -w /home/lemper/webapps/example.test

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Output Default virtual host directive, fill with user input
# To be outputted into new file
# Work for default and WordPress site.
#
function create_vhost_default() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<- EOL
server {
    listen 80;
    listen [::]:80;
    http2 off;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    access_log /home/${USERNAME}/logs/nginx/access_log combined buffer=32k;
    error_log /home/${USERNAME}/logs/nginx/error_log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}";
    root \$root_path;
    index index.php index.html index.htm;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    #include /etc/nginx/includes/compression_gzip.conf;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://${SERVERNAME};

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://${SERVERNAME};

    # PageSpeed should be disabled on the WP admin/dashboard 
    # adjust manually to suit your custom admin URLs.
    #pagespeed Disallow "*/admin/*";
    #pagespeed Disallow "*/account/*";
    #pagespeed Disallow "*/dashboard/*";
    #pagespeed Disallow "*/wp-admin/*";
    #pagespeed Disallow "*/wp-login*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "${SERVERNAME},*.${SERVERNAME}";

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "${SERVERNAME}";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "*.${SERVERNAME}";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

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

    ## PHP-FPM status monitoring
    location ~ ^/php-fpm_(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Vhost created in dry run mode, no data written."
    fi
}

##
# Output Drupal virtual host directive, fill with user input
# To be outputted into new file.
#
function create_vhost_drupal() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<- EOL
server {
    listen 80;
    listen [::]:80;
    http2 off;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    access_log /home/${USERNAME}/logs/nginx/access_log combined buffer=32k;
    error_log /home/${USERNAME}/logs/nginx/error_log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}";
    root \$root_path;
    index index.php index.html index.htm;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    #include /etc/nginx/includes/compression_gzip.conf;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://${SERVERNAME};

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://${SERVERNAME};

    # PageSpeed should be disabled on the user panel (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/user/*";
    #pagespeed Disallow "*/account/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "${SERVERNAME},*.${SERVERNAME}";

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "${SERVERNAME}";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "*.${SERVERNAME}";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_drupal.conf;

    ## Add your custom site directives here.

    ## End of custom site directives. 

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ '\.php$|^/update.php' {
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

    ## PHP-FPM status monitoring
    location ~ ^/php-fpm_(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Vhost created in dry run mode, no data written."
    fi
}

##
# Output Laravel virtual host skeleton, fill with user input
# To be outputted into new file.
#
function create_vhost_laravel() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<- EOL
server {
    listen 80;
    listen [::]:80;
    http2 off;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    access_log /home/${USERNAME}/logs/nginx/access_log combined buffer=32k;
    error_log /home/${USERNAME}/logs/nginx/error_log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}/public";
    root \$root_path;
    index index.php index.html index.htm;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    #include /etc/nginx/includes/compression_gzip.conf;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://${SERVERNAME};

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://${SERVERNAME};

    # PageSpeed should be disabled on the admin (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/account/*";
    #pagespeed Disallow "*/dashboard/*";
    #pagespeed Disallow "*/admin/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "${SERVERNAME},*.${SERVERNAME}";

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "${SERVERNAME}";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "*.${SERVERNAME}";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_laravel.conf;

    ## Add your custom site directives here.

    ## End of custom site directives. 

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php$ {
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

    ## PHP-FPM status monitoring
    location ~ ^/php-fpm_(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Vhost created in dry run mode, no data written."
    fi
}

##
# Output Phalcon virtual host skeleton, fill with user input
# To be outputted into new file.
#
function create_vhost_phalcon() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<- EOL
server {
    listen 80;
    listen [::]:80;
    http2 off;

    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    access_log /home/${USERNAME}/logs/nginx/access_log combined buffer=32k;
    error_log /home/${USERNAME}/logs/nginx/error_log error;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}/public";
    root \$root_path;
    index index.php index.html index.htm;

    # Enable Compression.
    # gzip (default) or brotli (requires Nginx installed with brotli module).
    #include /etc/nginx/includes/compression_gzip.conf;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://${SERVERNAME};

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://${SERVERNAME};

    # PageSpeed should be disabled on the admin (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/account/*";
    #pagespeed Disallow "*/dashboard/*";
    #pagespeed Disallow "*/admin/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "${SERVERNAME},*.${SERVERNAME}";

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "${SERVERNAME}";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "*.${SERVERNAME}";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_phalcon.conf;

    ## Add your custom site directives here.

    ## End of custom site directives. 

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php {
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

    ## PHP-FPM status monitoring
    location ~ ^/php-fpm_(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;
}
EOL
    else
        info "Vhost created in dry run mode, no data written."
    fi
}

##
# Output Wordpress Multisite vHost header.
#
function prepare_vhost_wpms() {
    cat <<- EOL
# Wordpress Multisite Mapping for Nginx (Requires Nginx Helper plugin).
map \$http_host \$blogid {
    default 0;
    include ${WEBROOT}/wp-content/uploads/nginx-helper/[map].conf;
}

EOL
}

##
# Output server block for HTTP to HTTPS redirection.
#
function redirect_http_to_https() {
    cat <<- EOL

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

##
# Output index.html skeleton for default index page
# To be outputted into new index.html file in document root.
#
function create_index_file() {
    if [[ ${DRYRUN} != true ]]; then
        cat <<- EOL
<!DOCTYPE html>
<html lang="en">
<head>
<!--
Served by
 _     _____ __  __ ____           
| |   | ____|  \/  |  _ \ ___ _ __ 
| |   |  _| | |\/| | |_) / _ \ '__|
| |___| |___| |  | |  __/  __/ |   
|_____|_____|_|  |_|_|   \___|_|      
-->
<meta charset="utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Welcome to ${SERVERNAME}!</title>
<link href="https://fonts.googleapis.com/css?family=Cabin:400,700" rel="stylesheet">
<link href="https://fonts.googleapis.com/css?family=Montserrat:900" rel="stylesheet">
<style>
/**
 * Forked from Colorlib https://colorlib.com/etc/404/colorlib-error-404-3/
*/
*{-webkit-box-sizing:border-box;box-sizing:border-box}body{padding:0;margin:0}#errorpg{position:relative;height:100vh}#errorpg .errorpg{position:absolute;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%)}.errorpg{max-width:520px;width:100%;line-height:1.4;/*text-align:center*/}.errorpg .errorpg-msg{position:relative;height:240px}.errorpg .errorpg-msg h1{font-family:Montserrat,sans-serif;position:absolute;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%);font-size:252px;font-weight:900;margin:0;color:#262626;text-transform:uppercase;letter-spacing:-40px;margin-left:-20px}.errorpg .errorpg-msg h1>span{text-shadow:-8px 0 0 #fff}.errorpg .errorpg-msg h3{font-family:Cabin,sans-serif;position:relative;font-size:16px;font-weight:700;text-transform:uppercase;color:#262626;margin:0;letter-spacing:3px;padding-left:6px}.errorpg h2{font-family:Cabin,sans-serif;font-size:20px;font-weight:400;text-transform:uppercase;color:#000;margin-top:0;margin-bottom:25px}@media only screen and (max-width:767px){.errorpg .errorpg-msg{height:200px}.errorpg .errorpg-msg h1{font-size:200px}}@media only screen and (max-width:480px){.errorpg .errorpg-msg{height:162px}.errorpg .errorpg-msg h1{font-size:162px;height:150px;line-height:162px}.errorpg h2{font-size:16px}}
div.banner{color:#009639;font-family:Montserrat,sans-serif;position:absolute;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);-ms-transform:translate(-50%,-50%);transform:translate(-50%,-50%);font-size:180px;font-weight:900;margin:0;letter-spacing:-25px;margin-left:-10px}
</style>
<!--[if lt IE 9]>
<script src="https://oss.maxcdn.com/html5shiv/3.7.3/html5shiv.min.js"></script>
<script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
<![endif]-->
</head>
<body>
<div id="errorpg">
<div class="errorpg">
<div class="errorpg-msg">
<h3>Honest_Coder presents...</h3>
<div class="banner">
<span>L</span><span>E</span><span>M</span><span>P</span><span>er</span></div>
</div>
<h2>This is the default index page of your website.</h2>
<p>This file may be deleted or overwritten without any difficulty. This is produced by the file index.html in the web directory.</p>
<p>To disable this page, please remove the index.html file and replace it with your own. Our handy <a href="https://github.com/joglomedia/LEMPer/wiki">Quick Start Guide</a> can help you get up and running fast.</p>
<p>For questions or problems, please contact our support team.</p>
</div>
</div>
<script src="https://ajax.cloudflare.com/cdn-cgi/scripts/95c75768/cloudflare-static/rocket-loader.min.js" data-cf-settings="d841170f43ff1e03f58512ad-|49" defer=""></script>
</body>
</html>
EOL
    else
        info "index file created in dry run mode, no data written."
    fi
}

##
# Output PHP-FPM pool configuration
# To be outputted into new pool file in fpm/pool.d.
#
function create_fpm_pool_conf() {
    local POOLNAME="${1}"
    local PHPv="${2}"

    cat <<- EOL
[${POOLNAME}]
user = ${POOLNAME}
group = ${POOLNAME}

listen = /run/php/php${PHPv}-fpm.\$pool.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
;listen.allowed_clients = 127.1.0.1

; Custom PHP-FPM optimization, adjust here to meet your specs.
; Default value here is optimized for a single CPU with at least 1GB RAM.
pm = dynamic
pm.max_children = 30
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.process_idle_timeout = 30s
pm.max_requests = 500

pm.status_path = /php-fpm_status
ping.path = /php-fpm_ping

slowlog = /home/${POOLNAME}/logs/php/php${PHPv}-fpm_slow.log
request_slowlog_timeout = 10s

;chroot = /home/${POOLNAME}
chdir = /home/${POOLNAME}

;catch_workers_output = yes
;decorate_workers_output = no

security.limit_extensions = .php .php7 .php8 .php${PHPv//./}

; Custom PHP ini settings for LEMPer Stack.
php_admin_value[open_basedir] = /home/${POOLNAME}
;php_admin_value[disable_functions] = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals,exec,passthru,popen,proc_open,shell_exec,system
;php_admin_value[disable_classes] = 
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /home/${POOLNAME}/logs/php/php${PHPv}-fpm_error.log
php_admin_value[sys_temp_dir] = /home/${POOLNAME}/.lemper/tmp
php_admin_value[upload_tmp_dir] = /home/${POOLNAME}/.lemper/tmp
;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f www@my.domain.com

; Configuration below can be overwritten from PHP call 'ini_set'.
php_flag[short_open_tag] = off
php_value[max_execution_time] = 300
php_value[max_input_time] = 60
php_value[memory_limit] = 128M
php_value[post_max_size] = 50M
php_flag[file_uploads] = on
php_value[upload_max_filesize] = 50M
php_value[max_file_uploads] = 20
php_value[default_socket_timeout] = 60
php_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
php_flag[display_errors] = on
php_flag[cgi.fix_pathinfo] = 1
php_value[date.timezone] = UTC
php_value[session.save_handler] = files
php_value[session.save_path] = /home/${POOLNAME}/.lemper/php/sessions
php_value[soap.wsdl_cache_dir]  = /home/${POOLNAME}/.lemper/php/wsdlcache
php_value[opcache.file_cache] = /home/${POOLNAME}/.lemper/php/opcache
php_value[opcache.error_log] = /home/${POOLNAME}/logs/php/php${PHPv}-opcache_error.log
EOL
}

##
# Get server IP Address.
#
function get_ip_addr() {
    local SERVER_IP_PRIVATE && \
    SERVER_IP_PRIVATE=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    local SERVER_IP_PUBLIC && \
    SERVER_IP_PUBLIC=$(curl -s http://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${SERVER_IP_PRIVATE}" == "${SERVER_IP_PUBLIC}" ]]; then
        echo "${SERVER_IP_PRIVATE}"
    else
        echo "${SERVER_IP_PUBLIC}"
    fi
}

##
# Check whether IPv4 is valid.
#
function validate_ipv4() {
    local ip=${1}
    local return=false

    if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=${IFS}
        IFS='.' read -r -a ips <<< "${ip}"
        IFS=${OIFS}

        if [[ ${ips[0]} -le 255 && ${ips[1]} -le 255 && ${ips[2]} -le 255 && ${ips[3]} -le 255 ]]; then
            return=true
        fi
    fi

    echo ${return}
}

##
# Check whether IPv6 is valid.
#
function validate_ipv6() {
    local ip=${1}
    local return=false

    if [[ ${ip} =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        return=true
    fi

    echo ${return}
}

##
# Workaround for local domain (e.g. example.test)
# working on Local/Dev environment.
#
function add_local_domain() {
    local DOMAIN_IP && DOMAIN_IP=${1}
    local DOMAIN_NAME && DOMAIN_NAME=${2}

    if grep -qwE "${DOMAIN_NAME}" "/etc/hosts"; then
        LINE_EXISTS=$(grep "${DOMAIN_NAME}" /etc/hosts)
        warning "Domain hostname already exists: ${LINE_EXISTS}"
    else
        info "Adding ${DOMAIN_NAME} to your '/etc/hosts'..."
        run bash -c "echo -e '${DOMAIN_IP}\t${DOMAIN_NAME}' >> /etc/hosts"

        if grep -qwE "${DOMAIN_NAME}" "/etc/hosts"; then
            run service networking restart
            success "${DOMAIN_NAME} was added succesfully..."
        else
            error "Failed to add ${DOMAIN_NAME} to your '/etc/hosts', try again!"
        fi
    fi
}

##
# Create new Database for application.
#
function create_app_db() {
    echo "Creating application database (SQL)..."

    APP_UID="$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)"
    APP_DB_USER=${1:-"db_${APP_UID}"}
    APP_DB_PASS=${2:-"$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"}
    APP_DB_NAME=${3:-"app_${APP_UID}"}

    run lemper-cli db account create --dbuser="${APP_DB_USER}" --dbpass="${APP_DB_PASS}" && \
    run lemper-cli db create --dbname="${APP_DB_NAME}" --dbuser="${APP_DB_USER}"
}

##
# Install WordPress
# Installing WordPress skeleton.
#
function install_wordpress() {
    # Clone new WordPress skeleton files
    if [[ "${INSTALL_APP}" == true ]]; then
        # Check WordPress install directory.
        if [ ! -f "${WEBROOT}/wp-includes/class-wp.php" ]; then
            if [[ -z $(command -v "wp-cli") ]]; then
                info "WP CLI command not found, trying to install it first."
                run wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
                     -O /usr/local/bin/wp-cli  && \
                run chmod ugo+x /usr/local/bin/wp-cli && \
                run ln -sf /usr/local/bin/wp-cli /usr/bin/wp-cli
            fi

            # Download WordPress skeleton files.
            run sudo -u "${USERNAME}" -i -- wp-cli core download --path="${WEBROOT}"

            # create_app_db [app_db_username] [app_db_password] [app_db_name]
            create_app_db "${APP_DB_USER}" "${APP_DB_PASS}" "${APP_DB_NAME}"

            run sudo -u "${USERNAME}" -i -- wp-cli config create --dbname="${APP_DB_NAME}" \
                --dbuser="${APP_DB_USER}" --dbpass="${APP_DB_PASS}" --dbprefix=ls_ --path="${WEBROOT}"
        else
            info "It seems that WordPress files already exists."
        fi
    else
        # Create default index file.
        echo "Creating default WordPress index file..."

        if [ ! -e "${WEBROOT}/index.html" ]; then
            create_index_file > "${WEBROOT}/index.html"
        fi
    fi

    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"
}

##
# Main App
#
function init_lemper_create() {
    # Command line arguments.
    OPTS=$(getopt -o u:d:e:f:4:6:w:p:iScPsFWDhv \
      -l username:,domain-name:,admin-email:,framework:,ipv4:,ipv6:,webroot:,php-version:,install-app,subdomains \
      -l enable-fastcgi-cache,enable-pagespeed,enable-ssl,enable-fail2ban,wildcard-domain,dryrun,help,version \
      -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

    # Default parameter values.
    IPv4=""
    IPv6=""
    USERNAME=""
    SERVERNAME=""
    WEBROOT=""
    FRAMEWORK="default"
    PHP_VERSION="8.1"
    INSTALL_APP=false
    WPMS_SUBDOMAINS=""
    ENABLE_FASTCGI_CACHE=false
    ENABLE_PAGESPEED=false
    ENABLE_SSL=false
    ENABLE_WILDCARD_DOMAIN=false
    ENABLE_FAIL2BAN=false
    TMPDIR="/tmp/lemper"

    # Dry run (test mode).
    DRYRUN=false

    # Args counter
    MAIN_ARGS=0

    # Parse flags
    while true; do
        case "${1}" in
            -4 | --ipv4)
                shift
                IPv4="${1}"
                shift
            ;;
            -6 | --ipv6)
                shift
                IPv6="${1}"
                shift
            ;;
            -d | --domain-name)
                shift
                SERVERNAME="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -e | --admin-email)
                shift
                APP_ADMIN_EMAIL="${1}"
                shift
            ;;
            -f | --framework)
                shift
                FRAMEWORK="${1}"
                shift
            ;;
            -u | --username)
                shift
                USERNAME="${1}"
                shift
            ;;
            -w | --webroot)
                shift
                # Remove badly and trailing slash.
                #WEBROOT=$(echo "${1}" | sed 's:/*$::')
                WEBROOT=$(echo "${1}" | tr -s /)
                shift
            ;;
            -p | --php-version)
                shift
                PHP_VERSION="${1}"
                shift
            ;;

            -c | --enable-fastcgi-cache)
                shift
                ENABLE_FASTCGI_CACHE=true
            ;;
            -D | --dryrun)
                shift
                DRYRUN=true
            ;;
            -F | --enable-fail2ban)
                shift
                ENABLE_FAIL2BAN=true
            ;;
            -h | --help)
                shift
                show_usage
                exit 0
            ;;
            -i | --install-app)
                shift
                INSTALL_APP=true
            ;;
            -S | --subdomains)
                shift
                WPMS_SUBDOMAINS="--subdomains"
            ;;
            -P | --enable-pagespeed)
                shift
                ENABLE_PAGESPEED=true
            ;;
            -s | --enable-ssl)
                shift
                ENABLE_SSL=true
            ;;
            -v | --version)
                shift
                echo "${PROG_NAME} version ${PROG_VER}"
                exit 0
            ;;
            -W | --wildcard-domain)
                shift
                ENABLE_WILDCARD_DOMAIN=true
            ;;
            --)
                # End of all options, shift to the next (non getopt) argument as $1. 
                shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    if [[ "${MAIN_ARGS}" -ge 1 ]]; then
        # Additional Check - ensure that Nginx's configuration meets the requirements.
        if [[ ! -d /etc/nginx/sites-available && ! -d /etc/nginx/vhost ]]; then
            fail "It seems that your Nginx installation doesn't meet LEMPer requirements. Aborting..."
        fi

        # Check domain parameter.
        if [[ -z "${SERVERNAME}" ]]; then
            fail -e "Domain name parameter shouldn't be empty.\n       -d or --domain-name parameter is required!"
        else
            if ! grep -qP "(?=^.{4,253}\.?$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}\.?$)" <<< "${SERVERNAME}"; then
                fail -e "Domain name parameter must be a valid FQDN!"
            fi
        fi

        # Make temp dir.
        if [[ ! -d "${TMPDIR}" ]]; then
            run mkdir -p "${TMPDIR}"
        fi

        # Define vhost file.
        VHOST_FILE="/etc/nginx/sites-available/${SERVERNAME}.conf"

        # Check if vhost not exists.
        if [[ ! -f "${VHOST_FILE}" ]]; then
            echo "Add new domain name '${SERVERNAME}' to virtual host."

            # Check for username.
            if [[ -z "${USERNAME}" ]]; then
                info "Username parameter is empty. Attempt to use default '${LEMPER_USERNAME}' account."
                USERNAME=${LEMPER_USERNAME:-"lemper"}
            fi

            # Additional Check - are user account exist?
            if [[ -z $(getent passwd "${USERNAME}") ]]; then
                fail "User account '${USERNAME}' does not exist. Please add new account first! Aborting..."
            fi

            # Check PHP runtime version is exists.
            if [[ -n $(command -v "php${PHP_VERSION}") && -d "/etc/php/${PHP_VERSION}/fpm" ]]; then
                # PHP runtime commands.
                PHP_BIN=$(command -v "php${PHP_VERSION}")
                PHP_COMPOSER_BIN=$(command -v "composer")

                # Additional check - if FPM user's pool doesn't exist.
                if [[ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" ]]; then
                    info "The PHP${PHP_VERSION} FPM pool configuration for user ${USERNAME} doesn't exist."
                    echo "Creating new PHP-FPM pool '${USERNAME}' configuration..."

                    # Create PHP FPM pool conf.
                    create_fpm_pool_conf "${USERNAME}" "${PHP_VERSION}" > "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf"

                    # Create default directories & log files.
                    run mkdir -p "/home/${USERNAME}/.lemper/tmp"
                    run mkdir -p "/home/${USERNAME}/.lemper/php/opcache"
                    run mkdir -p "/home/${USERNAME}/.lemper/php/sessions"
                    run mkdir -p "/home/${USERNAME}/.lemper/php/wsdlcache"
                    run mkdir -p "/home/${USERNAME}/cgi-bin"
                    run mkdir -p "/home/${USERNAME}/logs/php"
                    run touch "/home/${USERNAME}/logs/php/php${PHP_VERSION}-fpm_slow.log"
                    run touch "/home/${USERNAME}/logs/php/php${PHP_VERSION}-fpm_error.log"
                    run touch "/home/${USERNAME}/logs/php/php${PHP_VERSION}-opcache_error.log"
                    run chown -hR "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.lemper" "/home/${USERNAME}/cgi-bin" "/home/${USERNAME}/logs"

                    # Restart PHP FPM.
                    echo "Restart php${PHP_VERSION}-fpm configuration..."

                    run systemctl restart "php${PHP_VERSION}-fpm"

                    success "New php${PHP_VERSION}-fpm pool [${USERNAME}] has been created."
                fi
            else
                fail "Oops, PHP ${PHP_VERSION} runtime not found. Please install it first! Aborting..."
            fi

            # Check web root parameter.
            if [[ -z "${WEBROOT}" ]]; then
                WEBROOT="/home/${USERNAME}/webapps/${SERVERNAME}"
                info "Webroot parameter is empty. Set to default web root '${WEBROOT}'."
            fi

            # Creates document root.
            if [[ ! -d "${WEBROOT}" ]]; then
                echo "Creating web root directory '${WEBROOT}'..."

                run mkdir -p "${WEBROOT}" && \
                run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}" && \
                run chmod 755 "${WEBROOT}"
            fi

            # Set default application credential data.
            APP_UID="$(openssl rand -base64 32 | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"
            APP_DB_USER="${USERNAME}_${APP_UID}"
            APP_DB_PASS="$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
            APP_DB_NAME="app_${APP_UID}"
            APP_ADMIN_USER="admin"
            APP_ADMIN_PASS="$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
            [[ -z "${APP_ADMIN_EMAIL}" ]] && APP_ADMIN_EMAIL=${LEMPER_ADMIN_EMAIL:-"admin@${SERVERNAME}"}

            # Check framework parameter.
            if [[ -z "${FRAMEWORK}" ]]; then
                FRAMEWORK="default"
                info "Framework parameter is empty. Set to default framework '${FRAMEWORK}'."
            fi

            echo "Selecting '${FRAMEWORK^}' framework..."

            # Ugly hacks for custom framework-specific configs + Skeleton auto installer.
            case "${FRAMEWORK}" in
                codeigniter)
                    echo "Setting up CodeIgniter framework virtual host..."

                    # Clone CodeIgniter skeleton files.
                    if [[ ${INSTALL_APP} == true ]]; then
                        # Checking CodeIgniter installation.
                        if [[ ! -f "${WEBROOT}/spark" ]]; then
                            echo "Downloading CodeIgniter v4 skeleton files..."

                            if [[ -n "${PHP_COMPOSER_BIN}" ]]; then
                                run "${PHP_BIN}" "${PHP_COMPOSER_BIN}" create-project --prefer-source codeigniter4/appstarter "${WEBROOT}"
                            else
                                run git clone --depth=1 --branch=master "https://github.com/codeigniter4/appstarter.git" "${WEBROOT}" || \
                                error "Something went wrong while downloading CodeIgniter v4 files."
                            fi
                        else
                            info "It seems that CodeIgniter v4 skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        if [[ ! -e "${WEBROOT}/public/index.php" ]]; then
                            echo "Creating default index file..."
                            run mkdir -p "${WEBROOT}/public"
                            create_index_file > "${WEBROOT}/public/index.html"
                        fi
                    fi

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_laravel > "${VHOST_FILE}"
                ;;

                drupal)
                    echo "Setting up Drupal virtual host..."

                    # Clone Drupal skeleton files.
                    if [[ ${INSTALL_APP} == true ]]; then
                        # Checking Drupal installation.
                        if [[ ! -d "${WEBROOT}/core/lib/Drupal" ]]; then
                            echo "Downloading Drupal latest skeleton files..."

                            if curl -sLI https://www.drupal.org/download-latest/zip | grep -q "HTTP/[.12]* [2].."; then
                                run wget https://www.drupal.org/download-latest/zip \
                                    -O "${TMPDIR}/drupal.zip"  && \
                                run unzip -q "${TMPDIR}/drupal.zip" -d "${TMPDIR}" && \
                                run rsync -rq ${TMPDIR}/drupal-*/ "${WEBROOT}" && \
                                run rm -f "${TMPDIR}/drupal.zip" && \
                                run rm -fr ${TMPDIR}/drupal-*/
                            else
                                error "Something went wrong while downloading Drupal files."
                            fi
                        else
                            info "It seems that Drupal files already exists."
                        fi
                    else
                        # Create default index file.
                        if [[ ! -e "${WEBROOT}/index.php" ]]; then
                            echo "Creating default index file..."
                            create_index_file > "${WEBROOT}/index.html"
                        fi
                    fi

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_drupal > "${VHOST_FILE}"
                ;;

                laravel | lumen)
                    echo "Setting up ${FRAMEWORK^} framework virtual host..."

                    # Clone Laravel/Lumen skeleton files.
                    if [[ ${INSTALL_APP} == true ]]; then
                        # Checking Laravel installation.
                        if [[ ! -f "${WEBROOT}/artisan" ]]; then
                            echo "Downloading ${FRAMEWORK^} skeleton files..."

                            if [[ -n "${PHP_COMPOSER_BIN}" ]]; then
                                run sudo -u "${USERNAME}" -i -- "${PHP_BIN}" "${PHP_COMPOSER_BIN}" \
                                    create-project --prefer-dist "laravel/${FRAMEWORK}" "${WEBROOT}"
                            else
                                run git clone --depth=1 --branch=master "https://github.com/laravel/${FRAMEWORK}.git" "${WEBROOT}" || \
                                error "Something went wrong while downloading ${FRAMEWORK^} files."
                            fi

                            # create_app_db [app_db_username] [app_db_password] [app_db_name]
                            create_app_db "${APP_DB_USER}" "${APP_DB_PASS}" "${APP_DB_NAME}"
                        else
                            info "It seems that ${FRAMEWORK^} skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        if [[ ! -e "${WEBROOT}/public/index.php" ]]; then
                            echo "Creating default index file..."
                            run mkdir -p "${WEBROOT}/public"
                            create_index_file > "${WEBROOT}/public/index.html"
                        fi
                    fi

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Return Lumen framework as Laravel for vhost creation.
                    [[ "${FRAMEWORK}" == "lumen" ]] && FRAMEWORK="laravel"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_laravel > "${VHOST_FILE}"
                ;;

                phalcon | phalcon-cli | phalcon-micro | phalcon-modules)
                    echo "Setting up Phalcon framework virtual host..."

                    # Clone Phalcon skeleton files.
                    if [[ ${INSTALL_APP} == true ]]; then
                        # Checking Phalcon installation.
                        if [[ ! -f "${WEBROOT}/app/config/config.php" ]]; then
                            echo "Downloading ${FRAMEWORK} skeleton files..."

                            # Switch Phalcon framework type.
                            case "${FRAMEWORK}" in
                                phalcon-cli)
                                    PHALCON_TYPE="cli"
                                ;;
                                phalcon-micro)
                                    PHALCON_TYPE="micro"
                                ;;
                                phalcon-modules)
                                    PHALCON_TYPE="modules"
                                ;;
                                *)
                                    PHALCON_TYPE="simple"
                                ;;
                            esac

                            if [[ -n $(command -v phalcon) ]]; then
                                PHP_PHALCON_BIN=$(command -v phalcon)
                                run sudo -u "${USERNAME}" -i -- "${PHP_PHALCON_BIN}" project \
                                    --name="${SERVERNAME}" --type="${PHALCON_TYPE}" --directory="/home/${USERNAME}/webapps"
                            else
                                run git clone --depth=1 --branch=master "https://github.com/joglomedia/${FRAMEWORK}-skeleton.git" "${WEBROOT}" || \
                                error "Something went wrong while downloading ${FRAMEWORK} files."
                            fi
                        else
                            info "It seems that ${FRAMEWORK} skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        if [[ ! -e "${WEBROOT}/public/index.php" ]]; then
                            echo "Creating default index file..."
                            run mkdir -p "${WEBROOT}/public"
                            create_index_file > "${WEBROOT}/public/index.html"
                        fi
                    fi

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Return Micro framework as Phalcon for vhost creation.
                    [[ "${FRAMEWORK}" == "phalcon-cli" || "${FRAMEWORK}" == "phalcon-micro" || "${FRAMEWORK}" == "phalcon-modules" ]] \
                    && FRAMEWORK="phalcon"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_phalcon > "${VHOST_FILE}"
                ;;

                symfony)
                    echo "Setting up Symfony framework virtual host..."

                    # Clone Symfony skeleton files.
                    if [[ ${INSTALL_APP} == true ]]; then
                        # Checking Symfony installation.
                        if [ ! -f "${WEBROOT}/src/Kernel.php" ]; then
                            echo "Downloading Symfony skeleton files..."

                            if [[ -n "${PHP_COMPOSER_BIN}" ]]; then
                                run composer create-project --prefer-dist symfony/website-skeleton "${WEBROOT}"
                            else
                                warning "Symfony CLI not found, trying to install it first..."
                                run wget https://get.symfony.com/cli/installer -O - | bash

                                if [[ -f "${HOME}/.symfony/bin/symfony" ]]; then
                                    run cp -f "${HOME}/.symfony/bin/symfony" /usr/local/bin/symfony
                                    run chmod ugo+x /usr/local/bin/symfony
                                else
                                    run export PATH="${HOME}/.symfony/bin:${PATH}"
                                fi

                                run sudo -u "${USERNAME}" -i -- symfony new "${WEBROOT}" --full
                            fi
                        else
                            info "It seems that Symfony skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        if [[ ! -e "${WEBROOT}/index.php" ]]; then
                            echo "Creating default index file..."
                            create_index_file > "${WEBROOT}/index.html"
                        fi
                    fi
                    
                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                wordpress | woocommerce)
                    echo "Setting up WordPress virtual host..."

                    # Install WordPress skeleton.
                    install_wordpress

                    APP_ADMIN_USER="wpadmin"

                    if command -v wp-cli &> /dev/null; then
                        run sudo -u "${USERNAME}" -i -- wp-cli core install --url="${SERVERNAME}" \
                            --title="WordPress Managed by LEMPer Stack" \
                            --admin_user="${APP_ADMIN_USER}" --admin_password="${APP_ADMIN_PASS}" \
                            --admin_email="${APP_ADMIN_EMAIL}" --path="${WEBROOT}" && \
                        run sudo -u "${USERNAME}" -i -- wp-cli plugin install \
                            akismet autoptimize cache-enabler classic-editor nginx-helper redis-cache --activate --path="${WEBROOT}"
                    fi

                    # Install WooCommerce.
                    if [[ "${FRAMEWORK}" == "woocommerce" ]]; then
                        if [[ -d "${WEBROOT}/wp-content/plugins" && \
                            ! -d "${WEBROOT}/wp-content/plugins/woocommerce" ]]; then
                            echo "Add WooCommerce plugin into WordPress skeleton..."

                            if command -v wp-cli &> /dev/null; then
                                run sudo -u "${USERNAME}" -i -- wp-cli plugin install woocommerce --activate --path="${WEBROOT}"
                                run sudo -u "${USERNAME}" -i -- wp-cli theme install storefront --activate --path="${WEBROOT}"
                            else
                                if wget -q -O "${TMPDIR}/woocommerce.zip" \
                                    https://downloads.wordpress.org/plugin/woocommerce.zip; then
                                    run unzip -q "${TMPDIR}/woocommerce.zip" -d "${WEBROOT}/wp-content/plugins/"
                                    run rm -f "${TMPDIR}/woocommerce.zip"
                                else
                                    error "Something went wrong while downloading WooCommerce files."
                                fi
                            fi
                        fi
                    fi

                    # Return WooCommerce as WordPress for vhost creation.
                    [[ "${FRAMEWORK}" == "woocommerce" ]] && FRAMEWORK="wordpress"

                    # Create vhost.
                    echo "Create virtual host file: ${VHOST_FILE}"
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                wordpress-ms)
                    echo "Setting up WordPress Multi-site virtual host..."

                    # Install WordPress.
                    install_wordpress

                    APP_ADMIN_USER="wpadmin"

                    if command -v wp-cli &> /dev/null; then
                        run sudo -u "${USERNAME}" -i -- wp-cli core multisite-install "${WPMS_SUBDOMAINS}" --url="${SERVERNAME}" \
                            --title="WordPress Multisite Managed by LEMPer Stack" --admin_user="${APP_ADMIN_USER}" \
                            --admin_password="${APP_ADMIN_PASS}" --admin_email="${APP_ADMIN_EMAIL}" --path="${WEBROOT}" && \
                        run sudo -u "${USERNAME}" -i -- wp-cli plugin install \
                            akismet autoptimize cache-enabler classic-editor nginx-helper redis-cache --activate-network --path="${WEBROOT}"
                    fi

                    # Mercator domain mapping.
                    run git clone --depth=1 --branch=master https://github.com/humanmade/Mercator.git "${WEBROOT}/wp-content/mu-plugins/mercator" && \
                    cat > "${WEBROOT}/wp-content/sunrise.php" <<EOL
<?php
// Default mu-plugins directory if you haven't set it
defined( 'WPMU_PLUGIN_DIR' ) or define( 'WPMU_PLUGIN_DIR', WP_CONTENT_DIR . '/mu-plugins' );

require WPMU_PLUGIN_DIR . '/mercator/mercator.php';
EOL

                    # Enable sunrise. (insert new line before match)
                    run sed -i "/\/*\ That/i define( 'SUNRISE', true );\n" "${WEBROOT}/wp-config.php"

                    # Pre-populate blog id mapping, used by Nginx vhost config.
                    if [[ ! -d "${WEBROOT}/wp-content/uploads/nginx-helper" ]]; then
                        run mkdir -p "${WEBROOT}/wp-content/uploads/nginx-helper"
                    fi

                    if [[ ! -f "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf" ]]; then
                        run touch "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf"
                    fi

                    echo "Creating virtual host file: ${VHOST_FILE}..."

                    # Prepare vhost specific rule for WordPress Multisite.
                    prepare_vhost_wpms > "${VHOST_FILE}"

                    # Create vhost.
                    create_vhost_default >> "${VHOST_FILE}"

                    # Enable wildcard host.
                    if grep -qwE "server_name\ ${SERVERNAME};$" "${VHOST_FILE}"; then
                        run sed -i "s/server_name\ ${SERVERNAME};/server_name\ ${SERVERNAME}\ \*.${SERVERNAME};/g" \
                            "${VHOST_FILE}"
                    fi
                ;;

                filerun)
                    echo "Setting up FileRun virtual host..."

                    # Install FileRun skeleton.
                    if [[ ${INSTALL_APP} == true ]]; then
                        # Clone new Filerun files.
                        if [ ! -f "${WEBROOT}/system/classes/filerun.php" ]; then
                            echo "Downloading FileRun skeleton files..."
                            
                            if wget -q -O "${TMPDIR}/FileRun.zip" http://www.filerun.com/download-latest; then
                                run unzip -q "${TMPDIR}/FileRun.zip" -d "${WEBROOT}"
                                run rm -f "${TMPDIR}/FileRun.zip"
                            else
                                error "Something went wrong while downloading FileRun files."
                            fi
                        else
                            info "FileRun skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        echo "Creating default index files..."

                        if [[ ! -e "${WEBROOT}/index.html" ]]; then
                            create_index_file > "${WEBROOT}/index.html"
                        fi
                    fi
                    
                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                default | mautic | roundcube | sendy)
                    # TODO: Auto install framework skeleton.

                    # Create default index file.
                    if [[ ! -e "${WEBROOT}/index.html" ]]; then
                        create_index_file > "${WEBROOT}/index.html"
                    fi

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create default vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                *)
                    # Not supported framework/cms, abort.
                    fail "Sorry, your framework/cms '${FRAMEWORK^}' is not supported yet. Please submit an issue at Github..."
                    exit 1
                ;;
            esac

            if [[ ${DRYRUN} != true ]]; then
                # Confirm virtual host.
                if grep -qwE "server_name ${SERVERNAME}" "${VHOST_FILE}"; then
                    success "New domain ${SERVERNAME} successfuly added to virtual host."
                fi

                # Creates Well-Known URIs: RFC 8615.
                echo "Creating .well-known directory (RFC8615)..."

                if [[ -d "${WEBROOT}/public" ]]; then
                    run mkdir -p "${WEBROOT}/public/.well-known/acme-challenge"
                else
                    run mkdir -p "${WEBROOT}/.well-known/acme-challenge"
                fi

                # Create log files.
                run touch "${WEBROOT}/access_log"
                run touch "${WEBROOT}/error_log"

                # Assign IPv4 to server vhost.
                if [[ $(validate_ipv4 "${IPv4}") == true ]]; then
                    echo "Assigning IPv4 ${IPv4} to ${SERVERNAME}..."

                    if grep -qwE "listen\ 80" "${VHOST_FILE}"; then
                        run sed -i "s/^\    listen\ 80/\    listen ${IPv4}:80/g" "${VHOST_FILE}"

                        # Add local domain (e.g. example.test) to hosts file.
                        add_local_domain "${IPv4}" "${SERVERNAME}"
                    fi
                fi

                # Assign IPv6 to server vhost.
                if [[ $(validate_ipv6 "${IPv6}") == true ]]; then
                    echo "Assigning IPv6 ${IPv6} to ${SERVERNAME}..."

                    if grep -qwE "listen\ \[::\]:80" "${VHOST_FILE}"; then
                        run sed -i "s/^\    listen\ \[::\]:80/\    listen [${IPv6}]:80/g" "${VHOST_FILE}"

                        # Add local domain (e.g. example.test) to hosts file.
                        add_local_domain "${IPv6}" "${SERVERNAME}"
                    fi
                fi

                # Enable Wildcard domain.
                if [[ ${ENABLE_WILDCARD_DOMAIN} == true ]]; then
                    echo "Enable wildcard domain for ${SERVERNAME}..."

                    if grep -qwE "server_name\ ${SERVERNAME};$" "${VHOST_FILE}"; then
                        run sed -i "s/server_name\ ${SERVERNAME};/server_name\ ${SERVERNAME}\ \*.${SERVERNAME};/g" "${VHOST_FILE}"
                    fi
                fi

                # Enable FastCGI cache.
                if [[ ${ENABLE_FASTCGI_CACHE} == true ]]; then
                    echo "Enable FastCGI cache for ${SERVERNAME}..."

                    if [[ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]]; then
                        # enable cached directives
                        run sed -i "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" "${VHOST_FILE}"
                        # enable fastcgi_cache conf
                        run sed -i "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" "${VHOST_FILE}"
                    else
                        info "FastCGI cache is not enabled due to no cached version of ${FRAMEWORK^} directive."
                    fi
                fi

                # Enable PageSpeed.
                if [[ ${ENABLE_PAGESPEED} == true ]]; then
                    echo "Enable Mod PageSpeed for ${SERVERNAME}..."

                    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/60-mod-pagespeed.conf ]]; then
                        # enable mod pagespeed
                        run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" /etc/nginx/nginx.conf
                        run sed -i "s|#include\ /etc/nginx/includes/mod_pagespeed.conf|include\ /etc/nginx/includes/mod_pagespeed.conf|g" "${VHOST_FILE}"
                        run sed -i "s|#pagespeed\ EnableFilters|pagespeed\ EnableFilters|g" "${VHOST_FILE}"
                        run sed -i "s|#pagespeed\ Disallow|pagespeed\ Disallow|g" "${VHOST_FILE}"
                        run sed -i "s|#pagespeed\ Domain|pagespeed\ Domain|g" "${VHOST_FILE}"
                    else
                        info "Mod PageSpeed is not enabled. Nginx must be installed with PageSpeed module."
                    fi
                fi

                # Enable fail2ban filter
                if [[ "${ENABLE_FAIL2BAN}" == true ]]; then
                    echo "Enable Fail2ban ${FRAMEWORK^} filter for ${SERVERNAME}..."

                    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/filter.d/${FRAMEWORK}.conf" ]]; then
                        cat > "/etc/fail2ban/jail.d/${SERVERNAME}.conf" <<EOL
[${SERVERNAME}]
enabled = true
port = http,https
filter = ${FRAMEWORK}
action = iptables-multiport[name=webapps, port="http,https", protocol=tcp]
logpath = ${WEBROOT}/access_log
bantime = 30d
findtime = 5m
maxretry = 3
EOL

                        # Reload fail2ban
                        run service fail2ban reload
                    else
                        info "Fail2ban or filter is not installed. Please install it first."
                    fi
                fi

                echo "Fix files ownership and permission..."

                # Fix document root ownership.
                run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                # Fix document root permission.
                if [[ $(ls -A "${WEBROOT}") ]]; then
                    run find "${WEBROOT}" -type d -print0 | xargs -0 chmod 755
                    run find "${WEBROOT}" -type f -print0 | xargs -0 chmod 644
                fi
            else
                info "New domain ${SERVERNAME} added in dry run mode."
            fi

            echo "Enable ${SERVERNAME} virtual host."

            # Enable site.
            if [[ ! -f "/etc/nginx/sites-enabled/${SERVERNAME}.conf" ]]; then
                run ln -s "/etc/nginx/sites-available/${SERVERNAME}.conf" \
                    "/etc/nginx/sites-enabled/${SERVERNAME}.conf"
            fi

            # Reload Nginx
            echo "Reloading Nginx server configuration..."

            # Validate config, reload when validated.
            if nginx -t 2>/dev/null > /dev/null; then
                run systemctl restart nginx
                echo "Nginx server reloaded with new configuration."
            else
                info "Something went wrong with Nginx configuration."
            fi

            if [[ -f "/etc/nginx/sites-enabled/${SERVERNAME}.conf" && -e /var/run/nginx.pid ]]; then
                success "Your ${SERVERNAME} successfully added to Nginx virtual host."

                # Enable HTTPS.
                if [[ ${ENABLE_SSL} == true ]]; then
                    echo ""
                    echo "You can enable HTTPS from lemper-cli after this setup!"
                    echo "command: lemper-cli manage --enable-ssl ${SERVERNAME}"
                fi

                # WordPress MS notice.
                if [[ "${FRAMEWORK}" == "wordpress-ms" ]]; then
                    echo ""
                    info -e "You're installing Wordpress Multisite.\nYou should activate Nginx Helper plugin to work properly."
                fi

                # Save app installation details.
                if [[ ${INSTALL_APP} == true ]]; then
                    echo -e "\nYour application login details:\nAdmin user: ${APP_ADMIN_USER}\nAdmin pass: ${APP_ADMIN_PASS}\nAdmin email: ${APP_ADMIN_EMAIL}"
                    echo -e "Database user: ${APP_DB_USER}\nDatabase pass: ${APP_DB_PASS}\nDatabase name: ${APP_DB_NAME}"
                    cat > "/etc/lemper/vhost.d/${SERVERNAME}.conf" <<EOL
[${SERVERNAME}]
APP_UID="${APP_UID}"
APP_FRAMEWORK="${FRAMEWORK}"
APP_DB_USER="${APP_DB_USER}"
APP_DB_PASS="${APP_DB_PASS}"
APP_DB_NAME="${APP_DB_NAME}"
APP_ADMIN_USER="${APP_ADMIN_USER}"
APP_ADMIN_PASS="${APP_ADMIN_PASS}"
APP_ADMIN_EMAIL="${APP_ADMIN_EMAIL}"
APP_WEBROOT="${WEBROOT}"
EOL
                    chmod 0600 "/etc/lemper/vhost.d/${SERVERNAME}.conf"
                fi
            else
                if [[ ${DRYRUN} == true ]]; then
                    info "Your ${SERVERNAME} successfully added in dry run mode."
                else
                    fail "An error occurred when adding ${SERVERNAME} to Nginx virtual host."
                fi
            fi
        else
            error "Virtual host config file for ${SERVERNAME} is already exists. Aborting..."
        fi
    else
        echo "${PROG_NAME}: missing required arguments."
        echo "See '${PROG_NAME} --help' for more information."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_create "$@"
