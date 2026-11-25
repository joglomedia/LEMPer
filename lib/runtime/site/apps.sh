#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Site Application Use Cases                                       |
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

function lemper_site_app_help() {
    cat <<EOF
Usage: ${CMD_PARENT:-lemperctl} site app <add|update|remove|list> DOMAIN [options]
  --mount /NAME          One lowercase URL path segment, e.g. /demo.
  --type laravel         Laravel front-controller routing (the default).
  --webroot PATH         Existing Laravel project directory, containing public/index.php.
  --runtime php@VERSION  Installed supported FPM version (default: parent site's runtime).
  --runtime-user USER    Existing non-root pool user (default: parent site's owner).
  --yes                 Confirm route removal. Application files are retained.
  --dry-run             Validate and preview without changing configuration.
  --help                Show this help.
Update preserves omitted project/runtime/user options. Remove never deletes project data.
EOF
}
function lemper_site_app_state_root() { printf '%s\n' "${LEMPER_SITE_APP_STATE_DIR:-/etc/lemper/site-apps}"; }
function lemper_site_app_read() {
    local domain="$1" mount="$2" file key value marker="" recorded_domain="" recorded_mount=""
    file="$(lemper_site_app_state_root)/$domain/${mount#/}.conf"
    LEMPER_APP_OWNER="" LEMPER_APP_WEBROOT="" LEMPER_APP_RUNTIME=""
    [[ -f "$file" && ! -L "$file" ]] || { error "Managed application mount not found."; return 1; }
    while IFS=$'\t' read -r key value; do
        case "$key" in
            OWNER_MARKER) marker="$value" ;; DOMAIN) recorded_domain="$value" ;; MOUNT) recorded_mount="$value" ;;
            OWNER) LEMPER_APP_OWNER="$value" ;; WEBROOT) LEMPER_APP_WEBROOT="$value" ;; RUNTIME) LEMPER_APP_RUNTIME="$value" ;;
        esac
    done < <(safe_parse_dotenv "$file")
    [[ "$marker" == lemper-app-v1 && "$recorded_domain" == "$domain" && "$recorded_mount" == "$mount" ]] || return 1
}
function lemper_site_app_apply() {
    local action="$1" domain="$2" mount="$3" project="$4" runtime="$5" owner="$6"
    local state fragment public="" socket="" metadata="" root key value parent_runtime="" path_pattern='^/[A-Za-z0-9_./ -]+$'
    root=$(lemper_site_app_state_root)
    state="$root/$domain/${mount#/}.conf"
    fragment="$(lemper_nginx_app_dir "$domain")/${mount#/}.conf"
    if [[ "$action" == add ]]; then
        [[ ! -e "$state" && ! -L "$state" && ! -e "$fragment" && ! -L "$fragment" ]] || {
            error "Application mount already exists; use update."; return 1;
        }
    else
        lemper_site_app_read "$domain" "$mount" || return 1
        [[ -f "$fragment" && ! -L "$fragment" ]] || { error "Managed application configuration is missing or unsafe."; return 1; }
    fi
    if [[ "$action" != remove ]]; then
        if ! lemper_nginx_site_exists "$domain" || ! lemper_site_read_state "$domain"; then
            error "A managed parent site is required; create or adopt it first."; return 1
        fi
        while IFS=$'\t' read -r key value; do
            [[ "$key" != RUNTIME ]] || parent_runtime="$value"
        done < <(safe_parse_dotenv "${LEMPER_SITE_STATE_DIR:-/etc/lemper/sites}/$domain.conf")
        if [[ "$action" == update ]]; then
            owner="${owner:-$LEMPER_APP_OWNER}"; project="${project:-$LEMPER_APP_WEBROOT}"; runtime="${runtime:-$LEMPER_APP_RUNTIME}"
        fi
        owner="${owner:-$LEMPER_SITE_OWNER}"; runtime="${runtime:-${parent_runtime:-php@${DEFAULT_PHP_VERSION:-8.5}}}"
        if ! is_valid_username "$owner" || [[ "$owner" == root ]]; then
            error "An existing non-root runtime user is required."; return 1
        fi
        [[ "$runtime" =~ ^php@(8\.[2-5])$ ]] || { error "Runtime must be php@8.2-8.5."; return 1; }
        local version="${BASH_REMATCH[1]}"
        [[ "$project" =~ $path_pattern ]] || { error "Invalid application path."; return 1; }
        project=$(safe_webroot "$project" "$owner") || { error "Application root must be an existing directory owned by its runtime user."; return 1; }
        [[ "$project" =~ $path_pattern && -d "$project/public" && ! -L "$project/public" && -f "$project/public/index.php" ]] || {
            error "Laravel needs a public directory and its index.php front controller."; return 1;
        }
        public="$project/public"
        socket=$(lemper_php_pool_socket "$version" "$owner") || return 1
        lemper_nginx_app_policy_check "$domain" || return 1
    fi
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would $action Laravel mount $domain$mount ($runtime, user $owner, project $project); project data retained."
        return 0
    fi
    if [[ "$action" != remove ]]; then
        metadata=$(mktemp) || return 1
        if ! printf 'OWNER_MARKER=lemper-app-v1\nDOMAIN=%s\nMOUNT=%s\nTYPE=laravel\nOWNER=%s\nWEBROOT=%s\nPUBLIC_ROOT=%s\nRUNTIME=%s\n' \
            "$domain" "$mount" "$owner" "$project" "$public" "$runtime" > "$metadata"; then rm -f "$metadata"; return 1; fi
    fi
    local rc=0
    lemper_nginx_app_publish "$domain" "$mount" "$public" "$socket" "$metadata" "$action" || rc=$?
    [[ -z "$metadata" ]] || rm -f "$metadata"
    [[ "$rc" == 0 ]] || return "$rc"
    success "Application mount $domain$mount: $action completed; project data retained."
}
function lemper_site_app_list() {
    local domain="$1" file mount key value
    for file in "$(lemper_site_app_state_root)/$domain"/*.conf; do
        [[ -f "$file" ]] || continue
        mount=""
        while IFS=$'\t' read -r key value; do [[ "$key" != MOUNT ]] || mount="$value"; done < <(safe_parse_dotenv "$file")
        [[ "$mount" =~ ^/[a-z][a-z0-9_-]{0,63}$ ]] || return 1
        lemper_site_app_read "$domain" "$mount" || return 1
        printf '%s\t%s\t%s\t%s\n' "$mount" "$LEMPER_APP_RUNTIME" "$LEMPER_APP_OWNER" "$LEMPER_APP_WEBROOT"
    done
}
function init_lemper_site_app() {
    local action="${1:-help}" argument domain="" mount="" project="" runtime="" owner="" type=laravel yes=false
    local DRYRUN="${DRYRUN:-false}"
    local -A seen=()
    [[ $# == 0 ]] || shift
    case "$action" in help|-h|--help) lemper_site_app_help; return 0 ;; add|update|remove|list) ;; *) error "Unknown site app operation."; return 1 ;; esac
    lemper_parse_args hy 'help,mount:,type:,webroot:,runtime:,runtime-user:,yes,dry-run' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            -h|--help) lemper_site_app_help; return 0 ;;
            --dry-run) DRYRUN=true ;;
            -y|--yes) yes=true ;;
            --) [[ $# == 1 ]] || { error "Specify one parent domain."; return 1; }; domain="$1"; break ;;
            *)
                [[ -z "${seen[$argument]:-}" ]] || { error "Duplicate application option."; return 1; }
                seen[$argument]=true
                case "$argument" in --mount) mount="$1" ;; --webroot) project="$1" ;; --runtime) runtime="$1" ;; --runtime-user) owner="$1" ;; --type) type="$1" ;; esac
                shift ;;
        esac
    done
    is_valid_domain "$domain" || { error "Invalid parent domain."; return 1; }
    [[ "$type" == laravel ]] || { error "Only Laravel application mounts are supported."; return 1; }
    lemper_load_module services/nginx/apps || return 1
    lemper_load_module services/php/lifecycle || return 1
    if [[ "$action" == list ]]; then
        [[ -z "$mount$project$runtime$owner" ]] || { error "List accepts only a domain."; return 1; }
        lemper_site_app_list "$domain"; return $?
    fi
    [[ "$mount" =~ ^/[a-z][a-z0-9_-]{0,63}$ ]] || { error "Mount must be one lowercase URL segment, e.g. /demo."; return 1; }
    case "$mount" in /lcp|/php-fpm_status|/php-fpm_ping|/nginx_status) error "Reserved management path."; return 1 ;; esac
    if [[ "$action" == remove ]]; then
        [[ -z "$project$runtime$owner" ]] || { error "Remove accepts only the domain and mount."; return 1; }
        if [[ "$yes" != true && "$DRYRUN" != true ]]; then
            local answer
            read -rp "Remove application route $domain$mount (retain project data)? [y/N]: " answer || return 1
            [[ "$answer" == y || "$answer" == Y ]] || return 1
        fi
    fi
    lemper_with_lock lemper_site_app_apply "$action" "$domain" "$mount" "$project" "$runtime" "$owner"
}
