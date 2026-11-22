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


function core_validate_nginx_config() {
    if nginx -t 2>/dev/null > /dev/null; then
        echo true # success
    else
        echo false # error
    fi
}

# Status predicates validate the entire literal value; grep validates lines.
function core_is_valid_fqdn() {
    local domain="${1:-}" trailing="${2:-false}" LC_ALL=C
    [[ ${#domain} -ge 4 && ${#domain} -le 253 ]] || return 1
    if [[ "$trailing" == true && "$domain" == *. ]]; then domain="${domain%.}"; fi
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}
function core_is_valid_ipv4() {
    local address="${1:-}" octet octets=()
    [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$address"
    for octet in "${octets[@]}"; do ((10#$octet <= 255)) || return 1; done
}
function core_is_valid_ipv6() {
    local address="${1:-}" tail left right group count=0 groups=() octets=() LC_ALL=C
    [[ ${#address} -ge 2 && ${#address} -le 45 && "$address" =~ ^[0-9A-Fa-f:.]+$ && "$address" == *:* ]] || return 1
    [[ "$address" != *:::* ]] || return 1
    if [[ "$address" == *.* ]]; then
        tail="${address##*:}"
        core_is_valid_ipv4 "$tail" || return 1
        IFS=. read -r -a octets <<< "$tail"
        for group in "${octets[@]}"; do [[ ${#group} == 1 || "$group" != 0* ]] || return 1; done
        address="${address%:*}:0:0"
    fi
    if [[ "$address" == *::* ]]; then
        left="${address%%::*}"; right="${address#*::}"
        [[ "$right" != *::* ]] || return 1
        for tail in "$left" "$right"; do
            [[ -n "$tail" ]] || continue
            [[ "$tail" != :* && "$tail" != *: ]] || return 1
            IFS=: read -r -a groups <<< "$tail"
            for group in "${groups[@]}"; do
                [[ "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
                count=$((count + 1))
            done
        done
        ((count < 8))
    else
        [[ "$address" != :* && "$address" != *: ]] || return 1
        IFS=: read -r -a groups <<< "$address"
        [[ ${#groups[@]} == 8 ]] || return 1
        for group in "${groups[@]}"; do [[ "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1; done
    fi
}
function core_is_valid_custom_ssl_version() {
    [[ "${1:-}" =~ ^(openssl-[0-9]+\.[0-9]+\.[0-9]+(-quic[0-9]+)?|libressl-[0-9]+\.[0-9]+\.[0-9]+|boringssl-(latest|master|[a-fA-F0-9]{40}))$ ]]
}
function core_is_valid_username() { [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

# Legacy callers consume printed true/false; preserve that API and status.
function core_validate_fqdn() {
    if core_is_valid_fqdn "${1:-}" true; then echo true; else echo false; fi
}
function core_validate_ipv4() {
    if core_is_valid_ipv4 "${1:-}"; then echo true; else echo false; fi
}
function core_validate_ipv6() {
    if core_is_valid_ipv6 "${1:-}"; then echo true; else echo false; fi
}
function core_validate_username() {
    if core_is_valid_username "${1:-}"; then echo true; else echo false; fi
}

function core_sanitize_sed_replacement() {
    local INPUT=${1}
    printf '%s' "${INPUT}" | sed -e 's/[\\&]/\\&/g' -e 's/\//\\\//g'
}

function core_sanitize_sed_pattern() {
    local INPUT=${1}
    printf '%s' "${INPUT}" | sed -e 's/\[/\\[/g'
}

function validate_nginx_config() {
    core_validate_nginx_config "$@"
}

function validate_fqdn() {
    core_validate_fqdn "$@"
}

function validate_ipv4() {
    core_validate_ipv4 "$@"
}

function validate_ipv6() {
    core_validate_ipv6 "$@"
}

function validate_username() {
    core_validate_username "$@"
}

function sanitize_sed_replacement() {
    core_sanitize_sed_replacement "$@"
}

function sanitize_sed_pattern() {
    core_sanitize_sed_pattern "$@"
}
