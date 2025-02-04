#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Virtual Host (Site) Manager                                |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
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
CMD_PARENT="${PROG_NAME}"
CMD_NAME="manage"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Main Functions
##

## 
# Show usage
# output to STDERR.
##
function show_usage() {
cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
LEMPer Stack virtual host (vhost) manager, 
enable, disable, remove Nginx vhost on Debian/Ubuntu server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTION]...

Options:
  -b, --enable-brotli <vhost domain name>
      Enable Brotli compression.
  -c, --enable-fastcgi-cache <vhost domain name>
      Enable FastCGI cache.
  --disable-fastcgi-cache <vhost domain name>
      Disable FastCHI cache.
  -d, --disable <vhost domain name>
      Disable virtual host.
  -e, --enable <vhost domain name>
      Enable virtual host.
  -f, --enable-fail2ban <vhost domain name>
      Enable fail2ban jail.
  --disable-fail2ban <vhost domain name>
      Disable fail2ban jail.
  -g, --enable-gzip <vhost domain name>
      Enable Gzip compression.
  --disable-compression  <vhost domain name>
      Disable Gzip/Brotli compression.
  -r, --remove <vhost domain name>
      Remove virtual host configuration.
  -s, --enable-ssl <vhost domain name>
      Enable HTTP over SSL with Let's Encrypt.
  -w, --enforce-non-www <vhost domain name>
      Redirect www to non www host.
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

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Enable vhost.
##
function enable_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling virtual host: ${DOMAIN}..."

    # Enable Nginx's vhost config.
    if [[ ! -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" && -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]]; then
        run ln -s "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
        success "Your virtual host ${DOMAIN} has been enabled..."
        reload_nginx
    else
        fail "${DOMAIN} couldn't be enabled. Probably, it has been enabled or not created yet."
        exit 1
    fi
}

##
# Disable vhost.
##
function disable_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling virtual host: ${DOMAIN}..."

    # Disable Nginx's vhost config.
    if [[ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]]; then
        run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"
        success "Your virtual host ${DOMAIN} has been disabled..."
        reload_nginx
    else
        fail "${DOMAIN} couldn't be disabled. Probably, it has been disabled or removed."
        exit 1
    fi
}

##
# Remove vhost.
##
function remove_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Removing virtual host is not reversible."
    read -t 30 -rp "Press [Enter] to continue..." </dev/tty

    # Get web root path from vhost config, first.
    local WEBROOT && \
    WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

    # Remove Nginx's vhost config.
    [[ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]] && \
        run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] && \
        run rm -f "/etc/nginx/sites-available/${DOMAIN}.conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] && \
        run rm -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf" ]] && \
        run rm -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

    [[ -f "/etc/lemper/vhost.d/${DOMAIN}.conf" ]] && \
        run rm -f "/etc/lemper/vhost.d/${DOMAIN}.conf"

    # If we have local domain setup in hosts file, remove it.
    if grep -qwE "${DOMAIN}" "/etc/hosts"; then
        info "Domain ${DOMAIN} found in your hosts file. Removing now...";
        run sed -i".backup" "/${DOMAIN}/d" "/etc/hosts"
    fi

    success "Virtual host configuration file removed."

    # Remove vhost root directory.
    read -rp "Do you want to delete website root directory? [y/n]: " -e DELETE_DIR

    # Fix web root path for framework apps that use 'public' directory.
    WEBROOT=$(echo "${WEBROOT}" | sed '$ s|\/public$||')

    if [[ "${DELETE_DIR}" == Y* || "${DELETE_DIR}" == y* ]]; then
        if [[ ! -d "${WEBROOT}" ]]; then
            read -rp "Enter real path to website root directory: " -i "${WEBROOT}" -e WEBROOT
        fi

        if [[ -d "${WEBROOT}" ]]; then
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

        echo "+-------------------------------+"

        until [[ "${DBNAME}" != "" ]]; do
            read -rp "MySQL Database: " -e DBNAME
		done

        if [[ -d "/var/lib/mysql/${DBNAME}" ]]; then
            echo "Deleting database ${DBNAME}..."
            run mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "DROP DATABASE ${DBNAME}"
            success "Database '${DBNAME}' dropped."
        else
            info "Sorry, database ${DBNAME} not found. Skipped..."
        fi
    fi

    echo "Virtual host ${DOMAIN} has been removed."

    # Reload Nginx.
    reload_nginx
}

