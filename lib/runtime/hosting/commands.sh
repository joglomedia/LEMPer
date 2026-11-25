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

function lemper_hosting_help() {
    cat <<'HELP'
Usage: lemperctl hosting <command> [options]
  check                                   Check quota-ready ext4 filesystem.
  plan put NAME --disk-soft=1G --disk-hard=2G --files-soft=50000 --files-hard=60000
  plan list                               Show plans (disk sizes in KiB).
  plan delete NAME --yes                  Delete an unassigned plan.
  assign USER --plan=NAME                  Assign/upgrade a managed account.
  status                                  Show actual usage and limits.
  detach USER --yes                        Restore original limits, retain data.
  recover USER --yes                       Restore baseline after interruption.
All mutations support --dry-run. Quotas must already be enabled by the administrator.
Use account USER --plan=NAME to provision a new hosting account with limits.
HELP
}
function lemper_hosting_command() {
    local action="${1:-help}" sub="" name="" plan="" disk_soft="" disk_hard="" file_soft="" file_hard=""
    local yes=false DRYRUN="${DRYRUN:-false}" root file row
    [[ $# == 0 ]] || shift
    if [[ "$action" == plan ]]; then
        sub="${1:-list}"
        [[ $# == 0 ]] || shift
    fi
    lemper_parse_args hv 'help,version,disk-soft:,disk-hard:,files-soft:,files-hard:,plan:,yes,dry-run' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                action=help
                shift
                ;;
            -v | --version)
                action=version
                shift
                ;;
            --disk-soft)
                disk_soft="$2"
                shift 2
                ;;
            --disk-hard)
                disk_hard="$2"
                shift 2
                ;;
            --files-soft)
                file_soft="$2"
                shift 2
                ;;
            --files-hard)
                file_hard="$2"
                shift 2
                ;;
            --plan)
                plan="$2"
                shift 2
                ;;
            --yes)
                yes=true
                shift
                ;;
            --dry-run)
                DRYRUN=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *) return 1 ;;
        esac
    done
    [[ $# -le 1 ]] || return 1
    name="${1:-}"
    case "$action" in
        help | -h | --help)
            lemper_hosting_help
            return 0
            ;;
        version | -v | --version)
            echo "${CMD_PARENT:-lemperctl} hosting version ${PROG_VERSION:-}"
            return 0
            ;;
    esac
    lemper_load_module services/hosting/quota || return 1
    lemper_load_module services/hosting/plans || return 1
    case "$action" in
        check)
            [[ -z "$name$plan$disk_soft$disk_hard$file_soft$file_hard" ]] || return 1
            lemper_quota_mount "${HOSTING_QUOTA_MOUNT:-/home}"
            ;;
        status)
            [[ -z "$name$plan$disk_soft$disk_hard$file_soft$file_hard" ]] || return 1
            lemper_hosting_status
            ;;
        plan)
            [[ -z "$plan" ]] || return 1
            case "$sub" in
                put)
                    disk_soft=$(lemper_hosting_size "$disk_soft") && disk_hard=$(lemper_hosting_size "$disk_hard") || return 1
                    lemper_with_lock lemper_hosting_plan_put "$name" "$disk_soft" "$disk_hard" "$file_soft" "$file_hard"
                    ;;
                delete)
                    [[ "$yes" == true && -z "$disk_soft$disk_hard$file_soft$file_hard" ]] || {
                        error "Plan deletion requires --yes and a plan name."
                        return 1
                    }
                    lemper_with_lock lemper_hosting_plan_delete "$name"
                    ;;
                list)
                    [[ -z "$name$disk_soft$disk_hard$file_soft$file_hard" ]] || return 1
                    root=$(lemper_hosting_root) || return 1
                    [[ ! -L "$root/plans" ]] || return 1
                    echo 'PLAN SOFT_KIB HARD_KIB SOFT_FILES HARD_FILES'
                    for file in "$root"/plans/*.conf; do
                        [[ -e "$file" ]] || continue
                        name=$(basename "$file" .conf)
                        row=$(lemper_hosting_plan_read "$name") || return 1
                        printf '%s %s\n' "$name" "$row"
                    done
                    ;;
                *)
                    error "Unknown hosting plan command."
                    return 1
                    ;;
            esac
            ;;
        assign)
            [[ -n "$plan" && -z "$disk_soft$disk_hard$file_soft$file_hard" ]] || return 1
            lemper_with_lock lemper_hosting_assign "$name" "$plan"
            ;;
        detach | recover)
            [[ "$yes" == true && -z "$plan$disk_soft$disk_hard$file_soft$file_hard" ]] || {
                error "Detach/recover requires --yes and a username."
                return 1
            }
            local recovery=false
            [[ "$action" != recover ]] || recovery=true
            lemper_with_lock lemper_hosting_detach "$name" "$recovery"
            ;;
        *)
            error "Unknown hosting command."
            return 1
            ;;
    esac
}
