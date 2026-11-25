#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Stack Lifecycle Entry Adapter                                    |
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

# Functions only. Legacy source-time initialization stays in disposable children.
function lemper_entry_help() {
    cat <<'HELP'
LEMPer v4 stack lifecycle
Usage: install.sh [--config FILE] [--minimal] [--yes] [--dry-run]
       remove.sh [--config FILE] [--yes] [--dry-run]
       update.sh [--check|--install-only] [--source-dir PATH] [--yes]
       lemper.sh <install|remove|update> [options]
       lemperctl stack <install|remove|update> --all [options]

--config FILE    Configuration profile; defaults to checkout .env or installed config.
--minimal        Install Nginx, PHP, MariaDB, Certbot, Fail2ban and the CLI;
                 skip optional services and web administration panels.
--yes            Unattended installation/removal; SSH key validation still applies.
--dry-run        Validate and print the selected recipe without system changes.
--check-config   Validate the effective profile without installing anything.
--help           Show help without root or configuration.

Legacy lemper.sh installer flags remain available through its isolated adapter.
HELP
}

function lemper_entry_merge_profile() {
    local profile="$1" target="$2"
    local key value decoded="" rc=0
    [[ -r "$profile" ]] || { error "Configuration profile is not readable."; return 1; }
    if is_config_encrypted "$profile"; then
        decoded=$(mktemp) || return 1
        local password
        password=$(resolve_config_password) || { rm -f "$decoded"; return 1; }
        if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
            -pass fd:3 3<<<"$password" -in "$profile" -out "$decoded" 2>/dev/null &&
           ! openssl enc -aes-256-cbc -d -a -salt -md sha256 \
            -pass fd:3 3<<<"$password" -in "$profile" -out "$decoded" 2>/dev/null; then
            secure_shred "$decoded"
            error "Cannot decrypt installed configuration."
            return 1
        fi
        profile="$decoded"
    fi
    if validate_config_file "$profile" compatible; then
        while IFS=$'\t' read -r key value; do
            # Empty template secrets must not erase credentials from an installed config.
            case "$key" in
                *PASSWORD|*_PASS|ACME_DNS_API_TOKEN|RSA_PUB_KEY) [[ -n "$value" ]] || continue ;;
            esac
            set_env_value "$target" "$key" "$value" || { rc=1; break; }
        done < <(safe_parse_dotenv "$profile")
    else
        rc=1
    fi
    [[ -z "$decoded" ]] || secure_shred "$decoded"
    [[ "$rc" -eq 0 ]] || return "$rc"
    return 0
}

function lemper_entry_profile() {
    local root="$1" profile="$2" target="$3" action="$4" yes="$5" minimal="$6"
    local installed="${7:-/etc/lemper/lemper.conf}" key
    cp "$root/.env.dist" "$target" || return 1
    if [[ "$action" == install && -r "$installed" && "$profile" != "$installed" ]]; then
        lemper_entry_merge_profile "$installed" "$target" || return 1
    fi
    lemper_entry_merge_profile "$profile" "$target" || return 1
    if [[ "$minimal" == true ]]; then
        for key in INSTALL_IMAGEMAGICK INSTALL_POSTGRES INSTALL_MEMCACHED INSTALL_MONGODB \
            INSTALL_REDIS INSTALL_BUNJS INSTALL_FTP_SERVER INSTALL_MAILER INSTALL_SPFDKIM \
            INSTALL_RESTIC INSTALL_MONITORING INSTALL_QUOTA INSTALL_CROWDSEC INSTALL_MODSEC INSTALL_WEB_ADMIN NGX_HTTP_BROTLI \
            NGX_HTTP_FANCYINDEX NGX_HTTP_GEOIP NGX_HTTP_HEADERS_MORE NGX_HTTP_IMAGE_FILTER \
            NGX_HTTP_SUBS_FILTER NGX_HTTP_VTS NGX_HTTP_XSLT_FILTER NGX_MAIL NGX_STREAM; do
            set_env_value "$target" "$key" false || return 1
        done
        for key in INSTALL_NGINX INSTALL_PHP INSTALL_MYSQL INSTALL_CERTBOT INSTALL_FAIL2BAN; do
            set_env_value "$target" "$key" true || return 1
        done
        # Use the distro PCRE library instead of building another copy.
        set_env_value "$target" NGINX_PCRE_VERSION "" || return 1
    fi
    if [[ "$yes" == true ]]; then
        [[ "$action" != install ]] || set_env_value "$target" AUTO_INSTALL true || return 1
        [[ "$action" != remove ]] || set_env_value "$target" AUTO_REMOVE true || return 1
    fi
    local mode=compatible
    [[ "$action" != install ]] || mode=install
    validate_config_file "$target" "$mode"
}

function lemper_entry_execute() {
    local action="$1" root="$2" profile="$3"
    export BASE_DIR="$root" LEMPER_ENV_FILE="$profile"
    cd "$root" || return 1
    # Helper/config initialization is deliberately contained inside this child.
    # shellcheck source=/dev/null
    . "$root/scripts/utils.sh" || return 1
    export DRYRUN=false
    preflight_system_check || return 1
    # shellcheck source=/dev/null
    . "$root/lib/runtime/stack/recipe.sh" || return 1
    if [[ "$action" == install ]]; then
        if [[ -L /opt/lemper/current && -x /usr/local/bin/lemperctl &&
              "$(readlink -f /opt/lemper/current)" == "$root" ]]; then
            export LEMPER_TOOLS_SKIP_CLI=true
        fi
        lemper_install
    else
        lemper_remove
    fi
}

