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
export PROG_VERSION && PROG_VERSION="2.x.x"
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
    [[ -f "${file}" ]] && head -c 10 "${file}" | grep -qE '^(U2FsdGVkX1|Salted__)'
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
    # Stored key file (generated at install time, mode 0600, root-only).
    # Preferred over LEMPER_PASSWORD because sudo strips the environment.
    if [[ -f /etc/lemper/.config_key ]]; then
        cat /etc/lemper/.config_key
        return 0
    fi
    # Legacy fallback for installs predating the key file.
    if [[ -n "${LEMPER_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_PASSWORD}"
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

    if ! openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
        -k "${password}" -in "${encrypted_file}" -out "${output_file}" 2>/dev/null; then
        # Legacy files used the default OpenSSL KDF.
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
        # The header is authoritative: the flag is not inherited under sudo.
        if ! temp_decrypted=$(decrypt_config_file "${CONFIG_FILE}"); then
            echo "Failed to decrypt configuration." >&2
            echo "Use --password if a custom config password was set during install." >&2
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
    local INPUT=${1}
    printf '%s' "${INPUT}" | sed -e 's/[\\&]/\\&/g' -e 's/\//\\\//g'
}

function memory_to_mb() {
    local VALUE="${1:-256M}"

    if [[ ! "${VALUE}" =~ ^[0-9]+[GgMm]?$ ]]; then
        echo 256
        return 0
    fi

    case "${VALUE}" in
        *[Gg]) echo $(( ${VALUE%[Gg]} * 1024 )) ;;
        *[Mm]) echo $(( ${VALUE%[Mm]} )) ;;
        *)     echo $(( VALUE )) ;;
    esac
}

function get_memory_mb() {
    if [[ "${LEMPER_MEMORY_MB:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "${LEMPER_MEMORY_MB}"
        return 0
    fi

    local MEM_MB
    MEM_MB=$(awk '/^MemTotal:/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)

    local CGROUP_LIMIT
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
    fi

    awk -v total="${MEM_MB:-0}" -v limit="${CGROUP_LIMIT:-0}" 'BEGIN {
        if (limit ~ /^[0-9]+$/) {
            mb = int(limit / 1048576);
            if (mb > 0 && mb < 1048576 && (total == 0 || mb < total)) total = mb;
        }
        printf "%.0f\n", total;
    }'
}

function detect_resource_profile() {
    local PROFILE="${LEMPER_PROFILE:-${SERVER_PROFILE:-auto}}"

    case "${PROFILE}" in
        micro|small|medium|large)
            echo "${PROFILE}"
            return 0
            ;;
        auto|"") ;;
        *)
            warning "Unknown resource profile '${PROFILE}', using auto-detection." >&2
            ;;
    esac

    local MEM_MB
    MEM_MB=$(get_memory_mb)

    if (( MEM_MB <= 0 )); then
        echo "small"
    elif (( MEM_MB < 1024 )); then
        echo "micro"
    elif (( MEM_MB < 2048 )); then
        echo "small"
    elif (( MEM_MB < 4096 )); then
        echo "medium"
    else
        echo "large"
    fi
}

function calc_php_max_children() {
    local PROFILE="${1:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)
    local MEMLIMIT="${2:-256}"
    local CAP

    case "${PROFILE}" in
        micro)  CAP=4 ;;
        small)  CAP=6 ;;
        medium) CAP=10 ;;
        large)  CAP=16 ;;
        *)      CAP=6 ;;
    esac

    local PER_CHILD=$(( MEMLIMIT / 3 ))
    (( PER_CHILD < 64 )) && PER_CHILD=64

    local TOTAL
    TOTAL=$(get_memory_mb)
    if (( TOTAL > 0 )); then
        local BUDGET=$(( TOTAL * 35 / 100 ))
        local BY_MEM=$(( BUDGET / PER_CHILD ))
        (( BY_MEM < 2 )) && BY_MEM=2
        (( BY_MEM < CAP )) && CAP=${BY_MEM}
    fi

    (( CAP < 2 )) && CAP=2
    echo "${CAP}"
}

