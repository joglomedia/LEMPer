#!/bin/bash

# +-------------------------------------------------------------------------+
# | Lemper Create - Simple LEMP Virtual Host Generator                      |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/ngxvhost)             |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# | Original concept: Fideloper <https://gist.github.com/fideloper/9063376> |
# +-------------------------------------------------------------------------+

set -e

# Version Control.
APP_NAME=$(basename "$0")
APP_VERSION="1.2.0"
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

Options:
  -d, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed, i.e. example.app or sub.example.app.
  -f, --framework <website framework>
      Type of PHP web Framework and CMS, i.e. default.
      Supported Framework and CMS: default (vanilla PHP), codeigniter, drupal, laravel,
      lumen, phalcon, symfony, wordpress, wordpress-ms.
      Another framework and cms will be added soon.
  -p, --php-version
      PHP version for selected framework. Latest recommended PHP version is "7.3".
  -u, --username <virtual-host username>
      Use username added from adduser/useradd. Do not use root user!!
  -w, --webroot <web root>
      Web root is an absolute path to the website root directory, i.e. /home/lemper/webapps/example.test.

  --clone-skeleton
      Clone default skeleton for selected framework.
  --enable-fastcgi-cache
      Enable FastCGI cache module.
  --enable-https
      Enable HTTPS with Let's Encrypt free SSL certificate.
  --enable-pagespeed
      Enable Nginx mod_pagespeed.
  --wildcard-domain
      Enable wildcard (*) domain.

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
    listen [::]:80 ipv6only=on;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## SSL configuration.
    #ssl_certificate /etc/nginx/ssl/${SERVERNAME}/default_ssl.crt;
    #ssl_certificate_key /etc/nginx/ssl/${SERVERNAME}/default_ssl.key;
    #include /etc/nginx/includes/ssl.conf;

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}';
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;
    # Async Google Analytics
    #pagespeed EnableFilters make_google_analytics_async;
    # Async Google Adsense
    #pagespeed EnableFilters make_show_ads_async;
    # PageSpeed should be disabled on the WP admin  (adjust to suit custom admin URLs)
    #pagespeed Disallow "*/wp-admin/*";
    # Enable fetch HTTPS
    #pagespeed FetchHttps enable;
    # This setting should be enabled when using HTTPS
    # Take care when using HTTP > HTTPS redirection to avoid loops
    #pagespeed MapOriginDomain "http://\$server_name" "https://\$server_name";

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

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## PHP-FPM status monitoring
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

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
    listen [::]:80 ipv6only=on;

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}';
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;
    # Async Google Analytics
    #pagespeed EnableFilters make_google_analytics_async;
    # Async Google Adsense
    #pagespeed EnableFilters make_show_ads_async;
    # PageSpeed should be disabled on the WP admin  (adjust to suit custom admin URLs)
    #pagespeed Disallow "*/wp-admin/*";
    # Enable fetch HTTPS
    #pagespeed FetchHttps enable;
    # This setting should be enabled when using HTTPS
    # Take care when using HTTP > HTTPS redirection to avoid loops
    #pagespeed MapOriginDomain "http://\$server_name" "https://\$server_name";

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

        # Overwrite FastCGI Params here.
        # Block httpoxy attacks. See https://httpoxy.org/.
        fastcgi_param HTTP_PROXY "";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param QUERY_STRING \$query_string;

        # Comment out HTTPS line for PHP behind SSL https.
        # old pre .03 method
        #fastcgi_param HTTPS on;
        # new .04+ map method
        #fastcgi_param HTTPS \$server_https;

        # Include FastCGI Configs.
        include /etc/nginx/includes/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## PHP-FPM status monitoring
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

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
    listen [::]:80 ipv6only=on;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}/public';
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;
    # Async Google Analytics
    #pagespeed EnableFilters make_google_analytics_async;
    # Async Google Adsense
    #pagespeed EnableFilters make_show_ads_async;
    # PageSpeed should be disabled on the WP admin  (adjust to suit custom admin URLs)
    #pagespeed Disallow "*/wp-admin/*";
    # Enable fetch HTTPS
    #pagespeed FetchHttps enable;
    # This setting should be enabled when using HTTPS
    # Take care when using HTTP > HTTPS redirection to avoid loops
    #pagespeed MapOriginDomain "http://\$server_name" "https://\$server_name";

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

        # Overwrite FastCGI Params here.
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        # Include FastCGI Configs.
        include /etc/nginx/includes/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## PHP-FPM status monitoring
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

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
    listen [::]:80 ipv6only=on;

    ## Make site accessible from world web.
    server_name ${SERVERNAME};

    ## SSL configuration.
    #include /etc/nginx/includes/ssl.conf;
    #ssl_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/${SERVERNAME}/privkey.pem;
    #ssl_trusted_certificate /etc/letsencrypt/live/${SERVERNAME}/fullchain.pem;

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}/public';
    root \$root_path;
    index index.php index.html index.htm;

    ## Uncomment to enable Mod PageSpeed (Nginx must be installed with mod PageSpeed).
    #include /etc/nginx/includes/mod_pagespeed.conf;
    # Async Google Analytics
    #pagespeed EnableFilters make_google_analytics_async;
    # Async Google Adsense
    #pagespeed EnableFilters make_show_ads_async;
    # PageSpeed should be disabled on the WP admin  (adjust to suit custom admin URLs)
    #pagespeed Disallow "*/wp-admin/*";
    # Enable fetch HTTPS
    #pagespeed FetchHttps enable;
    # This setting should be enabled when using HTTPS
    # Take care when using HTTP > HTTPS redirection to avoid loops
    #pagespeed MapOriginDomain "http://\$server_name" "https://\$server_name";

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

        # Uncomment to Enable PHP FastCGI cache.
        #include /etc/nginx/includes/fastcgi_cache.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/includes/error_pages.conf;

    ## PHP-FPM status monitoring
    location ~ ^/(status|ping)$ {
        include /etc/nginx/fastcgi_params;

        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;

        allow all;
        auth_basic "Denied";
        auth_basic_user_file /srv/.htpasswd;
    }

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
    include ${WEBROOT}/wp-content/uploads/nginx-helper/map.conf;
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
    listen [::]:80 ipv6only=on;

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
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed using LEMPer. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
LEMPer and ngxTools support is available at
<a href="https://github.com/joglomedia/LEMPer/issues">LEMPer Github</a>.</p>