##
# Enable fail2ban for virtual host.
##
function enable_fail2ban() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling Fail2ban ${FRAMEWORK^} filter for ${DOMAIN}..."

    # Get web root path from vhost config, first.
    local WEBROOT && \
    WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

    if [[ ! -d ${WEBROOT} ]]; then
        read -rp "Enter real path to website root directory containing your access_log file: " -i "${WEBROOT}" -e WEBROOT
    fi

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/filter.d/${FRAMEWORK}.conf" ]]; then
        cat > "/etc/fail2ban/jail.d/${DOMAIN}.conf" <<EOL
[${1}]
enabled = true
port = http,https
filter = ${FRAMEWORK}
action = iptables-multiport[name=webapps, port="http,https", protocol=tcp]
logpath = ${WEBROOT}/logs/nginx/access_log
bantime = 7d
findtime = 5m
maxretry = 3
EOL

        # Reload fail2ban
        run service fail2ban reload
        success "Fail2ban ${FRAMEWORK^} filter for ${DOMAIN} enabled."
    else
        info "Fail2ban or framework's filter is not installed. Please install it first!"
    fi
}

##
# Disable fail2ban for virtual host.
##
function disable_fail2ban() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling Fail2ban ${FRAMEWORK^} filter for ${DOMAIN}..."

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/jail.d/${DOMAIN}.conf" ]]; then
        run rm -f "/etc/fail2ban/jail.d/${DOMAIN}.conf"
        run service fail2ban reload
        success "Fail2ban ${FRAMEWORK^} filter for ${DOMAIN} disabled."
    else
        info "Fail2ban or framework's filter is not installed. Please install it first!"
    fi
}

##
# Enable Nginx's fastcgi cache.
##
function enable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling FastCGI cache for ${DOMAIN}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # Reload Nginx.
        reload_nginx
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi
}

##
# Disable Nginx's fastcgi cache.
##
function disable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling FastCGI cache for ${DOMAIN}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|^\    include\ /etc/nginx/includes/rules_fastcgi_cache.conf|\    #include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|^\        include\ /etc/nginx/includes/fastcgi_cache.conf|\        #include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # Reload Nginx.
        reload_nginx
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi
}

##
# Enable HTTPS (HTTP over SSL).
##
function enable_ssl() {
    # Verify user input hostname (domain name).
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        if [[ "${ENVIRONMENT}" == prod* ]]; then
            echo "Certbot: Get Let's Encrypt certificate..."

            # Get web root path from vhost config, first.
            local WEBROOT && \
            WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

            # Certbot get Let's Encrypt SSL.
            if [[ -n $(command -v certbot) ]]; then
                # Is it wildcard vhost?
                if grep -qwE "${DOMAIN}\ \*.${DOMAIN}" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                    run certbot certonly --force-renewal --manual --noninteractive --manual-public-ip-logging-ok \
                        --preferred-challenges dns --server https://acme-v02.api.letsencrypt.org/directory --agree-tos \
                        --webroot-path="${WEBROOT}" -d "${DOMAIN}" -d "*.${DOMAIN}"
                else
                    run certbot certonly --force-renewal --webroot --noninteractive --preferred-challenges http --agree-tos \
                        --webroot-path="${WEBROOT}" -d "${DOMAIN}"
                fi
            else
                fail "Certbot executable binary not found. Install it first!"
            fi
        else
            # Self-signed SSL.
            echo "Self-signed SSL: Generate SSL certificate..."
            
            generate_selfsigned_ssl "${DOMAIN}"
            
            if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
                run mkdir -p "/etc/letsencrypt/live/${DOMAIN}"
                run chmod 0700 /etc/letsencrypt/live
            fi

            run ln -sf "/etc/lemper/ssl/${DOMAIN}/cert.pem" "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" && \
            run ln -sf "/etc/lemper/ssl/${DOMAIN}/privkey.pem" "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        fi

        # Generate Diffie-Hellman parameters.
        if [ ! -f /etc/nginx/ssl/dhparam-2048.pem ]; then
            echo "Generating Diffie-Hellman parameters for enhanced HTTPS/SSL security."

            run openssl dhparam -out /etc/nginx/ssl/dhparam-2048.pem 2048
            #run openssl dhparam -out /etc/nginx/ssl/dhparam-4096.pem 4096
        fi
    else
        info "SSL certificates is already exists for ${DOMAIN}, trying to renew."
        renew_ssl "${DOMAIN}"
    fi

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        # Ensure there is no HTTPS enabled server block.
        if ! grep -qwE "^\    listen\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b:443\ ssl" "/etc/nginx/sites-available/${DOMAIN}.conf"; then

            # Make backup first.
            run cp -f "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf"

            # Change listening port to 443.
            if grep -qwE "^\    listen\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b:80" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                run sed -i "s/\:80/\:443\ ssl/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            fi
            
            run sed -i "s/listen\ 80/listen\ 443\ ssl/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/listen\ \[::\]:80/listen\ \[::\]:443\ ssl/g" "/etc/nginx/sites-available/${DOMAIN}.conf"

            # Enable SSL configs.
            run sed -i "s/http2\ off/http2\ on/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/#ssl_certificate/ssl_certificate/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/#ssl_certificate_key/ssl_certificate_key/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/#ssl_trusted_certificate/ssl_trusted_certificate/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s|#include\ /etc/nginx/includes/ssl.conf|include\ /etc/nginx/includes/ssl.conf|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"

            # Append HTTP <=> HTTPS redirection block.
            cat >> "/etc/nginx/sites-available/${DOMAIN}.conf" <<EOL

## HTTP to HTTPS redirection.
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world wide.
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
        fi
    else
        info "Updating HTTPS config in dry run mode."
    fi
}

