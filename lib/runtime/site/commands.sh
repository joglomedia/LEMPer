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



function lemper_site_help() {
    cat <<EOF
Usage: ${CMD_PARENT:-lemperctl} site <create|list|show|update|enable|disable|remove|adopt|app> [OPTIONS] DOMAIN [DOMAIN...]
Create: --type TYPE --runtime php@VERSION --runtime-user USER --install-skeleton --webroot PATH
Update: --ssl-enable/disable/remove/renew, --cors-enable/disable, --fastcgi-cache-enable/disable
        --enable/disable; verb-first legacy flags remain accepted.
Remove: --purge deletes recorded site-owned data; --yes bypasses confirmation.
Adopt: DOMAIN --runtime-user USER --runtime php@VERSION [--webroot PATH] records existing ownership.
All mutation commands accept --dry-run. Aliases: add, manage, mod, delete.
App: add/update/remove/list DOMAIN --mount /NAME; existing Laravel projects only. See site app --help.
EOF
}
function lemper_site_action_name() {
    case "$1" in
        --enable|-e) echo enable ;; --disable|-d) echo disable ;;
        --ssl-enable|--enable-ssl|-s) echo ssl-enable ;;
        --ssl-disable|--disable-ssl) echo ssl-disable ;;
        --ssl-remove|--remove-ssl) echo ssl-remove ;;
        --ssl-renew|--renew-ssl) echo ssl-renew ;;
        --cors-enable|--enable-cors) echo cors-enable ;;
        --cors-disable|--disable-cors) echo cors-disable ;;
        --fastcgi-cache-enable|--enable-fastcgi-cache|-c) echo fastcgi-cache-enable ;;
        --fastcgi-cache-disable|--disable-fastcgi-cache) echo fastcgi-cache-disable ;;
        --enable-fail2ban|-f) echo fail2ban-enable ;; --disable-fail2ban) echo fail2ban-disable ;;
        --enable-modsec) echo modsec-enable ;; --disable-modsec) echo modsec-disable ;;
        --enable-brotli|-b) echo brotli-enable ;; --enable-gzip|-g) echo gzip-enable ;;
        --disable-compression) echo compression-disable ;;
        *) return 1 ;;
    esac
}

