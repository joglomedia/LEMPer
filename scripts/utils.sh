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

# Export environment variables.
ENVFILE=$(echo "${BASE_DIR}/.env" | sed '$ s|\/scripts\/.env$|\/.env|')

if [ -f "${ENVFILE}" ]; then
    # Clean environemnt first.
    # shellcheck source=.env.dist
    # shellcheck disable=SC2046
    unset $(grep -v '^#' "${ENVFILE}" | grep -v '^\[' | sed -E 's/(.*)=.*/\1/' | xargs)

    # shellcheck source=.env.dist
    # shellcheck disable=SC1094
    source <(grep -v '^#' "${ENVFILE}" | grep -v '^\[' | sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
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
# having up to four components, since that's enough to handle both nginx (3) and
# ngx_pagespeed (4).
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
function validate_fqdn() {
    local FQDN=${1}

    if grep -qP "(?=^.{4,253}\.?$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}\.?$)" <<< "${FQDN}"; then
        echo true # success
    else
        echo false # error
    fi
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
        [[ "${ID_LIKE}" == "ubuntu" ]] && DISTRIB_NAME="ubuntu" || DISTRIB_NAME=${ID:-"unsupported"}
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
                    "18.04"|"LM19")
                        # Ubuntu release 18.04, LinuxMint 19
                        RELEASE_NAME=${UBUNTU_CODENAME:-"bionic"}
                    ;;
                    "20.04"|"LM20")
                        # Ubuntu release 20.04, LinuxMint 20
                        RELEASE_NAME=${UBUNTU_CODENAME:-"focal"}
                    ;;
                    "22.04"|"LM21")
                        # Ubuntu release 22.04, LinuxMint 21
                        RELEASE_NAME=${UBUNTU_CODENAME:-"jammy"}
                    ;;
                    *)
                        RELEASE_NAME="unsupported"
                    ;;
                esac
            ;;
            amzn)
                # Amazon based on RHEL/CentOS
                RELEASE_NAME="unsupported"

                # TODO for Amzn install
            ;;
            centos | fedora | rocky)
                # CentOS
                RELEASE_NAME="unsupported"

                # TODO for CentOS install
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
            run sed -i".bak" "/${SERVER_HOSTNAME}/d" /etc/hosts
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
        #if [[ $(dig "${HOSTNAME}" +short) != "${SERVER_IP}" && $(dig "${HOSTNAME}" +short) != "${SERVER_IP_LOCAL}" ]]; then
        if [[ $(host -4 "${HOSTNAME}" | awk '{print $NF}') != "${SERVER_IP}" && $(host -4 "${HOSTNAME}" | awk '{print $NF}') != "${SERVER_IP_LOCAL}" ]]; then
            error "It seems that your server's hostname '${HOSTNAME}' is not yet pointed to your server's public IP address."
            echo -n "In production environment you need to add an A record and point it to this IP address "; status -n "${SERVER_IP}"; echo " !"
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
    local _RAM_SIZE
    local RAM_SIZE_IN_MB

    # Calculate RAM size in MB.
    _RAM_SIZE=$(dmidecode -t 17 | awk '( /Size/ && $2 ~ /^[0-9]+$/ ) { x+=$2 } END{ print x}')

    # Hack for calculating RAM size in MiB.
    if [[ ${_RAM_SIZE} -le 128 ]]; then
        # If RAM size less than / equal 128, assume that the size is in GB.
        RAM_SIZE_IN_MB=$((_RAM_SIZE * 1024))
    else
        RAM_SIZE_IN_MB=$((_RAM_SIZE * 1))
    fi

    echo "${RAM_SIZE_IN_MB}"
}

