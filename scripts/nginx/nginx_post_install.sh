#!/usr/bin/env bash

# Nginx Post-Installation Configuration
# Part of LEMPer Stack - https://github.com/joglomedia/LEMPer
# Author: MasEDI.Net (me@masedi.net)
# Since Version: 2.x.x

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

##
# Copy Nginx configuration files
##
function configure_nginx_files() {
    echo "Creating Nginx configuration..."

    local SOURCE_DIR="${1:-.}"

    # Backup existing nginx.conf
    [[ -f /etc/nginx/nginx.conf ]] && run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf~

    # Copy main configuration files
    run cp -f "${SOURCE_DIR}/etc/nginx/nginx.conf" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/charset" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/fastcgi_cache" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/fastcgi_https_map" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/fastcgi_params" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/proxy_cache" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/proxy_params" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/http_cloudflare_ips" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/http_proxy_ips" /etc/nginx/
    run cp -f "${SOURCE_DIR}/etc/nginx/upstream" /etc/nginx/

    # Copy configuration directories
    run cp -fr "${SOURCE_DIR}/etc/nginx/conf.d" /etc/nginx/
    run cp -fr "${SOURCE_DIR}/etc/nginx/includes" /etc/nginx/
    run cp -fr "${SOURCE_DIR}/etc/nginx/vhost" /etc/nginx/

    # Copy custom error pages and index
    [[ ! -d /usr/share/nginx/html ]] && run mkdir -p /usr/share/nginx/html/
    run cp -fr "${SOURCE_DIR}/share/nginx/html/error-pages" /usr/share/nginx/html/
    run cp -f "${SOURCE_DIR}/share/nginx/html/index.html" /usr/share/nginx/html/

    # Let's Encrypt acme challenge directory
    [[ ! -d /usr/share/nginx/html/.well-known ]] && run mkdir -p /usr/share/nginx/html/.well-known/acme-challenge/
}

