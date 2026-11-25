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


# Pure validation and redaction; sourcing this module never changes the host.
function redact_secrets() {
    local message="$*" name value
    while IFS= read -r name; do
        case "${name}" in
            PASSWORD|PASSWORD_HASH|*_PASSWORD|*_PASSWORD_HASH|*_PASS|*_PASS2|*_TOKEN|*_SECRET|password|pw|secret)
                value="${!name}"
                [[ -n "${value}" ]] && message="${message//"${value}"/[REDACTED]}"
                ;;
        esac
    done < <(compgen -v)
    printf '%s' "${message}"
}

# Resolve symlinks and '..' before deciding whether a recursive mutation is safe.
# Application trees may live in /home, /srv, /var/www, /opt, or a custom mount.
function safe_webroot() {
    local target="${1:-}" resolved owner="${2:-}" prefix
    [[ "${target}" == /* && -d "${target}" && ! -L "${target}" ]] || return 1
    [[ "${target}" != *$'\n'* && "${target}" != *$'\r'* ]] || return 1
    resolved=$(cd -- "${target}" && pwd -P) || return 1
    case "${resolved}" in
        /|/home|/srv|/srv/www|/var|/var/www|/opt|/root|/tmp|/var/tmp|/mnt|/media)
            return 1 ;;
        /bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/lib|/lib/*|/lib32|/lib32/*|\
        /lib64|/lib64/*|/proc|/proc/*|/run|/run/*|/sbin|/sbin/*|/sys|/sys/*|/usr|/usr/*)
            return 1 ;;
        /var/*)
            [[ "${resolved}" == /var/www/* ]] || return 1 ;;
    esac
    # A user's home and shared application roots are never a site's deletion target.
    if [[ "${resolved}" == /home/* ]]; then
        prefix="${resolved#/home/}"
        [[ "${prefix}" == */* ]] || return 1
        [[ "${resolved}" != "/home/${prefix%%/*}/webapps" &&
           "${resolved}" != "/home/${prefix%%/*}/logs" &&
           "${resolved}" != "/home/${prefix%%/*}/.ssh" &&
           "${resolved}" != /home/*/.ssh/* ]] || return 1
    fi
    if [[ -n "${owner}" ]]; then
        if [[ "$(uname -s)" == Darwin ]]; then
            [[ "$(stat -f '%Su' "${resolved}")" == "${owner}" ]] || return 1
        else
            [[ "$(stat -c '%U' "${resolved}")" == "${owner}" ]] || return 1
        fi
    fi
    printf '%s\n' "${resolved}"
}

# All recursive site deletion goes through this boundary.
function delete_site_webroot() {
    local resolved
    resolved=$(safe_webroot "${1:-}" "${2:-}") || {
        error "Refusing unsafe or incorrectly owned website root."
        return 1
    }
    local owner="${2:-}"
    [[ -n "${owner}" ]] || { error "A website owner is required for data removal."; return 1; }
    # Drop privileges for the entire recursive operation. An owner can change
    # writable ancestors after validation, but cannot turn that race into root deletion.
    if command -v runuser >/dev/null 2>&1; then
        run runuser -u "${owner}" -- rm -rf -- "${resolved}"
    elif command -v sudo >/dev/null 2>&1; then
        run sudo -u "${owner}" -- rm -rf -- "${resolved}"
    else
        error "runuser or sudo is required to remove website data safely."
        return 1
    fi
}

function is_valid_username() {
    [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

function is_valid_domain() {
    local domain="${1:-}"
    [[ ${#domain} -ge 4 && ${#domain} -le 253 ]] &&
        [[ "${domain}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

# Replace the pathname atomically, never write through a versioned CLI symlink.
function install_cli_binary() {
    local source="${1}" destination="${2}" temporary
    [[ -f "${source}" ]] || return 1
    [[ "${DRYRUN:-false}" != true ]] || { info "Would install CLI binary."; return 0; }
    temporary=$(mktemp "${destination}.XXXXXX") || return 1
    if ! install -m 0755 "${source}" "${temporary}" || ! mv -f "${temporary}" "${destination}"; then
        rm -f "${temporary}"
        return 1
    fi
}
