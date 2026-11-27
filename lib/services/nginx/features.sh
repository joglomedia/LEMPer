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
        return 1
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
        return 1
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
        sed_inplace "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # enable fastcgi_cache conf
        sed_inplace "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        if [[ "${DRYRUN:-false}" != true ]]; then sync_site_cors_includes "${DOMAIN}" || return 1; fi
        # Reload Nginx.
        reload_nginx
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        return 1
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
        sed_inplace "s|^\    include\ /etc/nginx/includes/rules_fastcgi_cache.conf|\    #include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # enable fastcgi_cache conf
        sed_inplace "s|^\        include\ /etc/nginx/includes/fastcgi_cache.conf|\        #include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # Reload Nginx.
        reload_nginx
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        return 1
    fi
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
            return 0
        elif grep -qwE "^\    include\ /etc/nginx/includes/compression_gzip.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Found Gzip compression enabled, updating to Brotli..."

            sed_inplace "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_brotli.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        elif grep -qwE "^\    #include\ /etc/nginx/includes/compression_[a-z]*\.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Enabling Brotli compression module..."

            sed_inplace "s|#include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_brotli.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        else
            error "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Brotli module manually."
            return 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find Nginx and Brotli module config file"
        echo "it should be located under /etc/nginx/ directory."
        return 1
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
            return 0
        elif grep -qwE "^\    include\ /etc/nginx/includes/compression_brotli.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Found Brotli compression enabled, updating to Gzip..."

            sed_inplace "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_gzip.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        elif grep -qwE "^\    #include\ /etc/nginx/includes/compression_[a-z]*\.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Enabling Gzip compression module..."

            sed_inplace "s|#include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_gzip.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        else
            error "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Gzip module manually."
            return 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find Nginx config file"
        echo "it should be located under /etc/nginx/ directory."
        return 1
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
        sed_inplace "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|#include\ /etc/nginx/includes/compression_gzip.conf;|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"
    else
        error "Sorry, we couldn't find any enabled compression module."
        return 1
    fi

    reload_nginx
}

##
# Enable CORS for a virtual host.
##

# Cache locations declare their own headers, so they must carry CORS headers too.
# Rebuild only this site's includes; preserve its user-edited origin policy file.
function sync_site_cors_includes() {
    local domain="$1" vhost="/etc/nginx/sites-available/$1.conf"
    local include_line="include /etc/nginx/includes/cors-$1.conf;"
    [[ -f "/etc/nginx/includes/cors-$domain.conf" ]] || return 0
    awk -v target="$include_line" '
        { trimmed=$0; sub(/^[[:space:]]+/, "", trimmed); sub(/[[:space:]]+$/, "", trimmed) }
        trimmed == target { next }
        {
            print
            if (!server_added && /^[[:space:]]*server_name[[:space:]]/) {
                print "    " target
                server_added=1
            }
            if (/^[[:space:]]*include[[:space:]]+\/etc\/nginx\/includes\/fastcgi_cache[.]conf;/)
                print "        " target
        }
    ' "$vhost" >"$vhost.tmp" || {
        rm -f "$vhost.tmp"
        return 1
    }
    run mv "$vhost.tmp" "$vhost"
}

function enable_cors() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"
    local CORS_CONF="/etc/nginx/includes/cors.conf"
    local CORS_SITE="/etc/nginx/includes/cors-${DOMAIN}.conf"
    local INCLUDE_LINE="    include /etc/nginx/includes/cors-${DOMAIN}.conf;"

    if [[ ! -f "${CORS_CONF}" ]]; then
        error "CORS include not found: ${CORS_CONF}"
        return 1
    fi

    if grep -qF "${INCLUDE_LINE}" "${VHOST_FILE}"; then
        sync_site_cors_includes "${DOMAIN}" || return 1
        info "CORS is already enabled for ${DOMAIN}."
        return 0
    fi

    warning "Enabling CORS with a wildcard origin allows requests from any website."
    echo "To restrict origins, edit the 'set \$cors' line in ${CORS_SITE}."

    if [[ "${DRYRUN}" == true ]]; then
        info "Would create ${CORS_SITE} and enable CORS for ${DOMAIN}."
        return 0
    fi

    cat >"${CORS_SITE}" <<EOL
