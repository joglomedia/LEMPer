#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Nginx Application Mount Driver                                   |
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

function lemper_nginx_app_dir() { printf '%s/site-apps/%s\n' "${LEMPER_NGINX_DIR:-/etc/nginx}" "$1"; }
function lemper_nginx_app_template() {
    local root
    root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd) || return 1
    printf '%s/etc/nginx/vhost/app_laravel.conf\n' "$root"
}
function lemper_nginx_app_render() {
    local mount="$1" public="$2" socket="$3" template
    template=$(lemper_nginx_app_template) || return 1
    # Validated values have no sed replacement or Nginx expression characters.
    sed -e "s|@MOUNT@|$mount|g" -e "s|@NAME@|${mount#/}|g" \
        -e "s|@PUBLIC@|$public|g" -e "s|@SOCKET@|$socket|g" "$template"
}

# Prefix locations do not inherit sibling location policies. Refuse detected
# per-location authentication/access controls instead of silently bypassing them.
# Server-level policies are inherited; generated FPM monitoring keeps its own ACL.
function lemper_nginx_app_policy_check() {
    local domain="$1" root="${LEMPER_NGINX_DIR:-/etc/nginx}" file included
    for file in "$root/sites-available/$domain".{conf,nonssl-conf,ssl-conf}; do
        [[ -f "$file" ]] || continue
        if ! awk '
            /^[[:space:]]*#/ { next }
            /^    location[[:space:]]/ { monitor=($0 ~ /location[[:space:]]+~[[:space:]]+\^\/php-fpm_/) }
            /^    }/ { monitor=0 }
            !monitor && /(^|[;{[:space:]])(auth_basic|auth_request|satisfy|allow|deny|access_by_lua)[[:space:]]/ {
                if ($0 !~ /^    (auth_basic|auth_request|satisfy|allow|deny|access_by_lua)[[:space:]]/) bad=1
            }
            END { exit bad }
        ' "$file"; then
            error "Per-location access controls require explicit mount policy integration; configuration retained."
            return 1
        fi
        # The root location is commonly provided by a framework include.
        while IFS= read -r included; do
            included="${included#\"}"; included="${included%\"}"
            [[ -f "$included" ]] || continue
            if awk '
                /^[[:space:]]*#/ { next }
                /(^|[;{[:space:]])(auth_basic|auth_request|satisfy|allow|deny|access_by_lua)[[:space:]]/ { found=1 }
                END { exit !found }
            ' "$included"; then
                error "Framework location access controls require explicit mount policy integration."
                return 1
            fi
        done < <(awk '$1 == "include" && $2 ~ /\/vhost\/site_/ { sub(/;$/, "", $2); print $2 }' "$file")
    done
}

# Extend the known server-level root anchor in generated/adopted vhosts.
# SSL/non-SSL variants must share the hook so later TLS toggles retain mounts.
function lemper_nginx_app_hook() {
    local domain="$1" root="${LEMPER_NGINX_DIR:-/etc/nginx}" file resolved hook temporary count
    local -A seen=()
    lemper_nginx_app_policy_check "$domain" || return 1
    hook="include $root/site-apps/$domain/*.conf;"
    for file in "$root/sites-available/$domain".{conf,nonssl-conf,ssl-conf}; do
        [[ -f "$file" ]] || continue
        resolved=$(readlink -f "$file") || return 1
        case "$resolved" in "$root/sites-available/$domain".conf|"$root/sites-available/$domain".nonssl-conf|"$root/sites-available/$domain".ssl-conf) ;;
            *) error "Refusing a vhost selector outside the known site files."; return 1 ;;
        esac
        [[ -z "${seen[$resolved]:-}" ]] || continue
        seen[$resolved]=true
        grep -Fq "$hook" "$resolved" && continue
        count=$(awk '/^    root[[:space:]]+[^;]+;[[:space:]]*$/ { n++ } END { print n+0 }' "$resolved")
        [[ "$count" == 1 ]] || { error "Vhost needs one generated server-level root anchor before adding an app."; return 1; }
        temporary=$(mktemp "$resolved.app.XXXXXXXX") || return 1
        if ! awk -v hook="$hook" '{ print; if ($0 ~ /^    root[[:space:]]+[^;]+;[[:space:]]*$/) print "    " hook }' \
            "$resolved" > "$temporary" || ! chown --reference="$resolved" "$temporary" ||
            ! chmod --reference="$resolved" "$temporary" || ! lemper_exec mv -Tf "$temporary" "$resolved"; then
            rm -f "$temporary"; return 1
        fi
    done
}

function lemper_nginx_app_publish() {
    local domain="$1" mount="$2" public="$3" socket="$4" metadata="$5" action="$6"
    local directory file backup temporary="" state previous_state="" rc=0
    directory=$(lemper_nginx_app_dir "$domain")
    file="$directory/${mount#/}.conf"
    state="${LEMPER_SITE_APP_STATE_DIR:-/etc/lemper/site-apps}/$domain/${mount#/}.conf"
    backup=$(mktemp -d) || return 1
    lemper_nginx_site_snapshot "$domain" "$backup/site" || { rm -rf "$backup"; return 1; }
    if [[ -e "$file" ]]; then cp -p "$file" "$backup/fragment" || { rm -rf "$backup"; return 1; }; fi
    if [[ -e "$state" ]]; then previous_state=present; cp -p "$state" "$backup/state" || { rm -rf "$backup"; return 1; }; fi
    if [[ "$action" != remove ]]; then
        install -d -m 0755 "$directory" || rc=1
        if [[ "$rc" == 0 ]]; then
            temporary=$(mktemp "$directory/.app.XXXXXXXX") || rc=1
        fi
        if [[ "$rc" == 0 ]]; then
            if ! lemper_nginx_app_render "$mount" "$public" "$socket" > "$temporary" ||
                ! chmod 0644 "$temporary" || ! lemper_exec mv -Tf "$temporary" "$file" ||
                ! lemper_nginx_app_hook "$domain"; then rc=1; fi
        fi
    else lemper_exec rm -f "$file" || rc=1; fi
    if [[ "$rc" == 0 ]]; then lemper_nginx_site_reload || rc=1; fi
    if [[ "$rc" == 0 ]]; then
        if [[ "$action" != remove ]]; then
            install -d -m 0700 "${state%/*}" || rc=1
            if [[ "$rc" == 0 ]]; then lemper_exec mv -Tf "$metadata" "$state" || rc=1; fi
        else lemper_exec rm -f "$state" || rc=1; fi
    fi
    if [[ "$rc" != 0 ]]; then
        lemper_nginx_site_restore "$domain" "$backup/site" || error "Cannot restore the parent vhost."
        if [[ -f "$backup/fragment" ]]; then cp -p "$backup/fragment" "$file"; else rm -f "$file"; fi
        if [[ "$previous_state" == present ]]; then cp -p "$backup/state" "$state"; else rm -f "$state"; fi
        lemper_nginx_site_reload || error "Restored application configuration needs recovery."
        error "Application mount failed; previous vhost and application configuration restored."
    fi
    [[ -z "$temporary" ]] || rm -f "$temporary"
    rm -rf "$backup"
    return "$rc"
}
