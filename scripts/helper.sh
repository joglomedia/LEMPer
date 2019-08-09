#!/usr/bin/env bash

# Helper Functions
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Export environment variables.
if [ -f ".env" ]; then
    # shellcheck source=.env
    # shellcheck disable=SC1094
    source <(grep -v '^#' .env | grep -v '^\[' | sed -E 's|^(.+)=(.*)$|: ${\1=\2}; export \1|g')
else
    echo "Environment variables required, but not found."
    exit 1
fi

# Direct access? make as dryrun mode.
DRYRUN=${DRYRUN:-true}

# Set default color decorator.
RED=${RED:-31}
GREEN=${GREEN:-32}
YELLOW=${YELLOW:-33}

function begin_color() {
    color="$1"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="$1"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
function run() {
    if "$DRYRUN"; then
        echo_color "$YELLOW" -n "would run "
        echo "$@"
    else
        if ! "$@"; then
            local CMDSTR="$*"
            error "Failure running '${CMDSTR}', exiting."
            exit 1
        fi
    fi
}

function continue_or_exit() {
    local prompt="$1"
    echo_color "$YELLOW" -n "$prompt"
    read -rp " [y/n] " yn
    if [[ "$yn" == N* || "$yn" == n* ]]; then
        echo "Cancelled."
        exit 0
    fi
}

# Make sure only root can run LEMPer script.
function requires_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This command can only be used by root."
        exit 1
    fi
}

function get_distrib_name() {
    if [ -f "/etc/os-release" ]; then
        # Export os-release vars.
        . /etc/os-release

        # Export lsb-release vars.
        if [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
        fi

        if [[ "${ID_LIKE}" == "ubuntu" ]]; then
            DISTRIB_NAME="ubuntu"
        else
            DISTRIB_NAME=${ID:-}
        fi
    elif [ -e /etc/system-release ]; then
    	DISTRIB_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
    	DISTRIB_NAME="unsupported"
    fi

    echo "${DISTRIB_NAME}"
}

# Get general distribution release name.
function get_release_name() {
    if [ -f "/etc/os-release" ]; then
        # Export os-release vars.
        . /etc/os-release

        # Export lsb-release vars.
        if [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
        fi

        if [[ "${ID_LIKE}" == "ubuntu" ]]; then
            DISTRIB_NAME="ubuntu"
        else
            DISTRIB_NAME=${ID:-}
        fi

        case ${DISTRIB_NAME} in
            debian)
                #RELEASE_NAME=${VERSION_CODENAME:-}
                RELEASE_NAME="unsupported"

                # TODO for Debian install
            ;;

            ubuntu)
                # Hack for Linux Mint release number.
                DISTRO_VERSION=${VERSION_ID:-$DISTRIB_RELEASE}
                MAJOR_RELEASE_VERSION=$(echo ${DISTRO_VERSION} | awk -F. '{print $1}')
                if [[ "${DISTRIB_ID}" == "LinuxMint" || "${ID}" == "linuxmint" ]]; then
                    DISTRIB_RELEASE="LM${MAJOR_RELEASE_VERSION}"
                fi

                if [[ "${DISTRIB_RELEASE}" == "14.04" || "${DISTRIB_RELEASE}" == "LM17" ]]; then
                    # Ubuntu release 14.04, LinuxMint 17
                    RELEASE_NAME=${UBUNTU_CODENAME:-"trusty"}
                elif [[ "${DISTRIB_RELEASE}" == "16.04" || "${DISTRIB_RELEASE}" == "LM18" ]]; then
                    # Ubuntu release 16.04, LinuxMint 18
                    RELEASE_NAME=${UBUNTU_CODENAME:-"xenial"}
                elif [[ "${DISTRIB_RELEASE}" == "18.04" || "${DISTRIB_RELEASE}" == "LM19" ]]; then
                    # Ubuntu release 18.04, LinuxMint 19
                    RELEASE_NAME=${UBUNTU_CODENAME:-"bionic"}
                else
                    RELEASE_NAME="unsupported"
                fi
            ;;

            amzn)
                # Amazon based on RHEL/CentOS
                RELEASE_NAME="unsupported"

                # TODO for Amzn install
            ;;

            centos)
                # CentOS
                RELEASE_NAME="unsupported"

                # TODO for Amzn install
            ;;

            *)
                RELEASE_NAME="unsupported"
                warning "Sorry, this distro isn't supported yet. If you'd like it to be, let us know at eslabs.id@gmail.com."
            ;;
        esac
    elif [ -e /etc/system-release ]; then
    	RELEASE_NAME="unsupported"
    else
        # Red Hat /etc/redhat-release
    	RELEASE_NAME="unsupported"
    fi

    echo "${RELEASE_NAME}"
}

