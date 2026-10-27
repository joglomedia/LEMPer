#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Fix File & Directory Permissions                           |
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
CMD_NAME="fixpermission"

# Make sure only root can access and not direct access.
if [[ "$(type -t requires_root)" != "function" ]]; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Show permission repair help.
##
function fixpermission_show_usage() {
    cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
Recursively set directories to 755 and files to 644.

Usage:
  ${CMD_PARENT} ${CMD_NAME} <directory>

Options:
  -h, --help     Print this message and exit.
  -v, --version  Output version information and exit.

System directories (/etc, /usr, /var, ...) are refused.
EOL
}

##
# Refuse broad system paths that must never be chmod-ed recursively.
##
function is_protected_path() {
    local TARGET=${1}

    case "${TARGET}" in
        / | /bin | /boot | /dev | /etc | /home | /lib | /lib32 | /lib64 | \
        /opt | /proc | /root | /sbin | /srv | /sys | /usr | /var)
            return 0
        ;;
    esac

    return 1
}

##
# Fix permissions for a web root or application directory.
##
function fixpermission() {
    local TARGET="${1:-}"
    local RESOLVED

    if [[ -z "${TARGET}" ]]; then
        fixpermission_show_usage
        return 1
    fi

    if [[ ! -d "${TARGET}" ]]; then
        fail "Directory not found: ${TARGET}"
    fi

    if ! RESOLVED=$(cd "${TARGET}" && pwd -P); then
        fail "Unable to resolve directory: ${TARGET}"
    fi

    if is_protected_path "${TARGET}" || is_protected_path "${RESOLVED}"; then
        fail "Refusing to change permissions recursively on '${RESOLVED}'."
    fi

    info "Setting directories to 755 and files to 644 under ${RESOLVED}..."
    run find "${RESOLVED}" -type d -exec chmod 755 {} +
    run find "${RESOLVED}" -type f -exec chmod 644 {} +
    success "Permissions fixed for ${RESOLVED}."
}

##
# Main App
##
function init_lemper_fixpermission() {
    local OPTS

    if ! OPTS=$(getopt -o hv -l help,version -n "${PROG_NAME}" -- "$@"); then
        echo "See '${CMD_PARENT} ${CMD_NAME} --help' for more information."
        exit 1
    fi
    eval set -- "${OPTS}"

    while true; do
        case "${1}" in
            -h | --help)
                fixpermission_show_usage
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

    if [[ $# -lt 1 ]]; then
        fixpermission_show_usage
        exit 1
    fi

    if [[ $# -gt 1 ]]; then
        fail "Unexpected argument: ${2}"
    fi

    fixpermission "${1}"
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_fixpermission "$@"
