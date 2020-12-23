#!/bin/bash

# +-------------------------------------------------------------------------+
# | Lemper manage - Simple LEMP Virtual Host Manager                        |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2020 ESLabs (https://eslabs.id/lemper)               |
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

# Version control.
APP_NAME=$(basename "$0")
APP_VERSION="1.0.0"
CMD_PARENT="lemper-cli"
CMD_NAME="manage"

# Test mode.
DRYRUN=false

# Color decorator.
RED=91
GREEN=92
YELLOW=93

##
# Helper Functions
#
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
    begin_color "${color}"
    echo "$@"
    end_color
}

function error() {
    echo_color "${RED}" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "${GREEN}" "$@"
}

function warning() {
    echo_color "${YELLOW}" "$@"
}

function success() {
    echo_color "${GREEN}" -n "Success: " >&2
    echo "$@" >&2
}

function info() {
    echo_color "${YELLOW}" -n "Info: " >&2
    echo "$@" >&2
}

# Run command
function run() {
    if "$DRYRUN"; then
        echo_color "${YELLOW}" -n "would run "
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
if [ "$(id -u)" -ne 0 ]; then
    error "This command can only be used by root."
    exit 1
fi


##
# Main Functions
#

## 
# Show usage
# output to STDERR.
#
function show_usage() {
cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Simple NGiNX virtual host (vHost) manager,
enable/disable/remove NGiNX vHost on Debian/Ubuntu Server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTION]...

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
  -F, --enable-fail2ban <vhost domain name>
      Enable fail2ban jail.
  --disable-fail2ban <vhost domain name>
      Disable fail2ban jail.
  -g, --enable-gzip
      Enable Gzip compression.
  -p, --enable-pagespeed <vhost domain name>
      Enable Mod PageSpeed.
  --disable-pagespeed <vhost domain name>
      Disable Mod PageSpeed.
  -r, --remove <vhost domain name>
      Remove virtual host configuration.
  -s, --enable-ssl <vhost domain name>
      Enable HTTP over SSL with Let's Encrypt.
  --disable-ssl <vhost domain name>
      Disable HTTP over SSL.
  --remove-ssl <vhost domain name>
      Remove SSL certificate.
  --renew-ssl <vhost domain name>
      Renew SSL certificate.

  -h, --help
      Print this message and exit.
  -v, --version
      Output version information and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} --remove example.com

For more informations visit https://eslabs.id/lemper
Mail bug reports and suggestions to <eslabs.id@gmail.com>
_EOF_
}

##
# Enable vhost.
#
function enable_vhost() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Enabling virtual host: ${1}..."

    # Enable Nginx's vhost config.
    if [[ ! -f "/etc/nginx/sites-enabled/${1}.conf" && -f "/etc/nginx/sites-available/${1}.conf" ]]; then
        run ln -s "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-enabled/${1}.conf"

        success "Your virtual host ${1} has been enabled..."

        reload_nginx
    else
        fail "${1} couldn't be enabled. Probably, it has been enabled or not created yet."
        exit 1
    fi
}

##
# Disable vhost.
#
function disable_vhost() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Disabling virtual host: ${1}..."

    # Disable Nginx's vhost config.
    if [ -f "/etc/nginx/sites-enabled/${1}.conf" ]; then
        run unlink "/etc/nginx/sites-enabled/${1}.conf"

        success "Your virtual host ${1} has been disabled..."

        reload_nginx
    else
        fail "${1} couldn't be disabled. Probably, it has been disabled or removed."
        exit 1
    fi
}

