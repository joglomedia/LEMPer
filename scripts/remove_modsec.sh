#!/usr/bin/env bash

# Remove ModSecurity v3 WAF
# Since Version     : 3.4.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"
fi

##
# Remove ModSecurity v3 WAF and OWASP CRS.
##
function init_modsec_remove() {
    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${INSTALL_MODSEC}" == true ]]; then
            DO_REMOVE_MODSEC="y"
        else
            DO_REMOVE_MODSEC="n"
        fi
    else
        while [[ "${DO_REMOVE_MODSEC}" != "y" && "${DO_REMOVE_MODSEC}" != "Y" && \
            "${DO_REMOVE_MODSEC}" != "n" && "${DO_REMOVE_MODSEC}" != "N" ]]; do
            read -rp "Do you want to remove ModSecurity v3 WAF? [y/n]: " -e DO_REMOVE_MODSEC
        done
    fi

    if [[ ${DO_REMOVE_MODSEC} == y* || ${DO_REMOVE_MODSEC} == Y* ]]; then
        echo "[Removing ModSecurity v3 WAF]"

        # Disable ModSecurity nginx module.
        if [[ -f /etc/nginx/modules-enabled/mod-http-modsecurity.conf ]]; then
            echo "Disabling ModSecurity nginx module..."
            run rm -f /etc/nginx/modules-enabled/mod-http-modsecurity.conf
        fi

        # Remove ModSecurity configuration.
        echo "Removing ModSecurity configuration..."
        [[ -d /etc/modsecurity ]] && run rm -rf /etc/modsecurity

        # Remove OWASP CRS (only if installed by us).
        if [[ -d /usr/share/modsecurity-crs ]]; then
            echo "Removing OWASP Core Rule Set..."
            run rm -rf /usr/share/modsecurity-crs
        fi

        # Remove ModSecurity nginx include.
        if [[ -f "${BASE_DIR}/etc/nginx/includes/modsec.conf" ]]; then
            run rm -f "${BASE_DIR}/etc/nginx/includes/modsec.conf"
        fi

        # Remove nginx include from vhosts that reference it.
        if [[ -d /etc/nginx/sites-enabled ]]; then
            run sed -i '/modsecurity_rules_file/d' /etc/nginx/sites-enabled/* 2>/dev/null || true
        fi

        # Remove ModSecurity packages.
        if command -v apt-get; then
            echo "Removing ModSecurity packages..."
            run apt-get purge -q -y libmodsecurity3 nginx-mod-http-modsecurity 2>/dev/null || true
            run apt-get autoremove -q -y 2>/dev/null || true
        fi

        # Reload nginx (if still running).
        if [[ -f /lib/systemd/system/nginx.service ]] && command -v systemctl; then
            run systemctl reload nginx 2>/dev/null || true
        fi

        success "ModSecurity v3 WAF has been removed."
    else
        info "ModSecurity removal skipped."
    fi
}

echo "[ModSecurity v3 Removal]"

if [[ -z $(command -v modsecurity) && "${FORCE_REMOVE}" != true ]]; then
    info "ModSecurity is not installed, nothing to remove."
else
    init_modsec_remove "$@"
fi
