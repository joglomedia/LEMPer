#!/bin/bash

# +-------------------------------------------------------------------------+
# | Lemper CLI - Simple LEMP Stack Manager                                  |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/ngxtool)              |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

set -e

# Version control.
APP_NAME=$(basename "$0")
APP_VERSION="1.3.0"

# May need to run this as sudo!
if [ "$(id -u)" -ne 0 ]; then
    error "This command can only be used by root."
    exit 1
fi

# Export LEMPer stack configuration.
if [ -f "/etc/lemper/lemper.conf" ]; then
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
MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-""}

# App library directory.
APP_LIB_DIR="/usr/local/lib/lemper"


## 
# Show usage
# output to STDERR.
#
function cmd_help() {
    cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Command line management tool for LEMPer stack.

Usage: ${APP_NAME} [--version] [--help]
       <command> [<options>]

These are common ${APP_NAME} commands used in various situations:
  create  Create new virtual host
  db      Wrapper for managing SQL database
  manage  Enable, disable, delete existing virtual host

For help with each command run:
${APP_NAME} <command> -h|--help
_EOF_

    exit 0
}

## 
# Show version.
#
function cmd_version() {
    echo "${APP_NAME} version $APP_VERSION"
    exit 0
}

##
# Create new webapp.
#
function cmd_create() {
    if [ -x "$APP_LIB_DIR/lemper-create" ]; then
        "$APP_LIB_DIR/lemper-create" "$@"
    else
        echo "Oops, lemper create subcommand module couldn't be loaded."
        exit 1
    fi
}

# Aliases to create.
function cmd_app() {
    cmd_create "$@"
}

# Aliases to create.
function cmd_vhost() {
    cmd_create "$@"
}

##
# Manage existing webapp.
#
function cmd_manage() {
    if [ -x "$APP_LIB_DIR/lemper-manage" ]; then
        "$APP_LIB_DIR/lemper-manage" "$@"
    else
        echo "Oops, lemper manage subcommand module couldn't be loaded."
        exit 1
    fi
}

##
# Manage database.
#
function cmd_db() {
    if [ -x "$APP_LIB_DIR/lemper-db" ]; then
        "$APP_LIB_DIR/lemper-db" "$@"
    else
        echo "Oops, lemper db (database) subcommand module couldn't be loaded."
        exit 1
    fi
}

##
# TinyFileManager add user.
#
function cmd_tfm() {
    if [ -x "$APP_LIB_DIR/lemper-tfm" ]; then
        "$APP_LIB_DIR/lemper-tfm" "$@"
    else
        echo "Oops, lemper tfm subcommand module couldn't be loaded."
        exit 1
    fi
}


##
# Main App
#
SUBCOMMAND="${1}"
case ${SUBCOMMAND} in
    "" | "help" )
        cmd_help
    ;;

    "version")
        cmd_version
    ;;

    *)
        shift
        if declare -F "cmd_${SUBCOMMAND}" &>/dev/null; then
            "cmd_${SUBCOMMAND}" "$@"
        else
            echo "Error: '${SUBCOMMAND}' is not a known command." >&2
            echo "Run '${APP_NAME} help' for a list of known commands." >&2
            exit 1
        fi
    ;;
esac