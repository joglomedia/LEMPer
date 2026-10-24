#!/usr/bin/env bash

# Helper Functions
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 06/08/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Define base directory.
BASE_DIR=${BASE_DIR:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

# Define scripts directory.
export SCRIPTS_DIR
if grep -q "scripts" <<< "${BASE_DIR}"; then
    SCRIPTS_DIR="${BASE_DIR}"
else
    SCRIPTS_DIR="${BASE_DIR}/scripts"
fi

##
# Parse a key=value line from a config file safely.
# Reads a single line and splits on the first '=' using IFS, avoiding eval.
# Returns: "key<TAB>value" or nothing if the line is a comment/blank/section.
#
# Must be defined before the dotenv loading block below runs.
##
function safe_parse_dotenv() {
    local envfile="${1}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip comments and section headers.
        line="${line#"${line%%[![:space:]]*}"}"  # ltrim
        [[ -z "${line}" || "${line}" == \#* || "${line}" == \[* ]] && continue
        # Split on first =.
        local key="${line%%=*}"
        local value="${line#*=}"
        # Strip surrounding quotes from value if present.
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        # Validate key name (prevent injection).
        if [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf '%s\t%s\n' "${key}" "${value}"
        fi
    done < "${envfile}"
}

# Export environment variables.
ENVFILE=$(echo "${BASE_DIR}/.env" | sed '$ s|\/scripts\/.env$|\/.env|')

if [ -f "${ENVFILE}" ]; then
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
    echo "Environment variables required, but the dotenv file doesn't exist. Copy .env.dist to .env first!"
    exit 1
fi

# Direct access? make as dry run mode.
DRYRUN=${DRYRUN:-true}

# Init timezone, set default to UTC.
TIMEZONE=${TIMEZONE:-"UTC"}

# Set default color decorator.
RED=31
GREEN=32
YELLOW=33
BLUE=34

function begin_color() {
    color="${1}"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="${1}"
    shift
    begin_color "${color}"
    echo "$@"
    end_color
}

function error() {
    echo_color "${RED}" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function success() {
    echo_color "${GREEN}" -n "Success: " >&2
    echo "$@" >&2
}

function info() {
    echo_color "${YELLOW}" -n "Info: " >&2
    echo "$@" >&2
}

function status() {
    echo_color "${GREEN}" "$@"
}

function warning() {
    echo_color "${YELLOW}" "$@"
}

function echo_ok() {
    echo_color "${GREEN}" "$@"
}

function echo_warn() {
    echo_color "${YELLOW}" "$@"
}

function echo_err() {
    echo_color "${RED}" "$@"
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
    if [[ "${DRYRUN}" == true ]]; then
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

# Create isolated PHP temp/session directories for an FPM pool.
# They live outside the user's home so uploaded/session files cannot be
# reached from the web root if the application is compromised.
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
# Progress indicator — shows a step counter (e.g. [3/10]).
##
PROGRESS_TOTAL=${PROGRESS_TOTAL:-0}
PROGRESS_CURRENT=${PROGRESS_CURRENT:-0}

function progress() {
    local description="${1}"
    PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
    if [[ "${PROGRESS_TOTAL}" -gt 0 ]]; then
        echo_color "${BLUE}" -n "[${PROGRESS_CURRENT}/${PROGRESS_TOTAL}] "
    else
        echo_color "${BLUE}" -n "▸ "
    fi
    echo "${description}"
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
    local i=0
    (
        while true; do
            local idx=$((i % ${#spinner_chars}))
            echo -ne "\b${spinner_chars:${idx}:1}"
            sleep 0.1
            i=$((i + 1))
        done
    ) &
    SPINNER_PID=$!
}

function spinner_stop() {
    if [[ -n "${SPINNER_PID}" ]] && kill -0 "${SPINNER_PID}" 2>/dev/null; then
        kill "${SPINNER_PID}" 2>/dev/null
        wait "${SPINNER_PID}" 2>/dev/null
        SPINNER_PID=""
        # Clear spinner character.
        echo -ne "\b \b"
    fi
}

##
# Run a command with a progress spinner and description.
# Usage: run_spinner "Description" command args...
##
function run_spinner() {
    local description="${1}"
    shift

    spinner_start "${description}"

    local status=0
    if [[ "${DRYRUN}" == true ]]; then
        echo_color "${YELLOW}" -n "would run "
        echo "$@"
    else
        "$@" || status=$?
    fi

    spinner_stop

    if [[ "${status}" -ne 0 ]]; then
        error "Failure running '$*', exiting."
        exit 1
    fi

    if [[ "${DRYRUN}" != true ]]; then
        success "${description} — done"
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
    if nginx -t 2>/dev/null > /dev/null; then
        echo true # success
    else
        echo false # error
    fi
}

# Validate FQDN domain.
# Uses ERE (grep -E) with a separate length check for portability.
# PCRE (grep -P) lookahead/lookbehind is not available on all platforms.
function validate_fqdn() {
    local FQDN=${1}

    # Length check: 4-253 characters (RFC 1035 / RFC 1123).
    if [[ ${#FQDN} -lt 4 || ${#FQDN} -gt 253 ]]; then
        echo false # error
        return
    fi

    # Validate format: labels of 1-63 chars separated by dots,
    # no leading/trailing dashes, TLD is 2-63 letters, optional trailing dot.
    if grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\.?$' <<< "${FQDN}"; then
        echo true # success
    else
        echo false # error
    fi
}

# Validate IPv4 address.
function validate_ipv4() {
    local IP=${1}

    if grep -qE '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' <<< "${IP}"; then
        echo true # success
    else
        echo false # error
    fi
}

# Validate Unix username (RFC 932 + POSIX: alphanumeric, dash, underscore; 1-32 chars, starts with letter).
function validate_username() {
    local USERNAME=${1}

    if grep -qE '^[a-z_][a-z0-9_-]{0,31}$' <<< "${USERNAME}"; then
        echo true # success
    else
        echo false # error
    fi
}

# Sanitize a string for safe use in sed replacement patterns.
# Escapes backslash, forward-slash, ampersand, and newline to prevent
# injection when interpolating user input into sed s/.../.../ commands.
function sanitize_sed_replacement() {
    local INPUT=${1}
    printf '%s' "${INPUT}" | sed -e 's/[\\&]/\\&/g' -e 's/\//\\\//g'
}

# Sanitize a string for safe use as a sed regex pattern (delimiter-aware).
# Uses a different delimiter ([) to avoid issues with slashes in paths.
function sanitize_sed_pattern() {
    local INPUT=${1}
    printf '%s' "${INPUT}" | sed -e 's/\[/\\[/g'
}

# Get general distribution name.
function get_distrib_name() {
    if [ -f /etc/os-release ]; then
        # Export os-release vars.
        # shellcheck disable=SC1091
        . /etc/os-release

        # Export lsb-release vars.
        # shellcheck disable=SC1091
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution name.
        if [[ "${ID_LIKE}" == "ubuntu" ]]; then
            DISTRIB_NAME="ubuntu"
        else
            DISTRIB_NAME=${ID:-"unsupported"}
        fi
    elif [[ -e /etc/system-release ]]; then
    	DISTRIB_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
    	DISTRIB_NAME="unsupported"
    fi

    echo "${DISTRIB_NAME}"
}

# Get general release name.
function get_release_name() {
    if [ -f /etc/os-release ]; then
        # Export os-release vars.
        # shellcheck disable=SC1091
        . /etc/os-release

        # Export lsb-release vars.
        # shellcheck disable=SC1091
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution name.
        if [[ "${ID_LIKE}" == "ubuntu" ]]; then
            DISTRIB_NAME="ubuntu"
        else
            DISTRIB_NAME=${ID:-"unsupported"}
        fi

        # Get distribution release / version ID.
        DISTRIB_VERSION=${VERSION_ID:-"${DISTRIB_RELEASE}"}
        MAJOR_RELEASE_VERSION=$(echo "${DISTRIB_VERSION}" | awk -F. '{print $1}')

        case ${DISTRIB_NAME} in
            debian)
                RELEASE_NAME=${VERSION_CODENAME:-"unsupported"}

                # TODO for Debian install
                case ${MAJOR_RELEASE_VERSION} in
                    10)
                        RELEASE_NAME="buster"
                    ;;
                    11)
                        RELEASE_NAME="bullseye"
                    ;;
                    12)
                        RELEASE_NAME="bookworm"
                    ;;
                    *)
                        RELEASE_NAME="unsupported"
                    ;;
                esac
            ;;
            ubuntu)
                # Hack for Linux Mint release number.
                [[ "${DISTRIB_ID}" == "LinuxMint" || "${ID}" == "linuxmint" ]] && \
                    DISTRIB_RELEASE="LM${MAJOR_RELEASE_VERSION}"

                case "${DISTRIB_RELEASE}" in
                    "22.04" | "LM21")
                        # Ubuntu release 22.04, LinuxMint 21
                        RELEASE_NAME=${UBUNTU_CODENAME:-"jammy"}
                    ;;
                    "24.04" | "LM22")
                        # Ubuntu release 24.04, LinuxMint 24
                        RELEASE_NAME=${UBUNTU_CODENAME:-"noble"}
                    ;;
                    *)
                        RELEASE_NAME="unsupported"
                    ;;
                esac
            ;;
            *)
                RELEASE_NAME="unsupported"
            ;;
        esac
    elif [ -f /etc/system-release ]; then
    	RELEASE_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
    	RELEASE_NAME="unsupported"
    fi

    echo "${RELEASE_NAME}"
}

# Get general release name.
function get_release_version() {
    if [ -f /etc/os-release ]; then
        # Export os-release vars.
        # shellcheck disable=SC1091
        . /etc/os-release

        # Export lsb-release vars.
        # shellcheck disable=SC1091
        [ -f /etc/lsb-release ] && . /etc/lsb-release

        # Get distribution release / version ID.
        RELEASE_VERSION=${VERSION_ID:-"${DISTRIB_RELEASE}"}
    elif [ -f /etc/system-release ]; then
    	RELEASE_VERSION="0.0"
    else
        # Red Hat /etc/redhat-release
    	RELEASE_VERSION="0.0"
    fi

    echo "${RELEASE_VERSION}"
}

# Get distribution architecture.
function get_distrib_arch() {
    local ARCH=${ARCH:-$(uname -p)}
    local DISTRIB_ARCH
    
    case "${ARCH}" in
        i386 | i486| i586 | i686)
            DISTRIB_ARCH="386"
        ;;
        x86_64 | amd64)
            DISTRIB_ARCH="amd64"
        ;;
        arm64 | aarch* | armv8*)
            DISTRIB_ARCH="arm64"
        ;;
        arm | armv7*)
            DISTRIB_ARCH="armv6l"
        ;;
        *)
            DISTRIB_ARCH="386"
        ;;
    esac

    echo "${DISTRIB_ARCH}"
}

