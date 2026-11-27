#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Simple LEMP Stack Manager                                  |
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

# Work even if somebody does "bash lemper-cli.sh".
#set -exv -o pipefail # For verbose output.
set -e -o pipefail

# Version control.
export PROG_NAME && PROG_NAME=$(basename "$0")
export PROG_VERSION && PROG_VERSION="4.0.0"
export LEMPER_CLI_BIN && LEMPER_CLI_BIN="$0"

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
            exec sudo -E -- "$0" "$@"
        fi
    fi
}

# Shared functions are loaded from the checkout or the installed root-only core.
CLI_SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "${CLI_SCRIPT_PATH}" ]]; do
    CLI_LINK=$(readlink "${CLI_SCRIPT_PATH}")
    if [[ "${CLI_LINK}" == /* ]]; then
        CLI_SCRIPT_PATH="${CLI_LINK}"
    else
        CLI_SCRIPT_PATH="$(dirname "${CLI_SCRIPT_PATH}")/${CLI_LINK}"
    fi
done
CLI_SOURCE_DIR=$(cd "$(dirname "${CLI_SCRIPT_PATH}")" && pwd -P)
CLI_LIBRARY_DIR="$CLI_SOURCE_DIR/../lib"
if [[ ! -f "$CLI_LIBRARY_DIR/core/registry.sh" ]]; then CLI_LIBRARY_DIR=/etc/lemper; fi
# The registry is static and has no configuration or host initialization.
# shellcheck source=/dev/null
. "$CLI_LIBRARY_DIR/core/registry.sh"
CLI_HELP=false
CLI_VERSION=false
for CLI_ARGUMENT in "$@"; do
    case "$CLI_ARGUMENT" in
        --password|--password=*|-P|-P=*) echo "Read the config password using --config-password-stdin." >&2; exit 1 ;;
    esac
    case "$CLI_ARGUMENT" in --help|-h) CLI_HELP=true ;; --version|-v) CLI_VERSION=true ;; esac
done
if [[ "$CLI_VERSION" == true || "${1:-}" == version ]]; then
    echo "$PROG_NAME version $PROG_VERSION"
    exit 0
fi
if [[ "$CLI_HELP" == true || "${1:-}" == help || $# -eq 0 ]]; then
    case "${1:-}" in
        site|create|add|manage|mod)
            # shellcheck source=/dev/null
            . "$CLI_LIBRARY_DIR/runtime/site/commands.sh"
            if [[ "${2:-}" == app ]]; then
                # shellcheck source=/dev/null
                . "$CLI_LIBRARY_DIR/runtime/site/apps.sh"
                lemper_site_app_help
            else lemper_site_help; fi ;;
        stack)
            # shellcheck source=/dev/null
            . "$CLI_LIBRARY_DIR/runtime/stack/commands.sh"
            stack_help ;;
        *)
            CLI_HELP_PLUGIN=""
            while IFS=: read -r CLI_HELP_NAME CLI_HELP_TARGET; do
                [[ "$CLI_HELP_TARGET" != "lemper-${1:-}" ]] || CLI_HELP_PLUGIN="$CLI_HELP_NAME"
            done < <(lemper_command_plugins)
            if [[ -n "$CLI_HELP_PLUGIN" && -f "$CLI_LIBRARY_DIR/$CLI_HELP_PLUGIN.sh" ]]; then
                (
                    # Pure helpers allow existing plugins to handle --help without private config.
                    # shellcheck source=/dev/null
                    . "$CLI_LIBRARY_DIR/core/loader.sh" || exit 1
                    # shellcheck source=/dev/null
                    . "$CLI_LIBRARY_DIR/$CLI_HELP_PLUGIN.sh" --help
                )
            else
                # shellcheck source=/dev/null
                . "$CLI_LIBRARY_DIR/runtime/help.sh"
                lemper_runtime_help
            fi ;;
    esac
    exit 0
fi
# Full-stack operations share the entry adapter with compatibility scripts.
# Route before config loading: first installation accepts an explicit profile.
if [[ "${1:-}" == stack && "${2:-}" =~ ^(install|remove|update)$ ]]; then
    CLI_ALL=false
    CLI_STACK_ARGS=()
    for CLI_ARGUMENT in "${@:2}"; do
        if [[ "$CLI_ARGUMENT" == --all ]]; then
            [[ "$CLI_ALL" == false ]] || { echo "Duplicate --all." >&2; exit 1; }
            CLI_ALL=true
        else
            CLI_STACK_ARGS+=("$CLI_ARGUMENT")
        fi
    done
    if [[ "$CLI_ALL" == true ]]; then
        export LEMPER_ROOT
        LEMPER_ROOT=$(cd "$CLI_LIBRARY_DIR/.." && pwd -P) || exit 1
        export LEMPER_ENTRY_CANONICAL=true
        # shellcheck source=/dev/null
        . "$CLI_LIBRARY_DIR/runtime/stack/entry.sh" || exit 1
        lemper_entry_main "${CLI_STACK_ARGS[@]}"
        exit $?
    fi
fi
requires_root "$@"

if [[ -f "${CLI_SOURCE_DIR}/../lib/core/loader.sh" ]]; then
    # Core modules are linted independently; avoid repeated expansion through every installer.
    # shellcheck source=/dev/null
    . "${CLI_SOURCE_DIR}/../lib/core/loader.sh"
else
    # Installed copy of the core already analyzed through the checkout loader.
    # shellcheck disable=SC1091
    . /etc/lemper/core/loader.sh
fi


# Read the decryption secret from protected input before loading the profile.
LEMPER_CONFIG_PASSWORD=""
new_args=()
for CLI_ARGUMENT in "$@"; do
    if [[ "$CLI_ARGUMENT" == --config-password-stdin ]]; then
        IFS= read -rs LEMPER_CONFIG_PASSWORD || [[ -n "$LEMPER_CONFIG_PASSWORD" ]] || exit 1
        [[ -n "$LEMPER_CONFIG_PASSWORD" ]] || exit 1
    else
        new_args+=("$CLI_ARGUMENT")
    fi
done
set -- "${new_args[@]}"

CLI_CONFIG_PASSWORD="${LEMPER_CONFIG_PASSWORD}"

# Encryption helpers (also available in lib/lemper-encrypt.sh).
ENCRYPT_CONFIG_AT_REST=${ENCRYPT_CONFIG_AT_REST:-false}

function is_config_encrypted() {
    core_is_config_encrypted "$@"
}

function secure_shred() {
    core_secure_shred "$@"
}

function resolve_config_password() {
    core_resolve_config_password
}

function decrypt_config_file() {
    local encrypted_file="${1}"
    local output_file="${2:-}"
    local password
    password=$(resolve_config_password) || return 1

    if [[ -z "${output_file}" ]]; then
        output_file=$(mktemp /tmp/lemper_config.XXXXXX)
    fi

    if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
        -pass fd:3 3<<<"${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
        # Legacy files used the default OpenSSL KDF.
        if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 \
            -pass fd:3 3<<<"${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
            secure_shred "${output_file}"
            return 1
        fi
    fi
    echo "${output_file}"
}

# Export LEMPer Stack configuration.
CONFIG_FILE="${LEMPER_CONFIG_FILE:-/etc/lemper/lemper.conf}"
if [[ -f "${CONFIG_FILE}" ]]; then
    source_file="${CONFIG_FILE}"
    temp_decrypted=""

    # Check if config is encrypted.
    if is_config_encrypted "${CONFIG_FILE}"; then
        # The header is authoritative: the flag is not inherited under sudo.
        if ! temp_decrypted=$(decrypt_config_file "${CONFIG_FILE}"); then
            echo "Failed to decrypt configuration." >&2
            echo "Use --config-password-stdin if a custom config password was set during install." >&2
            exit 1
        fi
        source_file="${temp_decrypted}"
    fi

    if ! validate_config_file "${source_file}"; then
        [[ -z "${temp_decrypted}" ]] || secure_shred "${temp_decrypted}"
        exit 1
    fi
    while IFS=$'\t' read -r key _; do
        unset "${key}" 2>/dev/null || true
    done < <(safe_parse_dotenv "${source_file}")
    while IFS=$'\t' read -r key value; do
        export "${key}=${value}"
    done < <(safe_parse_dotenv "${source_file}")

    # Securely clean up temp decrypted file.
    if [[ -n "${temp_decrypted}" ]]; then
        secure_shred "${temp_decrypted}"
    fi
else
    echo "LEMPer Stack configuration required, but the file doesn't exist."
    echo "It should be created during installation process and placed under '/etc/lemper/lemper.conf'."
    exit 1
fi

[[ -z "${CLI_CONFIG_PASSWORD}" ]] || LEMPER_CONFIG_PASSWORD="${CLI_CONFIG_PASSWORD}"

# Set default variables.
LEMPER_USERNAME=${LEMPER_USERNAME:-"lemper"}
LEMPER_PASSWORD=${LEMPER_PASSWORD:-""}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-""}

# Set CLI plugins directory.
export CLI_PLUGINS_DIR="/etc/lemper/cli-plugins"

# Color decorator.
export RED=31 GREEN=32 YELLOW=33

##
# Helper Functions.
##
function begin_color() {
    core_begin_color "$@"
}

function end_color() {
    core_end_color
}

function echo_color() {
    core_echo_color "$@"
}

function status() {
    core_status "$@"
}

function warning() {
    core_warning "$@"
}

function success() {
    core_success "$@"
}

function info() {
    core_info "$@"
}

function error() {
    core_error "$@"
}

# Prints an error message and exits with an error code.
function fail() {
    core_fail "$@"
}

function echo_ok() {
    core_echo_ok "$@"
}

function echo_warn() {
    core_echo_warn "$@"
}

function echo_err() {
    core_echo_err "$@"
}

# Run command.
function run() {
    core_run "$@"
}

# Portable in-place sed (GNU and BSD).
function sed_inplace() {
    local backup_suffix=""
    local extra_opts=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -E|-r)
                extra_opts+=("${1}")
                shift
            ;;
            -b|--backup)
                backup_suffix=".bak"
                shift
            ;;
            --)
                shift
                break
            ;;
            -*)
                error "sed_inplace: unsupported option '${1}'."
                return 2
            ;;
            *)
                break
            ;;
        esac
    done

    if [[ $# -lt 2 ]]; then
        error "Usage: sed_inplace [-E|-r] [-b] 'script' file [file...]"
        return 2
    fi

    local script="${1}"
    shift

    if [[ "${DRYRUN}" == true ]]; then
        echo_color "${YELLOW}" -n "would run "
        echo "sed -i${backup_suffix} ${extra_opts[*]} '${script}' $*"
        return 0
    fi

    local result=0
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i "${backup_suffix}" "${extra_opts[@]}" "${script}" "$@" || result=$?
    else
        sed -i"${backup_suffix}" "${extra_opts[@]}" "${script}" "$@" || result=$?
    fi

    if [[ "${result}" -ne 0 ]]; then
        error "Failure running sed in-place on: $*"
        return 1
    fi
}

# Escape backslashes, ampersands, and slashes for sed replacements.
function sanitize_sed_replacement() {
    core_sanitize_sed_replacement "$@"
}

function memory_to_mb() {
    core_memory_to_mb "$@"
}

function get_memory_mb() {
    core_get_memory_mb
}

function detect_resource_profile() {
    core_detect_resource_profile
}

function calc_php_max_children() {
    core_calc_php_max_children "$@"
}

function calc_php_pool_sizing() {
    core_calc_php_pool_sizing "$@"
}

function create_php_temp_dirs() {
    core_create_php_temp_dirs "$@"
}

##
# Print a top-level command and its description.
##
function help_entry() {
    core_help_entry "$@"
}

##
# Print a subcommand and its description, nested under its parent.
##
function help_subentry() {
    core_help_subentry "$@"
}

## 
# Show usage
# output to STDERR.
##
function cmd_help() {
    core_cmd_help
}

## 
# Show version.
##
function cmd_version() {
    core_cmd_version
}

##
# Main LEMPer CLI Wrapper.
##
function init_lemper_cli() {
    core_init_lemper_cli "$@"
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_cli "$@"
