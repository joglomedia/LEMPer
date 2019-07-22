#!/usr/bin/env bash

# Helper Functions
# Min. Requirement  : GNU/Linux Ubuntu 14.04 & 16.04
# Last Build        : 17/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

export $(grep -v '^#' .env | grep -v '^\[' | xargs)
#unset $(grep -v '^#' ../.env | grep -v '^\[' | sed -E 's/(.*)=.*/\1/' | xargs)

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
    local error_message="$@"
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
INITIAL_ENV=$(printenv | sort)
function run() {
    if "$DRYRUN"; then
        echo_color "$YELLOW" -n "would run"
        echo " $@"
        env_differences=$(comm -13 <(echo "$INITIAL_ENV") <(printenv | sort))

        #if [ -n "$env_differences" ]; then
            #echo "  with the following additional environment variables:"
            #echo "$env_differences" | sed 's/^/    /'
        #fi
    else
        if ! "$@"; then
            error "Failure running '$@', exiting."
            exit 1
        fi
    fi
}

function continue_or_exit() {
    local prompt="$1"
    echo_color "$YELLOW" -n "$prompt"
    read -p " [y/n] " yn
    if [[ "$yn" == N* || "$yn" == n* ]]; then
        echo "Cancelled."
        exit 0
    fi
}

# Make sure only root can run this installer script.
function is_root() {
    if [ $(id -u) -ne 0 ]; then
        return 1
    fi
}

# Create custom Swap.
function create_swap() {
    echo "Enabling 1GiB swap..."

    L_SWAP_FILE="/lemper-swapfile"

    RAM_SIZE=$(get_ram_size)
    if [[ ${RAM_SIZE} -lt 8192 ]]; then
        # If machine RAM less than 8GiB, set swap to half of it.
        SWAP_SIZE=$(expr ${RAM_SIZE} / 2)
    else
        # Otherwise, set swap to max of 4GiB.
        SWAP_SIZE=4096
    fi

    run fallocate -l ${SWAP_SIZE}M ${L_SWAP_FILE} && \
        chmod 600 ${L_SWAP_FILE} && \
        chown root:root ${L_SWAP_FILE} && \
        mkswap ${L_SWAP_FILE} && \
        swapon ${L_SWAP_FILE}

    # Make the change permanent.
    echo "${L_SWAP_FILE} swap swap defaults 0 0" >> /etc/fstab

    # Adjust swappiness, default Ubuntu set to 60
    # meaning that the swap file will be used fairly often if the memory usage is
    # around half RAM, for production servers you may need to set a lower value.
    if [[ $(cat /proc/sys/vm/swappiness) -gt 15 ]]; then
        run sysctl vm.swappiness=15
        run echo "vm.swappiness=15" >> /etc/sysctl.conf
    fi
}

# Remove created Swap.
function remove_swap() {
    echo -e "\nDisabling swap..."

    L_SWAP_FILE="/lemper-swapfile"

    run swapoff -v ${L_SWAP_FILE} && \
        sed -i "s|${L_SWAP_FILE}|#\ ${L_SWAP_FILE}|g" /etc/fstab && \
        rm -f ${L_SWAP_FILE}
}

# Get physical RAM size.
function get_ram_size() {
    # RAM size in MB
    local RAM=$(dmidecode -t 17 | awk '( /Size/ && $2 ~ /^[0-9]+$/ ) { x+=$2 } END{ print x}')
    echo $RAM
}

# Check available Swap size.
function check_swap() {
    echo -e "\nChecking swap..."

    if free | awk '/^Swap:/ {exit !$2}'; then
        swapsize=$(free -m | awk '/^Swap:/ { print $2 }')
        status "Swap size ${swapsize}MiB."
    else
        warning "No swap detected"
        create_swap
        status "Adding swap completed..."
    fi
}

# Create system account
function create_account() {
    if [[ -n $1 ]]; then
        USERNAME="$1"
    else
        USERNAME="lemper" # default system account for LEMPer
    fi

    echo -e "\nCreating default LEMPer account..."

    if [[ -z $(getent passwd ${USERNAME}) ]]; then
        PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
        run useradd -d /home/${USERNAME} -m -s /bin/bash ${USERNAME}
        run echo "${USERNAME}:${PASSWORD}" | chpasswd
        run usermod -aG sudo ${USERNAME}

        if [ -d /home/${USERNAME} ]; then
            run mkdir /home/${USERNAME}/webapps
            run chown -hR ${USERNAME}:${USERNAME} /home/${USERNAME}/webapps
        fi

        # Save data to log
        echo "
        Your default system account information:
        Username: ${USERNAME} | Password: ${PASSWORD}
        " >> lemper.log 2>&1

        status "Username ${USERNAME} created."
    else
        warning "Username ${USERNAME} already exists."
    fi
}

# Delete system account
function delete_account() {
    if [[ -n $1 ]]; then
        USERNAME="$1"
    else
        USERNAME="lemper" # default system account for LEMPer
    fi

    echo ""
    while [[ $REMOVE_ACCOUNT != "y" && $REMOVE_ACCOUNT != "n" ]]; do
        read -p "Remove default LEMPer account? [y/n]: " -e REMOVE_ACCOUNT
    done
    if [[ "$REMOVE_ACCOUNT" == Y* || "$REMOVE_ACCOUNT" == y* ]]; then
        if [[ ! -z $(getent passwd "${USERNAME}") ]]; then
            run userdel -r ${USERNAME} >> lemper.log 2>&1
            status "Default LEMPer account deleted."
        else
            warning "Default LEMPer account not found."
        fi
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

# Compare two numeric versions in the form "A.B.C".    Works with version numbers
# having up to four components, since that's enough to handle both nginx (3) and
# ngx_pagespeed (4).
function version_older_than() {
    local test_version="$1"
    local compare_to="$2"

    local older_version=$(echo $@ | tr ' ' '\n' | version_sort | head -n 1)
    test "$older_version" != "$compare_to"
}

# Validate Nginx configuration.
function validate_nginx_config() {
    NGX_BIN=$(which nginx)
    ${NGX_BIN} -t 2>/dev/null > /dev/null

    if [[ $? == 0 ]]; then
        echo "success"
        # do things on success
    else
        echo "fail"
        # do whatever on fail
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
#        LEMPer v1.0.0 for Ubuntu-based server, Written by ESLabs.ID       #
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
#         Thank's for installing LNMP stack using LEMPer Installer         #
#        Found any bugs / errors / suggestions? please let me know         #
#    If this script useful, don't forget to buy me a coffee or milk :D     #
#   My PayPal is always open for donation, here https://paypal.me/masedi   #
#                                                                          #
#         (c) 2014-2019 - ESLabs.ID - https://eslabs.id/lemper ;)          #
#==========================================================================#
_EOF_
}
