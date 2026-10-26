#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Interactive System User Creator                            |
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
CMD_NAME="adduser"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Show interactive user creation help.
##
function adduser_show_usage() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
Interactively add a system user on a Debian/Ubuntu server.

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTIONS]

Options:
  -h, --help     Print this message and exit.
  -v, --version  Output version information and exit.

For non-interactive account creation, use '${CMD_PARENT} account'.
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

function header_msg() {
    if [[ -t 1 ]]; then
        clear
    fi
    cat <<- EOL
#==========================================================================#
#         Welcome to LEMPer Stack Manager for Debian/Ubuntu server         #
#==========================================================================#
#                 A simple tool to add new user into system.               #
#                                                                          #
#        For more information please visit https://masedi.net/lemper       #
#==========================================================================#
EOL
}

##
# Prompt for and create a single user account.
##
function prompt_for_user() {
    local namauser="" katasandi="" expired="" aksessh="" enablehomedir="" setug="" setsudoers=""
    local -a useradd_args=()

    echo -en "\nUsername: "
    read -r namauser || return 1
    if ! validate_username "${namauser}"; then
        error "Invalid username '${namauser}'. Expected lowercase letters," \
            "digits, '_' or '-', starting with a letter or '_'."
        return 1
    fi

    echo -n "Password: "
    read -rs katasandi || return 1
    echo ""
    if [[ -z "${katasandi}" ]]; then
        error "Password must not be empty."
        return 1
    fi

    echo -en "Expire date [yyyy-mm-dd]? '-1' or 'unlimited' for no expiry: "
    read -r expired || return 1

    echo -n "Allow Bash shell access? [y/n]: "
    read -r aksessh || return 1

    echo -n "Create home directory? [y/n]: "
    read -r enablehomedir || return 1

    echo -n "Set users group? [y/n]: "
    read -r setug || return 1

    if getent passwd "${namauser}" >/dev/null 2>&1; then
        warning "User '${namauser}' already exists."
        return 0
    fi

    if [[ -n "${expired}" && "${expired}" != "unlimited" && "${expired}" != "-1" ]]; then
        if [[ ! "${expired}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            error "Invalid expiry date '${expired}'; expected yyyy-mm-dd."
            return 1
        fi
        useradd_args+=(-e "${expired}")
    fi

    if [[ "${aksessh}" == y* || "${aksessh}" == Y* ]]; then
        useradd_args+=(-s /bin/bash)
    else
        useradd_args+=(-s /bin/false)
    fi

    if [[ "${enablehomedir}" == y* || "${enablehomedir}" == Y* ]]; then
        useradd_args+=(-d "/home/${namauser}" -m)
    else
        useradd_args+=(-d "/home/${namauser}" -M)
    fi

    if [[ "${setug}" == y* || "${setug}" == Y* ]]; then
        useradd_args+=(-g users)
    fi

    if ! useradd "${useradd_args[@]}" -- "${namauser}"; then
        error "Failed to create user '${namauser}'."
        return 1
    fi

    if ! printf '%s:%s\n' "${namauser}" "${katasandi}" | chpasswd; then
        error "Failed to set password for '${namauser}'."
        return 1
    fi

    echo -n "Add user ${namauser} to sudoers? [y/n]: "
    read -r setsudoers || return 1
    if [[ "${setsudoers}" == y* || "${setsudoers}" == Y* ]]; then
        # Use restricted sudoers instead of full sudo group membership.
        cat > "/etc/sudoers.d/90-${namauser}" <<SUDOERS_EOF
# Restricted sudoers for LEMPer admin user.
${namauser} ALL=(root) NOPASSWD: /bin/systemctl reload nginx, /bin/systemctl reload php*, /bin/systemctl restart nginx, /bin/systemctl restart php*
SUDOERS_EOF
        chmod 0440 "/etc/sudoers.d/90-${namauser}"
        if command -v visudo &>/dev/null && ! visudo -cf "/etc/sudoers.d/90-${namauser}" >/dev/null 2>&1; then
            error "Generated sudoers file failed validation; removing it."
            rm -f "/etc/sudoers.d/90-${namauser}"
            return 1
        fi
    fi

    success "User '${namauser}' created."
}

##
# Main App
##
function init_lemper_adduser() {
    local OPTS

    if ! OPTS=$(getopt -o hv -l help,version -n "${PROG_NAME}" -- "$@"); then
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
    fi
    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            -h | --help)
                adduser_show_usage
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

    if [[ $# -gt 0 ]]; then
        fail "Unexpected argument: ${1}"
    fi

    header_msg

    echo -en "\nAdd new user? [y/n]: "
    read -r tambah || exit 0

    while [[ "${tambah}" != n* && "${tambah}" != N* ]]; do
        prompt_for_user || true

        header_msg

        echo -en "\nAdd another user? [y/n]: "
        read -r tambah || exit 0
    done
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_adduser "$@"
