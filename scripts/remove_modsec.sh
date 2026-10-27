#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | ModSecurity v3 WAF Uninstaller                                          |
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

    # Make sure only root can run this uninstaller script.
    requires_root "$@"

    # Make sure only supported distribution can run this uninstaller script.
    preflight_system_check
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

        # Disable the nginx connector (package installs the 50- prefixed link;
        # keep the unprefixed name for older installs).
        local MODSEC_MODULE_LINK
        for MODSEC_MODULE_LINK in \
            /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf \
            /etc/nginx/modules-enabled/mod-http-modsecurity.conf; do
            if [[ -e "${MODSEC_MODULE_LINK}" || -L "${MODSEC_MODULE_LINK}" ]]; then
                echo "Disabling ModSecurity nginx module..."
                run rm -f "${MODSEC_MODULE_LINK}"
            fi
        done

        # Remove the include from vhosts. sites-enabled entries are symlinks,
        # so edit the real files in sites-available.
        if [[ -d /etc/nginx/sites-available ]]; then
            local VHOST
            for VHOST in /etc/nginx/sites-available/*.conf; do
                [[ -f "${VHOST}" ]] || continue
                if grep -qF 'include /etc/nginx/includes/modsec.conf;' "${VHOST}"; then
                    sed_inplace '\#^[[:space:]]*include[[:space:]]*/etc/nginx/includes/modsec\.conf;#d' "${VHOST}"
                fi
            done
        fi

        # Remove the ModSecurity nginx include and generated configuration.
        [[ -f /etc/nginx/includes/modsec.conf ]] && run rm -f /etc/nginx/includes/modsec.conf
        [[ -f /etc/modsecurity/lemper-tuning.conf ]] && run rm -f /etc/modsecurity/lemper-tuning.conf
        [[ -f /etc/modsecurity/modsecurity.conf ]] && run rm -f /etc/modsecurity/modsecurity.conf

        # Remove ModSecurity packages. The CRS and engine files are owned by
        # these packages, so purge them instead of deleting directories.
        if command -v apt-get >/dev/null 2>&1; then
            echo "Removing ModSecurity packages..."
            run apt-get purge -q -y libnginx-mod-http-modsecurity libmodsecurity3 modsecurity-crs
            run apt-get autoremove -q -y
        fi

        # Reload nginx (if still running).
        if command -v nginx >/dev/null 2>&1; then
            nginx -t >/dev/null 2>&1 || warning "Nginx configuration test failed after removing ModSecurity."
        fi
        if [[ -f /lib/systemd/system/nginx.service ]] && command -v systemctl >/dev/null 2>&1; then
            run systemctl reload nginx
        fi

        success "ModSecurity v3 WAF has been removed."
    else
        info "ModSecurity removal skipped."
    fi
}

echo "[ModSecurity v3 Removal]"

if ! dpkg-query -W -f='${Status}' libnginx-mod-http-modsecurity 2>/dev/null | grep -q 'install ok installed' && \
    [[ ! -f /etc/modsecurity/modsecurity.conf && "${FORCE_REMOVE}" != true ]]; then
    info "ModSecurity is not installed, nothing to remove."
else
    init_modsec_remove "$@"
fi
