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
# Enable fail2ban for virtual host.
##
function enable_fail2ban() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling Fail2ban ${FRAMEWORK^} filter for ${DOMAIN}..."

    # Get web root path from vhost config, first.
    local WEBROOT \
        && WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

    if [[ ! -d ${WEBROOT} ]]; then
        read -rp "Enter real path to website root directory containing your access_log file: " -i "${WEBROOT}" -e WEBROOT
    fi

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/filter.d/${FRAMEWORK}.conf" ]]; then
        cat >"/etc/fail2ban/jail.d/${DOMAIN}.conf" <<EOL
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
# Enable ModSecurity v3 WAF for a virtual host.
##
function enable_modsec() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"
    local MODSEC_CONF="/etc/nginx/includes/modsec.conf"

    if [[ ! -f "${MODSEC_CONF}" ]]; then
        error "ModSecurity is not installed."
        echo "Reinstall with INSTALL_MODSEC=true, or run 'bash scripts/install_modsec.sh'."
        return 1
    fi

    if grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/includes/modsec\.conf;' "${VHOST_FILE}"; then
        info "ModSecurity is already enabled for ${DOMAIN}."
        return 0
    fi

    echo "Enabling ModSecurity for ${DOMAIN}..."
    sed_inplace "/^[[:space:]]*server_name[[:space:]]/a\\    include /etc/nginx/includes/modsec.conf;" "${VHOST_FILE}"

    if grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/includes/modsec\.conf;' "${VHOST_FILE}"; then
        success "ModSecurity has been enabled for ${DOMAIN}."
        reload_nginx
    else
        fail "Failed to enable ModSecurity for ${DOMAIN}."
    fi
}

##
# Disable ModSecurity v3 WAF for a virtual host.
##
function disable_modsec() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    local VHOST_FILE="/etc/nginx/sites-available/${DOMAIN}.conf"

    if ! grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/includes/modsec\.conf;' "${VHOST_FILE}"; then
        info "ModSecurity is not enabled for ${DOMAIN}."
        return 0
    fi

    echo "Disabling ModSecurity for ${DOMAIN}..."
    sed_inplace '\#^[[:space:]]*include[[:space:]]*/etc/nginx/includes/modsec\.conf;#d' "${VHOST_FILE}"

    if ! grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/includes/modsec\.conf;' "${VHOST_FILE}"; then
        success "ModSecurity has been disabled for ${DOMAIN}."
        reload_nginx
    else
        fail "Failed to disable ModSecurity for ${DOMAIN}."
    fi
}
