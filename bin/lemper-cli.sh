#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Lemper CLI - Simple LEMP Stack Manager                                  |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2022 MasEDI.Net (https://masedi.net/lemper)          |
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

# Work even if somebody does "bash lemper-cli.sh".
#set -exv -o pipefail # For verbose output.
set -e -o pipefail

# Version control.
export PROG_NAME && PROG_NAME=$(basename "$0")
export PROG_VERSION && PROG_VERSION="2.x.x"

# Test mode.
DRYRUN=false

# Make sure only root can run this script.
function requires_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        if ! hash sudo 2>/dev/null; then
            echo "${PROG_NAME} command must be run as 'root' or with sudo."
            exit 1
        else
            #echo "Switching to root user to run this script."
            sudo -E "$0" "$@"
            exit 0
        fi
    fi
}

requires_root "$@"

# Export LEMPer Stack configuration.
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
    echo "LEMPer Stack configuration required, but the file doesn't exist."
    echo "It should be created during installation process and placed under '/etc/lemper/lemper.conf'."
    exit 1
fi

# Set default variables.
LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
LEMPER_PASSWORD=${LEMPER_PASSWORD:-""}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-""}

# Set CLI plugins directory.
CLI_PLUGINS_DIR="/etc/lemper/cli-plugins"

# Color decorator.
RED=31
GREEN=32
YELLOW=33

##
# Helper Functions.
##
function begin_color() {
    local COLOR="${1}"
    echo -e -n "\e[${COLOR}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    local COLOR="${1}"
    shift
    begin_color "${COLOR}"
    echo "$@"
    end_color
}

function status() {
    echo_color "${GREEN}" "$@"
}

function warning() {
    echo_color "${YELLOW}" "$@"
}

function success() {
    echo_color "${GREEN}" -n "Success: " >&2
    echo "$@" >&2
}

function info() {
    echo_color "${YELLOW}" -n "Info: " >&2
    echo "$@" >&2
}

function error() {
    echo_color "${RED}" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"
    #echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function echo_ok() {
    echo_color "${GREEN}" "OK"
}

function echo_warn() {
    echo_color "${YELLOW}" "WARN"
}

function echo_err() {
    echo_color "${RED}" "ERROR"
}

# Run command.
function run() {
    if "${DRYRUN}"; then
        echo_color "${YELLOW}" -n "would run "
        echo "$@"
    else
        if ! "$@"; then
            local CMDSTR="$*"
            error "Failure running '${CMDSTR}', exiting."
            exit 1
        fi
    fi
}

## 
# Show usage
# output to STDERR.
##
function cmd_help() {
    cat <<- EOL
${PROG_NAME} ${PROG_VERSION}
Command line management tool for LEMPer Stack (Linux, Nginx, MySQL/MariaDB, PHP).

Usage: ${PROG_NAME} [command] [subcommand] [options]

LEMP Stack Management:
  create          Create a new virtual host (add a domain).
  add             Alias of 'create'.
  site            Virtual host management.
                        site list [options]          List all vhosts (table or JSON).
                        site show <domain> [options] Show detailed vhost config.
                        site enable <domain>         Enable a vhost.
                        site disable <domain>        Disable a vhost.
  manage          Manage existing virtual hosts (mod/ssl/rewrite).
  mod             Alias of 'manage'.

Database Management:
  db              MySQL/MariaDB database manager.
                        db create [options]          Create a new database.
                        db drop <name>               Delete a database.
                        db export [options]          Export a database to SQL.
                        db backup [options]          Create a timestamped backup (.sql.gz).
                        db restore [options]         Restore from a backup file.
                        db backup-schedule [options] Schedule automated backups via cron.
                        db account [subcommand]      Manage database user accounts.

System Administration:
  account         Interactive system user/account creator.
  adduser         Alias of 'account'.
  tui             Launch interactive TUI dashboard.
  selfssl         Generate self-signed SSL certificates.
  fixpermission   Fix file/directory permissions for web root.
  bench           Run server benchmark checks.

Options:
  --version, -v   Show version and exit.
  --help, -h      Show this help message.

For detailed help on a specific command:
  ${PROG_NAME} <command> --help
  ${PROG_NAME} <command> <subcommand> --help
EOL

exit 0
}

## 
# Show version.
##
function cmd_version() {
    echo "${PROG_NAME} version ${PROG_VERSION}"
    exit 0
}

##
# Main LEMPer CLI Wrapper.
##
function init_lemper_cli() {
    # Check command line arguments.
    if [[ -n "${1}" ]]; then
        CMD="${1}"
        shift # Pass the remaining arguments as sub-command options (parameters).

        case "${CMD}" in
            help | -h | --help)
                cmd_help
            ;;
            version | -v | --version)
                cmd_version
            ;;
            tui | --tui | -i | --interactive)
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-tui" ]]; then
                    # shellcheck disable=SC1090,SC1091
                    . "${CLI_PLUGINS_DIR}/lemper-tui" "$@"
                else
                    echo "${PROG_NAME}: TUI plugin not found."
                    echo "See '${PROG_NAME} --help' for more information."
                    exit 1
                fi
            ;;
            *)
                if [[ -x "${CLI_PLUGINS_DIR}/lemper-${CMD}" ]]; then
                    # Source the plugin executable file.
                    # shellcheck disable=SC1090
                    . "${CLI_PLUGINS_DIR}/lemper-${CMD}" "$@"
                else
                    echo "${PROG_NAME}: '${CMD}' is not valid command."
                    echo "See '${PROG_NAME} --help' for more information."
                    exit 1
                fi
            ;;
        esac
    else
        echo "${PROG_NAME}: missing required arguments"
        echo "See '${PROG_NAME} --help' for more information"
        exit 1
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_cli "$@"
