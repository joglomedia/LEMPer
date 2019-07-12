#!/usr/bin/env bash

# Dry run
DRYRUN=false

# Decorator
RED=31
GREEN=32
YELLOW=33

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

        if [ -n "$env_differences" ]; then
            echo "  with the following additional environment variables:"
            echo "$env_differences" | sed 's/^/    /'
        fi
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

# Make sure only root can run this installer script
function is_root() {
    if [ $(id -u) -ne 0 ]; then
        return 1
    fi
}

# Create custom Swap
function create_swap() {
    echo "Enabling 1GiB swap..."

    L_SWAP_FILE="/lemper-swapfile"

    RAM_SIZE=$(get_ram_size)
    if [[ $RAM_SIZE -lt 8192 ]]; then
        # If machine RAM less than 8GiB, set swap to half of it.
        SWAP_SIZE=$(($RAM_SIZE / 2))
    else
        # Otherwise, set swap to max of 4GiB
        SWAP_SIZE=4096
    fi

    fallocate -l ${SWAP_SIZE}M $L_SWAP_FILE && \
    chmod 600 $L_SWAP_FILE && \
    chown root:root $L_SWAP_FILE && \
    mkswap $L_SWAP_FILE && \
    swapon $L_SWAP_FILE

    # Make the change permanent
    echo "$L_SWAP_FILE swap swap defaults 0 0" >> /etc/fstab

    # Adjust swappiness, default Ubuntu set to 60
    # meaning that the swap file will be used fairly often if the memory usage is
    # around half RAM, for production servers you may need to set a lower value.
    if [[ $(cat /proc/sys/vm/swappiness) -gt 15 ]]; then
        sysctl vm.swappiness=15
        echo "vm.swappiness=15" >> /etc/sysctl.conf
    fi
}

# Remove created Swap
function remove_swap() {
    echo -e "\nDisabling swap..."

    L_SWAP_FILE="/lemper-swapfile"

    swapoff -v $L_SWAP_FILE
    sed -i "s|$L_SWAP_FILE|#\ $L_SWAP_FILE|g" /etc/fstab
    rm -f $L_SWAP_FILE
}

# Get physical RAM size
function get_ram_size() {
    # RAM size in MB
    local RAM=$(dmidecode -t 17 | awk '( /Size/ && $2 ~ /^[0-9]+$/ ) { x+=$2 } END{ print x}')
    echo $RAM
}

# Check available Swap size
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
        USERNAME="lemper" # default account
    fi

    echo -e "\nCreating default LEMPer account..."

    if [[ -z $(getent passwd "${USERNAME}") ]]; then
        PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
        run useradd -d /home/${USERNAME} -m -s /bin/bash ${USERNAME}
        echo "${USERNAME}:${PASSWORD}" | chpasswd
        run usermod -aG sudo ${USERNAME}

        if [ -d /home/${USERNAME} ]; then
            run mkdir /home/${USERNAME}/webapps
            run chown -hR ${USERNAME}:${USERNAME} /home/${USERNAME}/webapps
        fi

        status "Username ${USERNAME} created."
    else
        warning "Username ${USERNAME} already exists."
    fi
}

function header_msg() {
clear
cat <<- _EOF_
#========================================================================#
#       LEMPer v1.0.0 for Debian-based server, Written by ESLabs.ID      #
#========================================================================#
#     A small tool to install Nginx + MariaDB (MySQL) + PHP on Linux     #
#                                                                        #
#       For more information please visit https://eslabs.id/lemper       #
#========================================================================#
_EOF_
}

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
