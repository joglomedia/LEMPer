#!/bin/bash

# +-------------------------------------------------------------------------+
# | Lemper manage - Simple LEMP Virtual Host Manager                        |
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

# Version control
APP_NAME=$(basename "$0")
APP_VERSION="1.2.0-dev"

# Decorator
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

# Help
function show_usage() {
cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Simple Nginx virtual host (vHost) manager
enable/disable/remove Nginx vHost config file on Debian/Ubuntu Server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage:
  ${APP_NAME} [OPTION]...

Options:
  -b, --enable-brotli
      Enable Brotli compression.
  -c, --enable-fastcgi-cache <vhost domain name>
      Enable FastCGI cache.
  --disable-fastcgi-cache <vhost domain name>
      Disable FastCHI cache.
  -d, --disable <vhost domain name>
      Disable virtual host.
  -e, --enable <vhost domain name>
      Enable virtual host.
  -g, --enable-gzip
      Enable Gzip compression.
  -p, --enable-pagespeed <vhost domain name>
      Enable Mod PageSpeed.
  --disable-pagespeed <vhost domain name>
      Disable Mod PageSpeed.
  -r, --remove <vhost domain name>
      Remove virtual host configuration.
  -s, --enable-https <vhost domain name>
      Enable HTTPS with Let's Encrypt SSL certificate.
  --disable-https <vhost domain name>
      Disable HTTPS.

  -h, --help
      Print this message and exit.
  -v, --version
      Output version information and exit.

Example:
 ${APP_NAME} --remove example.com

For more informations visit https://eslabs.id/lemper
Mail bug reports and suggestions to <eslabs.id@gmail.com>
_EOF_
}

# Enable vhost
function enable_vhost() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo "Enabling virtual host: ${1}..."

    # Enable Nginx's vhost config.
    if [[ ! -f "/etc/nginx/sites-enabled/${1}.conf" && -f "/etc/nginx/sites-available/${1}.conf" ]]; then
        run ln -s "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-enabled/${1}.conf"

        status "Your virtual host ${1} has been enabled..."

        reload_nginx
    else
        fail -e "${1} couldn't be enabled. Probably, it has been enabled or not created yet."
        exit 1
    fi
}

# Disable vhost
function disable_vhost() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo "Disabling virtual host: ${1}..."

    # Disable Nginx's vhost config.
    if [ -f "/etc/nginx/sites-enabled/${1}.conf" ]; then
        run unlink "/etc/nginx/sites-enabled/${1}.conf"

        status "Your virtual host ${1} has been disabled..."
        
        reload_nginx
    else
        fail -e "${1} couldn't be disabled. Probably, it has been disabled or removed."
        exit 1
    fi
}

# Remove vhost
function remove_vhost() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo -e "Removing virtual host is not reversible."
    read -t 30 -rp "Press [Enter] to continue..." </dev/tty

    # Remove Nginx's vhost config.
    if [ -f "/etc/nginx/sites-enabled/${1}.conf" ]; then
        run unlink "/etc/nginx/sites-enabled/${1}.conf"
    fi

    run rm -f "/etc/nginx/sites-available/${1}.conf"

    status -e "\nVirtual host configuration file removed."

    # Remove vhost root directory.
    echo -en "\nDo you want to delete website root directory? [y/n]: "; read -rp DELETE_DIR
    if [[ "${DELETE_DIR}" == Y* || "${DELETE_DIR}" == y* ]]; then
        read -rp "Enter the real path to website root directory: " -e WEBROOT

        if [ -d "${WEBROOT}" ]; then
            run rm -fr "${WEBROOT}"
            status -e "\nVirtual host root directory removed."
        else
            warning -e "\nSorry, directory couldn't be found. Skipped..."
        fi
    fi

    # Drop MySQL database.
    echo -en "\nDo you want to Drop database associated with this vhost? [y/n]: "; read -rp DROP_DB
    if [[ "${DROP_DB}" == Y* || "${DROP_DB}" == y* ]]; then
        until [[ "$MYSQLUSER" != "" ]]; do
			read -rp "MySQL Username: " -e MYSQLUSER
		done

        until [[ "$MYSQLPSWD" != "" ]]; do
			echo -n "MySQL Password: "; stty -echo; read -r MYSQLPSWD; stty echo; echo
		done

        echo "Starting to drop database..."
        echo "Please select your database name below!"
        echo "+----------------------+"

        # Show user's databases
        run mysql -u "$MYSQLUSER" -p"$MYSQLPSWD" -e "SHOW DATABASES" | grep -E -v "Database|mysql|*_schema"

        echo "+----------------------+"

        until [[ "$DBNAME" != "" ]]; do
            read -rp "MySQL Database: " -e DBNAME
		done

        if [ -d "/var/lib/mysql/${DBNAME}" ]; then
            echo -e "Dropping database..."
            run mysql -u "$MYSQLUSER" -p"$MYSQLPSWD" -e "DROP DATABASE $DBNAME"
            status -e "Database [${DBNAME}] dropped."
        else
            warning -e "\nSorry, database ${DBNAME} not found. Skipped..."
        fi
    fi

    status -e "\nYour virtual host ${1} has been removed."

    # Reload Nginx.
    reload_nginx
}

