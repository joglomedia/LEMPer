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

##
# Upgrade MariaDB packages and restart only when the version changed.
##
function update_mariadb() {
    local before after pkgs=() pkg before_branch after_branch

    if ! dpkg -s mariadb-server >/dev/null 2>&1; then
        info "MariaDB server is not installed."
        return 0
    fi

    before=$(dpkg-query -W -f='${Version}' mariadb-server)

    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && pkgs+=("${pkg}")
    done < <(dpkg-query -W -f='${Package}\n' 'mariadb-server*' 'mariadb-client*' 'mariadb-common' 2>/dev/null || true)

    [[ "${#pkgs[@]}" -eq 0 ]] && pkgs=("mariadb-server" "mariadb-client" "mariadb-common")

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade "${pkgs[@]}"; then
        error "Failed to upgrade MariaDB packages."
        return 1
    fi

    after=$(dpkg-query -W -f='${Version}' mariadb-server)
    if [[ "${before}" == "${after}" ]]; then
        info "MariaDB is already current (${after})."
        return 0
    fi

    success "MariaDB upgraded: ${before} -> ${after}."
    if ! systemctl try-restart mariadb 2>/dev/null; then
        error "MariaDB upgraded but could not be restarted."
        return 1
    fi
    success "MariaDB restarted."

    before_branch=$(printf '%s' "${before#*:}" | awk -F. '{print $1"."$2}')
    after_branch=$(printf '%s' "${after#*:}" | awk -F. '{print $1"."$2}')
    if [[ "${before_branch}" != "${after_branch}" ]]; then
        warning "MariaDB branch changed (${before_branch} -> ${after_branch}); run 'mariadb-upgrade' and review the upgrade notes."
    fi
}
