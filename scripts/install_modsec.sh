#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | ModSecurity v3 WAF Installer                                            |
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
# Install ModSecurity v3 WAF and OWASP CRS.
##
function init_modsec_install() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MODSEC}" == true ]]; then
            DO_INSTALL_MODSEC="y"
        else
            DO_INSTALL_MODSEC="n"
        fi
    else
        while [[ "${DO_INSTALL_MODSEC}" != "y" && "${DO_INSTALL_MODSEC}" != "Y" && \
            "${DO_INSTALL_MODSEC}" != "n" && "${DO_INSTALL_MODSEC}" != "N" ]]; do
            read -rp "Do you want to install ModSecurity v3 WAF? [y/n]: " -e DO_INSTALL_MODSEC
        done
    fi

    if [[ ${DO_INSTALL_MODSEC} == y* || ${DO_INSTALL_MODSEC} == Y* ]]; then
        echo "Installing ModSecurity v3 WAF..."

        # The nginx connector is shipped as a module package built against the
        # repository nginx ABI; source builds need to compile it themselves.
        if [[ "${NGINX_INSTALLER:-repo}" == "source" ]]; then
            warning "The ModSecurity nginx connector is only packaged for repository installs."
            warning "Set NGINX_INSTALLER=repo or build the connector manually; skipping ModSecurity."
            return 0
        fi

        # libmodsecurity3 provides the engine, libnginx-mod-http-modsecurity the
        # nginx connector (which also enables itself in modules-enabled), and
        # modsecurity-crs the OWASP Core Rule Set.
        run apt-get install -q -y libmodsecurity3 libnginx-mod-http-modsecurity modsecurity-crs

        if [[ "${DRYRUN}" != true ]]; then
            local CRS_DIR="/etc/modsecurity/crs"
            local MODSEC_LOG_DIR="/var/log/modsecurity"

            run mkdir -p /etc/modsecurity "${MODSEC_LOG_DIR}"

            # The package ships the setup template only; copy it once so
            # administrators can tune it without editing a conffile.
            if [[ ! -f "${CRS_DIR}/crs-setup.conf" && -f "${CRS_DIR}/crs-setup.conf.example" ]]; then
                run cp -f "${CRS_DIR}/crs-setup.conf.example" "${CRS_DIR}/crs-setup.conf"
            fi

            # Tuning values (overridable from .env).
            local MODSEC_ENGINE="${MODSEC_ENGINE:-DetectionOnly}"
            local MODSEC_PARANOIA_LEVEL="${MODSEC_PARANOIA_LEVEL:-1}"
            local MODSEC_INBOUND_THRESHOLD="${MODSEC_INBOUND_THRESHOLD:-5}"
            local MODSEC_OUTBOUND_THRESHOLD="${MODSEC_OUTBOUND_THRESHOLD:-4}"
            local MODSEC_BODY_LIMIT="${MODSEC_BODY_LIMIT:-20971520}"

            [[ "${MODSEC_ENGINE}" =~ ^(On|Off|DetectionOnly)$ ]] || MODSEC_ENGINE="DetectionOnly"
            [[ "${MODSEC_PARANOIA_LEVEL}" =~ ^[1-4]$ ]] || MODSEC_PARANOIA_LEVEL=1
            [[ "${MODSEC_INBOUND_THRESHOLD}" =~ ^[0-9]+$ ]] || MODSEC_INBOUND_THRESHOLD=5
            [[ "${MODSEC_OUTBOUND_THRESHOLD}" =~ ^[0-9]+$ ]] || MODSEC_OUTBOUND_THRESHOLD=4
            [[ "${MODSEC_BODY_LIMIT}" =~ ^[0-9]+$ ]] || MODSEC_BODY_LIMIT=20971520

            # Write the LEMPer CRS tuning file.
            cat > /etc/modsecurity/lemper-tuning.conf <<EOL
# LEMPer ModSecurity tuning
# Adjust with: lemper-cli modsec tune [--auto] --apply

SecRuleEngine ${MODSEC_ENGINE}

