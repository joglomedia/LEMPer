#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | CrowdSec HIPS Uninstaller                                               |
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
# Remove CrowdSec.
##
function init_crowdsec_remove() {
    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${INSTALL_CROWDSEC}" == true ]]; then
            DO_REMOVE_CROWDSEC="y"
        else
            DO_REMOVE_CROWDSEC="n"
        fi
    else
        while [[ "${DO_REMOVE_CROWDSEC}" != "y" && "${DO_REMOVE_CROWDSEC}" != "Y" && \
            "${DO_REMOVE_CROWDSEC}" != "n" && "${DO_REMOVE_CROWDSEC}" != "N" ]]; do
            read -rp "Do you want to remove CrowdSec HIPS? [y/n]: " -e DO_REMOVE_CROWDSEC
        done
    fi

    if [[ ${DO_REMOVE_CROWDSEC} == y* || ${DO_REMOVE_CROWDSEC} == Y* ]]; then
        echo "[Removing CrowdSec]"

        # Stop and disable CrowdSec even when the unit is inactive.
        # `systemctl status` is false for a stopped unit, and `run` exits on
        # failure, so neither can express a best-effort stop.
        if command -v systemctl >/dev/null 2>&1 && systemctl cat crowdsec.service >/dev/null 2>&1; then
            echo "Stopping CrowdSec daemon..."
            if [[ "${DRYRUN}" == true ]]; then
                run systemctl stop crowdsec
                run systemctl disable crowdsec
            else
                systemctl stop crowdsec >/dev/null 2>&1 || true
                systemctl disable crowdsec >/dev/null 2>&1 || true
            fi
        fi

        # Kill any remaining processes. Match the exact process name so the
        # removal script itself (whose path contains "crowdsec") is not hit.
        if pgrep -x crowdsec >/dev/null 2>&1; then
            if [[ "${DRYRUN}" == true ]]; then
                run pkill -x crowdsec
            else
                pkill -x crowdsec >/dev/null 2>&1 || true
            fi
        fi

        # Remove CrowdSec bouncer includes from nginx config.
        if [[ -f /etc/nginx/nginx.conf ]]; then
            if grep -qE 'crowdsec(-nginx)?\.conf|crowdsec-webapp\.conf' /etc/nginx/nginx.conf; then
                sed_inplace '/crowdsec-nginx.conf/d;/crowdsec-webapp.conf/d' /etc/nginx/nginx.conf
            fi
        fi
        [[ -f /etc/lemper/waf/crowdsec-webapp.conf ]] && run rm -f /etc/lemper/waf/crowdsec-webapp.conf

        # Remove binaries and plugins left by wizard.sh. The release install
        # uses /usr/local/bin and symlinks /usr/bin when that directory is
        # absent from PATH. Packaged copies are removed by apt below.
        for CROWDSEC_BINARY in /usr/local/bin/crowdsec /usr/local/bin/cscli \
            /usr/bin/crowdsec /usr/bin/cscli; do
            [[ -e "${CROWDSEC_BINARY}" || -L "${CROWDSEC_BINARY}" ]] && run rm -f "${CROWDSEC_BINARY}"
        done
        [[ -d /usr/local/lib/crowdsec ]] && run rm -rf /usr/local/lib/crowdsec

        # Remove CrowdSec packages.
        if command -v apt-get >/dev/null 2>&1; then
            echo "Removing CrowdSec packages..."
            local CROWDSEC_PACKAGES=()
            local CROWDSEC_PACKAGE
            for CROWDSEC_PACKAGE in crowdsec crowdsec-nginx-bouncer crowdsec-firewall-bouncer-iptables; do
                if dpkg-query -W -f='${Status}' "${CROWDSEC_PACKAGE}" 2>/dev/null | grep -q 'install ok installed'; then
                    CROWDSEC_PACKAGES+=("${CROWDSEC_PACKAGE}")
                fi
            done
            if [[ ${#CROWDSEC_PACKAGES[@]} -gt 0 ]]; then
                run apt-get purge -q -y "${CROWDSEC_PACKAGES[@]}"
                run apt-get autoremove -q -y
            fi
        fi

        # Remove CrowdSec data and config directories.
        echo "Cleaning up CrowdSec data and configuration..."
        [[ -d /etc/crowdsec ]] && run rm -rf /etc/crowdsec
        [[ -d /var/lib/crowdsec ]] && run rm -rf /var/lib/crowdsec
        [[ -d /var/log/crowdsec ]] && run rm -rf /var/log/crowdsec
        [[ -f /etc/systemd/system/crowdsec.service ]] && run rm -f /etc/systemd/system/crowdsec.service

        # Remove CrowdSec apt repository. The packagecloud setup script uses
        # <name>_<repo> suffixes for both the list and the signing key.
        local CROWDSEC_APT_FILE
        for CROWDSEC_APT_FILE in /etc/apt/sources.list.d/crowdsec*.list \
            /etc/apt/trusted.gpg.d/crowdsec*.gpg /etc/apt/keyrings/crowdsec*.gpg; do
            [[ -e "${CROWDSEC_APT_FILE}" ]] && run rm -f "${CROWDSEC_APT_FILE}"
        done

        # Reload nginx and systemd after the packages are gone.
        if command -v systemctl >/dev/null 2>&1 && systemctl status nginx &>/dev/null; then
            if nginx -t >/dev/null 2>&1; then
                run systemctl restart nginx
            else
                warning "Nginx configuration test failed after removing CrowdSec."
            fi
        fi
        if command -v systemctl >/dev/null 2>&1; then
            run systemctl daemon-reload
        fi

        success "CrowdSec HIPS has been removed."
    else
        info "CrowdSec removal skipped."
    fi
}

echo "[CrowdSec Removal]"

if [[ -z $(command -v crowdsec) && "${FORCE_REMOVE}" != true ]]; then
    info "CrowdSec is not installed, nothing to remove."
else
    init_crowdsec_remove "$@"
fi
