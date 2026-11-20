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



# Dependencies are loaded by the command adapter, never at source time.
function stack_help() {
    cat <<EOF
${CMD_PARENT:-lemperctl} stack ${PROG_VERSION:-}
Usage: ${CMD_PARENT:-lemperctl} stack <install|remove|update|start|stop|restart|reload|status> <service> [options]
Services: $(lemper_component_ids | tr '\n' ' ')
Options:
  --php-version VERSION  Limit the operation to one installed PHP version.
  --all-versions         Explicitly select all installed PHP versions.
  --source-dir PATH      Component source checkout.
  --yes                 Confirm removal without prompting.
  --force               Remove a pre-existing component (site references still checked).
  --dry-run             Print operations without mutation.
  --help, --version     Show help or version.
Versionless PHP control/update targets all installed instances.
PHP install defaults to the configured supported version; multi-version removal requires selection.
EOF
}
function stack_service_spec() { lemper_component_spec "$@"; }
function stack_run_component() { lemper_legacy_component "$@"; }
function stack_control() { lemper_service_control "$@"; }

function stack_source_root() {
    local root="${1:-}"
    if [[ -z "$root" && -r /etc/lemper/update-source ]]; then
        IFS= read -r root < /etc/lemper/update-source
    fi
    if [[ -z "$root" ]]; then
        root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
    fi
    [[ -f "$root/scripts/utils.sh" && -f "$root/.env.dist" ]] ||
        { error "A LEMPer checkout is required for this component operation."; return 1; }
    printf '%s\n' "$root"
}