# Enable fastcgi cache
function enable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo "Enabling FastCGI cache for ${1}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
    else
        warning "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

# Disable fastcgi cache
function disable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo "Disabling FastCGI cache for ${1}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|include\ /etc/nginx/includes/fastcgi_cache.conf|#include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
    else
        warning "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

# Enable Mod PageSpeed
function enable_mod_pagespeed() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo "Enabling Mod PageSpeed for ${1}..."

    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
        # enable mod pagespeed
        run sed -i "s|#include\ /etc/nginx/includes/mod_pagespeed.conf|include\ /etc/nginx/includes/mod_pagespeed.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
    else
        warning "Mod PageSpeed is not enabled. Nginx must be installed with PageSpeed module."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

# Disable Mod PageSpeed
function disable_mod_pagespeed() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    echo "Disabling Mod PageSpeed for ${1}..."

    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
        # Enable mod pagespeed
        run sed -i "s|include\ /etc/nginx/includes/mod_pagespeed.conf|#include\ /etc/nginx/includes/mod_pagespeed.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
    else
        warning "Mod PageSpeed is not enabled. Nginx must be installed with PageSpeed module."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

# Enable HTTPS.
function enable_https() {
    # Verify user input hostname (domain name).
    verify_host "${1}"

    #TODO: Generate Let's Encrypt SSL using Certbot.
    if [[ ! -d "/etc/nginx/ssl/${1}" ]]; then
        echo "Certbot: Get Let's Encrypt certificate..."

        # Certbot get Let's Encrypt SSL.
        if [ ! -d /etc/nginx/ssl ]; then
            run mkdir "/etc/nginx/ssl/${1}"
        fi
    fi

    # Generate Diffie-Hellman parameters.
    if [ ! -f /etc/letsencrypt/ssl-dhparams-4096.pem ]; then
        echo "Generating Diffie-Hellman parameters for enhanced security..."

        #run openssl dhparam -out /etc/letsencrypt/ssl-dhparams-2048.pem 2048
        #run openssl dhparam -out /etc/letsencrypt/ssl-dhparams-4096.pem 4096
    fi

    # Update vhost config.
    if "${DRYRUN}"; then
        warning "Updating HTTPS config in dryrun mode."
    else
        # Make backup first.
        run cp -f "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-available/${1}.nonssl-conf"
        
        # Change listening port to 443.
        run sed -i "s/listen\ 80/listen\ 443 ssl http2/g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s/listen\ \[::\]:80/listen\ \[::\]:443 ssl http2/g" "/etc/nginx/sites-available/${1}.conf"
        
        # Enable SSL configs.
        run sed -i "s|#include\ /etc/nginx/includes/ssl.conf;|include\ /etc/nginx/includes/ssl.conf|g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s/#ssl_certificate/ssl_certificate/g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s/#ssl_certificate_key/ssl_certificate_key/g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s/#ssl_dhparam/ssl_dhparam/g" "/etc/nginx/sites-available/${1}.conf"

        # Append redirection block.
        cat >> "/etc/nginx/sites-available/${1}.conf" <<EOL

# HTTP to HTTPS redirection
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world web.
    server_name ${1};

    ## Automatically redirect site to HTTPS protocol.
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

EOL

        reload_nginx
    fi

    exit 0
}

# Disable HTTPS.
function disable_https() {
    # Verify user input hostname (domain name)
    verify_host "${1}"

    # Update vhost config.
    if "${DRYRUN}"; then
        warning "Disabling HTTPS config in dryrun mode."
    else
        if [ -f "/etc/nginx/sites-available/${1}.nonssl-conf" ]; then
            # Disable first.
            run unlink "/etc/nginx/sites-enabled/${1}.conf"
            run mv "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-available/${1}.ssl-conf"
            
            # Restore non ssl.
            run cp -f "/etc/nginx/sites-available/${1}.nonssl-conf" "/etc/nginx/sites-available/${1}.conf"
            run ln -s "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-enabled/${1}.conf"

            reload_nginx
        else
            fail "Something went wrong. You still could disable HTTPS manually."
            exit 1
        fi
    fi

    exit 0
}