# Get server private IP Address.
function get_ip_private() {
    local SERVER_IP_PRIVATE && \
    SERVER_IP_PRIVATE=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

    echo "${SERVER_IP_PRIVATE}"
}

# Get server public IP Address.
function get_ip_public() {
    local SERVER_IP_PRIVATE && SERVER_IP_PRIVATE=$(get_ip_private)
    local SERVER_IP_PUBLIC && \
    SERVER_IP_PUBLIC=$(curl -sk --ipv4 --connect-timeout 10 --retry 3 --retry-delay 0 https://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${SERVER_IP_PRIVATE}" == "${SERVER_IP_PUBLIC}" ]]; then
        echo "${SERVER_IP_PRIVATE}"
    else
        echo "${SERVER_IP_PUBLIC}"
    fi
}

# Get server IP address (public preferred, fallback to private, then localhost).
# Used by SSL certificate generation and other scripts.
function get_ip() {
    local IP

    # Try public IP first
    IP=$(get_ip_public 2>/dev/null)

    # Fallback to private IP
    if [[ -z "${IP}" ]]; then
        IP=$(get_ip_private 2>/dev/null)
    fi

    # Fallback to localhost for CI/CD or isolated environments
    if [[ -z "${IP}" ]]; then
        IP="127.0.0.1"
    fi

    echo "${IP}"
}

# Get server private IPv6 Address.
function get_ipv6_private() {
    local SERVER_IPV6_PRIVATE && \
    SERVER_IPV6_PRIVATE=$(ip addr | grep 'inet6' | \
        grep -oE '(::)?[0-9a-fA-F]{1,4}(::?[0-9a-fA-F]{1,4}){1,7}(::)?' | head -1)

    echo "${SERVER_IPV6_PRIVATE}"
}

# Get server public IPv6 Address.
function get_ipv6_public() {
    local SERVER_IPV6_PRIVATE && SERVER_IPV6_PRIVATE=$(get_ipv6_private)
    local SERVER_IPV6_PUBLIC && \
    SERVER_IPV6_PUBLIC=$(curl -sk --ipv6 --connect-timeout 10 --retry 3 --retry-delay 0 https://ipecho.net/plain)

    # Ugly hack to detect aws-lightsail public IP address.
    if [[ "${SERVER_IPV6_PRIVATE}" == "${SERVER_IPV6_PUBLIC}" ]]; then
        echo "${SERVER_IPV6_PRIVATE}"
    else
        echo "${SERVER_IPV6_PUBLIC}"
    fi
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
        run hostname "${SERVER_HOSTNAME}" && \
        run bash -c "echo '${SERVER_HOSTNAME}' > /etc/hostname"

        if grep -q "${SERVER_HOSTNAME}" /etc/hosts; then
            sed_inplace -b "/${SERVER_HOSTNAME}/d" /etc/hosts
            run bash -c "echo -e '${SERVER_IP}\t${SERVER_HOSTNAME}' >> /etc/hosts"
        else
            run bash -c "echo -e '\n# LEMPer local hosts\n${SERVER_IP}\t${SERVER_HOSTNAME}' >> /etc/hosts"
        fi

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
            error "Your hostname '${V_DOMAIN}' doesn't appear to be currently pointed to this server's public IP address."
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
    local RAM_SIZE_IN_MB=0

    # Calculate total RAM size in MB by summing all memory modules.
    # dmidecode may return multiple lines for systems with multiple RAM modules.
    while read -r size unit; do
        if [[ "${size}" =~ ^[0-9]+$ ]]; then
            case "${unit}" in
                "GB")
                    RAM_SIZE_IN_MB=$((RAM_SIZE_IN_MB + size * 1024))
                ;;
                "MB")
                    RAM_SIZE_IN_MB=$((RAM_SIZE_IN_MB + size))
                ;;
            esac
        fi
    done < <(dmidecode -t 17 2>/dev/null | awk '/Size/ && $2 ~ /^[0-9]+$/ { print $2, $3 }')

    # Fallback to /proc/meminfo if dmidecode returns 0 or fails
    if [[ "${RAM_SIZE_IN_MB}" -eq 0 ]]; then
        RAM_SIZE_IN_MB=$(awk '/MemTotal/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)
    fi

    echo "${RAM_SIZE_IN_MB:-0}"
}

# Get total usable memory in MiB (cgroup-aware).
# LEMPER_MEMORY_MB overrides detection (useful in tests and containers).
function get_memory_mb() {
    if [[ "${LEMPER_MEMORY_MB:-}" =~ ^[1-9][0-9]*$ ]]; then
        echo "${LEMPER_MEMORY_MB}"
        return 0
    fi

    local MEM_MB
    MEM_MB=$(awk '/^MemTotal:/ { printf "%.0f", $2/1024 }' /proc/meminfo 2>/dev/null)

    # Respect cgroup limits (containers and systemd slices).
    local CGROUP_LIMIT
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        CGROUP_LIMIT=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
    fi

    # Ignore "unlimited" sentinels (1 PiB and friends).
    awk -v total="${MEM_MB:-0}" -v limit="${CGROUP_LIMIT:-0}" 'BEGIN {
        if (limit ~ /^[0-9]+$/) {
            mb = int(limit / 1048576);
            if (mb > 0 && mb < 1048576 && (total == 0 || mb < total)) total = mb;
        }
        printf "%.0f\n", total;
    }'
}