function lemper_stack_execute() {
    local action="$1" service="$2" php="$3" source="$4" yes="$5" force="$6"
    local installer remover units key family unit component preexisting=false binary marker
    read -r installer remover units key family < <(stack_service_spec "$service")
    [[ -n "$installer" ]] || return 1
    local state="${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}"
    marker="$state/$service"
    [[ "$service" != php ]] || marker="$state/php-$php"
    case "$action" in
        start|stop|restart|reload|status)
            [[ "$units" != PHP ]] || units="php$php-fpm"
            [[ "$units" != - ]] || { error "This component has no systemd service."; return 1; }
            local unit_list=() rc=0
            IFS=',' read -r -a unit_list <<< "$units"
            for unit in "${unit_list[@]}"; do stack_control "$action" "$unit" || rc=1; done
            return "$rc" ;;
        install|remove)
            source=$(stack_source_root "$source") || return 1
            if [[ "$action" == remove ]]; then
                # Aggregate legacy PHP markers do not establish per-version ownership.
                if [[ "$force" != true && ! -f "$marker" ]]; then
                    error "No LEMPer provisioning marker; use --force to remove a pre-existing component."
                    return 1
                fi
                if [[ "$yes" != true && "${DRYRUN:-false}" != true ]]; then
                    local answer
                    read -rp "Remove $service $php? [y/N]: " answer || return 1
                    [[ "$answer" == y || "$answer" == Y ]] || return 1
                fi
                component="$source/scripts/remove_$remover.sh"
            else
                component="$source/scripts/install_$installer.sh"
            fi
            [[ -f "$component" ]] || { error "Component script is missing."; return 1; }
            binary="${units%%,*}"
            case "$service" in
                php) binary="php$php" ;;
                postgres|postgresql) binary=psql ;;
                mariadb|mysql) binary=mariadb ;;
                bun) binary=bun ;;
                certbot) binary=certbot ;;
            esac
            if [[ "$action" == install ]] && command -v "$binary" >/dev/null 2>&1; then
                preexisting=true
            fi
            if [[ "$action" == install && "$family" != - ]]; then
                local package state_text
                while IFS=$'\t' read -r package state_text; do
                    [[ "$state_text" == 'install ok installed' ]] && preexisting=true
                done < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' \
                    "$([[ "$service" == php ]] && printf 'php%s-*' "$php" || printf '%s*' "$family")" 2>/dev/null)
            fi
            stack_run_component "$action" "$service" "$source" "$php" "$key" "$component" "$force" || return 1
            if [[ "${DRYRUN:-false}" != true ]]; then
                if [[ "$action" == install && "$preexisting" != true ]]; then
                    install -d -m 0700 "$state" || return 1
                    touch "$marker" || return 1
                elif [[ "$action" == remove ]]; then
                    rm -f "$marker" || return 1
                fi
            fi ;;
        update)
            case "$service" in
                php) lemper_php_update "$php" ;;
                nginx|mariadb) lemper_exec "${LEMPER_CLI_BIN:-lemperctl}" update "$service" ;;
                tools) lemper_exec "${LEMPER_CLI_BIN:-lemperctl}" update lemper ;;
                *)
                    [[ "$family" != - ]] || { error "This component has no package update path."; return 1; }
                    local packages=() package state_text
                    while IFS=$'\t' read -r package state_text; do
                        [[ "$state_text" == 'install ok installed' ]] || continue
                        package="${package%%:*}"
                        # Boundary matching excludes unrelated names sharing a prefix.
                        case "$package" in "$family"|"$family"-*) packages+=("$package") ;; esac
                    done < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' "$family*" 2>/dev/null)
                    [[ ${#packages[@]} -gt 0 ]] ||
                        { error "No managed package update path; source builds require a rebuild."; return 1; }
                    lemper_exec apt-get update -q || return 1
                    lemper_exec apt-get install --only-upgrade -y "${packages[@]}" || return 1
                    if [[ "$units" != - ]]; then
                        local updated_units=()
                        IFS=',' read -r -a updated_units <<< "$units"
                        for unit in "${updated_units[@]}"; do stack_control restart "$unit" || return 1; done
                    fi ;;
            esac ;;
    esac
}

function lemper_stack_batch() {
    local action="$1" service="$2" versions="$3" source="$4" yes="$5" force="$6" rc=0 version
    # Validate every PHP reference before removing any selected version.
    if [[ "$service" == php && "$action" == remove ]]; then
        while IFS= read -r version; do
            lemper_php_check_references "$version" || return 1
            [[ "$force" == true || -f "${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}/php-$version" ]] ||
                { error "No LEMPer provisioning marker for PHP $version; use --force."; return 1; }
        done <<< "$versions"
    fi
    while IFS= read -r version; do
        lemper_stack_execute "$action" "$service" "$version" "$source" "$yes" "$force" || rc=1
    done <<< "$versions"
    return "$rc"
}

function init_lemper_stack() {
    local action="${1:-help}" service="" php="" source="" yes=false force=false all=false argument versions=""
    local DRYRUN="${DRYRUN:-false}"
    [[ $# -eq 0 ]] || shift
    case "$action" in
        help|-h|--help) stack_help; return 0 ;;
        version|-v|--version) echo "${CMD_PARENT:-lemperctl} stack version ${PROG_VERSION:-}"; return 0 ;;
        install|remove|update|start|stop|restart|reload|status) ;;
        *) error "Unknown stack operation."; return 1 ;;
    esac
    lemper_parse_args hyv 'help,version,php-version:,all-versions,source-dir:,yes,force,dry-run' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            -h|--help) stack_help; return 0 ;;
            -v|--version) echo "${CMD_PARENT:-lemperctl} stack version ${PROG_VERSION:-}"; return 0 ;;
            --php-version) [[ -z "$php" ]] || { error "Duplicate PHP version."; return 1; }; php="$1"; shift ;;
            --source-dir) source="$1"; shift ;;
            --all-versions) all=true ;;
            -y|--yes) yes=true ;;
            --force) force=true ;;
            --dry-run) DRYRUN=true ;;
            --) [[ $# -eq 1 ]] || { error "Specify exactly one stack service."; return 1; }; service="$1"; break ;;
        esac
    done
    # Canonicalize aliases before resolving ownership and update handlers.
    case "$service" in
        mysql) service=mariadb ;;
        postgresql) service=postgres ;;
        ftp) service="${FTP_SERVER_NAME:-pureftpd}" ;;
    esac
    stack_service_spec "$service" >/dev/null || return 1
    lemper_load_module services/systemd || return 1
    lemper_load_module compat/components || return 1
    if [[ "$service" == php ]]; then
        lemper_load_module services/php/lifecycle || return 1
        versions=$(lemper_php_resolve "$action" "$php" "$all") || return 1
        info "PHP targets: $(printf '%s' "$versions" | tr '\n' ' ')"
    elif [[ -n "$php" || "$all" == true ]]; then
        error "PHP version options require the php component."
        return 1
    fi
    if [[ "$action" == status ]]; then
        lemper_stack_batch "$action" "$service" "$versions" "$source" "$yes" "$force"
    else
        lemper_with_lock lemper_stack_batch "$action" "$service" "$versions" "$source" "$yes" "$force"
    fi
}
