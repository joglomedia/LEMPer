#!/usr/bin/env bash

# Install CrowdSec HIPS
# Min. Requirement  : GNU/Linux Ubuntu/Debian
# Since Version     : 3.3.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Install CrowdSec.
##
function init_crowdsec_install() {
    local SELECTED_INSTALLER=""

    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_CROWDSEC}" == true ]]; then
            DO_INSTALL_CROWDSEC="y"
            SELECTED_INSTALLER=${CROWDSEC_INSTALLER:-"repo"}
        else
            DO_INSTALL_CROWDSEC="n"
        fi
    else
        while [[ "${DO_INSTALL_CROWDSEC}" != "y" && "${DO_INSTALL_CROWDSEC}" != "Y" && \
            "${DO_INSTALL_CROWDSEC}" != "n" && "${DO_INSTALL_CROWDSEC}" != "N" ]]; do
            read -rp "Do you want to install CrowdSec HIPS (Host Intrusion Prevention System)? [y/n]: " -e DO_INSTALL_CROWDSEC
        done
    fi

    if [[ ${DO_INSTALL_CROWDSEC} == y* || ${DO_INSTALL_CROWDSEC} == Y* ]]; then
        echo "Available CrowdSec installation method:"
        echo "  1). Install from Repository (repo)"
        echo "  2). Compile from Source (source)"
        echo "-------------------------------------"

        while [[ "${SELECTED_INSTALLER}" != "1" && "${SELECTED_INSTALLER}" != "2" && \
            "${SELECTED_INSTALLER}" != "repo" && "${SELECTED_INSTALLER}" != "source" ]]; do
            read -rp "Select an option [1-2]: " -i "${CROWDSEC_INSTALLER}" -e SELECTED_INSTALLER
        done

        case "${SELECTED_INSTALLER}" in
            1 | "repo")
                echo "Installing CrowdSec from repository..."

                # Add CrowdSec apt repository.
                run curl -sSL https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash

                # Install CrowdSec.
                run apt-get install -q -y crowdsec
            ;;
            2 | "source")
                echo "Installing CrowdSec from source..."

                CROWDSEC_VERSION=${CROWDSEC_VERSION:-"1.6.10"}

                if [[ "${CROWDSEC_VERSION}" == "latest" ]]; then
                    CROWDSEC_VERSION=$(curl -sSL https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest | grep -E '^  "tag_name":' | cut -d'"' -f4 | sed 's/^v//')
                fi

                local CURRENT_DIR && \
                CURRENT_DIR=$(pwd)
                run cd "${BUILD_DIR}" || return 1

                # Install from source.
                # https://github.com/crowdsecurity/crowdsec
                local crowdsec_download_link="https://github.com/crowdsecurity/crowdsec/releases/download/v${CROWDSEC_VERSION}/crowdsec_${CROWDSEC_VERSION}_linux_amd64.tar.gz"

                if curl -sLI "${crowdsec_download_link}" | grep -q "HTTP/[.12]* [2].."; then
                    run curl -sSL -o crowdsec.tar.gz "${crowdsec_download_link}" && \
                    run tar -zxf crowdsec.tar.gz && \
                    run cd crowdsec-*/ || return

                    # Build from source.
                    run apt-get install -q -y golang-go libsqlite3-dev
                    run make release
                    run ./crowdsec install --exclude ./cmd/crowdsec-cli
                    run ln -sf "${BUILD_DIR}/crowdsec-*/bin/crowdsec" /usr/local/bin/crowdsec
                    run ln -sf "${BUILD_DIR}/crowdsec-*/bin/crowdsec-cli" /usr/local/bin/crowdsec-cli
                    run ln -sf "${BUILD_DIR}/crowdsec-*/bin/cscli" /usr/local/bin/cscli
                    run cp configs/crowdsec.service /etc/systemd/system/crowdsec.service
                    run systemctl daemon-reload
                fi

                run cd "${CURRENT_DIR}" || return 1
            ;;
        esac

        # Configure CrowdSec.
        echo "Configuring CrowdSec HIPS..."

        if [[ "${DRYRUN}" != true ]]; then
            # Install CrowdSec bouncers (nginx + firewall).
            run apt-get install -q -y crowdsec-bouncer crowdsec-bouncer-nginx

            # Configure CrowdSec collections.
            # https://crowdsecurity.net/
            echo "Installing CrowdSec security collections..."

            # Install SSH brute-force detection.
            run cscli hub update
            run cscli hub install crowdsecurity/ssh-buster
            run cscli hub install crowdsecurity/nginx
            run cscli hub install crowdsecurity/whitelist

            # Install PHP web app security collections (WordPress priority).
            install_crowdsec_webapp_support

            # Enable nginx bouncer in nginx config.
            if [[ -f /etc/nginx/nginx.conf ]]; then
                # Add CrowdSec bouncer include to nginx http block.
                if ! grep -q 'crowdsec-bouncer' /etc/nginx/nginx.conf; then
                    run sed -i '/http {/a \    include /etc/crowdsec/crowdsec-nginx.conf;' /etc/nginx/nginx.conf
                fi
            fi

            # Create CrowdSec nginx include for PHP web app WAF rules.
            configure_crowdsec_webapp_rules

            # Restart nginx to apply CrowdSec bouncer.
            if [[ -f /lib/systemd/system/nginx.service ]]; then
                run systemctl restart nginx
            fi

            # Enable and start CrowdSec daemon.
            echo "Starting CrowdSec daemon..."
            run systemctl enable crowdsec
            run systemctl restart crowdsec

            if [[ $(pgrep -c crowdsec) -gt 0 ]]; then
                success "CrowdSec HIPS server started successfully."
                info "CrowdSec is now actively monitoring your server."
                echo "    Manage with: cscli"
                echo "    Dashboard:   crowdsec-cli"
            else
                info "Something went wrong with CrowdSec installation."
            fi
        else
            info "CrowdSec installed in dry run mode."
        fi
    else
        info "CrowdSec installation skipped."
    fi
}