# Normalize a PHP memory value (e.g. 256M, 1G, 512) to MiB.
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

# Classify the server by RAM: micro | small | medium | large.
# LEMPER_PROFILE (or SERVER_PROFILE in .env) overrides auto-detection.
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

    local MEM_MB && MEM_MB=$(get_memory_mb)

    if (( MEM_MB <= 0 )); then
        # Unknown memory: assume the conservative middle.
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

# Calculate a safe pm.max_children for a profile and PHP memory_limit (MiB).
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

    # A busy PHP worker typically holds 40-80 MiB. Budget a third of
    # memory_limit so the cap is realistic for small CMS workloads while
    # still bounding the worst case.
    local PER_CHILD=$(( MEMLIMIT / 3 ))
    (( PER_CHILD < 64 )) && PER_CHILD=64

    local TOTAL && TOTAL=$(get_memory_mb)
    if (( TOTAL > 0 )); then
        local BUDGET=$(( TOTAL * 35 / 100 ))
        local BY_MEM=$(( BUDGET / PER_CHILD ))
        (( BY_MEM < 2 )) && BY_MEM=2
        (( BY_MEM < CAP )) && CAP=${BY_MEM}
    fi

    (( CAP < 2 )) && CAP=2
    echo "${CAP}"
}

# Print FPM sizing: "max_children start_servers min_spare max_spare".
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

