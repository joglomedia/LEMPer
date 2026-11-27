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
    local DOMAIN="${1:-}" framework
    verify_vhost "${DOMAIN}" || return 1
    framework=$(awk '
        $1 == "include" && $2 ~ /^\/etc\/nginx\/vhost\/site_[a-z0-9_-]+\.conf;$/ {
            sub(/^.*\/site_/, "", $2); sub(/\.conf;$/, "", $2); print $2; exit
        }' "/etc/nginx/sites-available/${DOMAIN}.conf") || return 1
    lemper_nginx_fail2ban_enable "$DOMAIN" "$framework" 7d
}

function lemper_nginx_fail2ban_enable() {
    local domain="$1" filter="$2" bantime="$3"
    local logs=/var/log/nginx jails=/etc/fail2ban/jail.d owner mode stage previous=false log jail
    is_valid_domain "$domain" || return 1
    case "$filter" in wordpress-*) filter=wordpress ;; esac
    [[ "$filter" =~ ^[a-z0-9_-]+$ && "$bantime" =~ ^[0-9]+d$ ]] || {
        error "This site has no supported Fail2ban filter."
        return 1
    }
    [[ "${DRYRUN:-false}" != true ]] || { info "Would enable Fail2ban for $domain."; return 0; }
    command -v fail2ban-client >/dev/null && [[ -f "/etc/fail2ban/filter.d/$filter.conf" ]] || {
        error "Install Fail2ban and the $filter filter before enabling the jail."
        return 1
    }
    log="$logs/$domain.access.log"
    jail="$jails/$domain.conf"

    if ! lemper_directory_trusted "$logs" || [[ ! -f "$log" || -L "$log" ]] ||
        ! read -r owner mode < <(stat -c '%U %a' -- "$log") ||
        [[ "$owner" != root && "$owner" != www-data ]] || (( (8#$mode & 0022) != 0 )) ||
        ! awk -v wanted="$log" '
            $1 == "access_log" { sub(/;$/, "", $2); if ($2 == wanted) found = 1 }
            END { exit !found }' "/etc/nginx/sites-available/$domain.conf"; then
        error "Activate the site's managed Nginx access log before enabling Fail2ban."
        return 1
    fi
    lemper_directory_trusted "$jails" && [[ -d "$jails" && ! -L "$jail" ]] || return 1
    stage=$(mktemp -d "$jails/.lemper-jail.XXXXXXXX") || return 1
    if [[ -e "$jail" ]]; then
        if [[ ! -f "$jail" ]] || ! cp -p -- "$jail" "$stage/previous"; then
            rm -rf -- "$stage"
            return 1
        fi
        previous=true
    fi
    if ! cat >"$stage/new" <<EOL
[$domain]
enabled = true
port = http,https
filter = $filter
action = iptables-multiport[name=webapps, port="http,https", protocol=tcp]
logpath = $log
bantime = $bantime
findtime = 5m
maxretry = 3
EOL
    then
        rm -rf -- "$stage"
        return 1
    fi
    if ! chmod 0644 "$stage/new" || ! mv -T -- "$stage/new" "$jail"; then
        rm -rf -- "$stage"
        return 1
    fi
    if ! lemper_exec service fail2ban reload; then
        if [[ "$previous" == true ]]; then mv -T -- "$stage/previous" "$jail" || return 1
        else rm -f -- "$jail" || return 1; fi
        rm -rf -- "$stage"
        error "Could not activate Fail2ban for $domain. The previous jail configuration was restored."
        return 1
    fi
    rm -rf -- "$stage"
    success "Fail2ban ${filter^} filter for $domain enabled."
}

##
# Disable fail2ban for virtual host.
##
function disable_fail2ban() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}" || return 1

    echo "Disabling the Fail2ban jail for ${DOMAIN}..."

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/jail.d/${DOMAIN}.conf" ]]; then
        run rm -f "/etc/fail2ban/jail.d/${DOMAIN}.conf"
        run service fail2ban reload || return 1
        success "Fail2ban jail for ${DOMAIN} disabled."
    else
        info "Fail2ban or the site's jail is not installed."
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
