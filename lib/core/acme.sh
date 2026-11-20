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



# Certbot DNS credentials use provider-specific keys, never executable config.
function dns01_provider_key() {
    case "${1:-}" in
        cloudflare) printf '%s\n' dns_cloudflare_api_token ;;
        digitalocean) printf '%s\n' dns_digitalocean_token ;;
        *) error "Unsupported DNS provider; use cloudflare or digitalocean."; return 1 ;;
    esac
}

function dns01_credentials() {
    local provider="${1}" token="${2:-}" directory="${3:-/etc/lemper/acme}" key file temporary
    key=$(dns01_provider_key "${provider}") || return 1
    file="${directory}/dns-${provider}.ini"
    if [[ "${DRYRUN:-false}" == true ]]; then
        printf '%s\n' "${file}"
        return 0
    fi
    if [[ -z "${token}" ]]; then
        [[ -f "${file}" && ! -L "${file}" ]] || { error "DNS credentials are required."; return 1; }
        chmod 0600 "${file}" || return 1
    else
        [[ "${token}" != *$'\n'* && "${token}" != *$'\r'* ]] || { error "Invalid DNS credential format."; return 1; }
        install -d -m 0700 "${directory}" || return 1
        temporary=$(mktemp "${directory}/.dns-credentials.XXXXXX") || return 1
        if ! printf '%s = %s\n' "${key}" "${token}" > "${temporary}" ||
           ! chmod 0600 "${temporary}" || ! mv -f "${temporary}" "${file}"; then
            rm -f "${temporary}"
            return 1
        fi
    fi
    printf '%s\n' "${file}"
}

function acme_flush_dns_cache() {
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if command -v resolvectl >/dev/null 2>&1; then
            run resolvectl flush-caches
        elif command -v systemd-resolve >/dev/null 2>&1; then
            run systemd-resolve --flush-caches
        fi
    fi
    return 0
}

# Explicit domain input shared by site creation, SSL management, and renewals.
function request_dns01_certificate() {
    local domain="${1:-}" force="${2:-false}" directory="${3:-/etc/lemper/acme}"
    local provider="${ACME_DNS_PROVIDER:-cloudflare}" credentials wait="${ACME_DNS_PROPAGATION_WAIT:-30}" rc=0
    is_valid_domain "${domain}" || { error "Invalid wildcard certificate domain."; return 1; }
    dns01_provider_key "${provider}" >/dev/null || return 1
    [[ "${wait}" =~ ^[0-9]+$ && ${#wait} -le 4 && "${wait}" -le 3600 ]] ||
        { error "DNS propagation wait must be 0-3600 seconds."; return 1; }
    credentials=$(dns01_credentials "${provider}" "${ACME_DNS_API_TOKEN:-}" "${directory}") || return 1
    local args=(certonly --non-interactive --agree-tos --cert-name "${domain}"
        "--dns-${provider}" "--dns-${provider}-credentials" "${credentials}"
        "--dns-${provider}-propagation-seconds" "${wait}"
        --email "${LEMPER_ADMIN_EMAIL:-cert@lemper.cloud}" -d "${domain}" -d "*.${domain}")
    [[ "${force}" == true ]] && args+=(--force-renewal)
    acme_flush_dns_cache || return 1
    # Capture failures without the fatal run() helper so the post-check flush runs.
    if [[ "${DRYRUN:-false}" == true ]]; then
        run certbot "${args[@]}"
    else
        certbot "${args[@]}" || rc=$?
    fi
    acme_flush_dns_cache || return 1
    return "${rc}"
}
