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



# The profile builder can be tested without touching the host SSH configuration.
function write_ssh_profile() {
    local destination="${1}" port="${2}" key_only="${3}" root_login="${4}" temporary
    [[ "${port}" =~ ^[0-9]+$ && ${#port} -le 5 && $((10#${port})) -ge 1 && $((10#${port})) -le 65535 ]] || return 1
    [[ "${key_only}" == true || "${key_only}" == false ]] || return 1
    [[ "${root_login}" == true || "${root_login}" == false ]] || return 1
    [[ "${DRYRUN:-false}" != true ]] || { info "Would configure SSH port ${port}."; return 0; }
    temporary=$(mktemp "${destination}.XXXXXX") || return 1
    {
        printf '# LEMPer-managed SSH policy\nPort %s\n' "${port}"
        if [[ "${key_only}" == true ]]; then
            printf 'PubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAuthenticationMethods publickey\nAuthorizedKeysFile .ssh/authorized_keys /etc/ssh/lemper-keys/%%u\n'
        fi
        [[ "${root_login}" == true ]] || printf 'PermitRootLogin no\n'
        printf 'ClientAliveInterval 600\nClientAliveCountMax 3\n'
    } > "${temporary}"
    if ! chmod 0600 "${temporary}" || ! mv -f "${temporary}" "${destination}"; then
        rm -f "${temporary}"; return 1
    fi
}

function verify_effective_ssh_policy() {
    local username="$1" port="$2" key_only="$3" root_login="$4" config="$5"
    local effective context account setting remote_addr local_addr
    local -a args contexts=("")
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    port="$((10#$port))"
    read -r remote_addr _ local_addr _ <<< "${SSH_CONNECTION:-}"
    for account in "$username" root; do
        contexts+=("user=$account,host=localhost,addr=127.0.0.1,laddr=127.0.0.1,lport=$port")
        if [[ -n "$remote_addr" && -n "$local_addr" ]]; then
            contexts+=("user=$account,host=$remote_addr,addr=$remote_addr,laddr=$local_addr,lport=$port")
        fi
    done
    for context in "${contexts[@]}"; do
        args=(-T -f "$config")
        [[ -z "$context" ]] || args+=(-C "$context")
        effective=$(sshd "${args[@]}") || return 1
        grep -Fxq "port $port" <<< "$effective" || return 1
        if [[ "$key_only" == true ]]; then
            for setting in 'pubkeyauthentication yes' 'passwordauthentication no' \
                'kbdinteractiveauthentication no' 'authenticationmethods publickey'; do
                grep -Fxq "$setting" <<< "$effective" || return 1
            done
            grep -Eq '^authorizedkeysfile (.* )?/etc/ssh/lemper-keys/%u( |$)' <<< "$effective" || return 1
        fi
        if [[ "$root_login" != true ]]; then
            grep -Fxq 'permitrootlogin no' <<< "$effective" || return 1
        fi
    done
}

function valid_ssh_key_material() {
    local key="${1:-}"
    is_ssh_public_key "${key}" || return 1
    printf '%s\n' "${key}" | ssh-keygen -lf /dev/stdin >/dev/null 2>&1
}

function install_managed_ssh_key() {
    local username="${1}" key="${2}" directory="${3:-/etc/ssh/lemper-keys}" temporary file
    is_valid_username "${username}" && valid_ssh_key_material "${key}" || return 1
    [[ ! -L "${directory}" ]] || return 1
    install -d -m 0755 "${directory}" || return 1
    file="${directory}/${username}"
    [[ ! -L "${file}" ]] || return 1
    temporary=$(mktemp "${directory}/.key.XXXXXX") || return 1
    [[ ! -f "${file}" ]] || cat "${file}" > "${temporary}"
    grep -qxF "${key}" "${temporary}" || printf '%s\n' "${key}" >> "${temporary}"
    if ! chmod 0644 "${temporary}" || ! mv -f "${temporary}" "${file}"; then
        rm -f "${temporary}"; return 1
    fi
}

function restore_ssh_configuration() {
    local snapshot="${LEMPER_SSH_SNAPSHOT:-}" account key_file
    [[ -d "${snapshot}" ]] || return 0
    cp -p "${snapshot}/sshd_config" /etc/ssh/sshd_config || return 1
    if [[ -f "${snapshot}/profile" ]]; then
        cp -p "${snapshot}/profile" /etc/ssh/sshd_config.d/90-lemper.conf || return 1
    else
        rm -f /etc/ssh/sshd_config.d/90-lemper.conf || return 1
    fi
    if [[ -f "$snapshot/key-account" ]]; then
        IFS= read -r account <"$snapshot/key-account" && is_valid_username "$account" || return 1
        key_file="/etc/ssh/lemper-keys/$account"
        if [[ -f "$snapshot/key" ]]; then
            cp -p "$snapshot/key" "$key_file" || return 1
        else
            rm -f -- "$key_file" || return 1
        fi
    fi
    rm -rf "${snapshot}"
    LEMPER_SSH_SNAPSHOT=""
}

# Keep active/previous listeners reachable until the administrator confirms migration.
function ssh_transition_ports() {
    local new="${1}" previous="${2:-22}" active="${3:-}" port
    local ports=()
    for port in ${new} ${previous} ${active}; do
        [[ "${port}" =~ ^[0-9]+$ && ${#port} -le 5 && $((10#${port})) -ge 1 && $((10#${port})) -le 65535 ]] || return 1
        ports+=("${port}")
    done
    printf '%s\n' "${ports[@]}" | sort -nu | paste -sd, -
}

# Ubuntu's default OpenSSH can be socket-activated without an active ssh.service.
function apply_ssh_service_policy() {
    [[ "${DRYRUN:-false}" != true ]] || { info "Would apply SSH listener policy."; return 0; }
    if systemctl is-active --quiet ssh.socket; then
        systemctl daemon-reload || return 1
        systemctl restart ssh.socket || return 1
        # Refresh a running daemon's inherited socket; leave idle activation idle.
        systemctl try-restart ssh.service || return 1
    elif systemctl is-active --quiet ssh.service; then
        systemctl reload ssh.service || return 1
    else
        systemctl start ssh.service || return 1
    fi
}