function calc_php_pool_sizing() {
    local PROFILE="${1:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)
    local MEMLIMIT="${2:-256}"
    local MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-}"

    if [[ ! "${MAX_CHILDREN}" =~ ^[0-9]+$ || "${MAX_CHILDREN}" -lt 2 ]]; then
        MAX_CHILDREN=$(calc_php_max_children "${PROFILE}" "${MEMLIMIT}")
    fi

    local START=$(( MAX_CHILDREN / 2 ))
    (( START > 2 )) && START=2
    (( START < 1 )) && START=1

    local MAX_SPARE=$(( MAX_CHILDREN / 2 ))
    (( MAX_SPARE < START )) && MAX_SPARE=${START}

    echo "${MAX_CHILDREN} ${START} 1 ${MAX_SPARE}"
}

function create_php_temp_dirs() {
    local POOLNAME="${1}"
    local TEMP_BASE="/var/lib/php/lemper/${POOLNAME}"

    run mkdir -p "${TEMP_BASE}/tmp" "${TEMP_BASE}/sessions" \
        "${TEMP_BASE}/wsdlcache" "${TEMP_BASE}/opcache" && \
    run chmod 700 "${TEMP_BASE}" "${TEMP_BASE}/tmp" "${TEMP_BASE}/sessions" \
        "${TEMP_BASE}/wsdlcache" "${TEMP_BASE}/opcache" && \
    run chown -hR "${POOLNAME}:${POOLNAME}" "${TEMP_BASE}"
}

##
# Print a top-level command and its description.
##
function help_entry() {
    printf '  %-16s%s\n' "${1}" "${2}"
}

##
# Print a subcommand and its description, nested under its parent.
##
function help_subentry() {
    printf '    %-28s  %s\n' "${1}" "${2}"
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
EOL

    echo
    echo "LEMP Stack Management:"
    help_entry create "Create a new virtual host (add a domain)."
    help_entry add "Alias of 'create'."
    help_entry site "Virtual host management."
    help_subentry "list [options]" "List all vhosts (table or JSON)."
    help_subentry "show <domain> [options]" "Show detailed vhost config."
    help_subentry "enable <domain>" "Enable a vhost."
    help_subentry "disable <domain>" "Disable a vhost."
    help_entry manage "Manage existing virtual hosts (mod/ssl/rewrite)."
    help_entry mod "Alias of 'manage'."

    echo
    echo "Database Management:"
    help_entry db "MySQL/MariaDB database manager."
    help_subentry "create [options]" "Create a new database."
    help_subentry "drop <name>" "Delete a database."
    help_subentry "export [options]" "Export a database to SQL."
    help_subentry "backup [options]" "Create a timestamped backup (.sql.gz)."
    help_subentry "restore [options]" "Restore from a backup file."
    help_subentry "backup-schedule [options]" "Schedule automated backups via cron."
    help_subentry "account <subcommand>" "Manage database user accounts."

    echo
    echo "System Administration:"
    help_entry account "Create a system user account."
    help_entry adduser "Interactively add a system user."
    help_entry tui "Launch interactive TUI dashboard."
    help_entry backup "Back up and restore LEMPer-managed configuration."
    help_subentry "create [options]" "Archive system configuration."
    help_subentry "list [options]" "List configuration archives."
    help_subentry "show <archive|latest>" "Show manifest details."
    help_subentry "verify <archive|latest>" "Check archive integrity."
    help_subentry "restore [options]" "Restore an archive (snapshots first)."
    help_subentry "prune [options]" "Delete old archives."
    help_entry selfssl "Generate self-signed SSL certificates."
    help_entry fixpermission "Fix file/directory permissions for web root."
    help_entry bench "Run server benchmark checks."
    help_entry modsec "ModSecurity WAF status, reporting, and auto-tuning."
    help_subentry status "Show engine and CRS status."
    help_subentry report "Summarize triggered rules."
    help_subentry "tune [options]" "Adjust paranoia/thresholds."
    help_entry update "Patch PHP2Shell and keep the stack current."
    help_subentry check "Audit PHP/nginx/MariaDB state."
    help_subentry php "Patch PHP; mitigate EOL pools."
    help_subentry nginx "Upgrade package-managed nginx from MyGuard."
    help_subentry mariadb "Upgrade MariaDB packages."
    help_subentry lemper "Reinstall CLI, plugins, and web admin tools."
    help_subentry all "Run every update step."

    cat <<- EOL

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
