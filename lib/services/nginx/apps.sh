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

# Inspect complete statements and block scope, independent of indentation.
# Return the serving root's line and whether its managed include is present.
function lemper_nginx_app_inspect() {
    local domain="$1" file="$2" root="${LEMPER_NGINX_DIR:-/etc/nginx}"
    local policy include status depth server hook="$root/site-apps/$domain/*.conf"
    local anchor=0 serving_server=0 hooked_server=0
    policy=$(awk '
        BEGIN { OFS="\t" }
        function push() {
            if (word != "") tokens[++count]=word
            word=""
        }
        function clear( i) {
            for (i=1; i<=count; i++) delete tokens[i]
            count=0
        }
        function reject() { invalid=1; exit 1 }
        function statement(end, key) {
            push()
            key=tokens[1]
            if (end == "}") {
                if (count || depth < 1) reject()
                if (depth == 1 && !has_root && !redirect) reject()
                delete block[depth--]
            } else if (!count) {
                reject()
            } else if (end == "{") {
                if (depth == 0 && key == "server" && count == 1) {
                    block[++depth]="server"
                    server++
                    has_root=redirect=0
                } else if (depth >= 1 && key == "location" && count >= 2) {
                    if (depth == 1 && count == 3 && tokens[2] == "~" &&
                        tokens[3] == "^/php-fpm_(status|ping)$") block[++depth]="monitor"
                    else if (depth == 1 && count == 3 && tokens[2] == "~*" &&
                        tokens[3] == "\\.(?:php[0-9]*|phtml|phar)(?:/|$)") block[++depth]="php-deny"
                    else block[++depth]="location"
                } else reject()
            } else if (depth == 0) {
                reject()
            } else if (key == "include" && count == 2) {
                if (tokens[2] ~ /[[:space:]]/) reject()
                print "include", tokens[2], depth, server
            } else if (depth == 1 && key == "root" && count == 2) {
                if (has_root || ++roots != 1) reject()
                print "root", start, NR, server
                has_root=1
            } else if (key ~ /^(auth_basic|auth_basic_user_file|auth_request|auth_delay|satisfy|allow|deny)$/) {
                if (depth != 1 && !(block[depth] == "monitor" && count == 2 &&
                    ((key == "allow" && (tokens[2] == "127.0.0.1" || tokens[2] == "::1")) ||
                     (key == "deny" && tokens[2] == "all")))) reject()
            } else if (key == "return") {
                if (depth == 1 && count == 3 && tokens[2] == "301" &&
                    tokens[3] == "https://$server_name$request_uri") redirect=1
                else if (!(block[depth] == "php-deny" && count == 2 && tokens[2] == "404")) reject()
            } else if (key !~ /^(listen|server_name|ssl_certificate|ssl_certificate_key|ssl_trusted_certificate|ssl_stapling|ssl_stapling_verify|ssl_protocols|ssl_ciphers|http2|http3|access_log|error_log|disable_symlinks|root|alias|index|client_max_body_size|set|try_files|fastcgi_split_path_info|fastcgi_index|fastcgi_pass|fastcgi_param|fastcgi_cache|fastcgi_cache_bypass|fastcgi_no_cache|add_header|expires|error_page|charset)$/) {
                reject()
            }
            clear()
        }
        {
            for (i=1; i<=length; i++) {
                c=substr($0,i,1)
                if (escaped) {
                    # Keep escaped characters distinct from literal directives.
                    word=word "\\" c
                    escaped=0
                } else if (c == "\\") escaped=1
                else if (quote != "") {
                    if (c == quote) quote=""
                    else word=word c
                } else if (c == "#" && word == "") break
                else if (c == "\"" || c == sprintf("%c",39)) quote=c
                else if (c ~ /[[:space:]]/) push()
                else if (c ~ /[;{}]/) statement(c)
                else {
                    if (!count && word == "") start=NR
                    word=word c
                }
            }
            if (escaped || quote != "") reject()
            push()
        }
        END { if (invalid || count || depth || roots != 1) exit 1 }
    ' "$file") || return 1
    while IFS=$'\t' read -r status include depth server; do
        if [[ "$status" == root ]]; then
            # The insertion point must be on its own line, after the root.
            [[ "$include" == "$depth" ]] || return 1
            anchor="$include"
            serving_server="$server"
        elif [[ "$include" == "$hook" || "$include" == "/etc/nginx/site-apps/$domain/*.conf" ]]; then
            [[ "$depth" == 1 && "$hooked_server" == 0 ]] || return 1
            lemper_nginx_app_check_fragments "$domain" || return 1
            hooked_server="$server"
        else
            lemper_nginx_app_check_include "$include" || return 1
        fi
    done <<< "$policy"
    [[ "$anchor" != 0 ]] || return 1
    [[ "$hooked_server" == 0 || "$hooked_server" == "$serving_server" ]] || return 1
    # Never insert on a line that also closes the server or opens a child block.
    sed -n "${anchor}p" "$file" | grep -Eq '^[[:space:]]*root[[:space:]]+[^;]+;[[:space:]]*(#.*)?$' || return 1
    printf '%s %s\n' "$anchor" "$hooked_server"
}

# Only known LEMPer includes are accepted. Compare their installed contents
# and known nested dependencies against the shipped templates.
function lemper_nginx_app_check_include() {
    local include="$1" root="${LEMPER_NGINX_DIR:-/etc/nginx}" relative template source
    [[ "$include" == "$root/"* || "$include" == /etc/nginx/* ]] || return 1
    relative="${include#"$root"/}"
    relative="${relative#/etc/nginx/}"
    [[ "$relative" == fastcgi_params ||
        "$relative" =~ ^includes/(compression_gzip|compression_brotli|fastcgi|monitoring|rules_security|rules_restriction|rules_archives|rules_staticfiles|security_headers|ssl|http3)\.conf$ ||
        "$relative" =~ ^vhost/site_(default|drupal|laravel|phalcon|wordpress|symfony)\.conf$ ]] || return 1
    template=$(lemper_nginx_app_template) || return 1
    source="${template%/vhost/app_laravel.conf}/$relative"
    [[ -f "$root/$relative" && ! -L "$root/$relative" && -f "$source" ]] || return 1
    if ! cmp -s "$source" "$root/$relative"; then
        [[ "$relative" == includes/rules_restriction.conf ]] || return 1
        cmp -s <(sed '/^#include \/etc\/nginx\/includes\/rules_archives.conf;$/s/^#//' "$source") "$root/$relative" ||
            return 1
        lemper_nginx_app_check_include "$root/includes/rules_archives.conf" || return 1
    fi
    case "$relative" in
        includes/rules_security.conf | includes/rules_staticfiles.conf)
            lemper_nginx_app_check_include "$root/includes/security_headers.conf" ;;
        includes/monitoring.conf) lemper_nginx_app_check_include "$root/fastcgi_params" ;;
    esac
}

function lemper_nginx_app_check_fragments() {
    local domain="$1" directory file mount public socket
    directory=$(lemper_nginx_app_dir "$domain") || return 1
    [[ ! -L "$directory" ]] || return 1
    for file in "$directory"/*.conf; do
        [[ -e "$file" || -L "$file" ]] || continue
        [[ -f "$file" && ! -L "$file" ]] || return 1
        mount="${file##*/}"
        mount="/${mount%.conf}"
        [[ "$mount" =~ ^/[a-z][a-z0-9_-]{0,63}$ ]] || return 1
        public=$(sed -n 's/^    root "\(.*\)";$/\1/p' "$file") || return 1
        socket=$(sed -n 's/^    fastcgi_pass unix:\(.*\);$/\1/p' "$file") || return 1
        [[ "$public" =~ ^/[A-Za-z0-9_./\ -]+$ && "$socket" =~ ^/run/php/[A-Za-z0-9_.-]+\.sock$ ]] || return 1
        cmp -s <(lemper_nginx_app_render "$mount" "$public" "$socket") "$file" || return 1
    done
}

function lemper_nginx_app_policy_check() {
    local domain="$1" root="${LEMPER_NGINX_DIR:-/etc/nginx}" file resolved
    if ! lemper_nginx_app_check_include "$root/includes/fastcgi.conf" ||
        ! lemper_nginx_app_check_include "$root/includes/rules_restriction.conf"; then
        error "Unknown Laravel include policy requires explicit mount integration."
        return 1
    fi
    for file in "$root/sites-available/$domain".{conf,nonssl-conf,ssl-conf}; do
        [[ -e "$file" || -L "$file" ]] || continue
        resolved=$(readlink -f "$file") || return 1
        case "$resolved" in "$root/sites-available/$domain".conf|"$root/sites-available/$domain".nonssl-conf|"$root/sites-available/$domain".ssl-conf) ;;
            *) return 1 ;;
        esac
        if ! lemper_nginx_app_inspect "$domain" "$resolved" >/dev/null; then
            error "Per-location access controls or unknown vhost policy require explicit mount integration."
            return 1
        fi
    done
}

