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



# Metadata contains ownership, not credentials. Older sites must be reconciled
# before unattended purge; guessing a database or owner from a domain is unsafe.
function lemper_site_record() {
    local domain="$1" owner="$2" webroot="$3" runtime="$4" skeleton="$5"
    local state="${LEMPER_SITE_STATE_DIR:-/etc/lemper/sites}" temporary key value db=""
    local app="/etc/lemper/vhost.d/$domain.conf"
    if [[ "$skeleton" == true && -f "$app" ]]; then
        while IFS=$'\t' read -r key value; do
            [[ "$key" != APP_DB_NAME ]] || db="$value"
        done < <(safe_parse_dotenv "$app")
    fi
    [[ -z "$db" || "$db" =~ ^app_[a-z0-9]+$ ]] || { error "Cannot record database ownership."; return 1; }
    install -d -m 0700 "$state" || return 1
    temporary=$(mktemp "$state/.site.XXXXXX") || return 1
    if ! printf 'OWNER_MARKER=lemper-site-v1\nDOMAIN=%s\nOWNER=%s\nWEBROOT=%s\nRUNTIME=%s\nDATABASE=%s\n' \
        "$domain" "$owner" "$webroot" "$runtime" "$db" > "$temporary" ||
       ! chmod 0600 "$temporary" || ! mv -T "$temporary" "$state/$domain.conf"; then
        rm -f "$temporary"
        return 1
    fi
}
function lemper_site_read_state() {
    local domain="$1" key value file="${LEMPER_SITE_STATE_DIR:-/etc/lemper/sites}/$1.conf"
    LEMPER_SITE_OWNER="" LEMPER_SITE_WEBROOT="" LEMPER_SITE_DATABASE=""
    local marker="" recorded=""
    [[ -f "$file" && ! -L "$file" ]] ||
        { error "Site ownership metadata required for purge; reconcile $domain first."; return 1; }
    while IFS=$'\t' read -r key value; do
        case "$key" in
            OWNER_MARKER) marker="$value" ;;
            DOMAIN) recorded="$value" ;;
            OWNER) LEMPER_SITE_OWNER="$value" ;;
            WEBROOT) LEMPER_SITE_WEBROOT="$value" ;;
            DATABASE) LEMPER_SITE_DATABASE="$value" ;;
        esac
    done < <(safe_parse_dotenv "$file")
    [[ "$marker" == lemper-site-v1 && "$recorded" == "$domain" ]] || return 1
    is_valid_username "$LEMPER_SITE_OWNER" || return 1
    [[ -z "$LEMPER_SITE_DATABASE" || "$LEMPER_SITE_DATABASE" =~ ^app_[a-z0-9]+$ ]] || return 1
}

function lemper_site_purge_preflight() {
    local domain="$1" file key value
    lemper_site_read_state "$domain" || return 1
    LEMPER_SITE_WEBROOT=$(safe_webroot "$LEMPER_SITE_WEBROOT" "$LEMPER_SITE_OWNER") ||
        { error "Refusing unsafe or incorrectly owned website root."; return 1; }
    # Protect shared roots and ancestor/descendant trees, including legacy sites.
    for file in "${LEMPER_NGINX_DIR:-/etc/nginx}"/sites-available/*.conf; do
        [[ -f "$file" && "$file" != */"$domain.conf" ]] || continue
        while IFS= read -r value; do
            [[ -n "$value" ]] || continue
            value=$(realpath -m -- "$value") || return 1
            case "$value/" in "$LEMPER_SITE_WEBROOT/"|"$LEMPER_SITE_WEBROOT/"*) error "Shared webroot referenced by $file."; return 1 ;; esac
            case "$LEMPER_SITE_WEBROOT/" in "$value/"*) error "Overlapping webroot referenced by $file."; return 1 ;; esac
        done < <(lemper_nginx_site_webroots "$file")
    done
    if [[ -n "$LEMPER_SITE_DATABASE" ]]; then
        for file in "${LEMPER_SITE_STATE_DIR:-/etc/lemper/sites}"/*.conf /etc/lemper/vhost.d/*.conf; do
            [[ -f "$file" && "$file" != */"$domain.conf" ]] || continue
            while IFS=$'\t' read -r key value; do
                if [[ "$key" == DATABASE || "$key" == APP_DB_NAME ]] && [[ "$value" == "$LEMPER_SITE_DATABASE" ]]; then
                    error "Shared database referenced by $file."
                    return 1
                fi
            done < <(safe_parse_dotenv "$file")
        done
        if [[ "${DRYRUN:-false}" != true ]]; then
            MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-}" mysql -u root -Nse 'SELECT 1' >/dev/null ||
                { error "Database access required before purge."; return 1; }
        fi
    fi
}
function lemper_site_purge_data() {
    local domain="$1"
    lemper_site_read_state "$domain" || return 1
    if [[ -n "$LEMPER_SITE_DATABASE" ]]; then
        MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-}" lemper_exec mysql -u root -e \
            "DROP DATABASE IF EXISTS \`$LEMPER_SITE_DATABASE\`;" || return 1
    fi
    # Drop privileges for the entire recursive operation, preserving the existing guard.
    # Legacy deletion calls run() indirectly; keep its dry-run semantics.
    # shellcheck disable=SC2329
    ( function run() { lemper_exec "$@"; }; delete_site_webroot "$LEMPER_SITE_WEBROOT" "$LEMPER_SITE_OWNER" ) || return 1
    lemper_exec rm -f -- "${LEMPER_SITE_STATE_DIR:-/etc/lemper/sites}/$domain.conf" \
        "/etc/lemper/vhost.d/$domain.conf"
}