# Apply resource-aware sizing to an installed PHP-FPM pool file.
function tune_php_pool() {
    local POOL_FILE="${1}"
    local PROFILE="${2:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)

    [[ -f "${POOL_FILE}" ]] || return 0

    local MEMLIMIT_MB && MEMLIMIT_MB=$(memory_to_mb "${PHP_MEMORY_LIMIT:-256M}")
    local MAX_CHILDREN START MIN_SPARE MAX_SPARE
    read -r MAX_CHILDREN START MIN_SPARE MAX_SPARE <<< \
        "$(calc_php_pool_sizing "${PROFILE}" "${MEMLIMIT_MB}")"

    sed_inplace "s/^pm\.max_children = .*/pm.max_children = ${MAX_CHILDREN}/" "${POOL_FILE}"
    sed_inplace "s/^pm\.start_servers = .*/pm.start_servers = ${START}/" "${POOL_FILE}"
    sed_inplace "s/^pm\.min_spare_servers = .*/pm.min_spare_servers = ${MIN_SPARE}/" "${POOL_FILE}"
    sed_inplace "s/^pm\.max_spare_servers = .*/pm.max_spare_servers = ${MAX_SPARE}/" "${POOL_FILE}"
    sed_inplace "s/^php_value\[memory_limit\] = .*/php_value[memory_limit] = ${PHP_MEMORY_LIMIT:-256M}/" "${POOL_FILE}"

    local COOKIE_SECURE=0
    [[ "${SESSION_COOKIE_SECURE:-false}" == true ]] && COOKIE_SECURE=1
    sed_inplace "s/^php_admin_value\[session\.cookie_secure\] = .*/php_admin_value[session.cookie_secure] = ${COOKIE_SECURE}/" "${POOL_FILE}"
}

