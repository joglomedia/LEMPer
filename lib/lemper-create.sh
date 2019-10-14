#!/bin/bash

# +-------------------------------------------------------------------------+
# | Lemper Create - Simple LEMP Virtual Host Generator                      |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/lemper)               |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

set -e

# Version Control.
APP_NAME=$(basename "$0")
APP_VERSION="1.3.0"
CMD_PARENT="lemper-cli"
CMD_NAME="create"

# Test mode.
DRYRUN=false

# Decorator.
RED=91
GREEN=92
YELLOW=93

DRYRUN=false

function begin_color() {
    color="${1}"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="${1}"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    #local error_message="$@"
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
function run() {
    if "${DRYRUN}"; then
        echo_color "$YELLOW" -n "would run "
        echo "$@"
    else
        if ! "$@"; then
            local CMDSTR="$*"
            error "Failure running '${CMDSTR}', exiting."
            exit 1
        fi
    fi
}

# May need to run this as sudo!
# I have it in /usr/local/bin and run command 'ngxvhost' from anywhere, using sudo.
if [ "$(id -u)" -ne 0 ]; then
    error "This command can only be used by root."
    exit 1  #error
fi

# Check prerequisite packages.
if [[ ! -f $(command -v unzip) || ! -f $(command -v git) || ! -f $(command -v rsync) ]]; then
    warning "${APP_NAME^} requires rsync, unzip and git, please install it first!"
    echo "help: sudo apt-get install rsync unzip git"
    exit 0
fi

## Show usage
# output to STDERR.
#
function show_usage {
cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Creates NGiNX virtual host (vHost) configuration file.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage: ${CMD_PARENT} ${CMD_NAME} [options]...
       ${CMD_PARENT} ${CMD_NAME} -d <domain-name> -f <framework>
       ${CMD_PARENT} ${CMD_NAME} -d <domain-name> -f <framework> -w <webroot-path>

Options:
  -d, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed, i.e. example.app or sub.example.app.
  -f, --framework <website framework>
      Type of PHP web Framework and CMS, i.e. default.
      Supported Framework and CMS: default (vanilla PHP), codeigniter, drupal, laravel,
      lumen, mautic, phalcon, sendy, symfony, wordpress, wordpress-ms.
      Another framework and cms will be added soon.
  -p, --php-version
      PHP version for selected framework. Latest recommended PHP version is "7.3".
  -u, --username <virtual-host username>
      Use username added from adduser/useradd. Do not use root user!!
  -w, --webroot <web root>
      Web root is an absolute path to the website root directory, i.e. /home/lemper/webapps/example.test.

  -s, --clone-skeleton
      Clone default skeleton for selected framework.
  -c, --enable-fastcgi-cache
      Enable FastCGI cache module.
  -S, --enable-https
      Enable HTTPS with Let's Encrypt free SSL certificate.
  -P, --enable-pagespeed
      Enable Nginx mod_pagespeed.
  -W, --wildcard-domain
      Enable wildcard (*) domain.

  -D, --dryrun
      Dry run mode, only for testing.
  -h, --help
      Print this message and exit.
  -v, --version
      Show version number and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} -u lemper -d example.com -f default -w /home/lemper/webapps/example.test

For more informations visit https://eslabs.id/lemper
Mail bug reports and suggestions to <eslabs.id@gmail.com>
_EOF_
}

## Output Default virtual host directive, fill with user input
# To be outputted into new file
# Work for default and WordPress site.
#
function create_vhost_default() {
cat <<- _EOF_
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log ${WEBROOT}/access_log combined buffer=32k;
    error_log ${WEBROOT}/error_log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}";
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://\$server_name;

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://\$server_name;

    # PageSpeed should be disabled on the WP admin/dashboard (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/admin/*";
    #pagespeed Disallow "*/dashboard/*";
    #pagespeed Disallow "*/wp-login*";
    #pagespeed Disallow "*/wp-admin/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "http://*.\$server_name, https://*.\$server_name";
    #include /etc/nginx/includes/cors.conf;

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "http://*.\$server_name";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "https://*.\$server_name";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_${FRAMEWORK}.conf;

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
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    include /etc/nginx/includes/error_pages.conf;

    ## Uncomment to enable support cgi-bin scripts using fcgiwrap (like cgi-bin in Apache).
    #include /etc/nginx/includes/fcgiwrap.conf;

    ## Add your custom site directives here.
}
_EOF_
}

