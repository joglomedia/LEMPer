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

function core_validate_fqdn() {
    local FQDN=${1}

    # Length check: 4-253 characters (RFC 1035 / RFC 1123).
    if [[ ${#FQDN} -lt 4 || ${#FQDN} -gt 253 ]]; then
        echo false # error
        return
    fi

    # Validate format: labels of 1-63 chars separated by dots,
    # no leading/trailing dashes, TLD is 2-63 letters, optional trailing dot.
    if grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\.?$' <<< "${FQDN}"; then
        echo true # success
    else
        echo false # error
    fi
}

function core_validate_ipv4() {
    local IP=${1}

    if grep -qE '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' <<< "${IP}"; then
        echo true # success
    else
        echo false # error
    fi
}

function core_validate_username() {
    local USERNAME=${1}

    if grep -qE '^[a-z_][a-z0-9_-]{0,31}$' <<< "${USERNAME}"; then
        echo true # success
    else
        echo false # error
    fi
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

function validate_username() {
    core_validate_username "$@"
}

function sanitize_sed_replacement() {
    core_sanitize_sed_replacement "$@"
}

function sanitize_sed_pattern() {
    core_sanitize_sed_pattern "$@"
}
