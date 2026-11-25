#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer Helper Functions                                                 |
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

SCRIPTS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
BASE_DIR=${BASE_DIR:-"$(cd "${SCRIPTS_DIR}/.." >/dev/null 2>&1 && pwd)"}
export SCRIPTS_DIR

# Core modules are linted independently; avoid repeated expansion through every installer.
# shellcheck source=/dev/null
. "${LEMPER_CORE_DIR:-${SCRIPTS_DIR}/../lib/core}/loader.sh" || return 1

##
# Parse a key=value line from a config file safely.
# Reads a single line and splits on the first '=' using IFS, avoiding eval.
# Returns: "key<TAB>value" or nothing if the line is a comment/blank/section.
#
# Must be defined before the dotenv loading block below runs.
##
function safe_parse_dotenv() {
    core_safe_parse_dotenv "$@"
}

##
# Set KEY=VALUE in an env file without shell or sed interpretation.
# Values may contain spaces, slashes, ampersands, quotes, and '=' characters.
# The first matching key is replaced; the key is appended when absent.
# Usage: set_env_value FILE KEY VALUE
##
function set_env_value() {
    core_set_env_value "$@"
}

##
# Validate an OpenSSH public key line (ssh-rsa, ed25519, ECDSA, or FIDO).
# Returns 0 when the key type is recognised and a base64 body is present.
##
function is_ssh_public_key() {
    core_is_ssh_public_key "$@"
}

# The dotenv lives at the repository root: either BASE_DIR itself or its
# parent when BASE_DIR points at scripts/. LEMPER_ENV_FILE lets an updater
# point at the installed /etc/lemper/lemper.conf without copying it.
if [[ -n "${LEMPER_ENV_FILE:-}" && -f "${LEMPER_ENV_FILE}" ]]; then
    ENVFILE="${LEMPER_ENV_FILE}"
elif [[ -f "${BASE_DIR}/.env" ]]; then
    ENVFILE="${BASE_DIR}/.env"
else
    ENVFILE="$( cd "${SCRIPTS_DIR}/.." >/dev/null 2>&1 && pwd )/.env"
fi

if [ -f "${ENVFILE}" ]; then
    if ! validate_config_file "${ENVFILE}"; then
        if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 1; else exit 1; fi
    fi
    # Clean environment first — unset existing vars from .env.
    # shellcheck source=.env.dist
    while IFS=$'\t' read -r key _; do
        unset "${key}" 2>/dev/null || true
    done < <(safe_parse_dotenv "${ENVFILE}")

    # shellcheck source=.env.dist
    # Safe parser: avoids eval-based source <(...) which is an injection vector.
    # Uses IFS-based line-by-line parsing with key name validation.
    while IFS=$'\t' read -r key value; do
        export "${key}=${value}"
    done < <(safe_parse_dotenv "${ENVFILE}")
else
    echo "Environment variables required, but the dotenv file doesn't exist at ${ENVFILE}. Copy .env.dist to .env first!"
    exit 1
fi

# Direct access? make as dry run mode.
DRYRUN=${DRYRUN:-true}

# Init timezone, set default to UTC.
TIMEZONE=${TIMEZONE:-"UTC"}

# Set default color decorator.
export RED=31 GREEN=32 YELLOW=33 BLUE=34

function begin_color() {
    core_begin_color "$@"
}

function end_color() {
    core_end_color
}

function echo_color() {
    core_echo_color "$@"
}

function error() {
    core_error "$@"
}

# Prints an error message and exits with an error code.
function fail() {
    core_fail "$@"
}

function success() {
    core_success "$@"
}

function info() {
    core_info "$@"
}

function status() {
    core_status "$@"
}

function warning() {
    core_warning "$@"
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

# Make sure only root can run LEMPer script.
function requires_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        if ! hash sudo 2>/dev/null; then
            echo "Installer script must be run as 'root' or with sudo."
            exit 1
        else
            #echo "Switching to root user to run installer script."
            sudo -E -H "$0" "$@"
            exit 0
        fi
    fi

    #success "Root privileges granted."
}

# Run command
function run() {
    core_run "$@"
}

# Create isolated PHP temp/session directories for an FPM pool.
# They live outside the user's home so uploaded/session files cannot be
# reached from the web root if the application is compromised.
function create_php_temp_dirs() {
    core_create_php_temp_dirs "$@"
}