## Output Drupal virtual host directive, fill with user input
# To be outputted into new file.
#
function create_vhost_drupal() {
cat <<- _EOF_
server {
    listen 80;
    listen [::]:80;

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log ${WEBROOT}/access_log combined buffer=32k;
    error_log ${WEBROOT}/error_log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}";
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://\$server_name;

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://\$server_name;

    # PageSpeed should be disabled on the user panel (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/user/*";
    #pagespeed Disallow "*/account/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "http://*.\$server_name, https://*.\$server_name";
    #include /etc/nginx/includes/cors.conf;

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "http://*.\$server_name";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "https://*.\$server_name";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_${FRAMEWORK}.conf;

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
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    include /etc/nginx/includes/error_pages.conf;

    ## Add your custom site directives here.
}
_EOF_
}

## Output Laravel virtual host skeleton, fill with user input
# To be outputted into new file.
#
function create_vhost_laravel() {
cat <<- _EOF_
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log ${WEBROOT}/access_log combined buffer=32k;
    error_log ${WEBROOT}/error_log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}/public";
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://\$server_name;

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://\$server_name;

    # PageSpeed should be disabled on the admin (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/account/*";
    #pagespeed Disallow "*/dashboard/*";
    #pagespeed Disallow "*/admin/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "http://*.\$server_name, https://*.\$server_name";
    #include /etc/nginx/includes/cors.conf;

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "http://*.\$server_name";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "https://*.\$server_name";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_${FRAMEWORK}.conf;

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
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    include /etc/nginx/includes/error_pages.conf;

    ## Add your custom site directives here.
}
_EOF_
}

## Output Phalcon virtual host skeleton, fill with user input
# To be outputted into new file.
#
function create_vhost_phalcon() {
cat <<- _EOF_
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log ${WEBROOT}/access_log combined buffer=32k;
    error_log ${WEBROOT}/error_log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path "${WEBROOT}/public";
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;

    # Authorizing domain.
    #pagespeed Domain ${SERVERNAME};
    #pagespeed Domain *.${SERVERNAME};

    # Authorize CDN host below here!
    ##pagespeed Domain your-cdn-host;

    # Map CDN host below here!
    ##pagespeed MapOriginDomain https://your-cdn-address https://\$server_name;

    # Rewrite CDN host below here!
    ##pagespeed MapRewriteDomain https://your-cdn-address https://\$server_name;

    # PageSpeed should be disabled on the admin (adjust to suit custom admin URLs).
    #pagespeed Disallow "*/account/*";
    #pagespeed Disallow "*/dashboard/*";
    #pagespeed Disallow "*/admin/*";

    ## Access control Cross-origin Resource Sharing (CORS).
    set \$cors "http://*.\$server_name, https://*.\$server_name";
    #include /etc/nginx/includes/cors.conf;

    # PageSpeed CORS support.
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "http://*.\$server_name";
    #pagespeed AddResourceHeader "Access-Control-Allow-Origin" "https://*.\$server_name";

    ## Global directives configuration.
    include /etc/nginx/includes/rules_security.conf;
    include /etc/nginx/includes/rules_staticfiles.conf;
    include /etc/nginx/includes/rules_restriction.conf;

    ## Default vhost directives configuration.
    #include /etc/nginx/includes/rules_fastcgi_cache.conf;
    include /etc/nginx/vhost/site_${FRAMEWORK}.conf;

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Overwrite FastCGI Params here.
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME \$fastcgi_script_name;

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
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

    ## Uncomment to enable error page directives configuration.
    include /etc/nginx/includes/error_pages.conf;

    ## Add your custom site directives here.
}
_EOF_
}

