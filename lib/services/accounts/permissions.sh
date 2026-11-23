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
