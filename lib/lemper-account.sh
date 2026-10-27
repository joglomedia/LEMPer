#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - System User Account Creator                                |
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

# Version control.
CMD_PARENT="${PROG_NAME}"
CMD_NAME="account"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Show account creation help.
##
function account_show_usage() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
Create a system user account for LEMPer-managed web applications.

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTIONS] [username]

Options:
  -u, --username <name>  Account name (default: LEMPER_USERNAME or 'lemper').
  -h, --help             Print this message and exit.
  -v, --version          Output version information and exit.

The password is taken from LEMPER_PASSWORD or generated randomly.
Use '${CMD_PARENT} adduser' for an interactive prompt.
EOL
}

##
# Validate a Linux username: lowercase letters, digits, '_' and '-',
# starting with a letter or underscore, max 32 characters.
##
function validate_username() {
    local NAME=${1}
    [[ "${NAME}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

##
# Create a system account and its web application directories.
##
function create_account() {
    local USERNAME="${1:-${LEMPER_USERNAME:-lemper}}"
    local PASSWORD="${LEMPER_PASSWORD:-}"
    local PASSWORD_HASH=""

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

    usermod -aG sudo "${USERNAME}"

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
        PASSWORD_HASH=$(mkpasswd --method=sha-256 "${PASSWORD}")
    elif command -v htpasswd &>/dev/null; then
        printf '%s\n' "${PASSWORD}" | htpasswd -i /srv/.htpasswd "${USERNAME}"
    else
        PASSWORD_HASH=$(printf '%s\n' "${PASSWORD}" | openssl passwd -1 -stdin)
    fi

    if [[ -n "${PASSWORD_HASH}" ]]; then
        sed_inplace "/^${USERNAME}:/d" /srv/.htpasswd
        echo "${USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
    fi

    # Save config.
    printf 'LEMPER_USERNAME=%s\nLEMPER_PASSWORD=%s\nLEMPER_ADMIN_EMAIL=%s\n' \
        "${USERNAME}" "${PASSWORD}" "${LEMPER_ADMIN_EMAIL:-}"

    # Save data to log file.
    printf 'Your default system account information:\nUsername: %s\nPassword: %s\n' \
        "${USERNAME}" "${PASSWORD}"

    echo "Username ${USERNAME} created."
}

##
# Main App
##
function init_lemper_account() {
    local USERNAME=""
    local OPTS

    if ! OPTS=$(getopt -o u:hv -l username:,help,version -n "${PROG_NAME}" -- "$@"); then
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
    fi
    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            -u | --username)
                USERNAME="${2}"
                shift 2
            ;;
            -h | --help)
                account_show_usage
                exit 0
            ;;
            -v | --version)
                echo "${PROG_NAME} version ${PROG_VERSION}"
                exit 0
            ;;
            --)
                shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
            ;;
        esac
    done

    if [[ -n "${1:-}" ]]; then
        USERNAME="${1}"
        shift
    fi

    if [[ $# -gt 0 ]]; then
        fail "Unexpected argument: ${1}"
    fi

    create_account "${USERNAME}"
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_account "$@"
