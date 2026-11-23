#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer MariaDB Repository Selection                                     |
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

# Distro-aware defaults; explicit database major versions are never replaced.
function lemper_mariadb_default_version() {
    local distro="$1" release="$2" requested="${3:-auto}"
    if [[ "$requested" == auto ]]; then
        if [[ "$distro/$release" == ubuntu/resolute ]]; then printf '11.8\n'; else printf '11.4\n'; fi
    elif [[ "$requested" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%s\n' "$requested"
    else
        error "Invalid MariaDB version; use auto or an explicit supported series."
        return 1
    fi
}
function lemper_mariadb_install_packages() {
    printf '%s\n' libmariadb-dev libmariadb3 mariadb-client mariadb-client-core mariadb-common mariadb-server mariadb-server-core mariadb-backup
    [[ "${DISTRIB_NAME:-}/${RELEASE_NAME:-}" == ubuntu/resolute ]] || printf 'libmariadbclient18\n'
}
function lemper_mariadb_default_data_directory() {
    if [[ "${DISTRIB_NAME:-}/${RELEASE_NAME:-}" == ubuntu/resolute ]]; then
        printf '/var/lib/mariadb\n'
    else
        printf '/var/lib/mysql\n'
    fi
}
function lemper_mariadb_prepare_native() {
    local version="$1" installed state
    [[ "$version" == 11.8 ]] || {
        error "Ubuntu Resolute provides MariaDB 11.8; set MYSQL_VERSION=auto or 11.8. The 11.4 repository is not published for Resolute."
        return 1
    }
    lemper_load_module services/apt/repositories || return 1
    if lemper_apt_has_source mariadb; then
        error "Reconcile external MariaDB sources before selecting the Resolute distribution package."
        return 1
    fi
    state=$(dpkg-query -W -f='${Status}' mariadb-server 2>/dev/null) || state=""
    if [[ "$state" == 'install ok installed' ]]; then
        installed=$(dpkg-query -W -f='${Version}' mariadb-server 2>/dev/null) || return 1
        [[ "$installed" =~ ^([0-9]+:)?11\.8[.-] ]] || {
            error "An installed MariaDB server uses another major series; perform a deliberate database migration first."
            return 1
        }
    fi
    info "Using Ubuntu Resolute's signed distribution packages for MariaDB 11.8."
    lemper_exec apt-get update -q -y
}
