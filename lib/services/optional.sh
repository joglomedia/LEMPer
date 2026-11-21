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



function lemper_optional_lifecycle() {
    local action="$1" component="$2" root=/etc/lemper/optional package="$2" unit="" marker
    case "$component" in
        restic) unit=lemper-data-backup.timer ;;
        monit) unit=lemper-monit.service ;;
        nftables) unit=lemper-nftables.service ;;
        *) error "Unknown optional component."; return 1 ;;
    esac
    marker="$root/$component"
    if [[ "${DRYRUN:-false}" == true ]]; then info "Would $action $component; repository/data retained."; return 0; fi
    case "$action" in
        install)
            # Validate the selected backend before package/configuration mutations.
            case "$component" in
                restic) lemper_load_module services/restic/backup || return 1; DRYRUN=true lemper_restic_environment || return 1 ;;
                monit) lemper_load_module services/monitoring/monit || return 1; DRYRUN=true lemper_monit_configure || return 1 ;;
                nftables) lemper_load_module services/firewall/nftables || return 1; DRYRUN=true lemper_nft_apply || return 1 ;;
            esac
            local present=false
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' && present=true
            lemper_exec apt-get install -q -y "$package" || return 1
            install -d -m 0700 "$root" || return 1
            [[ "$present" == true ]] || touch "$marker"
            case "$component" in
                restic)
                    local file="${RESTIC_PASSWORD_FILE:-/etc/lemper/restic.pass}"
                    [[ "$file" == /* && ! -L "$file" ]] || return 1
                    lemper_load_module services/mariadb/database || return 1
                    lemper_db_directory_safe "${file%/*}" || return 1
                    if [[ ! -e "$file" ]]; then
                        (umask 077; openssl rand -hex 32 > "$file") || return 1
                    fi
                    lemper_load_module services/restic/backup || return 1
                    lemper_restic_init ;;
                monit) lemper_load_module services/monitoring/monit || return 1; lemper_monit_configure ;;
                nftables) lemper_load_module services/firewall/nftables || return 1; lemper_nft_apply ;;
            esac || return 1
            # Configuration ownership is distinct from package ownership. Whole-stack
            # removal can stop our units while preserving pre-existing packages.
            local installed="${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}"
            install -d -m0700 "$installed" || return 1
            touch "$installed/$component" || return 1
            ;;
        remove)
            if [[ "$component" == nftables ]]; then
                lemper_load_module services/firewall/nftables || return 1
                lemper_nft_remove || return 1
            elif systemctl cat "$unit" >/dev/null 2>&1; then lemper_exec systemctl disable --now "$unit" || return 1; fi
            [[ -f "$marker" || "${FORCE_REMOVE:-false}" == true ]] || { info "Managed unit removed; unowned $package package retained."; return 0; }
            lemper_exec apt-get remove -q -y "$package" || return 1
            rm -f "$marker"
            info "Removed owned component; configuration, repositories and credentials retained." ;;
        *) return 1 ;;
    esac
}