# Enable Brotli compression module.
function enable_brotli() {
    echo "Enable NGiNX Brotli compression..."

    if [[ -f /etc/nginx/nginx.conf && -f /etc/nginx/modules-enabled/50-mod-http-brotli-static.conf ]]; then
        if grep -qwE "^\    include\ /etc/nginx/comp_gzip" /etc/nginx/nginx.conf; then
            echo "Found Gzip compression enabled, update to Brotli."

            run sed -i "s|include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_brotli;|g" \
                /etc/nginx/nginx.conf
        elif grep -qwE "^\    #include\ /etc/nginx/comp_gzip" /etc/nginx/nginx.conf; then
            echo "No compression module previously, enable Brotli."

            run sed -i "s|#include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_brotli;|g" \
                /etc/nginx/nginx.conf
        else
            warning "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Brotli module manually."
            exit 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find NGiNX and Brotli module config file"
        echo "it should be located under /etc/nginx/ directory."
        exit 1
    fi
}

# Enable Gzip compression module,
# enabled by default.
function enable_gzip() {
    echo "Enable NGiNX Gzip compression..."

    if [[ -f /etc/nginx/nginx.conf ]]; then
        if grep -qwE "^\    include\ /etc/nginx/comp_brotli" /etc/nginx/nginx.conf; then
            echo "Found Brotli compression enabled, update to Gzip."

            run sed -i "s|include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_gzip;|g" \
                /etc/nginx/nginx.conf
        elif grep -qwE "^\    #include\ /etc/nginx/comp_gzip" /etc/nginx/nginx.conf; then
            echo "No compression module previously, enable Gzip."

            run sed -i "s|#include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_gzip;|g" \
                /etc/nginx/nginx.conf
        else
            warning "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Gzip module manually."
            exit 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find NGiNX config file"
        echo "it should be located under /etc/nginx/ directory."
        exit 1
    fi
}

# Verify if virtual host exists.
function verify_host() {
    if [[ -z "${1}" ]]; then
        error "Virtual host (vhost) or domain name is required. Type ${APP_NAME} --help for more info!"
        exit 1
    fi

    if [ ! -f "/etc/nginx/sites-available/${1}.conf" ]; then
        error "Sorry, we couldn't find Nginx virtual host: ${1}..."
        exit 1
    fi
}

# Reload NGiNX safely.
function reload_nginx() {
    # Reload Nginx
    echo "Reloading NGiNX configuration..."

    if [[ -e /var/run/nginx.pid ]]; then
        if nginx -t 2>/dev/null > /dev/null; then
            service nginx reload -s > /dev/null 2>&1
        else
            fail "Configuration couldn't be validated. Please correct the error below:";
            echo ""
            nginx -t
            exit 1
        fi
    else
        # Nginx service dead? Try to start it
        if [[ -n $(command -v nginx) ]]; then
            service nginx restart > /dev/null 2>&1
        else
            warning "Something went wrong with your LEMP stack installation."
            exit 1
        fi
    fi

    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        status "Your change has been successfully applied."
        exit 0
    else
        fail "An error occurred when updating configuration.";
        exit 1
    fi
}

# Main App
#
function init_app() {
    OPTS=$(getopt -o e:d:r:c:p:s:bghv \
      -l enable:,disable:,remove:,enable-fastcgi-cache:,disable-fastcgi-cache:,enable-pagespeed: \
      -l disable-pagespeed:,enable-https:,disable-https:,enable-brotli,enable-gzip,help,version \
      -n "${APP_NAME}" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -e | --enable)
                enable_vhost "${2}"
                shift 2
            ;;
            -d | --disable)
                disable_vhost "${2}"
                shift 2
            ;;
            -r | --remove)
                remove_vhost "${2}"
                shift 2
            ;;
            -c | --enable-fastcgi-cache)
                enable_fastcgi_cache "${2}"
                shift 2
            ;;
            --disable-fastcgi-cache)
                disable_fastcgi_cache "${2}"
                shift 2
            ;;
            -p | --enable-pagespeed)
                enable_mod_pagespeed "${2}"
                shift 2
            ;;
            --disable-pagespeed)
                disable_mod_pagespeed "${2}"
                shift 2
            ;;
            -s | --enable-https)
                enable_https "${2}"
                shift 2
            ;;
            --disable-https)
                disable_https "${2}"
                shift 2
            ;;
            -b | --enable-brotli)
                enable_brotli
                shift 2
            ;;
            -g | --enable-gzip)
                enable_gzip
                shift 2
            ;;
            -h | --help)
                show_usage
                exit 0
                shift 2
            ;;
            -v | --version)
                echo "${APP_NAME} version ${APP_VERSION}"
                exit 0
                shift 2
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

    echo "${APP_NAME}: missing required argument"
    echo "Try '${APP_NAME} --help' for more information."
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_app "$@"