# Get physical RAM size.
function get_ram_size() {
    local RAM_SIZE

    # RAM size in MB
    RAM_SIZE=$(dmidecode -t 17 | awk '( /Size/ && $2 ~ /^[0-9]+$/ ) { x+=$2 } END{ print x}')

    echo "${RAM_SIZE}"
}

# Create custom Swap.
function create_swap() {
    local SWAP_FILE="/proc/lemper-swapfile"
    local RAM_SIZE && \
    RAM_SIZE=$(get_ram_size)

    if [[ ${RAM_SIZE} -lt 8192 ]]; then
        # If machine RAM less than 8GiB, set swap to half of it.
        local SWAP_SIZE=$((RAM_SIZE / 2))
    else
        # Otherwise, set swap to max of 4GiB.
        local SWAP_SIZE=4096
    fi

    echo "Create ${SWAP_SIZE}MiB swap..."

    # Create swap.
    run fallocate -l ${SWAP_SIZE}M ${SWAP_FILE} && \
    run chmod 600 ${SWAP_FILE} && \
    run chown root:root ${SWAP_FILE} && \
    run mkswap ${SWAP_FILE} && \
    run swapon ${SWAP_FILE}

    # Make the change permanent.
    if "${DRYRUN}"; then
        echo "Add persistent swap to fstab in dryrun mode."
    else
        run echo "${SWAP_FILE} swap swap defaults 0 0" >> /etc/fstab
    fi

    # Adjust swappiness, default Ubuntu set to 60
    # meaning that the swap file will be used fairly often if the memory usage is
    # around half RAM, for production servers you may need to set a lower value.
    if [[ $(cat /proc/sys/vm/swappiness) -gt 15 ]]; then
        run sysctl vm.swappiness=15

        if "${DRYRUN}"; then
            echo "Update swappiness value in dryrun mode."
        else
            run echo "vm.swappiness=15" >> /etc/sysctl.conf
        fi
    fi
}

# Remove created Swap.
function remove_swap() {
    echo "Disabling swap..."

    local SWAP_FILE="/proc/lemper-swapfile"

    run swapoff -v ${SWAP_FILE} && \
    run sed -i "s/${SWAP_FILE}/#\ ${SWAP_FILE}/g" /etc/fstab && \
    run rm -f ${SWAP_FILE}
}

# Enable swap.
function enable_swap() {
    echo "Checking swap..."

    if free | awk '/^Swap:/ {exit !$2}'; then
        local SWAP_SIZE && \
        SWAP_SIZE=$(free -m | awk '/^Swap:/ { print $2 }')
        status "Swap size ${SWAP_SIZE}MiB."
    else
        warning "No swap detected."
        create_swap
        status "Swap created and enabled."
    fi
}

# Create system account.
function create_account() {
    export USERNAME=${1:-"lemper"}
    export PASSWORD && \
    PASSWORD=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

    echo "Creating default LEMPer account..."

    if [[ -z $(getent passwd "${USERNAME}") ]]; then
        if "${DRYRUN}"; then
            echo "Username ${USERNAME} created in dryrun mode."
        else
            run useradd -d "/home/${USERNAME}" -m -s /bin/bash "${USERNAME}"
            run echo "${USERNAME}:${PASSWORD}" | chpasswd
            run usermod -aG sudo "${USERNAME}"

            if [ -d "/home/${USERNAME}" ]; then
                run mkdir "/home/${USERNAME}/webapps"
                run chown -hR "${USERNAME}" "/home/${USERNAME}/webapps"
            fi

            # Save data to log file.
            echo "
Your default system account information:
Username: ${USERNAME} | Password: ${PASSWORD}
" >> lemper.log 2>&1

            status "Username ${USERNAME} created."
        fi
    else
        warning "Unable to create account, username \"${USERNAME}\" already exists."
    fi
}