##
# Remove vhost.
#
function remove_vhost() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Removing virtual host is not reversible."
    read -t 30 -rp "Press [Enter] to continue..." </dev/tty

    # Get web root path from vhost config, first.
    #shellcheck disable=SC2154
    local WEBROOT && \
    WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${1}.conf" | awk '{print $3}' | cut -d'"' -f2)

    # Remove Nginx's vhost config.
    if [ -f "/etc/nginx/sites-enabled/${1}.conf" ]; then
        run unlink "/etc/nginx/sites-enabled/${1}.conf"
    fi

    run rm -f "/etc/nginx/sites-available/${1}.*"

    success "Virtual host configuration file removed."

    # Remove vhost root directory.
    read -rp "Do you want to delete website root directory? [y/n]: " -e DELETE_DIR
    if [[ "${DELETE_DIR}" == Y* || "${DELETE_DIR}" == y* ]]; then
        if [[ ! -d ${WEBROOT} ]]; then
            read -rp "Enter real path to website root directory: " -i "${WEBROOT}" -e WEBROOT
        fi

        if [ -d "${WEBROOT}" ]; then
            run rm -fr "${WEBROOT}"
            success "Virtual host root directory removed."
        else
            info "Sorry, directory couldn't be found. Skipped..."
        fi
    fi

    # Drop MySQL database.
    read -rp "Do you want to Drop database associated with this domain? [y/n]: " -e DROP_DB
    if [[ "${DROP_DB}" == Y* || "${DROP_DB}" == y* ]]; then
        until [[ "${MYSQL_USER}" != "" ]]; do
			read -rp "MySQL Username: " -e MYSQL_USER
		done

        until [[ "${MYSQL_PASS}" != "" ]]; do
			echo -n "MySQL Password: "; stty -echo; read -r MYSQL_PASS; stty echo; echo
		done

        echo ""
        echo "Please select your database below!"
        echo "+-------------------------------+"
        echo "|         Database name          "
        echo "+-------------------------------+"

        # Show user's databases
        #run mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema"
        local DATABASES && \
        DATABASES=$(mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema")

        if [[ -n "${DATABASES}" ]]; then
            printf '%s\n' "${DATABASES}"
        else
            echo "No database found."
        fi

        echo "+----------------------+"

        until [[ "${DBNAME}" != "" ]]; do
            read -rp "MySQL Database: " -e DBNAME
		done

        if [ -d "/var/lib/mysql/${DBNAME}" ]; then
            echo "Deleting database ${DBNAME}..."
            run mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "DROP DATABASE ${DBNAME}"
            success "Database '${DBNAME}' dropped."
        else
            info "Sorry, database ${DBNAME} not found. Skipped..."
        fi
    fi

    echo "Virtual host ${1} has been removed."

    # Reload Nginx.
    reload_nginx
}


function enable_fail2ban() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Enabling Fail2ban ${FRAMEWORK^} filter for ${1}..."

    # Get web root path from vhost config, first.
    #shellcheck disable=SC2154
    local WEBROOT && \
    WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${1}.conf" | awk '{print $3}' | cut -d'"' -f2)

    if [[ ! -d ${WEBROOT} ]]; then
        read -rp "Enter real path to website root directory containing your access_log file: " -i "${WEBROOT}" -e WEBROOT
    fi

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/filter.d/${FRAMEWORK}.conf" ]]; then
        cat > "/etc/fail2ban/jail.d/${1}.conf" <<_EOL_
[${1}]
enabled = true
port = http,https
filter = ${FRAMEWORK}
action = iptables-multiport[name=webapps, port="http,https", protocol=tcp]
logpath = ${WEBROOT}/access_log
maxretry = 3
_EOL_

        # Reload fail2ban
        run service fail2ban reload
    else
        info "Fail2ban or filter is not installed. Please install it first."
    fi
}

##
# Enable Nginx's fastcgi cache.
#
function enable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Enabling FastCGI cache for ${1}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

##
# Disable Nginx's fastcgi cache.
#
function disable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Disabling FastCGI cache for ${1}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|^\    include\ /etc/nginx/includes/rules_fastcgi_cache.conf|\    #include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|^\        include\ /etc/nginx/includes/fastcgi_cache.conf|\        #include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

##
# Enable Nginx's Mod PageSpeed.
#
function enable_mod_pagespeed() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Enabling Mod PageSpeed for ${1}..."

    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/60-mod-pagespeed.conf ]]; then
        # enable mod pagespeed
        run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" /etc/nginx/nginx.conf
        run sed -i "s|#include\ /etc/nginx/includes/mod_pagespeed.conf|include\ /etc/nginx/includes/mod_pagespeed.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s|#pagespeed\ EnableFilters|pagespeed\ EnableFilters|g" \
            "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s|#pagespeed\ Disallow|pagespeed\ Disallow|g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s|#pagespeed\ Domain|pagespeed\ Domain|g" "/etc/nginx/sites-available/${1}.conf"

        # If SSL enabled, ensure to also to enable PageSpeed related vars.
        #if grep -qwE "^\    include\ /etc/nginx/includes/ssl.conf" "/etc/nginx/sites-available/${1}.conf"; then
        #    run sed -i "s/#pagespeed\ FetchHttps/pagespeed\ FetchHttps/g" \
        #        "/etc/nginx/sites-available/${1}.conf"
        #    run sed -i "s/#pagespeed\ MapOriginDomain/pagespeed\ MapOriginDomain/g" \
        #        "/etc/nginx/sites-available/${1}.conf"
        #fi
    else
        info "Mod PageSpeed is not enabled. NGiNX must be installed with PageSpeed module."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