SecAction "id:1000001,phase:1,nolog,pass,t:none,setvar:tx.paranoia_level=${MODSEC_PARANOIA_LEVEL}"
SecAction "id:1000002,phase:1,nolog,pass,t:none,setvar:tx.executing_paranoia_level=${MODSEC_PARANOIA_LEVEL}"
SecAction "id:1000003,phase:1,nolog,pass,t:none,setvar:tx.inbound_anomaly_score_threshold=${MODSEC_INBOUND_THRESHOLD}"
SecAction "id:1000004,phase:1,nolog,pass,t:none,setvar:tx.outbound_anomaly_score_threshold=${MODSEC_OUTBOUND_THRESHOLD}"
EOL

            run chmod 0644 /etc/modsecurity/lemper-tuning.conf

            # Write main ModSecurity configuration.
            cat > /etc/modsecurity/modsecurity.conf <<EOL
# ModSecurity v3 Main Configuration
# Generated by LEMPer Stack

# CRS setup, then LEMPer tuning overrides, then the rule set itself.
Include /etc/modsecurity/crs/crs-setup.conf
Include /etc/modsecurity/lemper-tuning.conf
Include /etc/modsecurity/crs/rules/*.conf

# Unicode mapping used by CRS transformations.
SecUnicodeMapFile /etc/modsecurity/unicode.mapping 20127

# Request body access for POST inspection.
SecRequestBodyAccess On

# Response body access for sensitive data leakage checks.
SecResponseBodyAccess On

# Maximum request body size (matches nginx client_max_body_size).
SecRequestBodyLimit ${MODSEC_BODY_LIMIT}

# Audit logging. The log file must be writable by the nginx worker user.
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!03|04))"
SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecAuditLog ${MODSEC_LOG_DIR}/modsec_audit.log
EOL

            run touch "${MODSEC_LOG_DIR}/modsec_audit.log"
            run chown www-data:adm "${MODSEC_LOG_DIR}/modsec_audit.log"
            run chmod 0640 "${MODSEC_LOG_DIR}/modsec_audit.log"

            # Create the per-vhost nginx include.
            run mkdir -p /etc/nginx/includes

            cat > /etc/nginx/includes/modsec.conf <<'EOL'
## ModSecurity v3 WAF include.
# Include in server{} block to enable WAF for a vhost.

modsecurity on;
modsecurity_rules_file /etc/modsecurity/modsecurity.conf;
EOL

            # The package normally enables the connector itself; restore the
            # symlink if it was removed.
            local MODSEC_MODULE_AVAILABLE="/usr/share/nginx/modules-available/mod-http-modsecurity.conf"
            local MODSEC_MODULE_LINK="/etc/nginx/modules-enabled/50-mod-http-modsecurity.conf"

            if [[ -f "${MODSEC_MODULE_AVAILABLE}" && ! -e "${MODSEC_MODULE_LINK}" ]]; then
                run ln -sf "${MODSEC_MODULE_AVAILABLE}" "${MODSEC_MODULE_LINK}"
            fi

            if command -v nginx >/dev/null 2>&1; then
                if ! nginx -t; then
                    warning "Nginx configuration test failed after installing ModSecurity."
                fi
            fi

            success "ModSecurity v3 WAF installed with OWASP CRS."
            info "ModSecurity is in ${MODSEC_ENGINE} mode with CRS paranoia level ${MODSEC_PARANOIA_LEVEL}."
            info "To change modes or tune thresholds, run:"
            info "  lemper-cli modsec tune --engine On --paranoia 1 --apply"
        else
            info "ModSecurity installed in dry run mode."
        fi
    else
        info "ModSecurity installation skipped."
    fi
}

echo "[ModSecurity v3 Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if dpkg-query -W -f='${Status}' libnginx-mod-http-modsecurity 2>/dev/null | grep -q 'install ok installed' && \
    [[ -f /etc/modsecurity/modsecurity.conf && "${FORCE_INSTALL}" != true ]]; then
    info "ModSecurity already exists, installation skipped."
else
    init_modsec_install "$@"
fi
