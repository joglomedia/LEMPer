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

# Issuance is staged per domain; shared OpenSSL templates remain immutable.
function lemper_ssl_directory_safe() {
    local directory="$1" parent
    [[ "$directory" =~ ^/[a-zA-Z0-9_./-]+$ && "$directory" != *..* ]] || return 1
    parent="$directory"
    while [[ "$parent" != / ]]; do
        [[ ! -L "$parent" ]] || {
            error "Refusing symlink certificate storage."
            return 1
        }
        parent="${parent%/*}"
        [[ -n "$parent" ]] || parent=/
    done
}
function lemper_ssl_generate_selfsigned() (
    local domain="$1" ipv4="$2" ipv6="${3:-}" root="${LEMPER_SSL_ROOT:-/etc/lemper/ssl}" templates code stage target backup
    local bits="${KEY_HASH_LENGTH:-4096}"
    if [[ $(core_validate_fqdn "$domain") != true ]] || ! core_is_valid_ipv4 "$ipv4"; then
        error "Invalid certificate domain or IPv4 address."
        return 1
    fi
    [[ -z "$ipv6" ]] || core_is_valid_ipv6 "$ipv6" || {
        error "Invalid certificate IPv6 address."
        return 1
    }
    [[ "$bits" =~ ^[0-9]{4,5}$ ]] && ((10#$bits >= 2048 && 10#$bits <= 16384)) || return 1
    lemper_ssl_directory_safe "$root" || return 1
    target="$root/$domain"
    lemper_ssl_directory_safe "$target" || return 1
    if [[ "${DRYRUN:-false}" == true ]]; then
        info "Would generate self-signed certificate for $domain."
        return 0
    fi
    code=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") || return 1
    templates="${LEMPER_SSL_TEMPLATE_DIR:-$root}"
    if [[ ! -e "$templates/ca.conf" && ! -e "$templates/csr.conf" ]]; then templates="$code/../../../etc/openssl"; fi
    [[ -f "$templates/ca.conf" && -f "$templates/csr.conf" ]] || {
        error "OpenSSL templates are missing."
        return 1
    }
    lemper_exec install -d -m0700 "$root" || return 1
    stage=$(mktemp -d "$root/.issue.XXXXXXXX") || return 1
    trap 'rm -rf -- "$stage"' EXIT
    umask 077
    sed -e "s|^CN = .*|CN = $domain|" "$templates/ca.conf" >"$stage/ca.conf" || return 1
    sed -e "s|^CN = .*|CN = $domain|" -e "s|^DNS.1 = .*|DNS.1 = $domain|" \
        -e "s|^DNS.2 = .*|DNS.2 = www.$domain|" -e "s|^IP.1 = .*|IP.1 = $ipv4|" \
        -e "s|^IP.2 = .*|IP.2 = ${ipv6:-$ipv4}|" "$templates/csr.conf" >"$stage/csr.conf" || return 1
    {
        printf 'authorityKeyIdentifier=keyid,issuer\nbasicConstraints=critical,CA:FALSE\n'
        printf 'keyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=@alt_names\n[alt_names]\n'
        printf 'DNS.1=%s\nDNS.2=www.%s\nIP.1=%s\n' "$domain" "$domain" "$ipv4"
        [[ -z "$ipv6" ]] || printf 'IP.2=%s\n' "$ipv6"
    } >"$stage/cert.conf" || return 1
    lemper_exec openssl req -x509 -sha256 -days 365 -nodes -newkey "rsa:$bits" \
        -keyout "$stage/ca.key" -out "$stage/ca.crt" -config "$stage/ca.conf" \
        -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' || return 1
    lemper_exec openssl genrsa -out "$stage/privkey.pem" "$bits" || return 1
    lemper_exec openssl req -new -key "$stage/privkey.pem" -out "$stage/csr.csr" -config "$stage/csr.conf" || return 1
    lemper_exec openssl x509 -req -sha256 -days 365 -CAcreateserial -CA "$stage/ca.crt" -CAkey "$stage/ca.key" \
        -in "$stage/csr.csr" -out "$stage/cert.pem" -extfile "$stage/cert.conf" || return 1
    openssl verify -CAfile "$stage/ca.crt" "$stage/cert.pem" >/dev/null || return 1
    cat "$stage/cert.pem" "$stage/ca.crt" >"$stage/fullchain.pem" || return 1
    chmod 0600 "$stage"/* || return 1
    chmod 0644 "$stage/ca.crt" "$stage/cert.pem" "$stage/fullchain.pem" || return 1
    if [[ -e "$target" ]]; then
        [[ -d "$target" && ! -L "$target" ]] || return 1
        backup=$(mktemp -d "$root/.previous-$domain.XXXXXXXX") || return 1
        rmdir "$backup" || return 1
        lemper_exec mv -T "$target" "$backup" || return 1
    fi
    if ! lemper_exec mv -T "$stage" "$target"; then
        [[ -z "${backup:-}" ]] || lemper_exec mv -T "$backup" "$target"
        return 1
    fi
    info "Self-signed certificate generated for $domain; private key is protected."
)
