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

# Pre-parse --password / -P flag before loading config (may need it for decryption).
# Scans all args, extracts password, and rebuilds args list without it.
LEMPER_CONFIG_PASSWORD=""
new_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --password=*)
            LEMPER_CONFIG_PASSWORD="${1#--password=}"
            shift
            ;;
        --password)
            LEMPER_CONFIG_PASSWORD="${2:-}"
            shift 2
            ;;
        -P=*)
            LEMPER_CONFIG_PASSWORD="${1#-P=}"
            shift
            ;;
        -P)
            LEMPER_CONFIG_PASSWORD="${2:-}"
            shift 2
            ;;
        *)
            new_args+=("$1")
            shift
            ;;
    esac
done
if [[ ${#new_args[@]} -gt 0 ]]; then
    set -- "${new_args[@]}"
fi

# Encryption helpers (also available in lib/lemper-encrypt.sh).
ENCRYPT_CONFIG_AT_REST=${ENCRYPT_CONFIG_AT_REST:-false}

function is_config_encrypted() {
    local file="${1}"
    [[ -f "${file}" ]] && head -1 "${file}" | grep -q "^Salted__"
}

function secure_shred() {
    local file="${1}"
    [[ -f "${file}" ]] || return 0
    if command -v shred &>/dev/null; then
        shred -u -z -n 3 "${file}" 2>/dev/null || rm -f "${file}"
    else
        rm -f "${file}"
    fi
}

function resolve_config_password() {
    if [[ -n "${LEMPER_CONFIG_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_CONFIG_PASSWORD}"
        return 0
    fi
    if [[ -n "${LEMPER_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_PASSWORD}"
        return 0
    fi
    # Stored key file (generated at install time, mode 0600, root-only).
    if [[ -f /etc/lemper/.config_key ]]; then
        cat /etc/lemper/.config_key
        return 0
    fi
    return 1
}

function decrypt_config_file() {
    local encrypted_file="${1}"
    local output_file="${2:-}"
    local password
    password=$(resolve_config_password) || return 1

    if [[ -z "${output_file}" ]]; then
        output_file=$(mktemp /tmp/lemper_config.XXXXXX)
    fi

    if ! openssl enc -aes-256-gcm -d -a -salt -md sha256 \
        -k "${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
        if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 \
            -k "${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
            secure_shred "${output_file}"
            return 1
        fi
    fi
    echo "${output_file}"
}

# Export LEMPer Stack configuration.
CONFIG_FILE="/etc/lemper/lemper.conf"
if [[ -f "${CONFIG_FILE}" ]]; then
    source_file="${CONFIG_FILE}"
    temp_decrypted=""

    # Check if config is encrypted.
    if is_config_encrypted "${CONFIG_FILE}"; then
        if [[ "${ENCRYPT_CONFIG_AT_REST}" != true ]]; then
            echo "Config is encrypted but ENCRYPT_CONFIG_AT_REST is not enabled. Cannot load." >&2
            echo "Set ENCRYPT_CONFIG_AT_REST=true in config or provide --password." >&2
            exit 1
        fi

        temp_decrypted=$(decrypt_config_file "${CONFIG_FILE}")
        if [[ -z "${temp_decrypted}" ]]; then
            echo "Failed to decrypt configuration." >&2
            exit 1
        fi
        source_file="${temp_decrypted}"
    fi

    # Load configuration using safe parser (no eval — SEC-06 mitigation).
    # Clean environment first.
    while IFS=$'\t' read -r key _; do
        unset "${key}" 2>/dev/null || true
    done < <(grep -v '^#' "${source_file}" | grep -v '^\[' | \
        while IFS='=' read -r k v; do [[ "${k}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && printf '%s\t%s\n' "${k}" "${v}"; done)

    # Safely load key=value pairs without eval.
    while IFS='=' read -r key value; do
        [[ -z "${key}" || "${key}" == \#* || "${key}" == \[* ]] && continue
        key="${key// /}"
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        if [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            export "${key}=${value}"
        fi
    done < "${source_file}"

    # Securely clean up temp decrypted file.
    if [[ -n "${temp_decrypted}" ]]; then
        secure_shred "${temp_decrypted}"
    fi
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
  modsec          ModSecurity WAF status, reporting, and auto-tuning.
                        modsec status                Show engine and CRS status.
                        modsec report                Summarize triggered rules.
                        modsec tune [options]        Adjust paranoia/thresholds.
  update          Patch PHP2Shell and keep the stack current.
                        update check                 Audit PHP/nginx/MariaDB state.
                        update php                   Patch PHP; mitigate EOL pools.
                        update nginx                 Upgrade package-managed nginx.
                        update mariadb               Upgrade MariaDB packages.
                        update lemper                Refresh CLI and plugins.
                        update all                   Run every update step.

Options:
  --version, -v   Show version and exit.
  --help, -h      Show this help message.
  --password=xxx  Decrypt encrypted config (also: -P xxx).
                  Falls back to LEMPER_PASSWORD or /etc/lemper/.config_key.

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