##
# Progress indicator — shows a step counter (e.g. [3/10]).
##
PROGRESS_TOTAL=${PROGRESS_TOTAL:-0}
PROGRESS_CURRENT=${PROGRESS_CURRENT:-0}
lemper_load_module core/progress || return 1

function progress() {
    local description="${1}"
    local eta=""
    if [[ "${PROGRESS_ETA:-true}" == true && -t 1 && "${DRYRUN:-false}" != true && -n "${PROGRESS_STARTED:-}" ]]; then
        eta=$(lemper_progress_eta "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$PROGRESS_STARTED") || eta=""
    fi
    PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
    if [[ "${PROGRESS_TOTAL}" -gt 0 ]]; then
        if [[ -t 1 ]]; then echo_color "${BLUE}" -n "[${PROGRESS_CURRENT}/${PROGRESS_TOTAL}] "
        else printf '[%s/%s] ' "$PROGRESS_CURRENT" "$PROGRESS_TOTAL"; fi
    else
        if [[ -t 1 ]]; then echo_color "${BLUE}" -n "▸ "
        else printf '> '; fi
    fi
    echo "${description}${eta:+ (ETA $eta)}"
}

##
# Spinner — shows an animated spinner while a command runs.
# Only activates in interactive TTY mode (not in CI/dry-run).
##
SPINNER_PID=""