##
# Disable Nginx's Mod PageSpeed.
#
function disable_mod_pagespeed() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    echo "Disabling Mod PageSpeed for ${1}..."

    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/60-mod-pagespeed.conf ]]; then
        # Disable mod pagespeed
        #run sed -i "s|^\    include\ /etc/nginx/mod_pagespeed|\    #include\ /etc/nginx/mod_pagespeed|g" /etc/nginx/nginx.conf
        run sed -i "s|^\    include\ /etc/nginx/includes/mod_pagespeed.conf|\    #include\ /etc/nginx/includes/mod_pagespeed.conf|g" \
            "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s|^\    pagespeed\ EnableFilters|\    #pagespeed\ EnableFilters|g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s|^\    pagespeed\ Disallow|\    #pagespeed\ Disallow|g" "/etc/nginx/sites-available/${1}.conf"
        run sed -i "s|^\    pagespeed\ Domain|\    #pagespeed\ Domain|g" "/etc/nginx/sites-available/${1}.conf"

        # If SSL enabled, ensure to also disable PageSpeed related vars.
        #if grep -qwE "\    include /etc/nginx/includes/ssl.conf" "/etc/nginx/sites-available/${1}.conf"; then
        #    run sed -i "s/^\    pagespeed\ FetchHttps/\    #pagespeed\ FetchHttps/g" \
        #        "/etc/nginx/sites-available/${1}.conf"
        #    run sed -i "s/^\    pagespeed\ MapOriginDomain/\    #pagespeed\ MapOriginDomain/g" \
        #        "/etc/nginx/sites-available/${1}.conf"
        #fi
    else
        info "Mod PageSpeed is not enabled. NGiNX must be installed with PageSpeed module."
        exit 1
    fi

    # Reload Nginx.
    reload_nginx
}

##
# Enable HTTPS (HTTP over SSL).
#
function enable_ssl() {
    # Verify user input hostname (domain name).
    verify_vhost "${1}"

    #TODO: Generate Let's Encrypt SSL using Certbot.
    if [ ! -d "/etc/letsencrypt/live/${1}" ]; then
        echo "Certbot: Get Let's Encrypt certificate..."

        # Get web root path from vhost config, first.
        #shellcheck disable=SC2154
        local WEBROOT && \
        WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${1}.conf" | awk '{print $3}' | cut -d'"' -f2)

        # Certbot get Let's Encrypt SSL.
        if [[ -n $(command -v certbot) ]]; then
            # Is it wildcard vhost?
            if grep -qwE "${1}\ \*.${1}" "/etc/nginx/sites-available/${1}.conf"; then
                #run certbot certonly --rsa-key-size 4096 --manual --agree-tos --preferred-challenges dns --manual-public-ip-logging-ok \
                #    --webroot-path="${WEBROOT}" -d "${1}" -d "*.${1}"
                run certbot certonly --manual --agree-tos --preferred-challenges dns --server https://acme-v02.api.letsencrypt.org/directory \
                    --manual-public-ip-logging-ok --webroot-path="${WEBROOT}" -d "${1}" -d "*.${1}"
            else
                #run certbot certonly --rsa-key-size 4096 --webroot --agree-tos --preferred-challenges http --webroot-path="${WEBROOT}" -d "${1}"
                run certbot certonly --webroot --agree-tos --preferred-challenges http --webroot-path="${WEBROOT}" -d "${1}"
            fi
        else
            fail "Certbot executable binary not found. Install it first!"
        fi
    fi

    # Generate Diffie-Hellman parameters.
    if [ ! -f /etc/nginx/ssl/dhparam-2048.pem ]; then
        echo "Generating Diffie-Hellman parameters for enhanced HTTPS/SSL security."

        run openssl dhparam -out /etc/nginx/ssl/dhparam-2048.pem 2048
        #run openssl dhparam -out /etc/nginx/ssl/dhparam-4096.pem 4096
    fi

    # Update vhost config.
    if "${DRYRUN}"; then
        info "Updating HTTPS config in dryrun mode."
    else
        # Ensure there is no HTTPS enabled server block.
        if ! grep -qwE "^\    listen\ 443 ssl http2" "/etc/nginx/sites-available/${1}.conf"; then

            # Make backup first.
            run cp -f "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-available/${1}.nonssl-conf"

            # Change listening port to 443.
            run sed -i "s/listen\ 80/listen\ 443 ssl http2/g" "/etc/nginx/sites-available/${1}.conf"
            run sed -i "s/listen\ \[::\]:80/listen\ \[::\]:443 ssl http2/g" "/etc/nginx/sites-available/${1}.conf"

            # Enable SSL configs.
            run sed -i "s/#ssl_certificate/ssl_certificate/g" "/etc/nginx/sites-available/${1}.conf"
            run sed -i "s/#ssl_certificate_key/ssl_certificate_key/g" "/etc/nginx/sites-available/${1}.conf"
            run sed -i "s/#ssl_trusted_certificate/ssl_trusted_certificate/g" "/etc/nginx/sites-available/${1}.conf"
            run sed -i "s|#include\ /etc/nginx/includes/ssl.conf|include\ /etc/nginx/includes/ssl.conf|g" \
                "/etc/nginx/sites-available/${1}.conf"

            # Adjust PageSpeed if enabled.
            #if grep -qwE "^\    include\ /etc/nginx/includes/mod_pagespeed.conf" \
            #    "/etc/nginx/sites-available/${1}.conf"; then
            #    echo "Adjusting PageSpeed configuration..."
            #    run sed -i "s/#pagespeed\ FetchHttps/pagespeed\ FetchHttps/g" \
            #        "/etc/nginx/sites-available/${1}.conf"
            #    run sed -i "s/#pagespeed\ MapOriginDomain/pagespeed\ MapOriginDomain/g" \
            #        "/etc/nginx/sites-available/${1}.conf"
            #fi

            # Append redirection block.
            cat >> "/etc/nginx/sites-available/${1}.conf" <<EOL

# HTTP to HTTPS redirection.
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
        else
            warning -e "\nOops, Nginx HTTPS server block already exists. Please inspect manually for further action!"
            exit 1
        fi
    fi

    exit 0
}