# Extend the known server-level root anchor in generated/adopted vhosts.
# SSL/non-SSL variants must share the hook so later TLS toggles retain mounts.
function lemper_nginx_app_hook() {
    local domain="$1" root="${LEMPER_NGINX_DIR:-/etc/nginx}" file resolved hook temporary inspection anchor hooked
    local -A seen=()
    hook="include $root/site-apps/$domain/*.conf;"
    for file in "$root/sites-available/$domain".{conf,nonssl-conf,ssl-conf}; do
        [[ -f "$file" ]] || continue
        resolved=$(readlink -f "$file") || return 1
        case "$resolved" in "$root/sites-available/$domain".conf|"$root/sites-available/$domain".nonssl-conf|"$root/sites-available/$domain".ssl-conf) ;;
            *) error "Refusing a vhost selector outside the known site files."; return 1 ;;
        esac
        [[ -z "${seen[$resolved]:-}" ]] || continue
        seen[$resolved]=true
        inspection=$(lemper_nginx_app_inspect "$domain" "$resolved") || return 1
        read -r anchor hooked <<< "$inspection"
        [[ "$hooked" == 0 ]] || continue
        temporary=$(mktemp "$resolved.app.XXXXXXXX") || return 1
        if ! awk -v hook="$hook" -v anchor="$anchor" '{ print; if (NR == anchor) print "    " hook }' \
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