<p><em>Thank you for using nginx, ngxTools, and LEMPer.</em></p>

<p style="font-size:90%;">Generated using <em>LEMPer</em> from <a href="https://eslabs.id/lemper">Nginx vHost Tool</a>, a simple nginx web server management tool.</p>
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

request_slowlog_timeout = 6s
slowlog = /var/log/php/php${PHP_VERSION}-fpm_slow.\$pool.log

chdir = /home/${USERNAME}

security.limit_extensions = .php .php3 .php4 .php5 .php${PHP_VERSION//./}

;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f you@yourmail.com
php_flag[display_errors] = on
php_admin_value[error_log] = /var/log/php/php${PHP_VERSION}-fpm.\$pool.log
php_admin_flag[log_errors] = on
php_admin_value[memory_limit] = 128M
php_admin_value[open_basedir] = /home/${USERNAME}

_EOF_
}

## Install WordPress
# Installing WordPress skeleton.
#
function install_wordpress() {
    CLONE_SKELETON=${1:-false}
    # Clone new WordPress skeleton files
    if [ "${CLONE_SKELETON}" == true ]; then
        # Check WordPress install directory.
        if [ ! -d "${WEBROOT}/wp-admin" ]; then
            status "Copying WordPress skeleton files..."

            run wget --no-check-certificate -q https://wordpress.org/latest.zip
            run unzip -q latest.zip
            run rsync -r wordpress/ "${WEBROOT}"
            run rm -f latest.zip
            run rm -fr wordpress
        else
            warning "It seems that WordPress files already exists."
        fi
    else
        # Create default index file.
        status "Creating default WordPress index file..."

        create_index_file > "${WEBROOT}/index.html"
        run chown "${USERNAME}:${USERNAME}" "${WEBROOT}/index.html"
    fi

    # Pre-install nginx helper plugin.
    if [[ -d "${WEBROOT}/wp-content/plugins" && ! -d "${WEBROOT}/wp-content/plugins/nginx-helper" ]]; then
        status "Copying NGiNX Helper plugin into WordPress install..."
        warning "Please activate the plugin after WordPress installation!"

        run wget --no-check-certificate -q https://downloads.wordpress.org/plugin/nginx-helper.zip
        run unzip -q nginx-helper.zip
        run mv nginx-helper "${WEBROOT}/wp-content/plugins/"
        run rm -f nginx-helper.zip
    fi
}

