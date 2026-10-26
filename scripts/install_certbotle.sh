#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Certbot Let's Encrypt Installer                                         |
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

if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
    cd "${BASE_DIR}" || { echo "Cannot enter ${BASE_DIR}."; exit 1; }
    # shellcheck source=scripts/utils.sh
    . "${BASE_DIR}/scripts/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Install Certbot Let's Encrypt.
##
function init_certbotle_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_CERTBOT}" == true ]]; then
            DO_INSTALL_CERTBOT="y"
        else
            DO_INSTALL_CERTBOT="n"
        fi
    else
        while [[ "${DO_INSTALL_CERTBOT}" != "y" && "${DO_INSTALL_CERTBOT}" != "n" ]]; do
            read -rp "Do you want to install Certbot Let's Encrypt client? [y/n]: " -i y -e DO_INSTALL_CERTBOT
        done
    fi

    if [[ ${DO_INSTALL_CERTBOT} == y* || ${DO_INSTALL_CERTBOT} == Y* ]]; then
        echo "Installing Certbot Let's Encrypt client..."

        DISTRIB_NAME=${DISTRIB_NAME:-$(get_distrib_name)}
        RELEASE_NAME=${RELEASE_NAME:-$(get_release_name)}

        case "${DISTRIB_NAME}" in
            debian)
                case "${RELEASE_NAME}" in
                    jessie)
                        run apt-get install -q -y certbot -t jessie-backports
                    ;;
                    stretch | buster | bullseye | bookworm)
                        install_certbot_pip
                    ;;
                    *)
                        error "Unable to add Certbot, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                        echo "Sorry your system is not supported yet, installing from source may fix the issue."
                        exit 1
                    ;;
                esac
            ;;
            ubuntu)
                install_certbot_pip
            ;;
            *)
                error "Unable to add Certbot, unsupported distribution release: ${DISTRIB_NAME^} ${RELEASE_NAME^}."
                echo "Sorry your system is not supported yet, installing from source may fix the issue."
                exit 1
            ;;
        esac

        if [[ "${DRYRUN}" != true ]]; then
            if certbot --version | grep -q "certbot"; then
                # Register a new Letsencrypt's account.
                local LE_EMAIL=${LEMPER_ADMIN_EMAIL:-"cert@lemper.cloud"}

                if [[ -d /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/directory ]]; then
                    run certbot update_account --email "${LE_EMAIL}" --no-eff-email --agree-tos
                else
                    run certbot register --email "${LE_EMAIL}" --no-eff-email --agree-tos
                fi

                add_certbot_cron
                add_certbot_logrotate
                add_certbot_deploy_hook
                add_dns01_credentials

                # Request wildcard certificate if enabled.
                if [[ "${ACME_WILDCARD}" == true ]]; then
                    request_wildcard_certificate
                fi

                success "Certbot successfully installed."
            else
                info "Something went wrong with Certbot installation."
            fi
        else
            info "Certbot installed in dry run mode."
        fi
    fi
}

##
# Install Python Venv for Certbot.
##
function install_certbot_pip() {
    run python -m venv /opt/certbot/ && \
    run /opt/certbot/bin/pip install --upgrade pip setuptools cffi && \
    run /opt/certbot/bin/pip install --upgrade certbot certbot-nginx && \
    run ln -sf /opt/certbot/bin/certbot /usr/bin/certbot

    # Install ACME v2 DNS-01 provider plugin for wildcard certificates.
    if [[ "${ACME_WILDCARD}" == true && -n "${ACME_DNS_PROVIDER}" ]]; then
        local dns_plugin="certbot-dns-${ACME_DNS_PROVIDER}"
        echo "Installing DNS-01 provider plugin: ${dns_plugin}"
        run /opt/certbot/bin/pip install --upgrade "${dns_plugin}"
    fi
}

##
# Flush the systemd-resolved cache when the resolver is in use.
##
function flush_dns_cache() {
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if command -v resolvectl >/dev/null 2>&1; then
            run resolvectl flush-caches
        elif command -v systemd-resolve >/dev/null 2>&1; then
            run systemd-resolve --flush-caches
        fi
    fi
}