## Output Wordpress Multisite vHost header.
#
function prepare_vhost_wpms() {
cat <<- _EOF_
# Wordpress Multisite Mapping for NGiNX (Requires NGiNX Helper plugin).
map \$http_host \$blogid {
    default 0;
    include ${WEBROOT}/wp-content/uploads/nginx-helper/[map].conf;
}

_EOF_
}

## Output server block for HTTP to HTTPS redirection.
#
function redirect_http_to_https() {
cat <<- _EOF_

# HTTP to HTTPS redirection
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## Automatically redirect site to HTTPS protocol.
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

_EOF_
}

## Output index.html skeleton for default index page
# To be outputted into new index.html file in document root.
#
function create_index_file() {
cat <<- _EOF_
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
<title>Default Page</title>
<link href="https://fonts.googleapis.com/css?family=Cabin:400,700" rel="stylesheet">
<link href="https://fonts.googleapis.com/css?family=Montserrat:900" rel="stylesheet">
<link type="text/css" rel="stylesheet" href="css/style.css" />
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
<h3>Bad_Coder presents...</h3>
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
_EOF_
}

## Output PHP-FPM pool configuration
# To be outputted into new pool file in fpm/pool.d.
#
function create_fpm_pool_conf() {
    cat <<- _EOF_
[${USERNAME}]
user = ${USERNAME}
group = ${USERNAME}

listen = /run/php/php${PHP_VERSION}-fpm.\$pool.sock
listen.owner = ${USERNAME}
listen.group = ${USERNAME}
listen.mode = 0666
;listen.allowed_clients = 127.0.0.1

; Custom PHP-FPM optimization here
; adjust to meet your needs.
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.process_idle_timeout = 30s
pm.max_requests = 500

; PHP-FPM monitoring
; Do Not change this two lines
pm.status_path = /status
ping.path = /ping

request_slowlog_timeout = 5s
slowlog = /var/log/php/php${PHP_VERSION}-fpm_slow.\$pool.log

chdir = /home/${USERNAME}

security.limit_extensions = .php .php3 .php4 .php5 .php${PHP_VERSION//./}

;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f you@yourmail.com
php_flag[display_errors] = on
php_admin_value[error_log] = /var/log/php/php${PHP_VERSION}-fpm.\$pool.log
php_admin_flag[log_errors] = on
php_admin_value[memory_limit] = 128M
php_admin_value[open_basedir] = /home/${USERNAME}
php_admin_value[upload_tmp_dir] = /home/${USERNAME}/.tmp
php_admin_value[upload_max_filesize] = 10M
php_admin_value[opcache.file_cache] = /home/${USERNAME}/.opcache
_EOF_
}

## Install WordPress
# Installing WordPress skeleton.
#
function install_wordpress() {
    #CLONE_SKELETON=${1:-false}
    # Clone new WordPress skeleton files
    if [ "${CLONE_SKELETON}" == true ]; then
        # Check WordPress install directory.
        if [ ! -f "${WEBROOT}/wp-includes/class-wp.php" ]; then
            status "Downloading WordPress skeleton files..."

            if wget -q -t 10 -O "${TMPDIR}/wordpress.zip" https://wordpress.org/latest.zip; then
                run unzip -q "${TMPDIR}/wordpress.zip" -d "${TMPDIR}" && \
                run rsync -r "${TMPDIR}/wordpress/" "${WEBROOT}" && \
                run rm -f "${TMPDIR}/wordpress.zip" && \
                run rm -fr "${TMPDIR}/wordpress/"
            else
                error "Something went wrong while downloading WordPress files."
            fi
        else
            warning "It seems that WordPress files already exists."
        fi
    else
        # Create default index file.
        if ! "${DRYRUN}"; then
            status "Creating default WordPress index file..."

            if [ ! -e "${WEBROOT}/index.html" ]; then
                create_index_file > "${WEBROOT}/index.html"
            fi
        fi
    fi

    # Get default favicon.
    run wget -q -O "${WEBROOT}/favicon.ico" https://github.com/joglomedia/LEMPer/raw/master/favicon.ico

    # Pre-install nginx helper plugin.
    if [[ -d "${WEBROOT}/wp-content/plugins" && ! -d "${WEBROOT}/wp-content/plugins/nginx-helper" ]]; then
        status "Add NGiNX Helper plugin into WordPress skeleton..."

        if wget -q -O "${TMPDIR}/nginx-helper.zip" \
            https://downloads.wordpress.org/plugin/nginx-helper.zip; then
            run unzip -q "${TMPDIR}/nginx-helper.zip" -d "${WEBROOT}/wp-content/plugins/"
            run rm -f "${TMPDIR}/nginx-helper.zip"
        fi
    fi

    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"
}

# Get server IP Address.
function get_ip_addr() {
    local IP_INTERNAL && \
    IP_INTERNAL=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    local IP_EXTERNAL && \
    IP_EXTERNAL=$(curl -s http://ipecho.net/plain)

    if [[ "${IP_INTERNAL}" == "${IP_EXTERNAL}" ]]; then
        echo "${IP_EXTERNAL}"
    else
        echo "${IP_INTERNAL}"
    fi
}

## Main App
#
function init_app() {
    OPTS=$(getopt -o u:d:f:w:p:scPSWDhv \
      -l username:,domain-name:,framework:,webroot:,php-version:,clone-skeleton \
      -l enable-fastcgi-cache,enable-pagespeed,enable-https,wildcard-domain,dryrun,help,version \
      -n "${APP_NAME}" -- "$@")

    eval set -- "${OPTS}"

    # Default value
    USERNAME=""
    SERVERNAME=""
    WEBROOT=""
    FRAMEWORK="default"
    PHP_VERSION="7.3"
    CLONE_SKELETON=false
    ENABLE_FASTCGI_CACHE=false
    ENABLE_PAGESPEED=false
    ENABLE_HTTPS=false
    ENABLE_WILDCARD_DOMAIN=false
    TMPDIR="/tmp/lemper"

    # Args counter
    MAIN_ARGS=0

    # Parse flags
    while true
    do
        case "${1}" in
            -u | --username) shift
                USERNAME="${1}"
                #MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -d | --domain-name) shift
                SERVERNAME="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -f | --framework) shift
                FRAMEWORK="${1}"
                #MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -w | --webroot) shift
                # Remove trailing slash.
                # shellcheck disable=SC2001
                WEBROOT=$(echo "${1}" | sed 's:/*$::')
                #MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -p | --php-version) shift
                PHP_VERSION="${1}"
                shift
            ;;
            -s | --clone-skeleton) shift
                CLONE_SKELETON=true
            ;;
            -c | --enable-fastcgi-cache) shift
                ENABLE_FASTCGI_CACHE=true
            ;;
            -P | --enable-pagespeed) shift
                ENABLE_PAGESPEED=true
            ;;
            -S | --enable-https) shift
                ENABLE_HTTPS=true
            ;;
            -W | --wildcard-domain) shift
                ENABLE_WILDCARD_DOMAIN=true
            ;;
            -D | --dryrun) shift
                DRYRUN=true
            ;;
            -h | --help) shift
                show_usage
                exit 0
            ;;
            -v | --version) shift
                echo "${APP_NAME^} version ${APP_VERSION}"
                exit 1
            ;;
            --) shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    if [ ${MAIN_ARGS} -ge 1 ]; then
        # Additional Check - ensure that Nginx's configuration meets the requirements.
        if [[ ! -d /etc/nginx/sites-available && ! -d /etc/nginx/vhost ]]; then
            fail "It seems that your NGiNX installation doesn't meet LEMPer requirements. Aborting..."
        fi

        # Check domain option.
        if [[ -z "${SERVERNAME}" ]]; then
            fail -e "Domain name option shouldn't be empty.\n       -d or --domain-name option is required!"
        else
            if ! grep -q -P '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)' <<< "${SERVERNAME}"; then
                fail -e "Domain name option must be an valid fully qualified domain name (FQDN)!"
            fi
        fi

        # Make temp dir.
        if [ ! -d "${TMPDIR}" ]; then
            run mkdir -p "${TMPDIR}"
        fi

        # Define vhost file.
        VHOST_FILE="/etc/nginx/sites-available/${SERVERNAME}.conf"

        # Check if vhost not exists.
        if [ ! -f "${VHOST_FILE}" ]; then
            echo "Adding domain ${SERVERNAME} to virtual host..."

            # Check for username.
            if [[ -z "${USERNAME}" ]]; then
                warning "Username option is empty. Attempt to use default \"lemper\" account."
                USERNAME="lemper"
            fi

            # Additional Check - are user account exist?
            if [[ -z $(getent passwd "${USERNAME}") ]]; then
                fail "User account \"${USERNAME}\" does not exist. Please add new account first! Aborting..."
            fi

            # Check PHP fpm version is exists.
            if [[ -n $(command -v "php-fpm${PHP_VERSION}") && -d "/etc/php/${PHP_VERSION}/fpm" ]]; then
                # Additional check - if FPM user's pool already exist.
                if [ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" ]; then
                    warning "The PHP${PHP_VERSION} FPM pool configuration for user ${USERNAME} doesn't exist."
                    echo "Creating new PHP-FPM pool [${USERNAME}] configuration..."

                    # Create PHP FPM pool conf.
                    create_fpm_pool_conf > "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf"
                    run touch "/var/log/php${PHP_VERSION}-fpm_slow.${USERNAME}.log"

                    # Create default directories.
                    run mkdir -p "/home/${USERNAME}/.tmp"
                    run mkdir -p "/home/${USERNAME}/.opcache"
                    run chown -hR "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

                    # Restart PHP FPM.
                    echo "Restart php${PHP_VERSION}-fpm configuration..."

                    run service "php${PHP_VERSION}-fpm" restart

                    status "New PHP-FPM pool [${USERNAME}] has been created."
                fi
            else
                fail "Oops, PHP${PHP_VERSION} & FPM not found. Please install it first! Aborting..."
            fi

            # Check web root option.
            if [[ -z "${WEBROOT}" ]]; then
                WEBROOT="/home/${USERNAME}/webapps/${SERVERNAME}"
                warning "Webroot option is empty. Set to default web root: ${WEBROOT}"
            fi

            # Creates document root.
            if [ ! -d "${WEBROOT}" ]; then
                echo "Creating web root directory: ${WEBROOT}..."

                run mkdir -p "${WEBROOT}" && \
                run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}" && \
                run chmod 755 "${WEBROOT}"
            fi

            # Well-Known URIs: RFC 8615.
            if [ ! -d "${WEBROOT}/.well-known" ]; then
                echo "Creating .well-known directory (RFC8615)..."
                run mkdir -p "${WEBROOT}/.well-known/acme-challenge"
            fi

            # Create log files.
            run touch "${WEBROOT}/access_log"
            run touch "${WEBROOT}/error_log"

            # Check framework option.
            if [[ -z "${FRAMEWORK}" ]]; then
                FRAMEWORK="default"
                warning "Framework option is empty. Set to default framework: ${FRAMEWORK}"
            fi

            echo "Selecting ${FRAMEWORK^} framework..."

            # Ugly hacks for custom framework-specific configs + Skeleton auto installer.
            case "${FRAMEWORK}" in
                drupal)
                    echo "Setting up Drupal virtual host..."

                    # Clone new Drupal skeleton files.
                    if [ ${CLONE_SKELETON} == true ]; then
                        # Check Drupal install directory.
                        if [ ! -d "${WEBROOT}/core/lib/Drupal" ]; then
                            status "Downloading Drupal latest skeleton files..."

                            if wget -q -O "${TMPDIR}/drupal.zip" \
                                    https://www.drupal.org/download-latest/zip; then
                                run unzip -q "${TMPDIR}/drupal.zip" -d "${TMPDIR}"
                                run rsync -rq ${TMPDIR}/drupal-*/ "${WEBROOT}"
                                run rm -f "${TMPDIR}/drupal.zip"
                                run rm -fr ${TMPDIR}/drupal-*/
                            else
                                error "Something went wrong while downloading Drupal files."
                            fi
                        else
                            warning "It seems that Drupal files already exists."
                        fi
                    else
                        # Create default index file.
                        status "Creating default index file..."

                        if [ ! -e "${WEBROOT}/index.html" ]; then
                            create_index_file > "${WEBROOT}/index.html"
                        fi
                    fi

                    run wget -q -O "${WEBROOT}/favicon.ico" \
                        https://github.com/joglomedia/LEMPer/raw/master/favicon.ico

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_drupal > "${VHOST_FILE}"
                ;;

                laravel|lumen)
                    echo "Setting up Laravel framework virtual host..."

                    # Install Laravel framework skeleton
                    # clone new Laravel files.
                    if [ ${CLONE_SKELETON} == true ]; then
                        # Check Laravel install.
                        if [ ! -f "${WEBROOT}/artisan" ]; then
                            status "Downloading ${FRAMEWORK^} skeleton files..."
                            run git clone -q --depth=1 --branch=master \
                                "https://github.com/laravel/${FRAMEWORK}.git" "${WEBROOT}" || \
                                error "Something went wrong while downloading ${FRAMEWORK^} files."
                        else
                            warning "It seems that ${FRAMEWORK^} skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        status "Creating default index file..."
                        run mkdir -p "${WEBROOT}/public"

                        if [ ! -e "${WEBROOT}/public/index.html" ]; then
                            create_index_file > "${WEBROOT}/public/index.html"
                        fi
                    fi

                    # Well-Known URIs: RFC 8615.
                    if [ ! -d "${WEBROOT}/public/.well-known" ]; then
                        run mkdir -p "${WEBROOT}/public/.well-known"
                    fi

                    run wget -q -O "${WEBROOT}/public/favicon.ico" \
                        https://github.com/joglomedia/LEMPer/raw/master/favicon.ico

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_laravel > "${VHOST_FILE}"
                ;;

                phalcon|phalcon-micro)
                    echo "Setting up ${FRAMEWORK^} framework virtual host..."

                    # Auto install Phalcon PHP framework skeleton.
                    if [ ${CLONE_SKELETON} == true ]; then
                        # Check Phalcon skeleton install.
                        if [ ! -f "${WEBROOT}/app/config/loader.php" ]; then
                            status "Downloading ${FRAMEWORK^} skeleton files..."
                            run git clone -q --depth=1 --branch=master \
                                "https://github.com/joglomedia/${FRAMEWORK}-skeleton.git" "${WEBROOT}" || \
                                error "Something went wrong while downloading ${FRAMEWORK^} files."
                        else
                            warning "It seems that ${FRAMEWORK^} skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        status "Creating default index file..."
                        run mkdir -p "${WEBROOT}/public"
                        
                        if [ ! -e "${WEBROOT}/public/index.html" ]; then
                            create_index_file > "${WEBROOT}/public/index.html"
                        fi
                    fi

                    # Well-Known URIs: RFC 8615.
                    if [ ! -d "${WEBROOT}/public/.well-known" ]; then
                        run mkdir -p "${WEBROOT}/public/.well-known"
                    fi

                    run wget -q -O "${WEBROOT}/public/favicon.ico" \
                        https://github.com/joglomedia/LEMPer/raw/master/favicon.ico

                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_phalcon > "${VHOST_FILE}"
                ;;

                symfony)
                    echo "Setting up Symfony framework virtual host..."

                    # Auto install Symfony PHP framework skeleton.
                    if [ ${CLONE_SKELETON} == true ]; then
                        # Install Symfony binary if not exists.
                        if [[ -z $(command -v symfony) ]]; then
                            run wget -q https://get.symfony.com/cli/installer -O - | bash
                            if [ -f "${HOME}/.symfony/bin/symfony" ]; then
                                run cp -f "${HOME}/.symfony/bin/symfony" /usr/local/bin/symfony
                                run chmod ugo+x /usr/local/bin/symfony
                            else
                                run export PATH="${HOME}/.symfony/bin:${PATH}"
                            fi
                        fi

                        # Check Symfony install.
                        if [ ! -f "${WEBROOT}/src/Kernel.php" ]; then
                            status "Downloading Symfony skeleton files..."
                            run git clone -q --depth=1 --branch=master \
                                "https://github.com/joglomedia/${FRAMEWORK}-skeleton.git" "${WEBROOT}" || \
                                error "Something went wrong while downloading Symfony files."
                        else
                            warning "It seems that Symfony skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        status "Creating default index file..."

                        if [ ! -e "${WEBROOT}/index.html" ]; then
                            create_index_file > "${WEBROOT}/index.html"
                        fi
                    fi

                    # Well-Known URIs: RFC 8615.
                    if [ ! -d "${WEBROOT}/public/.well-known" ]; then
                        run mkdir -p "${WEBROOT}/public/.well-known"
                    fi

                    run wget -q -O "${WEBROOT}/public/favicon.ico" \
                        https://github.com/joglomedia/LEMPer/raw/master/favicon.ico
                    
                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                wordpress|woocommerce)
                    echo "Setting up WordPress virtual host..."

                    # Install WordPress skeleton.
                    install_wordpress ${CLONE_SKELETON}

                    # Install WooCommerce.
                    if [[ "${FRAMEWORK}" == "woocommerce" ]]; then
                        if [[ -d "${WEBROOT}/wp-content/plugins" && \
                            ! -d "${WEBROOT}/wp-content/plugins/woocommerce" ]]; then
                            status "Add WooCommerce plugin into WordPress skeleton..."

                            if wget -q -O "${TMPDIR}/woocommerce.zip" \
                                https://downloads.wordpress.org/plugin/woocommerce.zip; then
                                run unzip -q "${TMPDIR}/woocommerce.zip" -d "${WEBROOT}/wp-content/plugins/"
                                run rm -f "${TMPDIR}/woocommerce.zip"
                            else
                                error "Something went wrong while downloading WooCommerce files."
                            fi
                        fi

                        # Return framework as Wordpress for vhost creation.
                        FRAMEWORK="wordpress"
                    fi

                    # Create vhost.
                    if ! "${DRYRUN}"; then
                        echo "Create virtual host file: ${VHOST_FILE}"
                        create_vhost_default > "${VHOST_FILE}"
                    else
                        warning "Virtual host created in dryrun mode, no data written."
                    fi
                ;;

                wordpress-ms)
                    echo "Setting up WordPress Multi-site virtual host..."

                    # Install WordPress.
                    install_wordpress ${CLONE_SKELETON}

                    # Pre-populate blog id mapping, used by NGiNX vhost config.
                    if [ ! -d "${WEBROOT}/wp-content/uploads/nginx-helper" ]; then
                        run mkdir -p "${WEBROOT}/wp-content/uploads/nginx-helper"
                    fi

                    if [ ! -f "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf" ]; then
                        run touch "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf"
                    fi

                    # Virtual host.
                    if ! "${DRYRUN}"; then
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
                    else
                        warning "Virtual host created in dryrun mode, no data written."
                    fi
                ;;

                filerun)
                    echo "Setting up FileRun virtual host..."

                    # Install FileRun skeleton.
                    if [ ${CLONE_SKELETON} == true ]; then
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
                            warning "FileRun skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        echo "Creating default index files..."

                        if [ ! -e "${WEBROOT}/index.html" ]; then
                            create_index_file > "${WEBROOT}/index.html"
                        fi
                    fi

                    run wget -q -O "${WEBROOT}/favicon.ico" \
                        https://github.com/joglomedia/LEMPer/raw/master/favicon.ico
                    
                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                codeigniter|mautic|sendy|default)
                    # TODO: Auto install framework skeleton.

                    # Create default index file.
                    if [ ! -e "${WEBROOT}/index.html" ]; then
                        create_index_file > "${WEBROOT}/index.html"
                    fi

                    run wget -q -O "${WEBROOT}/favicon.ico" \
                        https://github.com/joglomedia/LEMPer/raw/master/favicon.ico
                    
                    # Fix ownership.
                    run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                    # Create default vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                ;;

                *)
                    # Not supported framework/cms, abort.
                    fail "Sorry, your framework/cms [${FRAMEWORK^}] is not supported yet. Aborting..."
                    exit 1
                ;;
            esac

            if "${DRYRUN}"; then
                warning "New domain ${SERVERNAME} has been added in dry run mode."
            else
                # Confirm virtual host.
                if grep -qwE "server_name ${SERVERNAME}" "${VHOST_FILE}"; then
                    status "New domain ${SERVERNAME} has been added to virtual host."
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

                    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
                        # enable cached directives
                        run sed -i "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" "${VHOST_FILE}"
                        # enable fastcgi_cache conf
                        run sed -i "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" "${VHOST_FILE}"
                    else
                        warning "FastCGI cache is not enabled due to no cached version of ${FRAMEWORK^} directive."
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
                        warning "Mod PageSpeed is not enabled. NGiNX must be installed with PageSpeed module."
                    fi
                fi

                echo "Fix files ownership and permission..."

                # Fix document root ownership.
                run chown -hR "${USERNAME}:${USERNAME}" "${WEBROOT}"

                # Fix document root permission.
                if [ "$(ls -A "${WEBROOT}")" ]; then
                    run find "${WEBROOT}" -type d -print0 | xargs -0 chmod 755
                    run find "${WEBROOT}" -type f -print0 | xargs -0 chmod 644
                fi
            fi

            echo "Enable ${SERVERNAME} virtual host..."

            # Enable site.
            if [ ! -f "/etc/nginx/sites-enabled/${SERVERNAME}.conf" ]; then
                run ln -s "/etc/nginx/sites-available/${SERVERNAME}.conf" \
                    "/etc/nginx/sites-enabled/${SERVERNAME}.conf"
            fi

            # Reload Nginx
            echo "Reloading NGiNX HTTP server configuration..."

            # Validate config, reload when validated.
            if nginx -t 2>/dev/null > /dev/null; then
                run service nginx reload -s
                echo "NGiNX HTTP server reloaded with new configuration."
            else
                warning "Something went wrong with NGiNX configuration."
            fi

            if [[ -f "/etc/nginx/sites-enabled/${SERVERNAME}.conf" && -e /var/run/nginx.pid ]]; then
                status "Your ${SERVERNAME} successfully added to NGiNX virtual host."

                # Enable HTTPS.
                if [ ${ENABLE_HTTPS} == true ]; then
                    echo ""
                    echo "You can enable HTTPS from lemper-cli after this setup!"
                    echo "command: lemper-cli manage --enable-https ${SERVERNAME}"
                    echo ""
                fi

                # WordPress MS notice.
                if [ "${FRAMEWORK}" = "wordpress-ms" ]; then
                    echo >&2
                    warning "Note: You're installing Wordpress Multisite."
                    warning "You should activate NGiNX Helper plugin to work properly."
                fi
            else
                if "${DRYRUN}"; then
                    warning "Your ${SERVERNAME} successfully added in dryrun mode."
                else
                    fail "An error occurred when adding ${SERVERNAME} to NGiNX virtual host."
                fi
            fi
        else
            error "Virtual host config file for ${SERVERNAME} is already exists. Aborting..."
        fi
    else
        echo "${APP_NAME}: missing required argument."
        echo "Try '${APP_NAME} --help' for more information."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_app "$@"