##
# Disable HTTPS (HTTP over SSL).
##
function disable_ssl() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        echo "Disabling HTTPS configuration..."

        if [ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]; then
            # Disable vhost first.
            run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            # Backup ssl config.
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] && \
            run mv "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

            # Restore non ssl config.
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] && \
            run mv "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run ln -sf "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            reload_nginx
        else
            error "It seems that SSL is not yet enabled."
        fi
    else
        info "Disabling HTTPS config in dry run mode."
    fi
}

##
# Disable HTTPS and remove Let's Encrypt SSL certificate.
##
function remove_ssl() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        # Disable HTTPS first.
        echo "Disabling HTTPS configuration..."

        if [ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]; then
            # Disable vhost first.
            run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            # Backup ssl config.
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] && \
            run mv "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

            # Restore non ssl config.
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] && \
            run mv "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run ln -sf "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
        else
            error "It seems that SSL is not yet enabled."
        fi

        # Remove SSL config.
        if [ -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf" ]; then
            run rm "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"
        fi

        # Remove SSL cert.
        echo "Removing SSL certificate..."

        if [[ "${ENVIRONMENT}" == prod* ]]; then
            if [[ -n $(command -v certbot) ]]; then
                run certbot delete --cert-name "${DOMAIN}"
            else
                fail "Certbot executable binary not found. Install it first!"
            fi
        else
            if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
                run unlink "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
            fi

            if [ -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" ]; then
                run unlink "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
            fi

            if [ -d "/etc/letsencrypt/live/${DOMAIN}/" ]; then
                run rm -rf "/etc/letsencrypt/live/${DOMAIN}/"
            fi

            if [ -d "/etc/lemper/ssl/${DOMAIN}/" ]; then
                run rm -rf "/etc/lemper/ssl/${DOMAIN}/"
            fi
        fi

        reload_nginx
    else
        info "SSL certificate removed in dry run mode."
    fi
}

##
# Renew Let's Encrypt SSL certificate.
##
function renew_ssl() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Renew SSL certificate..."

    # Renew Let's Encrypt SSL using Certbot.
    if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
        if [[ "${ENVIRONMENT}" == prod* ]]; then
            echo "Certbot: Renew Let's Encrypt certificate..."

            # Get web root path from vhost config, first.
            local WEBROOT && \
            WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

            # Certbot get Let's Encrypt SSL.
            if [[ -n $(command -v certbot) ]]; then
                # Is it wildcard vhost?
                if grep -qwE "${DOMAIN}\ \*.${DOMAIN}" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                    run certbot certonly --manual --agree-tos --preferred-challenges dns \
                        --server https://acme-v02.api.letsencrypt.org/directory \
                        --manual-public-ip-logging-ok --webroot-path="${WEBROOT}" -d "${DOMAIN}" -d "*.${DOMAIN}"
                else
                    run certbot renew --cert-name "${DOMAIN}"
                fi
            else
                fail "Certbot executable binary not found. Install it first!"
            fi
        else
            # Re-generate self-signed certs.
            generate_selfsigned_ssl "${DOMAIN}"

            if [[ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
                run mkdir -p "/etc/letsencrypt/live/${DOMAIN}"
                run chmod 0700 /etc/letsencrypt/live
            fi

            run ln -sf "/etc/lemper/ssl/${DOMAIN}/cert.pem" "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
            run ln -sf "/etc/lemper/ssl/${DOMAIN}/privkey.pem" "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        fi
    else
        info "Certificate file not found. May be your SSL is not activated yet."
    fi

    reload_nginx
}

##
# Enable Brotli compression module.
##
function enable_brotli() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    if [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" && -f /etc/nginx/modules-enabled/50-mod-http-brotli.conf ]]; then
        echo "Enable Nginx Brotli compression..."

        if grep -qwE "^\    include\ /etc/nginx/includes/compression_brotli.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            info "Brotli compression module already enabled."
            exit 0
        elif grep -qwE "^\    include\ /etc/nginx/includes/compression_gzip.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Found Gzip compression enabled, updating to Brotli..."

            run sed -i "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_brotli.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        elif grep -qwE "^\    #include\ /etc/nginx/includes/compression_[a-z]*\.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Enabling Brotli compression module..."

            run sed -i "s|#include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_brotli.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        else
            error "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Brotli module manually."
            exit 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find Nginx and Brotli module config file"
        echo "it should be located under /etc/nginx/ directory."
        exit 1
    fi
}

##
# Enable Gzip compression module,
# enabled by default.
##
function enable_gzip() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    if [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" && -f /etc/nginx/includes/compression_gzip.conf ]]; then
        echo "Enable Nginx Gzip compression..."

        if grep -qwE "^\    include\ /etc/nginx/includes/compression_gzip.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            info "Gzip compression module already enabled."
            exit 0
        elif grep -qwE "^\    include\ /etc/nginx/includes/compression_brotli.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Found Brotli compression enabled, updating to Gzip..."

            run sed -i "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_gzip.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        elif grep -qwE "^\    #include\ /etc/nginx/includes/compression_[a-z]*\.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Enabling Gzip compression module..."

            run sed -i "s|#include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_gzip.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        else
            error "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Gzip module manually."
            exit 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find Nginx config file"
        echo "it should be located under /etc/nginx/ directory."
        exit 1
    fi
}

##
# Disable Gzip/Brotli compression module
##
function disable_compression() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling compression module..."

    if grep -qwE "^\    include\ /etc/nginx/includes/compression_[a-z]*\.conf" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
        run sed -i "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|#include\ /etc/nginx/includes/compression_gzip.conf;|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"
    else
        error "Sorry, we couldn't find any enabled compression module."
        exit 1
    fi

    reload_nginx
}

##
# Verify if virtual host exists.
##
function verify_vhost() {
    if [[ -z "${1}" ]]; then
        error "Virtual host (vhost) or domain name is required."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
    fi

    if [[ "${1}" == "default" ]]; then
        error "Modify/delete default virtual host is prohibitted."
        exit 1
    fi

    if [[ ! -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]]; then
        error "Sorry, we couldn't find Nginx virtual host: ${1}..."
        exit 1
    fi
}

##
# Reload Nginx safely.
##
function reload_nginx() {
    # Reload Nginx
    echo "Reloading Nginx configuration..."

    if [[ -e /var/run/nginx.pid ]]; then
        if nginx -t > /dev/null 2>&1; then
            service nginx reload -s > /dev/null 2>&1
        else
            error "Configuration couldn't be validated. Please correct the error below:";
            nginx -t
            exit 1
        fi
    # Nginx service dead? Try to start it.
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
# Generate sel-signed certificate.
##
function generate_selfsigned_ssl() {
    # Verify user input hostname (domain name).
    local DOMAIN=${1}
    local SERVER_IP=${2:-$(get_ip_public)}
    verify_vhost "${DOMAIN}"

    if [ ! -d "/etc/lemper/ssl/${DOMAIN}" ]; then
        run mkdir -p "/etc/lemper/ssl/${DOMAIN}"
    fi

    run sed -i "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/ca.conf && \
    run sed -i "s|^CN\ =\ .*|CN\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    run sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    run sed -i "s|^DNS\.2\ =\ .*|DNS\.2\ =\ www\.${DOMAIN}|g" /etc/lemper/ssl/csr.conf && \
    run sed -r -i "s|^IP.1\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.1\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
    run sed -r -i "s|^IP.2\ =\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b$|IP.2\ =\ ${SERVER_IP}|g" /etc/lemper/ssl/csr.conf && \
    run sed -i "s|^DNS\.1\ =\ .*|DNS\.1\ =\ ${DOMAIN}|g" /etc/lemper/ssl/cert.conf

    # Create Certificate Authority (CA).
    run openssl req -x509 -sha256 -days 365000 -nodes -newkey rsa:2048 \
        -keyout "/etc/lemper/ssl/${DOMAIN}/ca.key" -out "/etc/lemper/ssl/${DOMAIN}/ca.crt" \
        -config /etc/lemper/ssl/ca.conf

    CA_KEY_FILE="/etc/lemper/ssl/${DOMAIN}/ca.key"
    CA_CRT_FILE="/etc/lemper/ssl/${DOMAIN}/ca.crt"

    # Create Server Private Key.
    run openssl genrsa -out "/etc/lemper/ssl/${DOMAIN}/privkey.pem" 2048 && \

    # Generate Certificate Signing Request (CSR) using Server Private Key.
    run openssl req -new -key "/etc/lemper/ssl/${DOMAIN}/privkey.pem" \
        -out "/etc/lemper/ssl/${DOMAIN}/csr.csr" -config /etc/lemper/ssl/csr.conf

    # Generate SSL certificate With self signed CA.
    run openssl x509 -req -sha256 -days 365000 -CAcreateserial \
        -CA "${CA_CRT_FILE}" -CAkey "${CA_KEY_FILE}" \
        -in "/etc/lemper/ssl/${DOMAIN}/csr.csr" -out "/etc/lemper/ssl/${DOMAIN}/cert.pem" \
        -extfile /etc/lemper/ssl/cert.conf

    # Create chain file.
    run cat "/etc/lemper/ssl/${DOMAIN}/cert.pem" "${CA_CRT_FILE}" >> \
        "/etc/lemper/ssl/${DOMAIN}/fullchain.pem"

    if [ -f "/etc/lemper/ssl/${DOMAIN}/cert.pem" ]; then
        success "Self-signed SSL certificate has been successfully generated."
    else
        fail "An error occurred while generating self-signed SSL certificate."
    fi
}

##
# Get server private IP Address.
##
function get_ip_private() {
    local SERVER_IP_PRIVATE && \
    SERVER_IP_PRIVATE=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

    echo "${SERVER_IP_PRIVATE}"
}

##
# Get server public IP Address.
##
function get_ip_public() {
    local SERVER_IP_PRIVATE && SERVER_IP_PRIVATE=$(get_ip_private)
    local SERVER_IP_PUBLIC && \
    SERVER_IP_PUBLIC=$(curl -sk --connect-timeout 10 --retry 3 --retry-delay 0 http://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${SERVER_IP_PRIVATE}" == "${SERVER_IP_PUBLIC}" ]]; then
        echo "${SERVER_IP_PRIVATE}"
    else
        echo "${SERVER_IP_PUBLIC}"
    fi
}


##
# Main Manage CLI Wrapper
##
function init_lemper_manage() {
    OPTS=$(getopt -o c:d:e:f:r:s:bghv \
      -l enable:,disable:,remove:,enable-fail2ban:,disable-fail2ban:,enable-fastcgi-cache:,disable-fastcgi-cache: \
      -l enable-ssl:,disable-ssl:,remove-ssl:,renew-ssl:,enable-brotli:,enable-gzip:,disable-compression:,help,version \
      -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -e | --enable)
                enable_vhost "${2}"
                shift 2
                exit 0
            ;;
            -d | --disable)
                disable_vhost "${2}"
                shift 2
                exit 0
            ;;
            -r | --remove)
                remove_vhost "${2}"
                shift 2
                exit 0
            ;;
            -c | --enable-fastcgi-cache)
                enable_fastcgi_cache "${2}"
                shift 2
                exit 0
            ;;
            --disable-fastcgi-cache)
                disable_fastcgi_cache "${2}"
                shift 2
                exit 0
            ;;
            -f | --enable-fail2ban)
                enable_fail2ban "${2}"
                shift 2
                exit 0
            ;;
            --disable-fail2ban)
                disable_fail2ban "${2}"
                shift 2
                exit 0
            ;;
            -s | --enable-ssl)
                enable_ssl "${2}"
                shift 2
                exit 0
            ;;
            --disable-ssl)
                disable_ssl "${2}"
                shift 2
                exit 0
            ;;
            --remove-ssl)
                remove_ssl "${2}"
                shift 2
                exit 0
            ;;
            --renew-ssl)
                renew_ssl "${2}"
                shift 2
                exit 0
            ;;
            -b | --enable-brotli)
                enable_brotli "${2}"
                shift 2
                exit 0
            ;;
            -g | --enable-gzip)
                enable_gzip "${2}"
                shift 2
                exit 0
            ;;
            --disable-compression)
                disable_compression "${2}"
                shift 2
                exit 0
            ;;
            -h | --help)
                show_usage
                shift 2
                exit 0
            ;;
            -v | --version)
                echo "${PROG_NAME} version ${PROG_VERSION}"
                shift 2
                exit 0
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

    echo "${CMD_PARENT} ${CMD_NAME}: missing required argument"
    echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_manage "$@"