# Create custom Swap.
function create_swap() {
    local SWAP_FILE="/swapfile"
    local RAM_SIZE && \
    RAM_SIZE=$(get_ram_size)

    if [[ ${RAM_SIZE} -le 2048 ]]; then
        # If machine RAM less than / equal 2GiB, set swap to 2x of RAM size.
        local SWAP_SIZE=$((RAM_SIZE * 2))
    elif [[ ${RAM_SIZE} -gt 2048 && ${RAM_SIZE} -le 32768 ]]; then
        # If machine RAM less than / equal 32GiB and greater than 2GiB, set swap equal to RAM size + 1x.
        local SWAP_SIZE=$((4096 + (RAM_SIZE - 2048)))
    else
        # Otherwise, set swap to max of 1x of the physical / allocated memory.
        local SWAP_SIZE=$((RAM_SIZE * 1))
    fi

    echo "Creating ${SWAP_SIZE}MiB swap..."

    # Create swap.
    run fallocate -l "${SWAP_SIZE}M" ${SWAP_FILE} && \
    run chmod 600 ${SWAP_FILE} && \
    run chown root:root ${SWAP_FILE} && \
    run mkswap ${SWAP_FILE} && \
    run swapon ${SWAP_FILE}

    # Make the change permanent.
    if [[ ${DRYRUN} != true ]]; then
        if grep -qwE "#${SWAP_FILE}" /etc/fstab; then
            run sed -i "s|#${SWAP_FILE}|${SWAP_FILE}|g" /etc/fstab
        else
            run echo "${SWAP_FILE} swap swap defaults 0 0" >> /etc/fstab
        fi
    else
        echo "Add persistent swap to fstab in dry run mode."
    fi
}

# Remove created Swap.
function remove_swap() {
    local SWAP_FILE="/swapfile"

    if [ -f "${SWAP_FILE}" ]; then
        run swapoff ${SWAP_FILE} && \
        run sed -i "s|${SWAP_FILE}|#\ ${SWAP_FILE}|g" /etc/fstab && \
        run rm -f ${SWAP_FILE}

        echo "Swap file removed."
    else
        info "Unable to remove swap."
    fi
}

# Enable swap.
function enable_swap() {
    echo "Checking swap..."

    if free | awk '/^Swap:/ {exit !$2}'; then
        local SWAP_SIZE && \
        SWAP_SIZE=$(free -m | awk '/^Swap:/ { print $2 }')
        info "Swap size ${SWAP_SIZE}MiB."
    else
        info "No swap detected."
        create_swap
        success "Swap created and enabled."
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
            run usermod -aG sudo "${LEMPER_USERNAME}"

            # Create default directories.
            run mkdir -p "/home/${LEMPER_USERNAME}/webapps" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/logs" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/logs/nginx" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/logs/php" && \
            run mkdir -p "/home/${LEMPER_USERNAME}/.lemper" && \
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
                run sed -i "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
                run echo "${LEMPER_USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            elif [[ -n $(command -v htpasswd) ]]; then
                run htpasswd -b /srv/.htpasswd "${LEMPER_USERNAME}" "${LEMPER_PASSWORD}"
            else
                PASSWORD_HASH=$(openssl passwd -1 "${LEMPER_PASSWORD}")
                run sed -i "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
                run echo "${LEMPER_USERNAME}:${PASSWORD_HASH}" >> /srv/.htpasswd
            fi

            # Save config.
            save_config -e "ENVIRONMENT=${ENVIRONMENT}\nHOSTNAME=${HOSTNAME}\nSERVER_IP=${SERVER_IP}\nSERVER_SSH_PORT=${SSH_PORT}"
            save_config -e "LEMPER_USERNAME=${LEMPER_USERNAME}\nLEMPER_PASSWORD=${LEMPER_PASSWORD}\nLEMPER_ADMIN_EMAIL=${LEMPER_ADMIN_EMAIL}"

            # Save data to log file.
            save_log -e "Your default system account information:\nUsername: ${LEMPER_USERNAME}\nPassword: ${LEMPER_PASSWORD}"

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
                run sed -i "/^${LEMPER_USERNAME}:/d" /srv/.htpasswd
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

    save_log -e "# LEMPer configuration.\n# Edit here if you change your password manually, but do NOT delete!"
}

# Save configuration.
function save_config() {
    if [[ ${DRYRUN} != true ]]; then
        [ -f /etc/lemper/lemper.conf ] && \
        echo "$@" >> /etc/lemper/lemper.conf
    fi
}

# Encrypt configuration.
function secure_config() {
    if [[ ${DRYRUN} != true ]]; then
        if [ -f /etc/lemper/lemper.conf ]; then
            run openssl aes-256-gcm -a -salt -md sha256 -k "${LEMPER_PASSWORD}" \
                -in /etc/lemper/lemper.conf -out /etc/lemper/lemper.cnf
        fi
    fi
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