##
# Install CrowdSec collections for PHP web applications.
# Priority: WordPress (most common LEMPer use case).
##
function install_crowdsec_webapp_support() {
    local INSTALL_CROWDSEC_WORDPRESS="${INSTALL_CROWDSEC_WORDPRESS:-true}"
    local INSTALL_CROWDSEC_PHPAPPS="${INSTALL_CROWDSEC_PHPAPPS:-false}"

    echo "Installing PHP web application security collections..."

    # OWASP baseline + HTTP observability for all web apps.
    run cscli hub install crowdsecurity/http-baseline
    run cscli hub install crowdsecurity/http-requests-oc

    # WordPress security (highest priority).
    if [[ "${INSTALL_CROWDSEC_WORDPRESS}" == true ]]; then
        echo "Installing WordPress security scenarios..."
        run cscli hub install crowdsecurity/wordpress
        run cscli hub install crowdsecurity/wordpress-hardcoded-password
        run cscli hub install crowdsecurity/wordpress-phpunit
    fi

    # Other popular PHP web apps.
    if [[ "${INSTALL_CROWDSEC_PHPAPPS}" == true ]]; then
        echo "Installing additional PHP web app scenarios..."
        # Joomla
        run cscli hub install crowdsecurity/joomla 2>/dev/null || true
        # Drupal
        run cscli hub install crowdsecurity/drupal 2>/dev/null || true
        # Magento
        run cscli hub install crowdsecurity/magento 2>/dev/null || true
        # Generic PHP
        run cscli hub install crowdsecurity/php 2>/dev/null || true
    fi

    # Custom WordPress scenarios (XML-RPC abuse, login brute-force).
    # These are created as local CrowdSec scenarios.
    # Ensure the crowdsec config directory exists.
    run mkdir -p /etc/crowdsec

    # WordPress XML-RPC flood protection.
    cat > /etc/crowdsec/wordpress-xmlrpc.yaml <<'EOF'
# LEMPer Stack — WordPress XML-RPC abuse detection
# Triggers on high-frequency XML-RPC requests (pingback, /xmlrpc.php)
name: wordpress-xmlrpc-abuse
description: "Detects WordPress XML-RPC abuse and pingback flood attacks"
type: http_wp
filter: |
  (evt.is_tx_request and evt.request.uri contains "/xmlrpc.php" and evt.request.method == "POST")
  or
  (evt.is_tx_request and evt.request.uri contains "/wp-admin/admin-ajax.php" and evt.request.method == "POST")
groupby: 1m
capacity: 30
leakfactor: 0
labels:
  service: http
  category: attack
  type: http_wp
EOF

    # WordPress login brute-force on wp-login.php.
    cat > /etc/crowdsec/wordpress-bruteforce.yaml <<'EOF'
# LEMPer Stack — WordPress login brute-force detection
# Triggers on repeated 403/401 responses to /wp-login.php
name: wordpress-bruteforce
description: "Detects WordPress wp-login.php brute-force attacks"
type: http_wp
filter: |
  evt.is_tx_request and
  evt.request.uri contains "/wp-login.php" and
  evt.request.method == "POST" and
  (evt.response.status == 403 or evt.response.status == 401)
groupby: 5m
capacity: 5
leakfactor: 0
labels:
  service: http
  category: attack
  type: http_wp
EOF

    success "WordPress security scenarios installed."
    info "  - crowdsecurity/wordpress (official collection)"
    info "  - Custom XML-RPC flood detection (local scenario)"
    info "  - Custom wp-login brute-force detection (local scenario)"
}