##
# Install a Certbot deploy hook that reloads Nginx and flushes DNS caches.
##
function add_certbot_deploy_hook() {
    local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
    local hook_file="${hook_dir}/lemper-nginx.sh"

    run mkdir -p "${hook_dir}"

    if [[ "${DRYRUN}" != true ]]; then
        cat > "${hook_file}" <<'EOL'
#!/usr/bin/env bash
# Reload Nginx and flush the systemd-resolved cache after ACME renewal.
# Generated by LEMPer Stack.

systemctl reload nginx 2>/dev/null || true

if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches 2>/dev/null || true
    elif command -v systemd-resolve >/dev/null 2>&1; then
        systemd-resolve --flush-caches 2>/dev/null || true
    fi
fi
EOL
        run chmod 0755 "${hook_file}"
        success "Certbot deploy hook installed at ${hook_file}"
    fi
}

##
# Configure ACME v2 DNS-01 DNS provider credentials.
##
function add_dns01_credentials() {
    if [[ "${ACME_WILDCARD}" != true ]]; then
        return 0
    fi

    if [[ -z "${ACME_DNS_PROVIDER}" ]]; then
        info "ACME_DNS_PROVIDER is not set, skipping DNS-01 configuration."
        return 0
    fi

    local creds_dir="/etc/lemper/acme"
    run mkdir -p "${creds_dir}"
    local creds_file="${creds_dir}/dns-${ACME_DNS_PROVIDER}.ini"

    # Write DNS provider credentials.
    cat > "${creds_file}" <<EOL
dns_${ACME_DNS_PROVIDER}_api_token = ${ACME_DNS_API_TOKEN}
EOL

    run chmod 0600 "${creds_file}"
    success "DNS-01 credentials configured at ${creds_file}"
}

##
# Request a wildcard certificate via ACME v2 DNS-01 challenge.
##
function request_wildcard_certificate() {
    if [[ "${ACME_WILDCARD}" != true ]]; then
        return 0
    fi

    if [[ -z "${LEMPER_DOMAIN}" ]]; then
        info "LEMPER_DOMAIN is not set, skipping wildcard certificate request."
        return 0
    fi

    local domain="${LEMPER_DOMAIN}"
    local creds_dir="/etc/lemper/acme"
    local creds_file="${creds_dir}/dns-${ACME_DNS_PROVIDER}.ini"

    echo "Requesting wildcard certificate for *.${domain} via DNS-01..."

    # Drop any cached negative lookups before validating the challenge.
    flush_dns_cache

    if [[ -f "${creds_file}" ]]; then
        run certbot certonly \
            --dns-"${ACME_DNS_PROVIDER}" \
            --dns-"${ACME_DNS_PROVIDER}"-credentials "${creds_file}" \
            --dns-"${ACME_DNS_PROVIDER}"-propagation-seconds "${ACME_DNS_PROPAGATION_WAIT:-30}" \
            --nginx \
            -d "*.${domain}" \
            -d "${domain}" \
            --email "${LEMPER_ADMIN_EMAIL:-cert@lemper.cloud}" \
            --agree-tos \
            --no-eff-email \
            --non-interactive \
            --redirect

        # Refresh cached DNS records after the challenge completes.
        flush_dns_cache
    else
        fail "DNS-01 credentials file not found: ${creds_file}"
    fi
}

##
# Add Certbot auto renew command to cronjob.
##
function add_certbot_cron() {
    export EDITOR=nano
    CRONCMD='0 */6 * * * /usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"'
    touch lemper.cron
    crontab -u root lemper.cron
    crontab -l > lemper.cron

    if ! grep -qwE "/usr/bin/certbot\ renew" lemper.cron; then
        cat >> lemper.cron <<EOL
# LEMPer Cronjob
# Certbot Auto-renew Let's Encrypt certificates.
SHELL=/bin/bash
PATH=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root

${CRONCMD}
EOL

        crontab lemper.cron
        rm -f lemper.cron
    else
        info "Certbot auto-renew command added to cronjob in dry run mode."
    fi
}

##
# Add logrotate for Certbot.
##
function add_certbot_logrotate() {
    if [[ -f /etc/logrotate.d/certbot ]]; then
        run rm -f /etc/logrotate.d/certbot
    fi

    run touch "/etc/logrotate.d/certbot"
    cat >> "/etc/logrotate.d/certbot" <<EOL
/var/log/letsencrypt/*.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
}
EOL

    run chmod 0644 "/etc/logrotate.d/certbot"
}

echo "[Certbot Let's Encrypt Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v certbot) && "${FORCE_INSTALL}" != true ]]; then
    info "Certbot Let's Encrypt already exists, installation skipped."
else
    init_certbotle_install "$@"
fi
