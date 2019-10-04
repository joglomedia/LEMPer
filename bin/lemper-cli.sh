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

# Version control
APP_NAME=$(basename "$0")
APP_VERSION="1.3.0"

LibDir="/usr/local/lib/lemper"

function cmd_help() {
cat <<- _EOF_
${APP_NAME^} ${APP_VERSION}
Command line management tool for LEMPer stack.

Usage: $APP_NAME [--version] [--help]
       <command> [<options>]

These are common $APP_NAME commands used in various situations:
  create  Create new virtual host
  manage  Enable, disable, delete existing virtual host

For help with each command run:
$APP_NAME <command> -h|--help
_EOF_
}

function cmd_version() {
    echo "$APP_NAME version $APP_VERSION"
}

function cmd_create() {
    if [ -x "$LibDir/lemper-create" ]; then
        "$LibDir/lemper-create" "$@"
    else
        echo "Oops, lemper create subcommand module couldn't be loaded."
        exit 1
    fi
}

function cmd_manage() {
    if [ -x "$LibDir/lemper-manage" ]; then
        "$LibDir/lemper-manage" "$@"
    else
        echo "Oops, lemper manage subcommand module couldn't be loaded."
        exit 1
    fi
}

function cmd_tfm() {
    if [ -x "$LibDir/lemper-tfm" ]; then
        "$LibDir/lemper-tfm" "$@"
    else
        echo "Oops, lemper tfm subcommand module couldn't be loaded."
        exit 1
    fi
}

SubCommand=$1
case ${SubCommand} in
    "" | "-h" | "--help")
        cmd_help
    ;;

    "-v" | "--version")
        cmd_version
    ;;

    *)
        shift
        if declare -F "cmd_${SubCommand}" &>/dev/null; then
            "cmd_${SubCommand}" "$@"
        else
            echo "Error: '${SubCommand}' is not a known command." >&2
            echo "      Run '${APP_NAME} --help' for a list of known commands." >&2
            exit 1
        fi
    ;;
esac