##
# Configure nginx to send PHP web app logs to CrowdSec and create
# vhost-level include for per-site CrowdSec WAF rules.
##
function configure_crowdsec_webapp_rules() {
    local config_dir="/etc/lemper/waf"
    run mkdir -p "${config_dir}"

    # Create CrowdSec nginx include for PHP web app WAF.
    cat > "${config_dir}/crowdsec-webapp.conf" <<'EOF'
## CrowdSec WAF rules for PHP web applications.
# Include in server{} block via: include /etc/lemper/waf/crowdsec-webapp.conf;

# CrowdSec bouncer (blocks malicious IPs at nginx level).
include /etc/crowdsec/crowdsec-nginx.conf;

# WordPress-specific access control.
# Block direct access to XML-RPC from non-whitelisted IPs.
location = /xmlrpc.php {
    # CrowdSec bouncer will block abusive IPs.
    # For rate limiting without CrowdSec, uncomment:
    #limit_req zone=xmlrpc burst=5 nodelay;
    try_files $uri =404;
}

# Block access to sensitive WordPress files.
location ~* /wp-content/plugins/.*\.php$ {
    # Allow CrowdSec to inspect, but deny direct access to plugin PHP files.
    try_files $uri =404;
}

location ~* /wp-includes/.*.php$ {
    # wp-includes should not be executed directly.
    return 444;
}

# Block access to wp-config.php and .htaccess.
location ~* /(?:wp-config\.php|\.htaccess) {
    return 444;
}
EOF

    # Update nginx.conf to include the webapp WAF config in the http block.
    if [[ -f /etc/nginx/nginx.conf ]] && ! grep -q 'crowdsec-webapp' /etc/nginx/nginx.conf; then
        run sed -i '/http {/a \    include /etc/lemper/waf/crowdsec-webapp.conf;' /etc/nginx/nginx.conf
    fi

    success "CrowdSec WAF nginx rules configured for PHP web apps."
}

echo "[CrowdSec Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v crowdsec) && "${FORCE_INSTALL}" != true ]]; then
    info "CrowdSec already exists, installation skipped."
else
    init_crowdsec_install "$@"
fi
