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
# Enable HTTPS (HTTP over SSL).
##
function enable_ssl() {
    # Verify user input hostname (domain name).
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    if grep -qE '^[[:space:]]*listen[[:space:]]+([^[:space:]]*:)?443[[:space:]]+ssl([[:space:];]|$)' \
        "/etc/nginx/sites-available/${DOMAIN}.conf"; then
        info "HTTPS is already enabled for ${DOMAIN}."
        return 0
    fi

    if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        if [[ "${ENVIRONMENT}" == prod* ]]; then
            echo "Certbot: Get Let's Encrypt certificate..."

            # Get web root path from vhost config, first.
            local WEBROOT \
                && WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

            # Certbot get Let's Encrypt SSL.
            if [[ -n $(command -v certbot) ]]; then
                # Is it wildcard vhost?
                if grep -qwE "${DOMAIN}\ \*.${DOMAIN}" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                    request_dns01_certificate "${DOMAIN}" true || return 1
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

            run ln -sf "/etc/lemper/ssl/${DOMAIN}/cert.pem" "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" \
                && run ln -sf "/etc/lemper/ssl/${DOMAIN}/privkey.pem" "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        fi

        # Generate Diffie-Hellman parameters.
        if [ ! -f /etc/nginx/ssl/dhparam-2048.pem ]; then
            echo "Generating Diffie-Hellman parameters (ffdhe2048) for enhanced HTTPS/SSL security."

            run openssl genpkey -genparam -algorithm DH -pkeyopt group:ffdhe2048 \
                -out /etc/nginx/ssl/dhparam-2048.pem
        fi
    else
        info "Reusing the existing SSL certificate for ${DOMAIN}."
    fi

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        # Ensure there is no HTTPS enabled server block.
        if ! grep -qwE "^\    listen\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b:443\ ssl" "/etc/nginx/sites-available/${DOMAIN}.conf"; then

            # Make backup first.
            run cp -f "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf"

            # Change listening port to 443.
            if grep -qwE "^\    listen\ (\b[0-9]{1,3}\.){3}[0-9]{1,3}\b:80" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                sed_inplace "s/\:80/\:443\ ssl/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            fi

            sed_inplace "s/listen\ 80/listen\ 443\ ssl/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            sed_inplace "s/listen\ \[::\]:80/listen\ \[::\]:443\ ssl/g" "/etc/nginx/sites-available/${DOMAIN}.conf"

            # Enable HTTP/2 with the non-deprecated directive form.
            if ! grep -qwE '^[[:space:]]*http2[[:space:]]+on;' "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                awk '!done && /listen .*443 ssl/ { print; print "    http2 on;"; done=1; next } { print }' \
                    "/etc/nginx/sites-available/${DOMAIN}.conf" >"/etc/nginx/sites-available/${DOMAIN}.conf.tmp" \
                    && run mv "/etc/nginx/sites-available/${DOMAIN}.conf.tmp" "/etc/nginx/sites-available/${DOMAIN}.conf"
            fi

            # Enable HTTP/3 when the stack was installed with QUIC support.
            if [[ -f /etc/nginx/includes/http3.conf ]] \
                && ! grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/includes/http3\.conf;' \
                    "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                sed_inplace "/^[[:space:]]*http2 on;/a\\    include /etc/nginx/includes/http3.conf;" \
                    "/etc/nginx/sites-available/${DOMAIN}.conf"
            fi

            # Enable SSL configs.
            sed_inplace "s/#ssl_certificate/ssl_certificate/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            sed_inplace "s/#ssl_certificate_key/ssl_certificate_key/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            sed_inplace "s/#ssl_trusted_certificate/ssl_trusted_certificate/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            sed_inplace "s|#include\ /etc/nginx/includes/ssl.conf|include\ /etc/nginx/includes/ssl.conf|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"

            # Append HTTP <=> HTTPS redirection block.
            cat >>"/etc/nginx/sites-available/${DOMAIN}.conf" <<EOL

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
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] \
                && run mv "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

            # Restore non ssl config.
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] \
                && run mv "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" "/etc/nginx/sites-available/${DOMAIN}.conf"
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
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] \
                && run mv "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

            # Restore non ssl config.
            [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] \
                && run mv "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" "/etc/nginx/sites-available/${DOMAIN}.conf"
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
            local WEBROOT \
                && WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

            # Certbot get Let's Encrypt SSL.
            if [[ -n $(command -v certbot) ]]; then
                # Is it wildcard vhost?
                if grep -qwE "${DOMAIN}\ \*.${DOMAIN}" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                    request_dns01_certificate "${DOMAIN}" true || return 1
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
# Generate sel-signed certificate.
##
function generate_selfsigned_ssl() {
    local domain="$1" ipv4="${2:-$(get_ip_public)}"
    verify_vhost "$domain" || return 1
    lemper_load_module services/ssl/certificates || return 1
    # The site orchestrator holds the lock; legacy direct access is isolated.
    lemper_ssl_generate_selfsigned "$domain" "$ipv4"
}
