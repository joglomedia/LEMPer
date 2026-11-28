#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Knot DNS Service Lifecycle                                              |
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

# Validate again at the point of use, including standalone component invocations.
function lemper_dns_network() {
    local role="${DNS_ROLE:-local}" address="${DNS_LISTEN_IPV4:-127.0.0.1}" peer peers=() seen=" "
    if ! core_is_valid_ipv4 "$address" || [[ "$address" == 0.* || "$address" =~ (^|\.)0[0-9] ]]; then
        error "Invalid DNS listener."; return 1
    fi
    read -r -a peers <<< "${DNS_TRANSFER_PEERS:-}"
    case "$role" in
        local) [[ "$address" == 127.* && ${#peers[@]} == 0 ]] || { error "Local DNS requires loopback and no peers."; return 1; } ;;
        hidden) [[ ${#peers[@]} -gt 0 ]] || { error "Hidden DNS requires transfer peers."; return 1; } ;;
        public) ;;
        *) error "Unknown DNS role."; return 1 ;;
    esac
    for peer in "${peers[@]}"; do
        if ! core_is_valid_ipv4 "$peer" || [[ "$peer" == 0.* || "$peer" == "$address" ||
              "$peer" =~ (^|\.)0[0-9] || "$seen" == *" $peer "* ]]; then
            error "Invalid or duplicate DNS peer."; return 1
        fi
        seen+="$peer "
    done
}

function lemper_dns_render() (
    set +x
    local address="${DNS_LISTEN_IPV4:-127.0.0.1}" peer peers=() ids=() id list key file
    read -r -a peers <<< "${DNS_TRANSFER_PEERS:-}"
    printf 'server:\n    listen: %s@53\n    udp-workers: 1\n    tcp-workers: 1\n' "$address"
    printf 'database:\n    storage: /var/lib/knot\n'
    for peer in "${peers[@]}"; do
        id="peer-${peer//./-}"
        file="/etc/lemper/dns-keys/$peer.key"
        lemper_directory_trusted "/etc/lemper/dns-keys" && [[ -f "$file" && ! -L "$file" ]] &&
            [[ "$(stat -c '%u:%a:%h' -- "$file")" == 0:600:1 ]] || { error "Expected a root-only TSIG key for $peer."; return 1; }
        key=$(cat -- "$file") || return 1
        [[ "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { error "Expected a base64-encoded 256-bit key for $peer."; return 1; }
        printf 'key:\n  - id: %s\n    algorithm: hmac-sha256\n    secret: %s\n' "$id" "$key"
        printf 'remote:\n  - id: %s\n    address: %s@53\n    key: %s\n' "$id" "$peer" "$id"
        printf 'acl:\n  - id: %s\n    address: %s\n    key: %s\n    action: transfer\n' "$id" "$peer" "$id"
        ids+=("$id")
    done
    if [[ "${DNS_ROLE:-local}" == hidden ]]; then
        list=$(IFS=,; echo "${peers[*]}")
        printf 'mod-queryacl:\n  - id: hidden\n    address: [%s,%s]\n' "$address" "$list"
    fi
    printf 'template:\n  - id: default\n    zonefile-sync: -1\n    zonefile-load: difference\n    journal-content: changes\n'
    if [[ "${DNS_ROLE:-local}" == hidden ]]; then printf '    global-module: mod-queryacl/hidden\n'; fi
    if [[ ${#ids[@]} -gt 0 ]]; then
        list=$(IFS=,; echo "${ids[*]}")
        printf '    notify: [%s]\n    acl: [%s]\n' "$list" "$list"
    fi
    printf 'include: "/etc/knot/lemper/published/*.conf"\n'
)

# Jammy ships kzonecheck in knot-dnsutils. Newer releases split out the checker.
function lemper_dns_checker_package() {
    if apt-cache policy knot-dnssecutils | awk '/Candidate:/ && $2!="(none)" {found=1} END {exit !found}'; then
        echo knot-dnssecutils
    else
        echo knot-dnsutils
    fi
}

function lemper_dns_install_entry() (
    local root=/etc/knot/lemper drop=/etc/systemd/system/knot.service.d/lemper.conf
    local template="$BASE_DIR/etc/knot/lemper.conf" state="${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}"
    local address="${DNS_LISTEN_IPV4:-127.0.0.1}" sockets candidate checker_package
    lemper_dns_network || return 1
    lemper_directory_trusted "$root" && lemper_directory_trusted "${drop%/*}" || return 1
    if [[ -e "$drop" || -L "$drop" ]]; then
        if [[ -L "$drop" ]] || ! cmp -s "$template" "$drop"; then error "Unrecognized Knot service override."; return 1; fi
    elif [[ -e /etc/knot/knot.conf || -e "$root" || -e "${drop%/*}" ]] || command -v knotd >/dev/null ||
         systemctl cat knot.service >/dev/null 2>&1; then
        error "Knot already exists outside LEMPer. Retaining its configuration."
        return 1
    fi
    if [[ ! -e "$root/enabled" ]] || ! systemctl is-active --quiet knot; then
        command -v ss >/dev/null || { error "Install iproute2 to check the DNS listener."; return 1; }
        sockets=$(ss -H -lntu 'sport = :53') || return 1
        if awk -v addr="$address:53" '$5 == addr || $5 == "*:53" || $5 == "0.0.0.0:53" || $5 == "[::]:53" { seen=1 } END { exit !seen }' <<<"$sockets"; then
            error "Port 53 is already in use on the requested address."
            return 1
        fi
    fi
    [[ "${DRYRUN:-false}" != true ]] || { info "Would configure Knot on $address for the ${DNS_ROLE:-local} role."; return 0; }
    umask 077
    if ! command -v knotd >/dev/null; then lemper_exec apt-get update -q || return 1; fi
    # Install the startup condition before APT can start the distribution service.
    if [[ ! -e "$drop" ]]; then
        install -d -m0755 "${drop%/*}" && install -m0644 "$template" "$drop" || return 1
        lemper_exec systemctl daemon-reload || return 1
    fi
    checker_package=$(lemper_dns_checker_package) || return 1
    lemper_exec apt-get install -q -y --no-install-recommends knot "$checker_package" bind9-utils dnsutils || return 1
    install -d -o root -g knot -m0750 "$root" "$root/zones" "$root/published" || return 1
    candidate=$(mktemp "$root/.config.XXXXXXXX") || return 1
    trap 'rm -f -- "$candidate"' EXIT
    lemper_dns_render > "$candidate" || return 1
    chgrp knot "$candidate" && chmod 0640 "$candidate" || return 1
    knotc -c "$candidate" conf-check >/dev/null 2>&1 || { error "Knot rejected the candidate configuration."; return 1; }
    if [[ -f "$root/enabled" ]] && cmp -s "$candidate" "$root/knot.conf"; then
        lemper_exec systemctl enable --now knot && install -d -m0700 "$state" && touch "$state/dns"
        return $?
    fi
    if [[ -f "$root/knot.conf" ]]; then cp -p -- "$root/knot.conf" "$root/previous.conf" || return 1; fi
    mv -fT -- "$candidate" "$root/knot.conf" && touch "$root/enabled" || return 1
    if ! lemper_exec systemctl enable knot || ! lemper_exec systemctl restart knot; then
        if [[ -f "$root/previous.conf" ]]; then
            if ! cp -p -- "$root/previous.conf" "$candidate" || ! mv -fT "$candidate" "$root/knot.conf" ||
                ! lemper_exec systemctl restart knot; then error "Restore the saved Knot configuration."; fi
        else
            rm -f -- "$root/enabled"
        fi
        return 1
    fi
    install -d -m0700 "$state" && touch "$state/dns"
)

function lemper_dns_remove_entry() {
    local root=/etc/knot/lemper drop=/etc/systemd/system/knot.service.d/lemper.conf
    if [[ ! -f "$root/enabled" ]]; then info "No active LEMPer DNS installation."; return 0; fi
    cmp -s "$BASE_DIR/etc/knot/lemper.conf" "$drop" || { error "Unmanaged Knot unit."; return 1; }
    local zones=() file
    for file in "$root"/published/*.conf; do [[ ! -f "$file" ]] || zones+=("${file##*/}"); done
    if ((${#zones[@]})); then info "Stopping authority for: ${zones[*]%.conf}"; fi
    [[ "${DRYRUN:-false}" != true ]] || return 0
    lemper_exec systemctl disable --now knot && lemper_exec apt-get remove -q -y knot || return 1
    rm -f -- "$root/enabled" "${LEMPER_INSTALLED_DIR:-/etc/lemper/installed}/dns"
}