# Delete system account.
function delete_account() {
    local USERNAME=${1:-"lemper"}

    if [[ -n $(getent passwd "${USERNAME}") ]]; then
        run userdel -r "${USERNAME}"
        status "Default LEMPer account deleted."
    else
        warning "Default LEMPer account not found."
    fi
}

# Get server IP Address.
function get_ip_addr() {
    IP_INTERNAL=$(ip addr | grep 'inet' | grep -v inet6 | \
        grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | \
        grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    IP_EXTERNAL=$(curl -s http://ipecho.net/plain)

    if [[ "${IP_INTERNAL}" == "${IP_EXTERNAL}" ]]; then
        echo "${IP_EXTERNAL}"
    else
        echo "${IP_INTERNAL}"
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
    local compare_to="$2"
    local older_version="${test_version}"

    test "$older_version" != "$compare_to"
}

function nginx_download_report_error() {
    fail "Couldn't automatically determine the latest nginx version: failed to $* Nginx's download page"
}

function get_nginx_versions_available() {
    # Scrape nginx's download page to try to find the all available nginx versions.
    nginx_download_url="https://nginx.org/en/download.html"

    local nginx_download_page
    nginx_download_page=$(curl -sS --fail "$nginx_download_url") || \
        nginx_download_report_error "download"

    local download_refs
    download_refs=$(echo "$nginx_download_page" | \
        grep -owE '"/download/nginx-[0-9.]*\.tar\.gz"') || \
        nginx_download_report_error "parse"

    versions_available=$(echo "$download_refs" | \
        sed -e 's~^"/download/nginx-~~' -e 's~\.tar\.gz"$~~') || \
        nginx_download_report_error "extract versions from"

    echo "$versions_available"
}

# Try to find the most recent nginx version (mainline).
function determine_latest_nginx_version() {
    local versions_available
    local latest_version

    versions_available=$(get_nginx_versions_available)
    latest_version=$(echo "$versions_available" | version_sort | tail -n 1) || \
        report_error "determine latest (mainline) version from"

    if version_older_than "$latest_version" "1.14.2"; then
        fail "Expected the latest version of nginx to be at least 1.14.2 but found
$latest_version on $nginx_download_url"
    fi

    echo "$latest_version"
}

# Try to find the stable nginx version (mainline).
function determine_stable_nginx_version() {
    local versions_available
    local stable_version

    versions_available=$(get_nginx_versions_available)
    stable_version=$(echo "$versions_available" | version_sort | tail -n 2 | sort -r | tail -n 1) || \
        report_error "determine stable (LTS) version from"

    if version_older_than "1.14.2" "$latest_version"; then
        fail "Expected the latest version of nginx to be at least 1.14.2 but found
$latest_version on $nginx_download_url"
    fi

    echo "$stable_version"
}

# Validate Nginx configuration.
function validate_nginx_config() {
    if nginx -t 2>/dev/null > /dev/null; then
        return 1
    else
        return 0
    fi
}

# Init logging.
function init_log() {
    touch lemper.log
    echo "" > lemper.log
}

# Header message.
function header_msg() {
    clear
    cat <<- _EOF_
#==========================================================================#
#        LEMPer v1.2.0 for Ubuntu-based server, Written by ESLabs.ID       #
#==========================================================================#
#      A small tool to install Nginx + MariaDB (MySQL) + PHP on Linux      #
#                                                                          #
#        For more information please visit https://eslabs.id/lemper        #
#==========================================================================#
_EOF_
}

# Footer credit message.
function footer_msg() {
    cat <<- _EOF_

#==========================================================================#
#         Thank's for installing LEMP stack using LEMPer Installer         #
#        Found any bugs / errors / suggestions? please let me know         #
#    If this script useful, don't forget to buy me a coffee or milk :D     #
#   My PayPal is always open for donation, here https://paypal.me/masedi   #
#                                                                          #
#         (c) 2014-2019 - ESLabs.ID - https://eslabs.id/lemper ;)          #
#==========================================================================#
_EOF_
}