# Print MariaDB sizing: "buffer_pool_mb max_connections table_open_cache performance_schema".
function calc_mariadb_sizing() {
    local PROFILE="${1:-}"
    [[ -z "${PROFILE}" ]] && PROFILE=$(detect_resource_profile)

    local BUFFER_POOL MAX_CONNECTIONS TABLE_CACHE PERF_SCHEMA

    case "${PROFILE}" in
        micro)  BUFFER_POOL=128;  MAX_CONNECTIONS=30;  TABLE_CACHE=64;  PERF_SCHEMA=OFF ;;
        small)  BUFFER_POOL=256;  MAX_CONNECTIONS=50;  TABLE_CACHE=128; PERF_SCHEMA=OFF ;;
        medium) BUFFER_POOL=512;  MAX_CONNECTIONS=75;  TABLE_CACHE=256; PERF_SCHEMA=ON ;;
        *)      BUFFER_POOL=1024; MAX_CONNECTIONS=100; TABLE_CACHE=512; PERF_SCHEMA=ON ;;
    esac

    # Large hosts can afford a bigger pool; cap it so the database does not
    # crowd out PHP-FPM and the web server.
    local TOTAL && TOTAL=$(get_memory_mb)
    if (( TOTAL >= 8192 )); then
        BUFFER_POOL=2048
    fi

    echo "${BUFFER_POOL} ${MAX_CONNECTIONS} ${TABLE_CACHE} ${PERF_SCHEMA}"
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

            # Restrict sudo access to specific systemctl service management.
            # This replaces the old NOPASSWD:ALL approach which granted full root.
            run mkdir -p /etc/sudoers.d
            run touch "/etc/sudoers.d/90-${LEMPER_USERNAME}"
            run chmod 0440 "/etc/sudoers.d/90-${LEMPER_USERNAME}"
            run cat > "/etc/sudoers.d/90-${LEMPER_USERNAME}" <<SUDOERS_EOF