function lemper_entry_main() (
    local action="$1" root="$LEMPER_ROOT" config="" yes=false dry=false check=false minimal=false
    local legacy=false argument effective="" original=() update_args=()
    shift
    original=("$@")
    case "$action" in
        help|-h|--help) lemper_entry_help; return 0 ;;
        --install) action=install ;;
        --remove|--uninstall|uninstall) action=remove ;;
        install|remove|update) ;;
        *) echo "Unknown stack operation." >&2; return 1 ;;
    esac
    for argument in "$@"; do
        case "$argument" in --help|-h) lemper_entry_help; return 0 ;; esac
    done
    # Load pure core functions before parsing, without reading any profile.
    # shellcheck source=/dev/null
    . "$root/lib/core/loader.sh" || return 1
    local parser_status=0
    if [[ "${LEMPER_ENTRY_CANONICAL:-false}" == true || "$action" == update ]]; then
        lemper_parse_args 'yh' 'config:,yes,unattended,dry-run,check-config,minimal,source-dir:,check,install-only,post-max-size:,help' "$@" || return 1
    else
        # A legacy grammar mismatch is handled by its adapter, not reported as a
        # canonical command failure before the compatibility parser sees it.
        lemper_parse_args 'yh' 'config:,yes,unattended,dry-run,check-config,minimal,source-dir:,check,install-only,post-max-size:,help' "$@" >/dev/null || parser_status=1
    fi
    if [[ "$parser_status" != 0 ]]; then
        # Compatibility-only getopt grammar remains in the isolated adapter.
        for argument in "${original[@]}"; do
            case "$argument" in --config|--config=*|--dry-run|--check-config|--minimal)
                error "Do not mix legacy installer flags with profile options."; return 1 ;;
            esac
        done
        legacy=true
    else
        set -- "${LEMPER_PARSED_ARGS[@]}"
        while [[ $# -gt 0 ]]; do
            argument="$1"; shift
            case "$argument" in
                --config)
                    [[ -z "$config" ]] || { error "Duplicate --config."; return 1; }
                    config="$1"; shift ;;
                --yes|-y|--unattended) yes=true; update_args+=(--yes) ;;
                --dry-run) dry=true ;;
                --check-config) check=true ;;
                --minimal) minimal=true ;;
                --source-dir|--post-max-size)
                    [[ "$action" == update ]] || { error "Update option requires update."; return 1; }
                    update_args+=("$argument=$1"); shift ;;
                --check|--install-only)
                    [[ "$action" == update ]] || { error "Update option requires update."; return 1; }
                    update_args+=("$argument") ;;
                --help|-h) lemper_entry_help; return 0 ;;
                --)
                    [[ $# -eq 0 ]] || { error "Unexpected stack operand."; return 1; }
                    break ;;
            esac
        done
    fi
    [[ "$minimal" == false || "$action" == install ]] || { echo "--minimal requires install." >&2; return 1; }
    if [[ "$legacy" == true && "$action" != update ]]; then
        [[ -z "$config" && "$dry" == false && "$check" == false && "$minimal" == false ]] ||
            { echo "Do not mix legacy installer flags with profile options." >&2; return 1; }
        export LEMPER_INSTALL_ROOT="$root"
        bash "$root/lib/compat/installer.sh" "$action" "${original[@]}"
        return $?
    fi
    [[ -n "$config" ]] || {
        if [[ "$action" != update && -r "$root/.env" ]]; then config="$root/.env"; else config=/etc/lemper/lemper.conf; fi
    }
    # Core defines functions only; no installer is sourced during validation/dry run.
    # shellcheck source=/dev/null
    . "$root/lib/core/loader.sh" || return 1
    effective=$(mktemp) || return 1
    trap 'secure_shred "$effective"' EXIT
    DRYRUN=false
    lemper_entry_profile "$root" "$config" "$effective" "$action" "$yes" "$minimal" || return 1
    local profile_key profile_value
    while IFS=$'\t' read -r profile_key profile_value; do
        [[ "$profile_key" != DRYRUN || "$profile_value" != true ]] || dry=true
    done < <(safe_parse_dotenv "$effective")
    if [[ "$check" == true ]]; then info "Configuration profile validated."; return 0; fi
    if [[ "$dry" == true ]]; then
        info "Would $action the configured stack; no system changes."
        if [[ "$action" == install ]]; then
            local key value service _installer _remover _units _family
            while IFS=$'\t' read -r key value; do printf -v "$key" '%s' "$value"; done < <(safe_parse_dotenv "$effective")
            while IFS= read -r service; do
                [[ "$service" != ftp ]] || service="$FTP_SERVER_NAME"
                read -r _installer _remover _units key _family < <(lemper_component_spec "$service")
                [[ "$key" == - || "${!key:-false}" == true ]] || continue
                printf '  %s\n' "$service"
            done < <(lemper_component_recipe install)
        fi
        return 0
    fi
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Run the stack operation as root or with sudo." >&2
        return 1
    fi
    if [[ "$action" == update ]]; then
        export LEMPER_INSTALL_ROOT="$root" LEMPER_CONFIG_FILE="$effective"
        lemper_with_lock bash "$root/lib/compat/updater.sh" "${update_args[@]}"
    else
        lemper_with_lock lemper_entry_execute "$action" "$root" "$effective"
    fi
)
