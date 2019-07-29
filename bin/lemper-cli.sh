#!/bin/bash

# +-------------------------------------------------------------------------+
# | NgxTool - Simple Nginx vHost Manager                                    |
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
ProgName=$(basename $0)
ProgVersion="1.2.0-dev"
LibDir="/usr/lib/lemper"

function cmd_help() {
    echo "Usage: $ProgName [--version] [--help]"
    echo "       <command> [<options>]"
    echo ""
    echo "These are common $ProgName commands used in various situations:"
    echo "  create  Create new virtual host"
    echo "  manage  Enable, disable, delete existing virtual host"
    echo ""
    echo "For help with each command run:"
    echo "$ProgName <command> -h|--help"
}

function cmd_version() {
    echo "$ProgName version $ProgVersion"
}

function cmd_create() {
    "$LibDir"/lemper-create $@
}

function cmd_manage() {
    "$LibDir"/lemper-manage $@
}

SubCommand=$1
case $SubCommand in
    "" | "-h" | "--help")
        cmd_help
    ;;

    "-v" | "--version")
        cmd_version
    ;;

    *)
        shift
        if declare -F "cmd_${SubCommand}" &>/dev/null; then
            cmd_${SubCommand} $@
        else
            echo "Error: '${SubCommand}' is not a known command." >&2
            echo "      Run '${ProgName} --help' for a list of known commands." >&2
            exit 1
        fi
    ;;
esac