function lemper_site_create() {
    local domain="" owner="" webroot="" type="" php="" skeleton=false ssl=false argument value
    local DRYRUN="${DRYRUN:-false}" key
    local -A fields=()
    local legacy=() operands=()
    lemper_parse_args 'u:d:e:f:4:6:w:p:iScsFWDhv' \
        'username:,domain-name:,admin-email:,framework:,ipv4:,ipv6:,webroot:,php-version:,install-app,subdomains,enable-fastcgi-cache,enable-ssl,enable-fail2ban,wildcard-domain,dryrun,dry-run,type:,runtime:,runtime-user:,install-skeleton,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            -h|--help) lemper_site_help; return 0 ;;
            -v|--version) echo "site version ${PROG_VERSION:-}"; return 0 ;;
            --) operands=("$@"); break ;;
            --dry-run|--dryrun|-D) DRYRUN=true ;;
            --install-skeleton|--install-app|-i) skeleton=true ;;
            --enable-ssl|-s) ssl=true ;;
            --runtime)
                [[ "$1" =~ ^php@([0-9]+\.[0-9]+)$ ]] || { error "Runtime must be php@VERSION."; return 1; }
                key=php; value="${BASH_REMATCH[1]}"; shift ;;
            --php-version|-p) key=php; value="$1"; shift ;;
            --type|--framework|-f) key="type"; value="$1"; shift ;;
            --runtime-user|--username|-u) key=owner; value="$1"; shift ;;
            --domain-name|-d) key=domain; value="$1"; shift ;;
            --webroot|-w) key=webroot; value="$1"; shift ;;
            --admin-email|-e|--ipv4|-4|--ipv6|-6) legacy+=("$argument" "$1"); shift ;;
            *) legacy+=("$argument") ;;
        esac
        if [[ -n "${key:-}" ]]; then
            [[ -z "${fields[$key]+set}" || "${fields[$key]}" == "$value" ]] ||
                { error "Conflicting $key values."; return 1; }
            fields[$key]="$value"; key=""
        fi
    done
    [[ ${#operands[@]} -le 1 ]] || { error "Create accepts one domain."; return 1; }
    domain="${fields[domain]:-${operands[0]:-}}"
    [[ ${#operands[@]} -eq 0 || "$domain" == "${operands[0]}" ]] || { error "Conflicting domains."; return 1; }
    is_valid_domain "$domain" || { error "Invalid or missing site domain."; return 1; }
    owner="${fields[owner]:-${LEMPER_USERNAME:-lemper}}"
    is_valid_username "$owner" || { error "Invalid runtime user."; return 1; }
    type="${fields[type]:-default}" php="${fields[php]:-${DEFAULT_PHP_VERSION:-8.5}}"
    case "$type" in default|codeigniter|drupal|laravel|lumen|phalcon|phalcon-cli|phalcon-micro|phalcon-modules|wordpress|woocommerce|wordpress-ms|symfony|owncloud|mautic|roundcube|sendy) ;;
        *) error "Unsupported site type: $type"; return 1 ;; esac
    lemper_load_module services/php/lifecycle || return 1
    lemper_php_supported "$php" || { error "Supported PHP versions are 8.2-8.5."; return 1; }
    webroot="${fields[webroot]:-/home/$owner/webapps/$domain}"
    [[ "$webroot" == /* && "$webroot" != *$'\n'* && "$webroot" != *$'\r'* && "$webroot" != *$'\t'* &&
       "$webroot" != *[\"\'\\\$]* ]] ||
        { error "Invalid webroot."; return 1; }
    legacy+=(--domain-name "$domain" --username "$owner" --framework "$type" --php-version "$php" --webroot "$webroot")
    [[ "$skeleton" != true ]] || legacy+=(--install-app)
    if [[ "$DRYRUN" == true ]]; then
        info "Would create $domain ($type, php@$php, user $owner, root $webroot)."
        return 0
    fi
    lemper_with_lock lemper_site_create_execute "$domain" "$owner" "$webroot" "$php" "$skeleton" "$ssl" "${legacy[@]}"
}
function lemper_site_create_execute() {
    local domain="$1" owner="$2" webroot="$3" php="$4" skeleton="$5" ssl="$6"
    shift 6
    lemper_nginx_site_exists "$domain" && { error "Site already exists."; return 1; }
    lemper_exec install -d -m 0755 "${LEMPER_NGINX_DIR:-/etc/nginx}/site-apps" || return 1
    lemper_legacy_site_create "$@" || return 1
    lemper_nginx_site_exists "$domain" || { error "Site creation did not produce configuration."; return 1; }
    if [[ "$ssl" == true ]]; then
        lemper_legacy_site_action ssl-enable "$domain" || return 1
        lemper_nginx_site_reload || return 1
    fi
    nginx -t || return 1
    # Record the actual document root, since framework branches may append /public.
    local actual
    actual=$(lemper_nginx_site_webroots "${LEMPER_NGINX_DIR:-/etc/nginx}/sites-available/$domain.conf")
    [[ -z "$actual" ]] || webroot="$actual"
    lemper_site_record "$domain" "$owner" "$webroot" "php@$php" "$skeleton"
}

function lemper_site_change() {
    local operation="$1" argument action group domain purge=false yes=false
    local DRYRUN="${DRYRUN:-false}"
    shift
    local -A actions=() groups=()
    local domains=() normalized=()
    local legacy_started=false legacy_domain=false name operand
    # Preserve legacy flag=value/attached short-domain forms. A legacy action
    # followed by a domain and another action is ambiguous: reject cross-target
    # expansion rather than silently changing its old first-action behavior.
    for argument in "$@"; do
        name="${argument%%=*}"
        case "$argument" in
            --remove|-r) operation=remove; continue ;;
            --remove=*) operation=remove; normalized+=("${argument#*=}"); continue ;;
        esac
        action=""
        if [[ "$name" == --enable* || "$name" == --disable* || "$name" == --renew-ssl || "$name" == --remove-ssl ]]; then
            action=$(lemper_site_action_name "$name") || return 1
            [[ "$legacy_domain" != true ]] || { error "Ambiguous legacy action/domain pairs; use feature-first flags and a target list."; return 1; }
            legacy_started=true
            if [[ "$argument" == *=* ]]; then
                normalized+=("--$action" "${argument#*=}")
                legacy_domain=true
                continue
            fi
        elif [[ "$argument" == -[scdefr]?* ]] && is_valid_domain "${argument:2}"; then
            name="${argument:0:2}" operand="${argument:2}"
            if [[ "$name" == -r ]]; then operation=remove; normalized+=("$operand"); continue; fi
            action=$(lemper_site_action_name "$name") || return 1
            normalized+=("--$action" "$operand")
            legacy_started=true legacy_domain=true
            continue
        elif lemper_site_action_name "$argument" >/dev/null 2>&1; then
            case "$argument" in -s|-c|-d|-e|-f) legacy_started=true ;; esac
            [[ "$legacy_domain" != true ]] || { error "Ambiguous legacy action/domain pairs; use feature-first flags and a target list."; return 1; }
        elif [[ "$argument" != -* && "$legacy_started" == true ]]; then
            legacy_domain=true
        fi
        normalized+=("$argument")
    done
    lemper_parse_args 'cdefsbghvyp' \
        'enable,disable,ssl-enable,ssl-disable,ssl-remove,ssl-renew,cors-enable,cors-disable,fastcgi-cache-enable,fastcgi-cache-disable,enable-ssl,disable-ssl,remove-ssl,renew-ssl,enable-cors,disable-cors,enable-fastcgi-cache,disable-fastcgi-cache,enable-fail2ban,disable-fail2ban,enable-modsec,disable-modsec,enable-brotli,enable-gzip,disable-compression,purge,yes,dry-run,help,version' "${normalized[@]}" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            -h|--help) lemper_site_help; return 0 ;;
            -v|--version) echo "site version ${PROG_VERSION:-}"; return 0 ;;
            --dry-run) DRYRUN=true ;;
            --purge|-p) purge=true ;;
            --yes|-y) yes=true ;;
            --) domains=("$@"); break ;;
            *)
                action=$(lemper_site_action_name "$argument") || return 1
                group="${action%-*}"
                case "$action" in enable|disable) group=state ;; brotli-enable|gzip-enable|compression-disable) group=compression ;; esac
                [[ -z "${groups[$group]:-}" || "${groups[$group]}" == "$action" ]] ||
                    { error "Conflicting $group actions."; return 1; }
                groups[$group]="$action"; actions[$action]=true ;;
        esac
    done
    [[ ${#domains[@]} -gt 0 ]] || { error "At least one site domain is required."; return 1; }
    if [[ "$operation" == remove ]]; then
        [[ ${#actions[@]} -eq 0 ]] || { error "Remove does not accept update actions."; return 1; }
    else
        [[ "$purge" != true ]] || { error "--purge requires site remove."; return 1; }
        [[ ${#actions[@]} -gt 0 ]] || { error "At least one site action is required."; return 1; }
    fi
    for domain in "${domains[@]}"; do
        is_valid_domain "$domain" || { error "Invalid site domain: $domain"; return 1; }
        if ! lemper_nginx_site_exists "$domain"; then
            if [[ "$operation" != remove ]]; then
                error "Site not found: $domain"
                return 1
            fi
            lemper_site_read_state "$domain" || { error "Site not found: $domain"; return 1; }
        fi
        if [[ "$purge" == true ]]; then lemper_site_purge_preflight "$domain" || return 1; fi
    done
    # Stable order independent of argument ordering; domains/actions are deduplicated.
    local ordered=() candidates=(disable ssl-disable ssl-remove ssl-renew ssl-enable fastcgi-cache-disable fastcgi-cache-enable \
        cors-disable cors-enable fail2ban-disable fail2ban-enable modsec-disable modsec-enable compression-disable gzip-enable brotli-enable enable)
    for action in "${candidates[@]}"; do [[ -z "${actions[$action]:-}" ]] || ordered+=("$action"); done
    if [[ "$DRYRUN" == true ]]; then
        for domain in "${domains[@]}"; do info "Would $operation $domain (actions: ${ordered[*]}; purge: $purge)."; done
        return 0
    fi
    if [[ "$operation" == remove && "$yes" != true ]]; then
        local answer
        read -rp "Remove ${domains[*]} (purge=$purge)? [y/N]: " answer || return 1
        [[ "$answer" == y || "$answer" == Y ]] || return 1
    fi
    lemper_with_lock lemper_site_change_execute "$operation" "$purge" domains ordered
}

function lemper_site_change_execute() {
    local operation="$1" purge="$2" backup domain action rc=0
    local -n targets="$3" requested="$4"
    local -A seen=()
    local unique=()
    if [[ "$purge" == true ]]; then
        for domain in "${targets[@]}"; do lemper_site_purge_preflight "$domain" || return 1; done
    fi
    backup=$(mktemp -d) || return 1
    for domain in "${targets[@]}"; do
        [[ -z "${seen[$domain]:-}" ]] || continue
        seen[$domain]=true
        lemper_nginx_site_snapshot "$domain" "$backup/$domain" || { rm -rf "$backup"; return 1; }
        unique+=("$domain")
    done
    # Prepare all recovery snapshots before the first target is changed.
    for domain in "${unique[@]}"; do
        if [[ "$operation" == remove ]]; then
            if ! lemper_nginx_site_unregister "$domain"; then
                lemper_nginx_site_restore "$domain" "$backup/$domain" || error "Configuration restore failed for $domain."
                rc=1
            fi
        else
            for action in "${requested[@]}"; do
                if ! lemper_legacy_site_action "$action" "$domain"; then
                    error "$domain: $action failed; restoring site configuration."
                    lemper_nginx_site_restore "$domain" "$backup/$domain" || error "Configuration restore failed for $domain."
                    rc=1
                    break
                fi
            done
        fi
    done
    if ! lemper_nginx_site_reload; then
        for domain in "${!seen[@]}"; do
            lemper_nginx_site_restore "$domain" "$backup/$domain" || error "Configuration restore failed for $domain."
        done
        error "Batch reload failed; site configuration restored. External effects may remain."
        lemper_nginx_site_reload || error "Reload of restored configuration failed."
        rm -rf "$backup"
        return 1
    fi
    if [[ "$operation" == remove && "$rc" -eq 0 ]]; then
        for domain in "${!seen[@]}"; do
            if [[ "$purge" == true ]]; then
                lemper_site_purge_data "$domain" || { error "$domain: purge incomplete; ownership metadata retained."; rc=1; }
            else
                info "$domain unregistered; application data and ownership metadata retained."
            fi
        done
    fi
    rm -rf "$backup"
    return "$rc"
}

function lemper_site_adopt() {
    local owner="" webroot="" runtime="" yes=false domain argument actual
    local DRYRUN="${DRYRUN:-false}"
    lemper_parse_args hyv 'runtime-user:,webroot:,runtime:,yes,dry-run,help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"
    while [[ $# -gt 0 ]]; do
        argument="$1"; shift
        case "$argument" in
            -h|--help) lemper_site_help; return 0 ;;
            -v|--version) echo "site version ${PROG_VERSION:-}"; return 0 ;;
            --runtime-user) owner="$1"; shift ;;
            --webroot) webroot="$1"; shift ;;
            --runtime) runtime="$1"; shift ;;
            --dry-run) DRYRUN=true ;;
            -y|--yes) yes=true ;;
            --) [[ $# -eq 1 ]] || { error "Adopt requires one domain."; return 1; }; domain="$1"; break ;;
        esac
    done
    if ! is_valid_domain "$domain" || ! is_valid_username "$owner"; then
        error "Adopt requires a domain and --runtime-user."
        return 1
    fi
    lemper_nginx_site_exists "$domain" || { error "Site not found."; return 1; }
    [[ "$runtime" =~ ^php@[0-9]+\.[0-9]+$ ]] || { error "Adopt requires --runtime php@VERSION."; return 1; }
    actual=$(lemper_nginx_site_webroots "${LEMPER_NGINX_DIR:-/etc/nginx}/sites-available/$domain.conf")
    [[ -n "$webroot" ]] || webroot="$actual"
    webroot=$(safe_webroot "$webroot" "$owner") || { error "Invalid or incorrectly owned webroot."; return 1; }
    [[ -n "$actual" && "$(realpath -m -- "$actual")" == "$webroot" ]] ||
        { error "Adopt webroot must match the configured document root."; return 1; }
    if [[ "$DRYRUN" == true ]]; then info "Would record ownership of $domain for $owner ($webroot)."; return 0; fi
    if [[ "$yes" != true ]]; then
        local answer
        read -rp "Assert ownership of $domain, $webroot and its recorded application database? [y/N]: " answer || return 1
        [[ "$answer" == y || "$answer" == Y ]] || return 1
    fi
    lemper_with_lock lemper_site_record "$domain" "$owner" "$webroot" "$runtime" true
}

function init_lemper_site() {
    local operation="${1:-help}"
    [[ $# -eq 0 ]] || shift
    case "$operation" in
        help|-h|--help) lemper_site_help; return 0 ;;
        version|-v|--version) echo "${CMD_PARENT:-lemperctl} site version ${PROG_VERSION:-}"; return 0 ;;
        add) operation=create ;; manage|mod) operation=update ;; delete) operation=remove ;;
    esac
    # Explicit internal dependencies are loaded only for a selected use case.
    local root
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || return 1
    # shellcheck source=/dev/null
    . "$root/compat/site.sh" || return 1
    # shellcheck source=/dev/null
    . "$root/services/nginx/site.sh" || return 1
    # shellcheck source=/dev/null
    . "$root/runtime/site/state.sh" || return 1
    case "$operation" in
        app)
            lemper_load_module runtime/site/apps || return 1
            init_lemper_site_app "$@" ;;
        create) lemper_site_create "$@" ;;
        adopt) lemper_site_adopt "$@" ;;
        update|remove) lemper_site_change "$operation" "$@" ;;
        enable|disable) lemper_site_change update "--$operation" "$@" ;;
        list|show|db|database)
            local plugin="$operation"
            [[ "$plugin" != database ]] || plugin=db
            [[ "$plugin" == db ]] || plugin="site-$plugin"
            (
                # Preserve exits/status from existing read/database plugins.
                # shellcheck source=/dev/null
                . "$root/lemper-$plugin.sh" "$@"
            ) ;;
        *) error "Unknown site operation: $operation"; return 1 ;;
    esac
}