# Restricted sudoers for LEMPer admin user.
# Allows the lemper user to manage specific services without full root.
%${LEMPER_USERNAME} ALL=(root) NOPASSWD: /bin/systemctl reload nginx, \\
    /bin/systemctl reload php*, \\
    /bin/systemctl restart nginx, \\
    /bin/systemctl restart php*, \\
    /bin/systemctl restart redis-server, \\
    /bin/systemctl restart mariadb, \\
    /bin/systemctl restart mysql, \\
    /bin/systemctl status nginx, \\
    /bin/systemctl status php*, \\
    /bin/systemctl status redis-server, \\
    /bin/systemctl status mariadb, \\
    /bin/systemctl status mysql
SUDOERS_EOF

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
                PASSWORD_HASH=$(mkpasswd --method=sha-256 "${LEMPER_PASSWORD}")
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
    export LOG_FILE=${LOG_FILE:-"./lemper_install.log"}
    [ ! -f "${LOG_FILE}" ] && run touch "${LOG_FILE}"
    save_log "Initialize LEMPer installation log..."
}

# Save log.
function save_log() {
    if [[ ${DRYRUN} != true ]]; then
        {
            date '+%d-%m-%Y %T %Z'
            echo "$@"
            echo ""
        } >> "${LOG_FILE}"
    fi
}

# Make config file if not exist.
function init_config() {
    if [ ! -f /etc/lemper/lemper.conf ]; then
        run mkdir -p /etc/lemper && run chmod 0700 /etc/lemper
        run touch /etc/lemper/lemper.conf && run chmod 0600 /etc/lemper/lemper.conf
    fi

    if [ ! -d /etc/lemper/vhost.d ]; then
        run mkdir -p /etc/lemper/vhost.d && run chmod 0700 /etc/lemper/vhost.d
    fi

    # Generate encryption key file for config at rest.
    if [[ "${ENCRYPT_CONFIG_AT_REST}" == true ]] && [[ ! -f /etc/lemper/.config_key ]]; then
        local config_key
        config_key=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9')
        echo "${config_key}" > /etc/lemper/.config_key
        run chmod 0600 /etc/lemper/.config_key
        success "Encrypted config key generated at /etc/lemper/.config_key"
    fi

    save_log -e "# LEMPer configuration.\n# Edit here if you change your password manually, but do NOT delete!"
}

