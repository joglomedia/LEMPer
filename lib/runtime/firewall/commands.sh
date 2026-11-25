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



function lemper_firewall_help() {
    echo 'Usage: lemperctl firewall <apply|status|check|confirm|rollback|remove> [--migrate-from-ufw] [--yes] [--dry-run]'
    echo 'Native inet lemper rules preserve unrelated tables. SSH changes arm timed rollback until confirmed.'
}
function lemper_firewall_command() {
    local action="${1:-help}" argument migrate=false yes=false DRYRUN="${DRYRUN:-false}"
    [[ $# == 0 ]] || shift
    lemper_parse_args hv 'help,version,migrate-from-ufw,yes,dry-run' "$@" || return 1
    for argument in "${LEMPER_PARSED_ARGS[@]}"; do
        case "$argument" in --migrate-from-ufw) migrate=true ;; --yes) yes=true ;; --dry-run) DRYRUN=true ;;
            -h|--help) action=help ;; -v|--version) action=version ;; --) ;; *) return 1 ;; esac
    done
    lemper_load_module services/firewall/nftables || return 1
    case "$action" in
        help|-h|--help) lemper_firewall_help ;;
        version|-v|--version) echo "${CMD_PARENT:-lemperctl} firewall version ${PROG_VERSION:-}" ;;
        apply) lemper_with_lock lemper_nft_apply "$migrate" ;;
        status) lemper_exec nft list table inet lemper ;;
        check) lemper_exec nft -c -f /etc/lemper/firewall/current.nft ;;
        confirm) lemper_with_lock lemper_nft_confirm ;;
        rollback) lemper_with_lock lemper_nft_rollback ;;
        remove) [[ "$yes" == true ]] || { error "Firewall removal requires --yes."; return 1; }; lemper_with_lock lemper_nft_remove ;;
        *) error "Unknown firewall command."; return 1 ;;
    esac
}
