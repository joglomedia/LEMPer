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

function init_pureftpd_removal() {
    # Stop Pure-FTPd process.
    if [[ $(pgrep -c pure-ftpd) -gt 0 ]]; then
        echo "Stopping pure-ftpd..."
        run systemctl stop pure-ftpd.service
        run systemctl disable pure-ftpd.service
    fi

    if dpkg-query -l | awk '/pure-ftpd/ { print $2 }' | grep -qwE "^pure-ftpd$"; then
        echo "Found FTP server (Pure-FTPd) package installation. Removing..."
        run apt-get purge -q -y pure-ftpd pure-ftpd-common pure-ftpd-mysql
    else
        info "FTP server (Pure-FTPd) package not found, possibly installed from source."
        echo "Remove it manually!!"

        PUREFTPD_BIN=$(command -v pure-ftpd)
        echo "Deleting Pure-FTPd binary executable: ${PUREFTPD_BIN}"

        if [[ -n $(command -v pure-ftpd) ]]; then
            run rm -f "${PUREFTPD_BIN}"
            run rm -f /usr/sbin/pure-*
        fi
    fi

    [[ -f /etc/systemd/system/multi-user.target.wants/pure-ftpd.service ]] \
        && run unlink /etc/systemd/system/multi-user.target.wants/pure-ftpd.service

    [[ -f /etc/systemd/system/pure-ftpd.service ]] && run rm -f /etc/systemd/system/pure-ftpd.service

    [[ -f /lib/systemd/system/pure-ftpd.service ]] && run rm /lib/systemd/system/pure-ftpd.service

    [[ -f /run/systemd/generator.late/multi-user.target.wants/pure-ftpd.service ]] \
        && run unlink /run/systemd/generator.late/multi-user.target.wants/pure-ftpd.service

    [[ -f /run/systemd/generator.late/graphical.target.wants/pure-ftpd.service ]] \
        && run unlink /run/systemd/generator.late/graphical.target.wants/pure-ftpd.service

    [[ -f /run/systemd/generator.late/pure-ftpd.service ]] \
        && run rm /run/systemd/generator.late/pure-ftpd.service

    if [[ -x /etc/init.d/pure-ftpd ]]; then
        run rm /etc/init.d/pure-ftpd
        run update-rc.d -f pure-ftpd remove
    fi

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
        [[ -f /etc/pure-ftpd.conf ]] && run rm -f /etc/pure-ftpd.conf
        [[ -f /etc/default/pure-ftpd-common ]] && run rm -f /etc/default/pure-ftpd-common
        [[ -f /etc/ssl/private/pure-ftpd.pem ]] && run rm -f /etc/ssl/private/pure-ftpd.pem

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

function lemper_pureftpd_remove_entry() {
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
}
