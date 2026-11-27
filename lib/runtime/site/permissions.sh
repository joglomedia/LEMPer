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
# Show permission repair help.
##
function fixpermission_show_usage() {
    cat <<-EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VERSION}
Recursively set directories to 755 and ordinary files to 644. Keep WordPress and dotenv credentials private.

Usage:
  ${CMD_PARENT} ${CMD_NAME} <directory>

Options:
  -h, --help     Print this message and exit.
  -v, --version  Output version information and exit.

Choose a dedicated site directory owned by its non-root runtime user.
EOL
}

##
# Main App
##
function init_lemper_fixpermission() {

    lemper_parse_args 'hv' 'help,version' "$@" || return 1
    set -- "${LEMPER_PARSED_ARGS[@]}"

    while true; do
        case "${1}" in
            -h | --help)
                fixpermission_show_usage
                return 0
                ;;
            -v | --version)
                echo "${PROG_NAME} version ${PROG_VERSION}"
                return 0
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
        return 1
    fi

    if [[ $# -gt 1 ]]; then
        fail "Unexpected argument: ${2}"
    fi

    fixpermission "${1}"
}
