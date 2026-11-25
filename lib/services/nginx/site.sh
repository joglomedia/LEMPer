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



function lemper_nginx_site_exists() {
    [[ -f "${LEMPER_NGINX_DIR:-/etc/nginx}/sites-available/$1.conf" ]]
}

function lemper_nginx_site_reload() {
    nginx -t || return 1
    lemper_exec systemctl reload nginx
}

# Snapshot only configuration this adapter can restore; external effects remain explicit.
function lemper_nginx_site_snapshot() {
    local domain="$1" backup="$2" root="${LEMPER_NGINX_DIR:-/etc/nginx}" dir suffix
    for dir in sites-available sites-enabled; do
        mkdir -p "$backup/$dir" || return 1
        for suffix in conf nonssl-conf ssl-conf; do
            if [[ -e "$root/$dir/$domain.$suffix" || -L "$root/$dir/$domain.$suffix" ]]; then
                cp -a -- "$root/$dir/$domain.$suffix" "$backup/$dir/" || return 1
            fi
        done
    done
}
function lemper_nginx_site_restore() {
    local domain="$1" backup="$2" root="${LEMPER_NGINX_DIR:-/etc/nginx}" dir suffix
    for dir in sites-available sites-enabled; do
        for suffix in conf nonssl-conf ssl-conf; do
            rm -f -- "$root/$dir/$domain.$suffix" || return 1
            if [[ -e "$backup/$dir/$domain.$suffix" || -L "$backup/$dir/$domain.$suffix" ]]; then
                cp -a -- "$backup/$dir/$domain.$suffix" "$root/$dir/" || return 1
            fi
        done
    done
}
function lemper_nginx_site_unregister() {
    local domain="$1" root="${LEMPER_NGINX_DIR:-/etc/nginx}" dir suffix
    for dir in sites-enabled sites-available; do
        for suffix in conf nonssl-conf ssl-conf; do
            lemper_exec rm -f -- "$root/$dir/$domain.$suffix" || return 1
        done
    done
}

# Preserve spaces in literal document roots; ignore variable-based root directives.
function lemper_nginx_site_webroots() {
    awk '
        $1 == "set" && $2 == "$root_path" {
            line=$0
            sub(/^[[:space:]]*set[[:space:]]+\$root_path[[:space:]]+/, "", line)
            emit(line)
            next
        }
        $1 == "root" {
            line=$0
            sub(/^[[:space:]]*root[[:space:]]+/, "", line)
            if (line !~ /\$/) emit(line)
        }
        function emit(line) {
            sub(/[[:space:]]*;[[:space:]]*(#.*)?$/, "", line)
            if (substr(line,1,1) == "\"" && substr(line,length(line),1) == "\"")
                line=substr(line,2,length(line)-2)
            if (line ~ /^\//) print line
        }
    ' "$1" | sort -u
}

function lemper_nginx_site_set_enabled() {
    local domain="$1" enabled="$2" root="${LEMPER_NGINX_DIR:-/etc/nginx}"
    [[ -f "$root/sites-available/$domain.conf" ]] || return 1
    if [[ "$enabled" == true ]]; then
        [[ ! -f "$root/sites-enabled/$domain.conf" ]] || return 0
        lemper_exec ln -sfn "$root/sites-available/$domain.conf" "$root/sites-enabled/$domain.conf"
    else
        lemper_exec rm -f -- "$root/sites-enabled/$domain.conf"
    fi
}