##
# Disable HTTPS (HTTP over SSL).
#
function disable_ssl() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    # Update vhost config.
    if "${DRYRUN}"; then
        info "Disabling HTTPS config in dryrun mode."
    else
        echo "Disabling HTTPS configuration..."

        if [ -f "/etc/nginx/sites-available/${1}.nonssl-conf" ]; then
            # Disable vhost first.
            run unlink "/etc/nginx/sites-enabled/${1}.conf"

            # Backup ssl config.
            run mv "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-available/${1}.ssl-conf"

            # Restore non ssl config.
            run mv "/etc/nginx/sites-available/${1}.nonssl-conf" "/etc/nginx/sites-available/${1}.conf"
            run ln -s "/etc/nginx/sites-available/${1}.conf" "/etc/nginx/sites-enabled/${1}.conf"

            reload_nginx
        else
            error "Something went wrong. You still could disable HTTPS manually."
        fi
    fi

    exit 0
}

##
# Disable HTTPS and remove Let's Encrypt SSL certificate.
#
function remove_ssl() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    # Update vhost config.
    if "${DRYRUN}"; then
        info "Disabling HTTPS and removing SSL certificate in dryrun mode."
    else
        # Disable HTTPS first.
        disable_ssl "${1}"

        # Remove SSL config.
        if [ -f "/etc/nginx/sites-available/${1}.ssl-conf" ]; then
            run rm "/etc/nginx/sites-available/${1}.ssl-conf"
        fi

        # Remove SSL cert.
        echo "Removing SSL certificate..."

        if [[ -n $(command -v certbot) ]]; then
            run certbot delete --cert-name "${1}"
        else
            fail "Certbot executable binary not found. Install it first!"
        fi
    fi
}

##
# Renew Let's Encrypt SSL certificate.
#
function renew_ssl() {
    # Verify user input hostname (domain name)
    verify_vhost "${1}"

    # Update vhost config.
    if "${DRYRUN}"; then
        info "Renew SSL certificate in dryrun mode."
    else
        echo "Renew SSL certificate..."

        # Renew Let's Encrypt SSL using Certbot.
        if [ -d "/etc/letsencrypt/live/${1}" ]; then
            echo "Certbot: Renew Let's Encrypt certificate..."

            # Get web root path from vhost config, first.
            #shellcheck disable=SC2154
            local WEBROOT && \
            WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${1}.conf" | awk '{print $3}' | cut -d'"' -f2)

            # Certbot get Let's Encrypt SSL.
            if [[ -n $(command -v certbot) ]]; then
                # Is it wildcard vhost?
                if grep -qwE "${1}\ \*.${1}" "/etc/nginx/sites-available/${1}.conf"; then
                    run certbot certonly --manual --agree-tos --preferred-challenges dns --server https://acme-v02.api.letsencrypt.org/directory \
                        --manual-public-ip-logging-ok --webroot-path="${WEBROOT}" -d "${1}" -d "*.${1}"
                else
                    run certbot renew --cert-name "${1}" --dry-run
                fi
            else
                fail "Certbot executable binary not found. Install it first!"
            fi
        else
            info "Certificate file not found. May be your SSL is not activated yet."
        fi
    fi
    exit 0
}

