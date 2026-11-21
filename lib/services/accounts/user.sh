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



function create_account() {
    local USERNAME="${1:-${LEMPER_USERNAME:-lemper}}"
    local PASSWORD="${LEMPER_PASSWORD:-}"
    local PASSWORD_HASH=""
    local ROLE="${2:-hosting}"

    if ! validate_username "${USERNAME}"; then
        error "Invalid username '${USERNAME}'. Expected lowercase letters," \
            "digits, '_' or '-', starting with a letter or '_'."
        return 1
    fi

    if [[ -z "${PASSWORD}" ]]; then
        PASSWORD=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    fi

    echo "Add new system account..."

    if getent passwd "${USERNAME}" >/dev/null 2>&1; then
        warning "Unable to create account, username '${USERNAME}' already exists."
        return 0
    fi

    if [[ "${DRYRUN}" == true ]]; then
        echo "Create ${USERNAME} account in dry mode."
        return 0
    fi

    if ! useradd -d "/home/${USERNAME}" -m -s /bin/bash -- "${USERNAME}"; then
        fail "Failed to create system account '${USERNAME}'."
    fi

    if ! printf '%s:%s\n' "${USERNAME}" "${PASSWORD}" | chpasswd; then
        fail "Failed to set password for '${USERNAME}'."
    fi

    if [[ "${ROLE}" == admin ]]; then
        write_account_sudoers "${USERNAME}" || return 1
    fi

    # Create default directories.
    run mkdir -p "/home/${USERNAME}/webapps" \
        "/home/${USERNAME}/logs/nginx" \
        "/home/${USERNAME}/logs/php" \
        "/home/${USERNAME}/.ssh"
    run chmod 700 "/home/${USERNAME}/.ssh"
    run touch "/home/${USERNAME}/.ssh/authorized_keys"
    run chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"
    create_php_temp_dirs "${USERNAME}"
    run chown -hR "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

    # Add account credentials to /srv/.htpasswd.
    if [[ ! -f "/srv/.htpasswd" ]]; then
        run touch /srv/.htpasswd
    fi

    # Protect .htpasswd file.
    run chmod 0600 /srv/.htpasswd
    run chown www-data:www-data /srv/.htpasswd

    # Generate password hash.
    if command -v mkpasswd &>/dev/null; then
        PASSWORD_HASH=$(printf '%s\n' "${PASSWORD}" | mkpasswd --method=sha-256 --stdin)
    elif command -v htpasswd &>/dev/null; then
        printf '%s\n' "${PASSWORD}" | htpasswd -i /srv/.htpasswd "${USERNAME}"
    else
        PASSWORD_HASH=$(printf '%s\n' "${PASSWORD}" | openssl passwd -1 -stdin)
    fi

    if [[ -n "${PASSWORD_HASH}" ]]; then
        sed_inplace "/^${USERNAME}:/d" /srv/.htpasswd
        echo "${USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
    fi

    # Account credentials are kept separately; creating a hosting account must
    # never overwrite the administrator's global username/password.
    run install -d -m 0700 /etc/lemper/accounts
    ( umask 077; printf 'USERNAME=%s\nPASSWORD=%s\n' "${USERNAME}" "${PASSWORD}" > "/etc/lemper/accounts/${USERNAME}.conf" ) || return 1
    run chmod 0600 "/etc/lemper/accounts/${USERNAME}.conf"
    info "Account credentials saved to /etc/lemper/accounts/${USERNAME}.conf (root-only)."

    echo "Username ${USERNAME} created."
}

##
# Main App
##
