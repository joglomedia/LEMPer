#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Authoritative DNS CLI Commands                                          |
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

function lemper_dns_help() {
    cat <<'HELP'
Usage: lemperctl dns plan DOMAIN [ZONEFILE | --ipv4=ADDRESS [--mail]]
       lemperctl dns check DOMAIN [SERVER ...] [--serial=N] [--ipv4=ADDRESS] [--file=ZONEFILE]
       lemperctl dns zone enroll DOMAIN OWNER
       lemperctl dns zone validate DOMAIN ZONEFILE
       lemperctl dns zone apply DOMAIN ZONEFILE [--base=REVISION]
       lemperctl dns zone status|resume|rollback DOMAIN
       lemperctl dns zone retire DOMAIN --base=REVISION --yes
Use --dry-run for enrollment, publication, rollback and retirement.
DNS is optional. Complete zone files preserve existing mail and verification records.
HELP
}

function lemper_dns_zone_status() {
    local dir="/etc/knot/lemper/zones/$1" ref
    [[ -f "$dir/owner" ]] || { error "Unknown zone."; return 1; }
    printf 'zone %s\nowner %s\n' "$1" "$(<"$dir/owner")"
    for ref in committed previous pending; do
        if [[ -f "$dir/$ref" ]]; then printf '%s %s\n' "$ref" "$(<"$dir/$ref")"; fi
    done
    if [[ -f "$dir/retired" ]]; then echo retired; fi
}

function lemper_dns_command() {
    local action="${1:-help}" domain arg base="" serial="" ipv4="" mail=false yes=false DRYRUN="${DRYRUN:-false}"
    local args=() file=""
    case "$action" in
        help|--help|-h) lemper_dns_help; return 0 ;;
        version|--version|-v) echo "${CMD_PARENT:-lemperctl} dns version ${PROG_VERSION:-}"; return 0 ;;
    esac
    shift
    if [[ "$action" == zone ]]; then action="zone-${1:-}"; [[ $# == 0 ]] || shift; fi
    domain="${1:-}"; domain="${domain%.}"; domain="${domain,,}"
    core_is_valid_fqdn "$domain" || { error "Specify a valid DNS zone name."; return 1; }
    shift
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRYRUN=true ;;
            --yes) [[ "$action" == zone-retire ]] || return 1; yes=true ;;
            --mail) [[ "$action" == plan ]] || return 1; mail=true ;;
            --file=*) [[ "$action" == check && -n "${arg#*=}" ]] || return 1; file="${arg#*=}" ;;
            --base=*) [[ "$action" == zone-apply || "$action" == zone-retire ]] || return 1
                base="${arg#*=}"; [[ "$base" == new || "$base" =~ ^[a-f0-9]{64}$ ]] || return 1 ;;
            --serial=*) [[ "$action" == check ]] || return 1
                serial="${arg#*=}"; [[ "$serial" =~ ^(0|[1-9][0-9]{0,9})$ ]] && ((10#$serial <= 4294967295)) || return 1 ;;
            --ipv4=*) [[ "$action" == check || "$action" == plan ]] || return 1
                ipv4="${arg#*=}"; core_is_valid_ipv4 "$ipv4" || return 1 ;;
            -*) error "Unknown DNS option."; return 1 ;;
            *) args+=("$arg") ;;
        esac
    done
    lemper_load_module services/dns/zones || return 1
    case "$action" in
        plan)
            if [[ ${#args[@]} == 1 && -z "$ipv4" && "$mail" == false ]]; then
                lemper_dns_plan "$domain" "${args[0]}"
            else
                [[ ${#args[@]} == 0 && ( -n "$ipv4" || "$mail" == true ) ]] || { lemper_dns_help; return 1; }
                [[ -z "$ipv4" ]] || printf '%s. IN A %s\n' "$domain" "$ipv4"
                if [[ "$mail" == true ]]; then
                    lemper_load_module runtime/mail/commands && lemper_load_module services/mail/store || return 1
                    lemper_mail_dns "$domain" || return 1
                fi
            fi ;;
        check) lemper_dns_check "$domain" "$serial" "$ipv4" "$file" "${args[@]}" ;;
        zone-enroll) [[ ${#args[@]} == 1 ]] && lemper_with_lock lemper_dns_enroll "$domain" "${args[0]}" ;;
        zone-validate)
            [[ ${#args[@]} == 1 ]] || return 1
            ( local work; work=$(mktemp -d) || exit 1; trap 'rm -rf -- "$work"' EXIT
              lemper_dns_compile "$domain" "${args[0]}" "$work" && kzonecheck -o "$domain" "$work/zone" ) ;;
        zone-status) [[ ${#args[@]} == 0 ]] && lemper_dns_zone_status "$domain" ;;
        zone-resume) [[ ${#args[@]} == 0 ]] && lemper_with_lock lemper_dns_resume "$domain" ;;
        zone-apply) [[ ${#args[@]} == 1 ]] && lemper_with_lock lemper_dns_apply "$domain" "${args[0]}" "$base" ;;
        zone-rollback) [[ ${#args[@]} == 0 ]] && lemper_with_lock lemper_dns_rollback "$domain" ;;
        zone-retire) [[ ${#args[@]} == 0 && "$yes" == true && -n "$base" ]] &&
            lemper_with_lock lemper_dns_retire "$domain" "$base" ;;
        *) lemper_dns_help; return 1 ;;
    esac
}