##
# Create Nginx directories
##
function configure_nginx_directories() {
    echo "Creating Nginx directories..."

    # Create cache directories
    [[ ! -d /var/cache/nginx/fastcgi_cache ]] && run mkdir -p /var/cache/nginx/fastcgi_cache
    [[ ! -d /var/cache/nginx/proxy_cache ]] && run mkdir -p /var/cache/nginx/proxy_cache

    # Create vhost directories
    [[ ! -d /etc/nginx/sites-available ]] && run mkdir -p /etc/nginx/sites-available
    [[ ! -d /etc/nginx/sites-enabled ]] && run mkdir -p /etc/nginx/sites-enabled

    # Create stream vhost directories (if stream module enabled)
    if "${NGX_STREAM:-false}"; then
        [[ ! -d /etc/nginx/streams-available ]] && run mkdir -p /etc/nginx/streams-available
        [[ ! -d /etc/nginx/streams-enabled ]] && run mkdir -p /etc/nginx/streams-enabled

        # Append stream config to nginx.conf
        if ! grep -q "streams-enabled" /etc/nginx/nginx.conf; then
            cat >> /etc/nginx/nginx.conf <<EOL

stream {
    # Load stream vhost configs.
    include /etc/nginx/streams-enabled/*;
}
EOL
        fi
    fi

    # Custom tmp, PHP opcache & sessions dir
    run mkdir -p /usr/share/nginx/html/.lemper/tmp
    run mkdir -p /usr/share/nginx/html/.lemper/php/sessions
    run mkdir -p /usr/share/nginx/html/.lemper/php/opcache
    run mkdir -p /usr/share/nginx/html/.lemper/php/wsdlcache

    # Fix ownership
    [[ -d /usr/share/nginx/html ]] && run chown -hR www-data:www-data /usr/share/nginx/html
    [[ -d /var/cache/nginx ]] && run chown -hR www-data:www-data /var/cache/nginx
}

##
# Configure Nginx performance settings
##
function configure_nginx_performance() {
    echo "Customizing Nginx configuration..."

    # Get CPU count
    local CPU_CORES
    CPU_CORES=$(get_cpu_cores)

    # Adjust worker processes
    if [[ "${CPU_CORES}" -gt 1 ]]; then
        run sed -i "s/worker_processes\ auto/worker_processes\ ${CPU_CORES}/g" /etc/nginx/nginx.conf
    fi

    # Adjust worker connections based on CPU cores
    local NGX_CONNECTIONS
    case ${CPU_CORES} in
        1)       NGX_CONNECTIONS=1024 ;;
        2|3)     NGX_CONNECTIONS=2048 ;;
        *)       NGX_CONNECTIONS=4096 ;;
    esac

    run sed -i "s/worker_connections\ 4096/worker_connections\ ${NGX_CONNECTIONS}/g" /etc/nginx/nginx.conf

    # Configure rate limiting if enabled
    if [[ "${NGINX_RATE_LIMITING:-false}" == true ]]; then
        run sed -i "s|#limit_|limit_|g" /etc/nginx/nginx.conf
        run sed -i "s|rate=10r\/s|rate=${NGINX_RATE_LIMIT_REQUESTS:-10}r\/s|g" /etc/nginx/nginx.conf
    fi

    # Enable Headers More if available
    if [[ "${NGX_HTTP_HEADERS_MORE:-false}" == true && \
          -f /etc/nginx/modules-enabled/50-mod-http-headers-more-filter.conf ]]; then
        run sed -i "s|#more_set_headers|more_set_headers|g" /etc/nginx/nginx.conf
    fi

    # Enable Lua package path if available
    if [[ "${NGX_HTTP_LUA:-false}" == true && \
          -f /etc/nginx/modules-enabled/40-mod-http-lua.conf ]]; then
        run sed -i "s|#lua_package_path|lua_package_path|g" /etc/nginx/nginx.conf
    fi

    # Configure FastCGI cache purge access
    configure_fastcgi_cache_access
}

##
# Configure FastCGI cache purge access
##
function configure_fastcgi_cache_access() {
    local ALLOWED_SERVER_IP
    ALLOWED_SERVER_IP=$(get_ip_private)

    run sed -i "s|#allow\ SERVER_IPV4|allow\ ${ALLOWED_SERVER_IP}|g" /etc/nginx/includes/rules_fastcgi_cache.conf

    local ALLOWED_SERVER_IPV6
    ALLOWED_SERVER_IPV6=$(get_ipv6_private)

    if [[ -n "${ALLOWED_SERVER_IPV6}" ]]; then
        run sed -i "s|#allow\ SERVER_IPV6|allow\ ${ALLOWED_SERVER_IPV6}|g" /etc/nginx/includes/rules_fastcgi_cache.conf
        ALLOWED_SERVER_IP="${ALLOWED_SERVER_IP} ${ALLOWED_SERVER_IPV6}"
    fi

    run sed -i "s|allow_SERVER_IP|${ALLOWED_SERVER_IP}|g" /etc/nginx/includes/rules_fastcgi_cache.conf
    run sed -i "s|#fastcgi_cache_purge\ PURGE|fastcgi_cache_purge\ PURGE|g" /etc/nginx/includes/rules_fastcgi_cache.conf
}

##
# Generate DH parameters for SSL
##
function generate_dh_params() {
    local DH_LENGTH=${KEY_HASH_LENGTH:-2048}

    if [[ ! -f "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" ]]; then
        echo "Generating DH parameters (${DH_LENGTH} bits)..."

        [[ ! -d /etc/nginx/ssl ]] && mkdir -p /etc/nginx/ssl
        run openssl dhparam -out "/etc/nginx/ssl/dhparam-${DH_LENGTH}.pem" "${DH_LENGTH}"
    fi
}

##
# Configure Nginx systemd service
##
function configure_nginx_systemd() {
    local SOURCE_DIR="${1:-.}"

    echo "Configuring Nginx systemd service..."

    # Init script
    if [[ ! -f /etc/init.d/nginx ]]; then
        run cp "${SOURCE_DIR}/etc/init.d/nginx" /etc/init.d/
        run chmod ugo+x /etc/init.d/nginx
    fi

    # Systemd service file
    [[ ! -f /lib/systemd/system/nginx.service ]] && \
        run cp "${SOURCE_DIR}/etc/systemd/nginx.service" /lib/systemd/system/

    # Enable service
    [[ ! -f /etc/systemd/system/multi-user.target.wants/nginx.service ]] && \
        run ln -s /lib/systemd/system/nginx.service \
            /etc/systemd/system/multi-user.target.wants/nginx.service

    # Reload daemon
    run systemctl daemon-reload
    run systemctl unmask nginx.service
    run systemctl enable nginx.service
}

##
# Configure default vhost
##
function configure_default_vhost() {
    local SOURCE_DIR="${1:-.}"
    local HOSTNAME_CERT_PATH="${2:-}"

    echo "Configuring default virtual host..."

    # Backup existing default vhost
    [[ -f /etc/nginx/sites-available/default ]] && \
        run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default~

    # Copy appropriate default vhost (SSL or non-SSL)
    if [[ -n "${HOSTNAME_CERT_PATH}" && -f "${HOSTNAME_CERT_PATH}/fullchain.pem" ]]; then
        run cp -f "${SOURCE_DIR}/etc/nginx/sites-available/default-ssl" /etc/nginx/sites-available/default
        run sed -i "s|HOSTNAME_CERT_PATH|${HOSTNAME_CERT_PATH}|g" /etc/nginx/sites-available/default
    else
        run cp -f "${SOURCE_DIR}/etc/nginx/sites-available/default" /etc/nginx/sites-available/default
    fi

    # Enable default vhost
    [[ -f /etc/nginx/sites-enabled/default ]] && run unlink /etc/nginx/sites-enabled/default
    [[ -f /etc/nginx/sites-enabled/00-default ]] && run unlink /etc/nginx/sites-enabled/00-default
    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/00-default

    # Configure hostname
    local SERVER_IP
    SERVER_IP=$(get_ip)

    if [[ $(dig "${HOSTNAME}" +short 2>/dev/null) == "${SERVER_IP}" ]]; then
        run sed -i "s/localhost.localdomain/${HOSTNAME}/g" /etc/nginx/sites-available/default
    else
        run sed -i "s/localhost.localdomain/${SERVER_IP}/g" /etc/nginx/sites-available/default
    fi
}

##
# Start or reload Nginx service
##
function start_nginx_service() {
    local SERVER_IP
    SERVER_IP=$(get_ip)

    echo "Starting Nginx HTTP server for ${HOSTNAME} (${SERVER_IP})..."

    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Nginx HTTP server installed in dry run mode."
        return 0
    fi

    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        # Nginx is already running, reload
        if nginx -t 2>/dev/null > /dev/null; then
            run systemctl reload nginx
            success "Nginx HTTP server restarted successfully."
        else
            error "Nginx configuration test failed:"
            nginx -t
            return 1
        fi
    elif [[ -n $(command -v nginx) ]]; then
        # Start Nginx
        if nginx -t 2>/dev/null > /dev/null; then
            run systemctl start nginx

            if [[ $(pgrep -c nginx) -gt 0 ]]; then
                success "Nginx HTTP server started successfully."
            else
                info "Something went wrong with Nginx installation."
                return 1
            fi
        else
            error "Nginx configuration test failed:"
            nginx -t
            return 1
        fi
    else
        error "Nginx binary not found."
        return 1
    fi
}

##
# Add Nginx logrotate configuration
##
function add_nginx_logrotate() {
    echo "Configuring Nginx logrotate..."

    [[ -f /etc/logrotate.d/nginx ]] && run rm -f /etc/logrotate.d/nginx

    cat > /etc/logrotate.d/nginx <<'EOL'
/var/log/nginx/*.log /home/*/logs/nginx/*_log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then
            run-parts /etc/logrotate.d/httpd-prerotate;
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOL

    run chmod 0644 /etc/logrotate.d/nginx
}

##
# Run all post-installation configuration
##
function configure_nginx_post_install() {
    local SOURCE_DIR="${1:-.}"
    local HOSTNAME_CERT_PATH="${2:-}"

    configure_nginx_files "${SOURCE_DIR}"
    configure_nginx_directories
    configure_nginx_performance
    generate_dh_params
    add_nginx_logrotate
    configure_nginx_systemd "${SOURCE_DIR}"
    configure_default_vhost "${SOURCE_DIR}" "${HOSTNAME_CERT_PATH}"
    start_nginx_service
}
