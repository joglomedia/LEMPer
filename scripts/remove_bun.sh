#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Bun.js Runtime Uninstaller                                              |
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
# Remove Bun.js runtime.
##
function init_bunjs_remove() {
    if [[ "${AUTO_REMOVE}" == true ]]; then
        if [[ "${INSTALL_BUNJS}" == true ]]; then
            DO_REMOVE_BUNJS="y"
        else
            DO_REMOVE_BUNJS="n"
        fi
    else
        while [[ "${DO_REMOVE_BUNJS}" != "y" && "${DO_REMOVE_BUNJS}" != "Y" && \
            "${DO_REMOVE_BUNJS}" != "n" && "${DO_REMOVE_BUNJS}" != "N" ]]; do
            read -rp "Do you want to remove Bun.js runtime? [y/n]: " -e DO_REMOVE_BUNJS
        done
    fi

    if [[ ${DO_REMOVE_BUNJS} == y* || ${DO_REMOVE_BUNJS} == Y* ]]; then
        echo "Removing Bun.js runtime..."

        # Remove binary.
        run rm -f /usr/local/bin/bun

        # Remove from opt directory.
        run rm -rf /opt/bun

        # Remove apt repository.
        if [[ -f /etc/apt/sources.list.d/bun.list ]]; then
            run rm -f /etc/apt/sources.list.d/bun.list
        fi

        # Remove GPG key.
        if [[ -f /usr/share/keyrings/bun-archive-keyring.gpg ]]; then
            run rm -f /usr/share/keyrings/bun-archive-keyring.gpg
        fi

        # Remove profile.d entry.
        if [[ -f /etc/profile.d/bun.sh ]]; then
            run rm -f /etc/profile.d/bun.sh
        fi

        # Remove config directory.
        if [[ -d /etc/lemper/bun ]]; then
            run rm -rf /etc/lemper/bun
        fi

        # Remove cache directory.
        if [[ -d /var/lib/bun ]]; then
            run rm -rf /var/lib/bun
        fi

        # Remove bun user.
        if [[ -n $(getent passwd bun) ]]; then
            if [[ "${DRYRUN}" != true ]]; then
                run userdel -r bun 2>/dev/null || true
                run groupdel bun 2>/dev/null || true
            else
                info "Remove Bun.js user in dry run mode."
            fi
        fi

        # Remove apt package if installed via repo.
        if [[ $(dpkg -l | grep -c 'bun') -gt 0 ]]; then
            run apt-get purge -q -y bun 2>/dev/null || true
        fi

        if [[ "${DRYRUN}" != true ]]; then
            success "Bun.js runtime has been removed."
        else
            info "Bun.js runtime removed in dry run mode."
        fi
    else
        info "Bun.js runtime removal skipped."
    fi
}

echo "[Bun.js Runtime Removal]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -z $(command -v bun) && "${FORCE_REMOVE}" != true ]]; then
    info "Bun.js runtime does not exist, removal skipped."
else
    init_bunjs_remove "$@"
fi
