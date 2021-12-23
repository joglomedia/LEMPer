#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Lemper CLI - Simple LEMP Stack Manager                                  |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2021 MasEDI.Net (https://masedi.net/lemper)          |
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

set -e

# Version control.
PROG_NAME=$(basename "$0")
PROG_VER="2.x.x"

# May need to run this as sudo!
if [[ "$(id -u)" -ne 0 ]]; then
    echo "This command can only be run by root."
    exit 1
fi

# Export LEMPer stack configuration.
if [[ -f "/etc/lemper/lemper.conf" ]]; then
    # Clean environemnt first.
    # shellcheck source=/etc/lemper/lemper.conf
    # shellcheck disable=SC2046
    unset $(grep -v '^#' /etc/lemper/lemper.conf | grep -v '^\[' | sed -E 's/(.*)=.*/\1/' | xargs)

    # shellcheck source=/etc/lemper/lemper.conf
    # shellcheck disable=SC1094
    # shellcheck disable=SC1091
    source <(grep -v '^#' /etc/lemper/lemper.conf | grep -v '^\[' | sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
else
    echo "LEMPer stack configuration required, but the file doesn't exist."
    echo "It should be created during installation process and placed under '/etc/lemper/lemper.conf'"
    exit 1
fi

# Set default variables.
LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
LEMPER_PASSWORD=${LEMPER_PASSWORD:-""}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-""}

# CLI plugins directory.
CLI_PLUGINS_DIR="/etc/lemper/cli-plugins"

## 
# Show usage
# output to STDERR.
#
function cmd_help() {
    cat <<- EOL
${PROG_NAME} ${PROG_VER}
Command line management tool for LEMPer Stack.

Usage: ${PROG_NAME} [--version] [--help]
       <command> [<options>]

These are common ${PROG_NAME} commands used in various situations:
  create    Create new virtual host (add new domain to LEMPer stack).
  db        Wrapper for managing SQL database (MySQL and MariaDB).
  manage    Manage existing virtual host (enable, disable, delete, etc).

For help with each command run:
${PROG_NAME} <command> -h | --help
EOL
}

## 
# Show version.
#
function cmd_version() {
    echo "${PROG_NAME} version $PROG_VER"
}

##
# Main LEMPer CLI Wrapper
#
function init_lemper_cli() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        CMD="${1}"
        shift # Pass the remaining arguments to the next function.

        case ${CMD} in
            help | -h | --help)
                cmd_help
                exit 0
            ;;
            version | -v | --version)
                cmd_version
                exit 0
            ;;
            *)
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-${CMD}" ]]; then
                    "${CLI_PLUGINS_DIR}/lemper-${CMD}" "$@"
                    exit 0
                else
                    echo "${PROG_NAME}: '${CMD}' is not ${PROG_NAME} command."
                    echo "See '${PROG_NAME} --help' for more information."
                    exit 1
                fi
            ;;
        esac
    else
        echo "${PROG_NAME}: missing required arguments."
        echo "See '${PROG_NAME} --help' for more information."
        exit 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_cli "$@"
