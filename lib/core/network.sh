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


function core_get_ip_private() {
    local SERVER_IP_PRIVATE && \
    SERVER_IP_PRIVATE=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

    echo "${SERVER_IP_PRIVATE}"
}

function core_get_ip_public() {
    local SERVER_IP_PRIVATE && SERVER_IP_PRIVATE=$(get_ip_private)
    local SERVER_IP_PUBLIC && \
    SERVER_IP_PUBLIC=$(curl -sk --ipv4 --connect-timeout 10 --retry 3 --retry-delay 0 https://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${SERVER_IP_PRIVATE}" == "${SERVER_IP_PUBLIC}" ]]; then
        echo "${SERVER_IP_PRIVATE}"
    else
        echo "${SERVER_IP_PUBLIC}"
    fi
}

function core_get_ip() {
    local IP

    # Try public IP first
    IP=$(get_ip_public 2>/dev/null)

    # Fallback to private IP
    if [[ -z "${IP}" ]]; then
        IP=$(get_ip_private 2>/dev/null)
    fi

    # Fallback to localhost for CI/CD or isolated environments
    if [[ -z "${IP}" ]]; then
        IP="127.0.0.1"
    fi

    echo "${IP}"
}

function core_get_ipv6_private() {
    local SERVER_IPV6_PRIVATE && \
    SERVER_IPV6_PRIVATE=$(ip addr | grep 'inet6' | \
        grep -oE '(::)?[0-9a-fA-F]{1,4}(::?[0-9a-fA-F]{1,4}){1,7}(::)?' | head -1)

    echo "${SERVER_IPV6_PRIVATE}"
}

function core_get_ipv6_public() {
    local SERVER_IPV6_PRIVATE && SERVER_IPV6_PRIVATE=$(get_ipv6_private)
    local SERVER_IPV6_PUBLIC && \
    SERVER_IPV6_PUBLIC=$(curl -sk --ipv6 --connect-timeout 10 --retry 3 --retry-delay 0 https://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${SERVER_IPV6_PRIVATE}" == "${SERVER_IPV6_PUBLIC}" ]]; then
        echo "${SERVER_IPV6_PRIVATE}"
    else
        echo "${SERVER_IPV6_PUBLIC}"
    fi
}

function get_ip_private() {
    core_get_ip_private
}

function get_ip_public() {
    core_get_ip_public
}

function get_ip() {
    core_get_ip
}

function get_ipv6_private() {
    core_get_ipv6_private
}

function get_ipv6_public() {
    core_get_ipv6_public
}

# /etc/hosts is bind-mounted by container runtimes: retain its inode.
function lemper_update_hosts() {
    local hostname="$1" address="$2" file="${3:-/etc/hosts}" temporary
    is_valid_domain "$hostname" || { error "Invalid hosts hostname."; return 1; }
    [[ "$(core_validate_ipv4 "$address")" == true ]] || { error "Invalid hosts address."; return 1; }
    [[ "${DRYRUN:-false}" != true ]] || { info "Would update hosts entry for $hostname."; return 0; }
    [[ -f "$file" && ! -L "$file.backup" ]] || return 1
    temporary=$(mktemp) || return 1
    if ! awk -v host="$hostname" -v address="$address" '
        /^[[:space:]]*#/ || NF == 0 { print; next }
        {
            line=$1; changed=0; aliases=0; comment=0
            for (i=2; i<=NF; i++) {
                if ($i ~ /^#/) comment=1
                if (!comment && $i == host) { changed=1; continue }
                line=line "\t" $i
                if (!comment) aliases++
            }
            if (!changed) print
            else if (aliases) print line
        }
        END { print address "\t" host }
    ' "$file" > "$temporary" ||
       ! cp -p -- "$file" "$file.backup"; then
        rm -f "$temporary"
        return 1
    fi
    if ! cat "$temporary" > "$file"; then
        cat "$file.backup" > "$file" || error "Failed to restore hosts file."
        rm -f "$temporary"
        return 1
    fi
    rm -f "$temporary"
}