##
# Enable Brotli compression module.
#
function enable_brotli() {
    if [[ -f /etc/nginx/nginx.conf && -f /etc/nginx/modules-enabled/50-mod-http-brotli-static.conf ]]; then
        echo "Enable NGiNX Brotli compression..."

        if grep -qwE "^\    include\ /etc/nginx/comp_brotli" /etc/nginx/nginx.conf; then
            info "Brotli compression module already enabled."
            exit 0
        elif grep -qwE "^\    include\ /etc/nginx/comp_gzip" /etc/nginx/nginx.conf; then
            echo "Found Gzip compression enabled, updating to Brotli..."

            run sed -i "s|include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_brotli;|g" \
                /etc/nginx/nginx.conf
        elif grep -qwE "^\    #include\ /etc/nginx/comp_[a-z]*" /etc/nginx/nginx.conf; then
            echo "Enabling Brotli compression module..."

            run sed -i "s|#include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_brotli;|g" \
                /etc/nginx/nginx.conf
        else
            error "Sorry, we couldn't find any compression module section."
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

##
# Enable Gzip compression module,
# enabled by default.
#
function enable_gzip() {
    if [[ -f /etc/nginx/nginx.conf && -d /etc/nginx/vhost ]]; then
        echo "Enable NGiNX Gzip compression..."

        if grep -qwE "^\    include\ /etc/nginx/comp_gzip" /etc/nginx/nginx.conf; then
            info "Gzip compression module already enabled."
            exit 0
        elif grep -qwE "^\    include\ /etc/nginx/comp_brotli" /etc/nginx/nginx.conf; then
            echo "Found Brotli compression enabled, updating to Gzip..."

            run sed -i "s|include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_gzip;|g" \
                /etc/nginx/nginx.conf
        elif grep -qwE "^\    #include\ /etc/nginx/comp_[a-z]*" /etc/nginx/nginx.conf; then
            echo "Enabling Gzip compression module..."

            run sed -i "s|#include\ /etc/nginx/comp_[a-z]*;|include\ /etc/nginx/comp_gzip;|g" \
                /etc/nginx/nginx.conf
        else
            error "Sorry, we couldn't find any compression module section."
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

##
# Verify if virtual host exists.
#
function verify_vhost() {
    if [[ -z "${1}" ]]; then
        error "Virtual host (vhost) or domain name is required. Type ${APP_NAME} --help for more info!"
        exit 1
    fi

    if [[ "${1}" == "default" ]]; then
        error "Modify/delete default virtual host is prohibitted."
        exit 1
    fi

    if [ ! -f "/etc/nginx/sites-available/${1}.conf" ]; then
        error "Sorry, we couldn't find NGiNX virtual host: ${1}..."
        exit 1
    fi
}

##
# Reload NGiNX safely.
#
function reload_nginx() {
    # Reload Nginx
    echo "Reloading NGiNX configuration..."

    if [[ -e /var/run/nginx.pid ]]; then
        if nginx -t 2>/dev/null > /dev/null; then
            service nginx reload -s > /dev/null 2>&1
        else
            error "Configuration couldn't be validated. Please correct the error below:";
            nginx -t
            exit 1
        fi
    # NGiNX service dead? Try to start it.
    else
        if [[ -n $(command -v nginx) ]]; then
            if nginx -t 2>/dev/null > /dev/null; then
                service nginx restart > /dev/null 2>&1
            else
                error "Configuration couldn't be validated. Please correct the error below:";
                nginx -t
                exit 1
            fi
        else
            info "Something went wrong with your LEMP stack installation."
            exit 1
        fi
    fi

    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        success "Your change has been successfully applied."
        exit 0
    else
        fail "An error occurred when updating configuration.";
    fi
}


##
# Main App
#
function init_app() {
    OPTS=$(getopt -o e:d:r:c:p:s:bghv \
      -l enable:,disable:,remove:,enable-fastcgi-cache:,disable-fastcgi-cache:,enable-pagespeed: \
      -l disable-pagespeed:,enable-ssl:,disable-ssl:,remove-ssl:,renew-ssl:,enable-brotli,enable-gzip,help,version \
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
            -s | --enable-ssl)
                enable_ssl "${2}"
                shift 2
            ;;
            --disable-ssl)
                disable_ssl "${2}"
                shift 2
            ;;
            --remove-ssl)
                remove_ssl "${2}"
                shift 2
            ;;
            --renew-ssl)
                renew_ssl "${2}"
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