# Generated by lemper-cli site mod --enable-cors for ${DOMAIN}.
# Default policy allows every origin. To restrict, replace "*" with an
# explicit origin, e.g. set \$cors "https://app.example.com";
# For multiple origins define a map in /etc/nginx/cors instead.
set \$cors "*";
include /etc/nginx/includes/cors.conf;
EOL

    sync_site_cors_includes "${DOMAIN}" || return 1

    if grep -qF "${INCLUDE_LINE}" "${VHOST_FILE}"; then
        success "CORS has been enabled for ${DOMAIN}."
        reload_nginx
    else
        fail "Failed to enable CORS for ${DOMAIN}."
    fi
}

##
# Disable CORS for a virtual host.
##
function disable_cors() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"
    local CORS_SITE="/etc/nginx/includes/cors-${DOMAIN}.conf"
    local INCLUDE_LINE="    include /etc/nginx/includes/cors-${DOMAIN}.conf;"

    if ! grep -qF "${INCLUDE_LINE}" "${VHOST_FILE}"; then
        info "CORS is not enabled for ${DOMAIN}."
        return 0
    fi

    echo "Disabling CORS for ${DOMAIN}..."
    sed_inplace "\#${INCLUDE_LINE}#d" "${VHOST_FILE}"
    [[ -f "${CORS_SITE}" ]] && run rm -f "${CORS_SITE}"

    if ! grep -qF "${INCLUDE_LINE}" "${VHOST_FILE}"; then
        success "CORS has been disabled for ${DOMAIN}."
        reload_nginx
    else
        fail "Failed to disable CORS for ${DOMAIN}."
    fi
}

##
# Validate FQDN domain.
# CLI plugins cannot access utils.sh, so each plugin that needs this
# defines its own copy (kept in sync with scripts/utils.sh).
# Uses ERE (grep -E) with a separate length check for portability.
##
function validate_fqdn() {
    core_validate_fqdn "$@"
}

##
# Validate IPv4 address.
##
function validate_ipv4() {
    core_validate_ipv4 "$@"
}

##
# Sanitize a string for safe use in sed replacement patterns.
##
function sanitize_sed_replacement() {
    core_sanitize_sed_replacement "$@"
}

##
# Verify if virtual host exists.
##
function verify_vhost() {
    if [[ -z "${1}" ]]; then
        error "Virtual host (vhost) or domain name is required."
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        return 1
    fi

    if [[ "${1}" == "default" ]]; then
        error "Modify/delete default virtual host is prohibitted."
        return 1
    fi

    # Validate domain name is a proper FQDN before using it in file paths,
    # sed patterns, and openssl commands — prevents injection attacks.
    if [[ $(validate_fqdn "${1}") == false ]]; then
        error "Invalid domain name: '${1}' is not a valid FQDN."
        return 1
    fi

    if [[ ! -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]]; then
        error "Sorry, we couldn't find Nginx virtual host: ${1}..."
        return 1
    fi
}

##
# Reload Nginx safely.
##
function reload_nginx() {
    # Reload Nginx
    echo "Reloading Nginx configuration..."

    if [[ -e /var/run/nginx.pid ]]; then
        if nginx -t >/dev/null 2>&1; then
            service nginx reload -s >/dev/null 2>&1
        else
            error "Configuration couldn't be validated. Please correct the error below:"
            nginx -t
            return 1
        fi
    # Nginx service dead? Try to start it.
    else
        if [[ -n $(command -v nginx) ]]; then
            if nginx -t 2>/dev/null >/dev/null; then
                service nginx restart >/dev/null 2>&1
            else
                error "Configuration couldn't be validated. Please correct the error below:"
                nginx -t
                return 1
            fi
        else
            info "Something went wrong with your LEMP stack installation."
            return 1
        fi
    fi

    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        success "Your change has been successfully applied."
        return 0
    else
        fail "An error occurred when updating configuration."
    fi
}

##
# Get server private IP Address.
##
function get_ip_private() {
    local SERVER_IP_PRIVATE \
        && SERVER_IP_PRIVATE=$(ip addr | grep 'inet' | grep -v inet6 \
            | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
            | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

    echo "${SERVER_IP_PRIVATE}"
}

##
# Get server public IP Address.
##
function get_ip_public() {
    core_get_ip_public
}