# Save configuration.
function save_config() {
    if [[ ${DRYRUN} != true ]]; then
        local config_file="/etc/lemper/lemper.conf"

        if [[ "${ENCRYPT_CONFIG_AT_REST}" == true ]]; then
            # Decrypt, write, re-encrypt.
            local temp_dec pw
            temp_dec=$(mktemp /tmp/lemper_save.XXXXXX)
            pw=$(resolve_config_password) 2>/dev/null || pw="${LEMPER_PASSWORD}"

            if is_config_encrypted "${config_file}"; then
                local decrypted=false

                if openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
                    -k "${pw}" -in "${config_file}" -out "${temp_dec}" 2>/dev/null; then
                    decrypted=true
                # Fall back to the admin password for configs written before
                # the install-time key file became authoritative.
                elif [[ -n "${LEMPER_PASSWORD}" && "${LEMPER_PASSWORD}" != "${pw}" ]] && \
                    openssl enc -aes-256-cbc -d -a -salt -md sha256 -pbkdf2 \
                        -k "${LEMPER_PASSWORD}" -in "${config_file}" -out "${temp_dec}" 2>/dev/null; then
                    decrypted=true
                fi

                if [[ "${decrypted}" != true ]]; then
                    secure_shred "${temp_dec}"
                    error "Failed to decrypt ${config_file}; refusing to overwrite it."
                    return 1
                fi
            elif [[ -f "${config_file}" ]]; then
                cp "${config_file}" "${temp_dec}"
            fi

            echo "$@" >> "${temp_dec}"

            # Re-encrypt with the preferred password, migrating legacy
            # password-encrypted configs to the key file.
            if [[ -n "${pw}" ]]; then
                openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 \
                    -k "${pw}" -in "${temp_dec}" -out "${config_file}"
            else
                cp "${temp_dec}" "${config_file}"
            fi
            secure_shred "${temp_dec}"
        else
            [ -f "${config_file}" ] && echo "$@" >> "${config_file}"
        fi
    fi
}

# Encrypt configuration at rest.
function secure_config() {
    if [[ ${DRYRUN} != true ]]; then
        local config_file="/etc/lemper/lemper.conf"
        if [ -f "${config_file}" ] && [[ "${ENCRYPT_CONFIG_AT_REST}" == true ]]; then
            local pw
            pw=$(resolve_config_password) 2>/dev/null || pw="${LEMPER_PASSWORD}"
            if [[ -n "${pw}" ]]; then
                run openssl enc -aes-256-cbc -a -salt -md sha256 -pbkdf2 -k "${pw}" \
                    -in "${config_file}" -out "${config_file}.enc"
                secure_shred "${config_file}"
                mv "${config_file}.enc" "${config_file}"
            fi
        fi
    fi
}

# Check if config file is encrypted (raw Salted__ or base64 header).
function is_config_encrypted() {
    local file="${1:-/etc/lemper/lemper.conf}"
    [[ -f "${file}" ]] && head -c 10 "${file}" | grep -qE '^(U2FsdGVkX1|Salted__)'
}

# Securely delete a file.
function secure_shred() {
    local file="${1}"
    [[ -f "${file}" ]] || return 0
    if command -v shred &>/dev/null; then
        shred -u -z -n 3 "${file}" 2>/dev/null || rm -f "${file}"
    else
        rm -f "${file}"
    fi
}

# Resolve config encryption password from available sources.
# The install-time key file is preferred over the admin password: sudo strips
# LEMPER_PASSWORD, while the key file is readable by root in both contexts.
function resolve_config_password() {
    if [[ -n "${LEMPER_CONFIG_PASSWORD}" ]]; then
        printf '%s' "${LEMPER_CONFIG_PASSWORD}"
        return 0
    fi

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
#         (c) 2014-2024 | MasEDI.Net | https://masedi.net/l/lemper         #
#==========================================================================#
EOL
}
