#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | VSFTPD Uninstaller                                                      |
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

function init_vsftpd_removal() {
    # Stop VSFTPD process.
    if [[ $(pgrep -c vsftpd) -gt 0 ]]; then
        echo "Stopping vsftpd..."
        run systemctl stop vsftpd
        run systemctl disable vsftpd
    fi

    if dpkg-query -l | awk '/vsftpd/ { print $2 }' | grep -qwE "^vsftpd$"; then
        echo "Found FTP server (VSFTPD) package installation. Removing..."
        run apt-get purge -q -y vsftpd
    else
        info "FTP server (VSFTPD) package not found, possibly installed from source."
        echo "Remove it manually!!"

        VSFTPD_BIN=$(command -v vsftpd)
        echo "Deleting vsftpd binary executable: ${VSFTPD_BIN}"

        [[ -n $(command -v vsftpd) ]] && run rm -f "${VSFTPD_BIN}"
    fi

    [[ -f /etc/systemd/system/multi-user.target.wants/vsftpd.service ]] && \
        run unlink /etc/systemd/system/multi-user.target.wants/vsftpd.service
    [[ -f /lib/systemd/system/vsftpd.service ]] && run rm /lib/systemd/system/vsftpd.service

    # Remove VSFTPD config files.
    echo "Removing FTP server (VSFTPD) configuration..."
    warning "!! This action is not reversible !!"

    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${FORCE_REMOVE}" == true ]]; then
            REMOVE_VSFTPD_CONFIG="y"
        else
            REMOVE_VSFTPD_CONFIG="n"
        fi
    else
        while [[ "${REMOVE_VSFTPD_CONFIG}" != "y" && "${REMOVE_VSFTPD_CONFIG}" != "n" ]]; do
            read -rp "Remove FTP server (VSFTPD) configuration files? [y/n]: " -e REMOVE_VSFTPD_CONFIG
        done
    fi

    if [[ "${REMOVE_VSFTPD_CONFIG}" == y* || "${REMOVE_VSFTPD_CONFIG}" == Y* ]]; then
        [ -f /etc/vsftpd.conf ] && run rm -f /etc/vsftpd.conf
        [ -f /etc/vsftpd.conf.bak ] && run rm -f /etc/vsftpd.conf.bak
        [ -f /etc/vsftpd.userlist ] && run rm -f /etc/vsftpd.userlist
        [ -f /etc/ftpusers ] && run rm -f /etc/ftpusers
        [ -f /etc/pam.d/vsftpd ] && run rm -f /etc/pam.d/vsftpd
        [ -f /etc/ssl/private/vsftpd-selfsigned.pem ] && run rm -f /etc/ssl/private/vsftpd-selfsigned.pem

        echo "All configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
        run systemctl daemon-reload

        if [[ -z $(command -v vsftpd) ]]; then
            success "FTP server (VSFTPD) removed succesfully."
        else
            info "Unable to remove FTP server (VSFTPD)."
        fi
    else
        info "FTP server (VSFTPD) server removed in dry run mode."
    fi
}

echo "Uninstalling FTP server (VSFTPD)..."

if [[ -n $(command -v vsftpd) ]]; then
    if [[ "${AUTO_REMOVE}" == true ]]; then
        REMOVE_VSFTPD="y"
    else
        while [[ "${REMOVE_VSFTPD}" != "y" && "${REMOVE_VSFTPD}" != "n" ]]; do
            read -rp "Are you sure to remove FTP server (VSFTPD)? [y/n]: " -e REMOVE_VSFTPD
        done
    fi

    if [[ "${REMOVE_VSFTPD}" == y* || "${REMOVE_VSFTPD}" == Y* ]]; then
        init_vsftpd_removal "$@"
    else
        echo "Found FTP server (VSFTPD), but not removed."
    fi
else
    info "Oops, FTP server (VSFTPD) installation not found."
fi
