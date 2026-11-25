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



function lemper_data_help() {
    cat <<'HELP'
Usage: lemperctl data <init|backup|snapshots|check|restore|prune|schedule|run-scheduled> [options] [paths...]
  backup /absolute/app/path [/var/vmail]   Back up application or mail files.
  restore SNAPSHOT --target /staging      Restore to an empty staging directory.
  prune --keep COUNT                      Keep successful snapshots per host/path/tag.
  schedule /absolute/app/path             Install a daily systemd timer.
  --dry-run                               Validate without changing data/repository/timers.
Repository and protected password file come from RESTIC_REPOSITORY / RESTIC_PASSWORD_FILE.
HELP
}
function lemper_data_command() {
    local action="${1:-help}" target="" keep="${DATA_BACKUP_KEEP:-7}" argument paths=() DRYRUN="${DRYRUN:-false}"
    [[ $# == 0 ]] || shift
    lemper_parse_args hv 'target:,keep:,dry-run,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            --target) target="$1"; shift ;;
            --keep) keep="$1"; shift ;;
            --dry-run) DRYRUN=true ;;
            -h|--help) lemper_data_help; return 0 ;;
            -v|--version) echo "${CMD_PARENT:-lemperctl} data version ${PROG_VERSION:-}"; return 0 ;;
            --) paths=("$@"); break ;;
        esac
    done
    case "$action" in help|-h|--help) lemper_data_help; return 0 ;; version|-v|--version) echo "${CMD_PARENT:-lemperctl} data version ${PROG_VERSION:-}"; return 0 ;; esac
    lemper_load_module services/restic/backup || return 1
    case "$action" in
        init|check|snapshots|run-scheduled) [[ ${#paths[@]} == 0 && -z "$target" ]] || return 1 ;;
        backup|schedule) [[ ${#paths[@]} -gt 0 && -z "$target" ]] || return 1 ;;
        restore) [[ ${#paths[@]} == 1 && -n "$target" ]] || return 1 ;;
        prune) [[ ${#paths[@]} == 0 && -z "$target" ]] || return 1 ;;
        *) error "Unknown data backup command."; return 1 ;;
    esac
    case "$action" in
        init) lemper_with_lock lemper_restic_init ;;
        backup) lemper_with_lock lemper_restic_backup "${paths[@]}" ;;
        snapshots) lemper_restic_run snapshots --tag lemper-data ;;
        check) lemper_restic_run check ;;
        restore) lemper_with_lock lemper_restic_restore "${paths[0]}" "$target" ;;
        prune) lemper_with_lock lemper_restic_prune "$keep" ;;
        schedule) lemper_with_lock lemper_restic_schedule "${paths[@]}" ;;
        run-scheduled)
            [[ -r /etc/lemper/data-backup/paths ]] || return 1
            mapfile -t paths < /etc/lemper/data-backup/paths
            lemper_with_lock lemper_data_scheduled "${paths[@]}" ;;
    esac
}
function lemper_data_scheduled() {
    lemper_restic_backup "$@" || return 1
    lemper_restic_prune "${DATA_BACKUP_KEEP:-7}"
}
