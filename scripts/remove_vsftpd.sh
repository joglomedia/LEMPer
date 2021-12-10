#!/usr/bin/env bash

# VSFTPD Uninstaller
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 10/12/2021
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.5.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

function init_vsftpd_removal() {
    # Stop VSFTPD process.
    if [[ $(pgrep -c vsftpd) -gt 0 ]]; then
        run systemctl stop vsftpd
    fi

    if dpkg-query -l | awk '/vsftpd/ { print $2 }' | grep -qwE "^vsftpd$"; then
        echo "Found FTP server (VSFTPD) package installation. Removing..."
        run apt-get remove --purge -qq -y vsftpd
    else
        info "FTP server (VSFTPD) package not found, possibly installed from source."
        echo "Remove it manually!!"

        VSFTPD_BIN=$(command -v vsftpd)
        echo "Deleting vsftpd binary executable: ${VSFTPD_BIN}"

        [[ -x "${VSFTPD_BIN}" ]] && run rm -f "${VSFTPD_BIN}"
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
        [[ -f /etc/vsftpd.conf ]] && run rm -f /etc/vsftpd.conf
        [[ -f /etc/vsftpd.conf.bak ]] && run rm -f /etc/vsftpd.conf.bak
        echo "All configuration files deleted permanently."
    fi

    # Final test.
    if [[ "${DRYRUN}" != true ]]; then
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
