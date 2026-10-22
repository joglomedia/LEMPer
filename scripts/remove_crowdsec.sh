#!/usr/bin/env bash

# Remove CrowdSec HIPS
# Since Version     : 3.3.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"
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

        # Stop and disable CrowdSec daemon.
        if [[ -f /lib/systemd/system/crowdsec.service ]] || \
           [[ $(command -v systemctl) ]] && systemctl is-enabled crowdsec &>/dev/null; then
            echo "Stopping CrowdSec daemon..."
            run systemctl stop crowdsec 2>/dev/null || true
            run systemctl disable crowdsec 2>/dev/null || true
        fi

        # Kill any remaining processes.
        if pgrep -c crowdsec &>/dev/null; then
            run pkill -f crowdsec 2>/dev/null || true
        fi

        # Remove CrowdSec bouncer from nginx config.
        if [[ -f /etc/nginx/nginx.conf ]]; then
            if grep -q 'crowdsec-bouncer' /etc/nginx/nginx.conf; then
                run sed -i '/crowdsec-nginx.conf/d' /etc/nginx/nginx.conf
            fi
        fi

        # Restart nginx to remove bouncer.
        if [[ -f /lib/systemd/system/nginx.service ]] && command -v systemctl; then
            run systemctl restart nginx
        fi

        # Remove CrowdSec packages.
        if command -v apt-get; then
            echo "Removing CrowdSec packages..."
            run apt-get purge -q -y crowdsec crowdsec-bouncer crowdsec-bouncer-nginx 2>/dev/null || true
            run apt-get autoremove -q -y 2>/dev/null || true
        fi

        # Remove CrowdSec data and config directories.
        echo "Cleaning up CrowdSec data and configuration..."
        [[ -d /etc/crowdsec ]] && run rm -rf /etc/crowdsec
        [[ -d /var/lib/crowdsec ]] && run rm -rf /var/lib/crowdsec
        [[ -d /var/log/crowdsec ]] && run rm -rf /var/log/crowdsec
        [[ -f /etc/systemd/system/crowdsec.service ]] && run rm -f /etc/systemd/system/crowdsec.service

        # Remove CrowdSec apt repository.
        if [[ -f /etc/apt/sources.list.d/crowdsec.list ]]; then
            run rm -f /etc/apt/sources.list.d/crowdsec.list
        fi
        if [[ -f /etc/apt/trusted.gpg.d/crowdsec.gpg ]]; then
            run rm -f /etc/apt/trusted.gpg.d/crowdsec.gpg
        fi

        # Reload systemd.
        if command -v systemctl; then
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
