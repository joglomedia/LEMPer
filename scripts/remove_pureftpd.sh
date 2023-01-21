#!/usr/bin/env bash

# Pure-FTPd Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 07/04/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.4

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

function init_pureftpd_removal() {
    # Stop Pure-FTPd process.
    if [[ $(pgrep -c pure-ftpd) -gt 0 ]]; then
        run systemctl stop pure-ftpd
        run systemctl disable pure-ftpd
    fi

    if dpkg-query -l | awk '/pure-ftpd/ { print $2 }' | grep -qwE "^pure-ftpd$"; then
        echo "Found FTP server (Pure-FTPd) package installation. Removing..."
        run apt-get purge -q -y pure-ftpd pure-ftpd-common pure-ftpd-mysql
    else
        info "FTP server (Pure-FTPd) package not found, possibly installed from source."
        echo "Remove it manually!!"

        PUREFTPD_BIN=$(command -v pure-ftpd)
        echo "Deleting Pure-FTPd binary executable: ${PUREFTPD_BIN}"

        [[ -n $(command -v pure-ftpd) ]] && run rm -f "${PUREFTPD_BIN}"
    fi

    [[ -f /etc/systemd/system/multi-user.target.wants/pure-ftpd.service ]] && \
        run unlink /etc/systemd/system/multi-user.target.wants/pure-ftpd.service
    [[ -f /lib/systemd/system/pure-ftpd.service ]] && run rm /lib/systemd/system/pure-ftpd.service && \
    [[ -x /etc/init.d/pure-ftpd ]] && run update-rc.d -f pure-ftpd remove

    # Remove Pure-FTPd config files.
    echo "Removing FTP server (Pure-FTPd) configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_PUREFTPD_CONFIG="y"
        else
            REMOVE_PUREFTPD_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_PUREFTPD_CONFIG}" != "y" && "${REMOVE_PUREFTPD_CONFIG}" != "n" ]]; do
            read -rp "Remove FTP server (Pure-FTPd) configuration files? [y/n]: " -e REMOVE_PUREFTPD_CONFIG
        done
    fi

    if [[ "${REMOVE_PUREFTPD_CONFIG}" == y* || "${REMOVE_PUREFTPD_CONFIG}" == Y* ]]; then
        [[ -d /etc/pure-ftpd ]] && run rm -fr /etc/pure-ftpd
        [[ -x /etc/init.d/pure-ftpd ]] && run update-rc.d -f pure-ftpd remove
        [[ -f /usr/sbin/pure-ftpd-wrapper ]] && run rm -f /usr/sbin/pure-ftpd-wrapper

        echo "All configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v pure-ftpd) ]]; then
            success "FTP server (Pure-FTPd) removed succesfully."
        else
            info "Unable to remove FTP server (Pure-FTPd)."
        fi
    else
        info "FTP server (Pure-FTPd) server removed in dry run mode."
    fi
}

echo "Uninstalling FTP server (Pure-FTPd)..."

if [[ -n $(command -v pure-ftpd) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_PUREFTPD="y"
    else
        while [[ "${REMOVE_PUREFTPD}" != "y" && "${REMOVE_PUREFTPD}" != "n" ]]; do
            read -rp "Are you sure to remove FTP server (Pure-FTPd)? [y/n]: " -e REMOVE_PUREFTPD
        done
    fi

    if [[ "${REMOVE_PUREFTPD}" == y* || "${REMOVE_PUREFTPD}" == Y* ]]; then
        init_pureftpd_removal "$@"
    else
        echo "Found FTP server (Pure-FTPd), but not removed."
    fi
else
    info "Oops, FTP server (Pure-FTPd) installation not found."
fi