# Get server IP Address.
function get_ip_addr() {
    IP_INTERNAL=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
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
    OPTS=$(getopt -o u:d:f:w:p:schv \
      -l username:,domain-name:,framework:,webroot:,php-version:,clone-skeleton \
      -l enable-fastcgi-cache,enable-pagespeed,enable-https,wildcard-domain,help,version \
      -n "${APP_NAME}" -- "$@")

    eval set -- "${OPTS}"

    # Default value
    FRAMEWORK="default"
    PHP_VERSION="7.3"
    ENABLE_FASTCGI_CACHE=false
    ENABLE_PAGESPEED=false
    ENABLE_HTTPS=false
    ENABLE_WILDCARD_DOMAIN=false
    CLONE_SKELETON=false
    DRYRUN=false

    # Args counter
    MAIN_ARGS=0

    # Parse flags
    while true
    do
        case "${1}" in
            -u | --username) shift
                USERNAME="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -d | --domain-name) shift
                SERVERNAME="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -f | --framework) shift
                FRAMEWORK="${1}"
                MAIN_ARGS=$((MAIN_ARGS + 1))
                shift
            ;;
            -w | --webroot) shift
                # Remove trailing slash.
                # shellcheck disable=SC2001
                #WEBROOT="${1%/}"
                WEBROOT=$(echo "${1}" | sed 's:/*$::')
                MAIN_ARGS=$((MAIN_ARGS + 1))
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
            --enable-pagespeed) shift
                ENABLE_PAGESPEED=true
            ;;
            --enable-https) shift
                ENABLE_HTTPS=true
            ;;
            --wildcard-domain) shift
                ENABLE_WILDCARD_DOMAIN=true
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

    if [ ${MAIN_ARGS} -ge 4 ]; then
        # Additional Check - are user already exist?
        if [[ -z $(getent passwd "${USERNAME}") ]]; then
            fail -e "The user ${USERNAME} does not exist, please add new user first! Aborting..."
        fi

        # Check domain options is not empty.
        if [[ -z "${SERVERNAME}" ]]; then
            fail -e "Domain name option shouldn't be empty.\n       -d or --domain-name option is required!"
        fi

        # Check framework options is not empty.
        if [[ -z "${FRAMEWORK}" ]]; then
            fail -e "Framework option shouldn't be empty.\n       -w or --webroot option is required!"
        fi

        # Check web root options is not empty.
        if [[ -z "${WEBROOT}" ]]; then
            fail -e "Web root option shouldn't be empty.\n       -w or --webroot option is required!"
        fi

        # Additional Check - ensure that Nginx's configuration meets the requirements.
        if [[ ! -d /etc/nginx/sites-available && ! -d /etc/nginx/vhost ]]; then
            fail "It seems that your NGiNX installation doesn't meet the requirements. Aborting..."
        fi

        # Check PHP fpm version is exists.
        if [[ -n $(command -v "php-fpm${PHP_VERSION}") && -d "/etc/php/${PHP_VERSION}/fpm" ]]; then
            # Additional check - if FPM user's pool already exist
            if [ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" ]; then
                warning "The PHP${PHP_VERSION} FPM pool configuration for user ${USERNAME} doesn't exist."
                echo "Creating new PHP-FPM pool [${USERNAME}] configuration..."

                create_fpm_pool_conf > "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf"
                run touch "/var/log/php${PHP_VERSION}-fpm_slow.${USERNAME}.log"

                # Restart PHP FPM
                echo "Restart php${PHP_VERSION}-fpm configuration..."

                run service "php${PHP_VERSION}-fpm" restart

                status "New PHP-FPM pool [${USERNAME}] has been created."
            fi
        else
            fail "No PHP & FPM version ${PHP_VERSION} installed, please install it first! Aborting..."
        fi

        # Define vhost file.
        VHOST_FILE="/etc/nginx/sites-available/${SERVERNAME}.conf"

        # Check if vhost not exists.
        if [ ! -f "${VHOST_FILE}" ]; then
            echo "Adding domain ${SERVERNAME} to virtual host..."

            # Creates document root.
            if [ ! -d "${WEBROOT}" ]; then
                echo "Creating web root directory: ${WEBROOT}..."

                run mkdir -p "${WEBROOT}"
                run chown -R "${USERNAME}:${USERNAME}" "${WEBROOT}"
                run chmod 755 "${WEBROOT}"
            fi

            echo "Selecting ${FRAMEWORK^} framewrok..."

            # Ugly hacks for custom framework-specific configs + Skeleton auto installer.
            case "${FRAMEWORK}" in
                drupal)
                    echo "Setting up Drupal virtual host..."

                    # Clone new Drupal skeleton files.
                    if [ ${CLONE_SKELETON} == true ]; then
                        # Check Drupal install directory.
                        if [ ! -d "${WEBROOT}/core/lib/Drupal" ]; then
                            status "Copying Drupal latest skeleton files..."

                            run wget --no-check-certificate -O drupal.zip -q \
                                    https://www.drupal.org/download-latest/zip
                            run unzip -q drupal.zip
                            run rsync -rq drupal-*/ "${WEBROOT}"
                            run rm -f drupal.zip
                            run rm -fr drupal-*/
                        else
                            warning "It seems that Drupal files already exists."
                        fi
                    else
                        # Create default index file.
                        status "Creating default index file..."
                        create_index_file > "${WEBROOT}/index.html"

                        run chown "${USERNAME}:${USERNAME}" "${WEBROOT}/index.html"
                    fi

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_drupal > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                laravel|lumen)
                    echo "Setting up Laravel framework virtual host..."

                    # Install Laravel framework skeleton
                    # clone new Laravel files.
                    if [ ${CLONE_SKELETON} == true ]; then
                        # Check Laravel install.
                        if [ ! -f "${WEBROOT}/artisan" ]; then
                            status "Copying ${FRAMEWORK^} skeleton files..."
                            run git clone -q "https://github.com/laravel/${FRAMEWORK}.git" "${WEBROOT}"
                        else
                            warning "It seems that ${FRAMEWORK^} skeleton files already exists."
                        fi
                    else
                        # Create default index file.
                        status "Creating default index file..."
                        create_index_file > "${WEBROOT}/index.html"
                        run chown "${USERNAME}:${USERNAME}" "${WEBROOT}/index.html"
                    fi

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_laravel > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                phalcon)
                    echo "Setting up Phalcon framework virtual host..."

                    # TODO: Auto install Phalcon PHP framework skeleton

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_phalcon > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                symfony)
                    echo "Setting up Symfony framework virtual host..."

                    # TODO: Auto install Symfony PHP framework skeleton

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                wordpress)
                    echo "Setting up WordPress virtual host..."

                    # Install WordPress skeleton.
                    install_wordpress ${CLONE_SKELETON}

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                wordpress-ms)
                    echo "Setting up WordPress Multi-site virtual host..."

                    # Install WordPress.
                    install_wordpress ${CLONE_SKELETON}

                    # Pre-populate blog id mapping, used by NGiNX vhost conf.
                    if [ ! -d "${WEBROOT}/wp-content" ]; then
                        run mkdir "${WEBROOT}/wp-content"
                    fi

                    if [ ! -d "${WEBROOT}/wp-content/uploads" ]; then
                        run mkdir "${WEBROOT}/wp-content/uploads"
                    fi

                    if [ ! -d "${WEBROOT}/wp-content/uploads/nginx-helper" ]; then
                        run mkdir "${WEBROOT}/wp-content/uploads/nginx-helper"
                    fi

                    if [ ! -f "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf" ]; then
                        run touch "${WEBROOT}/wp-content/uploads/nginx-helper/map.conf"
                    fi

                    echo "Creating virtual host file: ${VHOST_FILE}..."

                    # Prepare vhost specific rule for WordPress Multisite.
                    prepare_vhost_wpms > "${VHOST_FILE}"

                    # Create vhost.
                    create_vhost_default >> "${VHOST_FILE}"

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                filerun)
                    echo "Setting up FileRun virtual host..."

                    # Install FileRun skeleton.
                    if [ ! -f "${WEBROOT}/system/classes/filerun.php" ]; then
                        # Clone new Filerun files.
                        if [ ${CLONE_SKELETON} == true ]; then
                            echo "Copying FileRun skeleton files..."
                            run wget -q -O FileRun.zip http://www.filerun.com/download-latest
                            run unzip -q FileRun.zip -d "${WEBROOT}"
                            run rm -f FileRun.zip
                        else
                            # Create default index file.
                            echo "Creating default index files..."
                            create_index_file > "${WEBROOT}/index.html"
                            run chown "${USERNAME}:${USERNAME}" "${WEBROOT}/index.html"
                        fi
                    else
                        warning "FileRun skeleton files already exists."
                    fi

                    # Create vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                codeigniter|mautic|default)
                    # Create default index file.
                    create_index_file > "${WEBROOT}/index.html"
                    run chown "${USERNAME}:${USERNAME}" "${WEBROOT}/index.html"

                    # Create default vhost.
                    echo "Creating virtual host file: ${VHOST_FILE}..."
                    create_vhost_default > "${VHOST_FILE}"
                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                *)
                    # Not supported framework/cms, abort.
                    fail "Sorry, your framework/cms [${FRAMEWORK^}] is not supported yet. Aborting..."
                    exit 1
                ;;
            esac

            # Well-Known URIs: RFC 8615.
            if [ ! -d "${WEBROOT}/.well-known" ]; then
                echo "Create well-known directory, RFC 8615..."
                run mkdir -p "${WEBROOT}/.well-known"
            fi

            # Enable FastCGI cache.
            if [ ${ENABLE_FASTCGI_CACHE} == true ]; then
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
            if [ ${ENABLE_PAGESPEED} == true ]; then
                echo "Enable Mod PageSpeed for ${SERVERNAME}..."

                if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
                    # enable mod pagespeed
                    run sed -i "s|#include\ /etc/nginx/includes/mod_pagespeed.conf|include\ /etc/nginx/includes/mod_pagespeed.conf|g" "${VHOST_FILE}"
                else
                    warning "PageSpeed is not enabled. NGiNX must be installed with Mod_PageSpeed module enabled."
                fi
            fi

            # Enable Wildcard domain.
            if [ ${ENABLE_WILDCARD_DOMAIN} == true ]; then
                echo "Enable wildcard domain for ${SERVERNAME}..."

                if grep -qwE "server_name\ ${SERVERNAME};$" "${VHOST_FILE}"; then
                    run sed -i "s/server_name\ ${SERVERNAME};/server_name\ ${SERVERNAME}\ \*.${SERVERNAME};/g" "${VHOST_FILE}"
                fi
            fi

            echo "Enable ${SERVERNAME} virtual host..."

            # Enable site.
            if [ ! -f "/etc/nginx/sites-enabled/${SERVERNAME}.conf" ]; then
                run ln -s "/etc/nginx/sites-available/${SERVERNAME}.conf" \
                    "/etc/nginx/sites-enabled/${SERVERNAME}.conf"
            fi

            # Fix document root ownership.
            run chown -R "${USERNAME}:${USERNAME}" "${WEBROOT}"

            # Fix document root permission.
            if [ "$(ls -A "${WEBROOT}")" ]; then
                run find "${WEBROOT}" -type d -print0 | xargs -0 chmod 755
                run find "${WEBROOT}" -type f -print0 | xargs -0 chmod 644
            fi    

            # Reload Nginx
            echo "Reloading NGiNX HTTP server configuration..."

            # Validate config, reload when validated.
            if nginx -t 2>/dev/null > /dev/null; then
                run service nginx reload -s
                echo "NGiNX HTTP server reloaded with new configuration."
            else
                echo "Something went wrong with NGiNX configuration."
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
                fail "An error occurred when adding ${SERVERNAME} to NGiNX virtual host."
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