function spinner_start() {
    local message="${1}"
    # Only show spinner if we have a TTY and not in dry-run mode.
    if [[ "${DRYRUN}" == true ]] || [[ ! -t 1 ]]; then
        return 0
    fi

    echo -n "${message} "
    local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0 started=$SECONDS
    (
        while true; do
            local idx=$((i % ${#spinner_chars}))
            printf '\r%s %s (%ds)' "$message" "${spinner_chars:${idx}:1}" "$((SECONDS - started))"
            sleep 0.1
            i=$((i + 1))
        done
    ) &
    SPINNER_PID=$!
}

function spinner_stop() {
    if [[ -n "${SPINNER_PID}" ]] && kill -0 "${SPINNER_PID}" 2>/dev/null; then
        kill "${SPINNER_PID}" 2>/dev/null || true
        wait "${SPINNER_PID}" 2>/dev/null || true
        SPINNER_PID=""
        # Clear the spinner and elapsed-time line before the completion message.
        printf '\r\033[2K'
    fi
}

##
# Record that LEMPer provisioned a service. Uninstallers use this marker to
# avoid removing packages and configuration that predate LEMPer.
##
function mark_lemper_provisioned() {
    local service="${1}"

    if [[ "${DRYRUN}" == true ]]; then
        echo_color "${YELLOW}" -n "would mark "
        echo "${service} as provisioned by LEMPer"
        return 0
    fi

    run mkdir -p /etc/lemper/installed
    run touch "/etc/lemper/installed/${service}"
}

##
# Check whether LEMPer provisioned a service.
#
# Returns 0 when the marker exists, 1 otherwise.
##
function lemper_provisioned() {
    local service="${1}"
    [[ -f "/etc/lemper/installed/${service}" ]]
}

##
# Run a command with a progress spinner and description.
# Usage: run_spinner "Description" command args...
##
function run_spinner() {
    local description="${1}"
    local started=$SECONDS
    shift

    spinner_start "${description}"

    local status=0
    if [[ "${DRYRUN}" == true ]]; then
        info "Would run ${description}."
    else
        "$@" || status=$?
    fi

    spinner_stop

    if [[ "${status}" -ne 0 ]]; then
        error "Failure during ${description}, exiting."
        exit 1
    fi

    if [[ "${DRYRUN}" != true ]]; then
        success "${description} — done ($((SECONDS - started))s)"
    fi
}

##
# Portable in-place sed wrapper.
# On GNU/Linux (sed 4.x), `sed -i 's/.../.../' file` works without a backup suffix.
# On macOS/BSD (sed), `sed -i` requires an empty string argument: `sed -i '' 's/.../.../' file`.
# This wrapper detects the platform and uses the correct syntax.
#
# Usage:
#   sed_inplace "s/old/new/g" /path/to/file
#   sed_inplace "s/old/new/g" file1 file2 file3
#   sed_inplace -E "s/(old|older)/new/g" /path/to/file
#   sed_inplace -b "s/old/new/g" /path/to/file   # keep a .bak backup
##
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

    local status=0
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i "${backup_suffix}" "${extra_opts[@]}" "${script}" "$@" || status=$?
    else
        sed -i"${backup_suffix}" "${extra_opts[@]}" "${script}" "$@" || status=$?
    fi

    if [[ "${status}" -ne 0 ]]; then
        error "Failure running sed in-place on: $*"
        return 1
    fi
}

##
# Parse a key=value line from a config file safely.
# Defined at the top of this file: the dotenv loading block runs on source.
##

# Check if RedHat package (.rpm) is installed.
function redhat_is_installed() {
    local package_name="${1}"
    rpm -qa "${package_name}" | grep -q .
}

# Check if Debian package (.deb) is installed.
function debian_is_installed() {
    local package_name="${1}"
    dpkg -l "${package_name}" | grep ^ii | grep -q .
}

# Usage:
# install_dependencies install_pkg_cmd is_pkg_installed_cmd dep1 dep2 ...
#
# install_pkg_cmd is a command to install a dependency, e.g. apt-get install (Debian)
# is_pkg_installed_cmd is a command that returns true if the dependency is, e.g. debian_is_installed
# already installed
# each dependency is a package name
function install_dependencies() {
    local install_pkg_cmd="${1}"
    local is_pkg_installed_cmd="${2}"
    shift 2

    local missing_dependencies=""

    for package_name in "$@"; do
        if ! "${is_pkg_installed_cmd}" "${package_name}"; then
            missing_dependencies="${missing_dependencies} ${package_name}"
        fi
    done
    if [ -n "${missing_dependencies}" ]; then
        info "Detected that we're missing the following depencencies:"
        echo "     ${missing_dependencies}"
        info "Installing them:"
        # shellcheck disable=SC2086
        run ${install_pkg_cmd} ${missing_dependencies}
    fi
}

function gcc_too_old() {
    # We need gcc >= 4.8
    local gcc_major_version && \
    gcc_major_version=$(gcc -dumpversion | awk -F. '{print ${1}}')
    if [ "${gcc_major_version}" -lt 4 ]; then
        return 0 # too old
    elif [ "${gcc_major_version}" -gt 4 ]; then
        return 1 # plenty new
    fi
    # It's gcc 4.x, check if x >= 8:
    local gcc_minor_version && \
    gcc_minor_version=$(gcc -dumpversion | awk -F. '{print $2}')
    test "${gcc_minor_version}" -lt 8
}

# If a string is very simple we don't need to quote it.    But we should quote
# everything else to be safe.
function needs_quoting() {
    echo "$@" | grep -q '[^a-zA-Z0-9./_=-]'
}

function escape_for_quotes() {
    echo "$@" | sed -e 's~\\~\\\\~g' -e "s~'~\\\\'~g"
}

function quote_arguments() {
    local argument_str=""
    for argument in "$@"; do
        if [ -n "${argument_str}" ]; then
            argument_str+=" "
        fi
        if needs_quoting "${argument}"; then
            argument="'$(escape_for_quotes "${argument}")'"
        fi
        argument_str+="${argument}"
    done
    echo "${argument_str}"
}

# Delete if directory exists.
function delete_if_already_exists() {
    if [[ "${DRYRUN}" == true ]]; then return; fi

    local directory="${1}"
    if [ -d "${directory}" ]; then
        if [[ ${#directory} -lt 8 ]]; then
            fail "Not deleting ${directory}; name is suspiciously short. Something is wrong."
        fi

        if [[ "${FORCE_REMOVE}" == true ]]; then
            yn="y"
        else
            echo_color "${YELLOW}" -n "${directory} already exists, OK to delete?"
            read -rp " [y/n] " yn
        fi

        if [[ "${yn}" == Y* || "${yn}" == y* ]]; then
            run rm -rf "${directory}" && \
            success "${directory} deleted."
        else
            info "Deletion cancelled."
        fi
    fi
}

function version_sort() {
    # We'd rather use sort -V, but that's not available on Centos 5.    This works
    # for versions in the form A.B.C.D or shorter, which is enough for our use.
    sort -t '.' -k 1,1 -k 2,2 -k 3,3 -k 4,4 -g
}

# Compare two numeric versions in the form "A.B.C".    Works with version numbers
# having up to four components, since that's enough to handle nginx (3)
function version_older_than() {
    local test_version && \
    test_version=$(echo "$@" | tr ' ' '\n' | version_sort | head -n 1)
    local compare_to="${2}"
    local older_version="${test_version}"

    test "${older_version}" != "${compare_to}"
}

function nginx_download_report_error() {
    fail "Couldn't automatically determine the latest nginx version: failed to $* Nginx's download page"
}

function get_nginx_versions_available() {
    # Scrape nginx's download page to try to find the all available nginx versions.
    nginx_download_url="https://nginx.org/en/download.html"

    local nginx_download_page
    nginx_download_page=$(curl -sS --fail "${nginx_download_url}") || \
        nginx_download_report_error "download"

    local download_refs
    download_refs=$(echo "${nginx_download_page}" | \
        grep -owE '"/download/nginx-[0-9.]*\.tar\.gz"') || \
        nginx_download_report_error "parse"

    versions_available=$(echo "${download_refs}" | \
        sed -e 's~^"/download/nginx-~~' -e 's~\.tar\.gz"$~~') || \
        nginx_download_report_error "extract versions from"

    echo "${versions_available}"
}

# Try to find the most recent nginx version (mainline).
function determine_latest_nginx_version() {
    local versions_available
    local latest_version

    versions_available=$(get_nginx_versions_available)
    latest_version=$(echo "${versions_available}" | version_sort | tail -n 1) || \
        report_error "determine latest (mainline) version from"

    if version_older_than "${latest_version}" "1.14.2"; then
        fail "Expected the latest version of nginx to be at least 1.14.2 but found
${latest_version} on ${nginx_download_url}"
    fi

    echo "${latest_version}"
}

# Try to find the stable nginx version (mainline).
function determine_stable_nginx_version() {
    local versions_available
    local stable_version

    versions_available=$(get_nginx_versions_available)
    stable_version=$(echo "${versions_available}" | version_sort | tail -n 2 | sort -r | tail -n 1) || \
        report_error "determine stable (LTS) version from"

    if version_older_than "1.14.2" "${latest_version}"; then
        fail "Expected the latest version of nginx to be at least 1.14.2 but found
${latest_version} on ${nginx_download_url}"
    fi

    echo "${stable_version}"
}

# Validate Nginx configuration.
function validate_nginx_config() {
    core_validate_nginx_config "$@"
}

# Validate FQDN domain.
# Uses ERE (grep -E) with a separate length check for portability.
# PCRE (grep -P) lookahead/lookbehind is not available on all platforms.
function validate_fqdn() {
    core_validate_fqdn "$@"
}

# Validate IPv4 address.
function validate_ipv4() {
    core_validate_ipv4 "$@"
}

# Validate Unix username (RFC 932 + POSIX: alphanumeric, dash, underscore; 1-32 chars, starts with letter).
function validate_username() {
    core_validate_username "$@"
}

# Sanitize a string for safe use in sed replacement patterns.
# Escapes backslash, forward-slash, ampersand, and newline to prevent
# injection when interpolating user input into sed s/.../.../ commands.
function sanitize_sed_replacement() {
    core_sanitize_sed_replacement "$@"
}

# Sanitize a string for safe use as a sed regex pattern (delimiter-aware).
# Uses a different delimiter ([) to avoid issues with slashes in paths.
function sanitize_sed_pattern() {
    core_sanitize_sed_pattern "$@"
}

# Get general distribution name.
function get_distrib_name() {
    core_get_distrib_name
}

# Get general release name.
function get_release_name() {
    core_get_release_name
}

# Get general release name.
function get_release_version() {
    core_get_release_version
}

# Get distribution architecture.
function get_distrib_arch() {
    core_get_distrib_arch
}

# Get server private IP Address.
function get_ip_private() {
    core_get_ip_private
}

# Get server public IP Address.
function get_ip_public() {
    core_get_ip_public
}

# Get server IP address (public preferred, fallback to private, then localhost).
# Used by SSL certificate generation and other scripts.
function get_ip() {
    core_get_ip
}

# Get server private IPv6 Address.
function get_ipv6_private() {
    core_get_ipv6_private
}

# Get server public IPv6 Address.
function get_ipv6_public() {
    core_get_ipv6_public
}

# Make sure only supported distribution can run LEMPer script.
function preflight_system_check() {
    # Set system distro version.
    export DISTRIB_NAME && DISTRIB_NAME=$(get_distrib_name)
    export RELEASE_NAME && RELEASE_NAME=$(get_release_name)
    export RELEASE_VERSION && RELEASE_VERSION=$(get_release_version)

    # Check supported distribution and release version.
    if [[ "${DISTRIB_NAME}" == "unsupported" || "${RELEASE_NAME}" == "unsupported" ]]; then
        fail -e "This Linux distribution isn't supported yet. \nIf you'd like it to be, let us know at https://github.com/joglomedia/LEMPer/issues"
    fi

    # Set system architecture.
    export ARCH && \
    ARCH=$(uname -m)

    # Set default timezone.
    export TIMEZONE
    if [[ -z "${TIMEZONE}" || "${TIMEZONE}" == "none" ]]; then
        [ -f /etc/timezone ] && TIMEZONE=$(cat /etc/timezone) || TIMEZONE="UTC"
    fi

    # Set ethernet interface.
    export IFACE && \
    IFACE=$(find /sys/class/net -type l | grep -e "eno\|ens\|enp\|eth0" | cut -d'/' -f5)

    # Set server IP.
    export SERVER_IP && \
    SERVER_IP=${SERVER_IP:-$(get_ip_public)}
    SERVER_IP_LOCAL=$(get_ip_private)

    # Set server hostname.
    if [[ -n "${SERVER_HOSTNAME}" ]]; then
        if [[ "$(hostname)" != "${SERVER_HOSTNAME}" ]]; then
            run hostname "${SERVER_HOSTNAME}" || return 1
        fi
        if [[ ! -f /etc/hostname || "$(cat /etc/hostname 2>/dev/null)" != "${SERVER_HOSTNAME}" ]]; then
            run bash -c 'printf "%s\n" "$1" > /etc/hostname' _ "${SERVER_HOSTNAME}" || return 1
        fi

        lemper_update_hosts "${SERVER_HOSTNAME}" "${SERVER_IP}" || return 1

        export HOSTNAME && \
        HOSTNAME=${SERVER_HOSTNAME:-$(hostname)}
    fi

    # Validate server's hostname for production stack.
    if [[ "${ENVIRONMENT}" == prod* ]]; then
        # Check if the hostname is valid.
        if [[ $(validate_fqdn "${HOSTNAME}") != true ]]; then
            error "Your server's hostname is not fully qualified domain name (FQDN)."
            echo -e "In production environment you should use hostname that qualify FQDN format."
            echo -n "Update your hostname and points it to this server IP address "; status -n "${SERVER_IP}"; echo " !"
            exit 1
        fi

        # Check if the hostname is pointed to server IP address.
        sleep 2

        if [[ $(dig "${HOSTNAME}" +short) != "${SERVER_IP}" && $(dig "${HOSTNAME}" +short) != "${SERVER_IP_LOCAL}" ]]; then
            error "Your hostname '${HOSTNAME}' doesn't appear to be currently pointed to this server's public IP address."
            echo -n "In a production environment, you'll need to add an A record pointing to this IP address "; status -n "${SERVER_IP}"; echo " !"
            exit 1
        fi
    fi

    # Create a temporary directory for the LEMPer installation.
    BUILD_DIR=${BUILD_DIR:-"/tmp/lemper_build"}

    if [ ! -d "${BUILD_DIR}" ]; then
        run mkdir -p "${BUILD_DIR}"
    fi
}

# Get physical RAM size.
function get_ram_size() {
    core_get_ram_size
}

# Get total usable memory in MiB (cgroup-aware).
# LEMPER_MEMORY_MB overrides detection (useful in tests and containers).
function get_memory_mb() {
    core_get_memory_mb
}

# Normalize a PHP memory value (e.g. 256M, 1G, 512) to MiB.
function memory_to_mb() {
    core_memory_to_mb "$@"
}

# Classify the server by RAM: micro | small | medium | large.
# LEMPER_PROFILE (or SERVER_PROFILE in .env) overrides auto-detection.
function detect_resource_profile() {
    core_detect_resource_profile
}

# Calculate a safe pm.max_children for a profile and PHP memory_limit (MiB).
function calc_php_max_children() {
    core_calc_php_max_children "$@"
}

# Print FPM sizing: "max_children start_servers min_spare max_spare".
function calc_php_pool_sizing() {
    core_calc_php_pool_sizing "$@"
}

# Apply resource-aware sizing to an installed PHP-FPM pool file.
function tune_php_pool() {
    core_tune_php_pool "$@"
}

# Print MariaDB sizing: "buffer_pool_mb max_connections table_open_cache performance_schema".
function calc_mariadb_sizing() {
    core_calc_mariadb_sizing "$@"
}

# Create custom swap space for low end box.
function create_swap() {
    local SWAP_FILE="/swapfile"
    local SWAP_SIZE=1024
    local RAM_SIZE && \
    RAM_SIZE=$(get_ram_size)

    if [[ ${RAM_SIZE} -le 2048 ]]; then
        # If machine RAM less than / equal 2GiB, set swap to 2x of RAM size.
        SWAP_SIZE=$((RAM_SIZE * 2))
    elif [[ ${RAM_SIZE} -gt 2048 && ${RAM_SIZE} -le 32768 ]]; then
        # If machine RAM less than / equal 32GiB and greater than 2GiB, set swap equal to RAM size + 1x.
        SWAP_SIZE=$((4096 + (RAM_SIZE - 2048)))
    else
        # Otherwise, set swap to max of 1x of the physical / allocated memory.
        SWAP_SIZE=$((RAM_SIZE * 1))
    fi

    echo "Creating ${SWAP_SIZE}MiB swap space..."

    # Create swap.
    fallocate -l "${SWAP_SIZE}M" "${SWAP_FILE}" && \
    chmod 600 "${SWAP_FILE}" && \
    chown root:root "${SWAP_FILE}" && \
    mkswap "${SWAP_FILE}" && \
    swapon "${SWAP_FILE}"

    # Make the change permanent.
    if grep -qwE "#${SWAP_FILE}" /etc/fstab; then
        sed_inplace "s|#${SWAP_FILE}|${SWAP_FILE}|g" /etc/fstab
    else
        echo "${SWAP_FILE} swap swap defaults 0 0" >> /etc/fstab
        success "Swap space created and enabled at '${SWAP_FILE}'."
    fi
}

# Remove created Swap.
function remove_swap() {
    local SWAP_FILE="/swapfile"

    if [ -f "${SWAP_FILE}" ]; then
        run swapoff ${SWAP_FILE} && \
        sed_inplace "s|${SWAP_FILE}|#\ ${SWAP_FILE}|g" /etc/fstab && \
        run rm -f ${SWAP_FILE}

        echo "Swap file removed."
    else
        info "Unable to remove swap file."
    fi
}

# Enable swap.
function enable_swap() {
    echo "Checking swap..."

    if free | awk '/^Swap:/ {exit !$2}'; then
        local SWAP_SIZE && SWAP_SIZE=$(free -m | awk '/^Swap:/ { print $2 }')
        info "Swap size ${SWAP_SIZE}MiB."
    else
        info "No swap detected."
        create_swap
    fi
}

# Create default system account.
function create_account() {
    export LEMPER_USERNAME=${1:-"lemper"}
    export LEMPER_PASSWORD && \
    LEMPER_PASSWORD=${LEMPER_PASSWORD:-$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

    echo "Creating default LEMPer account..."

    if [[ -z $(getent passwd "${LEMPER_USERNAME}") ]]; then
        if [[ ${DRYRUN} != true ]]; then
            run useradd -d "/home/${LEMPER_USERNAME}" -m -s /bin/bash "${LEMPER_USERNAME}"
            run echo "${LEMPER_USERNAME}:${LEMPER_PASSWORD}" | chpasswd

            write_account_sudoers "${LEMPER_USERNAME}" || return 1

            # Create default directories.
            run mkdir -p "/home/${LEMPER_USERNAME}/webapps" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/logs" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/logs/nginx" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/logs/php" && \
            create_php_temp_dirs "${LEMPER_USERNAME}" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/.ssh" && \
            run chmod 700 "/home/${LEMPER_USERNAME}/.ssh" && \
            run touch "/home/${LEMPER_USERNAME}/.ssh/authorized_keys" && \
            run chmod 600 "/home/${LEMPER_USERNAME}/.ssh/authorized_keys" && \
            run chmod 755 "/home/${LEMPER_USERNAME}" && \
            run chown -hR "${LEMPER_USERNAME}:${LEMPER_USERNAME}" "/home/${LEMPER_USERNAME}"

            # Add account credentials to /srv/.htpasswd.
            [ ! -f "/srv/.htpasswd" ] && run touch /srv/.htpasswd

            # Protect .htpasswd file.
            run chmod 0600 /srv/.htpasswd
            run chown www-data:www-data /srv/.htpasswd

            # Generate password hash.
            if [[ -n $(command -v mkpasswd) ]]; then
                PASSWORD_HASH=$(printf '%s\n' "${LEMPER_PASSWORD}" | mkpasswd --method=sha-256 --stdin)
                sed_inplace "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
                run echo "${LEMPER_USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            elif [[ -n $(command -v htpasswd) ]]; then
                printf '%s\n' "${LEMPER_PASSWORD}" | run htpasswd -i /srv/.htpasswd "${LEMPER_USERNAME}"
            else
                PASSWORD_HASH=$(printf '%s\n' "${LEMPER_PASSWORD}" | openssl passwd -1 -stdin)
                sed_inplace "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
                run echo "${LEMPER_USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            fi

            # Save config.
            save_config -e "ENVIRONMENT=${ENVIRONMENT}\nHOSTNAME=${HOSTNAME}\nSERVER_IP=${SERVER_IP}\nSERVER_SSH_PORT=${SSH_PORT}"
            save_config -e "LEMPER_USERNAME=${LEMPER_USERNAME}\nLEMPER_PASSWORD=${LEMPER_PASSWORD}\nLEMPER_ADMIN_EMAIL=${LEMPER_ADMIN_EMAIL}"

            # Do NOT log passwords to the installation log file.
            # Credentials are saved securely to /etc/lemper/lemper.conf (mode 0600, root-only).
            save_log -e "Default system account '${LEMPER_USERNAME}' has been created successfully."

            success "Username ${LEMPER_USERNAME} created."
        else
            echo "Create ${LEMPER_USERNAME} account in dry run mode."
        fi
    else
        info "Unable to create account, username ${LEMPER_USERNAME} already exists."
    fi
}

# Delete default system account.
function delete_account() {
    local LEMPER_USERNAME=${1:-"lemper"}

    if [[ -n $(getent passwd "${LEMPER_USERNAME}") ]]; then
        if pgrep -u "${LEMPER_USERNAME}" > /dev/null; then
            error "Couldn't delete user currently used by running processes."
        else
            run userdel -r "${LEMPER_USERNAME}"

            if [ -f "/srv/.htpasswd" ]; then
                sed_inplace "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
            fi

            success "Account ${LEMPER_USERNAME} deleted."
        fi
    else
        info "Account ${LEMPER_USERNAME} not found."
    fi
}

# Init logging.
function init_log() {
    core_init_log "$@"
}

# Save log.
function save_log() {
    core_save_log "$@"
}

# Make config file if not exist.
function init_config() {
    core_init_config "$@"
}

# Save configuration.
function save_config() {
    core_save_config "$@"
}

# Encrypt configuration at rest.
function secure_config() {
    core_secure_config "$@"
}

# Check if config file is encrypted (raw Salted__ or base64 header).
function is_config_encrypted() {
    core_is_config_encrypted "$@"
}

# Securely delete a file.
function secure_shred() {
    core_secure_shred "$@"
}

# Resolve config encryption password from available sources.
# The install-time key file is preferred over the admin password: sudo strips
# LEMPER_PASSWORD, while the key file is readable by root in both contexts.
function resolve_config_password() {
    core_resolve_config_password
}

# Header message.
function header_msg() {
    clear
#    cat <<- EOL
#==========================================================================#
#          Welcome to LEMPer Stack Manager for Debian/Ubuntu server        #
#==========================================================================#
#     Bash scripts to install LEMP (Linux, Nginx, MariaDB (MySQL), PHP)    #
#                                                                          #
#        For more information please visit https://masedi.net/lemper       #
#==========================================================================#
#EOL
    status "
         _     _____ __  __ ____               _     
        | |   | ____|  \/  |  _ \ _welcome_to_| |__  
        | |   |  _| | |\/| | |_) / _ \ '__/ __| '_ \ 
        | |___| |___| |  | |  __/  __/ | _\__ \ | | |
        |_____|_____|_|  |_|_|   \___|_|(_)___/_| |_|
    "
}

# Footer credit message.
function footer_msg() {
    cat <<- EOL

#==========================================================================#
#              Thank's for installing LEMP Stack with LEMPer               #
#        Found any bugs/errors, or suggestions? please let me know         #
#       If useful, don't forget to buy me a cup of coffee or milk :D       #
#   My PayPal is always open for donation, here https://paypal.me/masedi   #
#                                                                          #
#         (c) 2014-2026 | MasEDI.Net | https://masedi.net/l/lemper         #
#==========================================================================#
EOL
}
