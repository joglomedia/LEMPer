#!/usr/bin/env bash

# Basic Server Security Hardening
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 06/08/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 2.6.4

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

function init_server_optimization() {
    ### Create and enable swap ###
    if [[ "${ENABLE_SWAP}" == true ]]; then
        echo ""
        enable_swap
    fi

    ### Create and enable sysctl ###
    echo "Configure kernel optimization..."

    # Adjust swappiness, default Ubuntu set to 60
    # meaning that the swap file will be used fairly often if the memory usage is
    # around half RAM, for production servers you may need to set a lower value.
    if [[ "${ENABLE_SWAP}" == true ]]; then
        echo "Adjusting swappiness..."

        if [[ $(cat /proc/sys/vm/swappiness) -gt 10 ]]; then
            if [[ ${DRYRUN} != true ]]; then
                run sed -i "s/vm.swappiness/#vm.swappiness/" /etc/sysctl.conf
                cat >> /etc/sysctl.conf <<EOL
###################################################################
# Custom optimization for LEMPer
#
vm.swappiness = 10
EOL

                run sysctl -w vm.swappiness=10
            else
                echo "Update swappiness value in dry run mode."
            fi
        fi
    fi

    # Custom kernel optimization.
    if [[ $(cat /proc/sys/net/core/somaxconn) -lt 65535 ]]; then
        echo "Adjusting socket connection limit..."
        cat >> /etc/sysctl.conf <<EOL
# Backlog socket tunning.
net.core.somaxconn = 65535
vm.overcommit_memory = 1

EOL

        run sysctl -w net.core.somaxconn=65535
        run sysctl -w vm.overcommit_memory=1
    fi

    if [[ $(cat /proc/sys/fs/file-max) -lt 200000 ]]; then
        echo "Adjusting file limits..."
        cat >> /etc/sysctl.conf <<EOL
# Open-files handle limits.
fs.file-max = 200000

EOL

        run sysctl -w fs.file-max=200000
    fi

    if [[ $(cat /proc/sys/fs/inotify/max_user_watches) -lt 65535 ]]; then
        echo "Adjusting file inotify watchers..."
        cat >> /etc/sysctl.conf <<EOL
# Open-files handle limits.
fs.inotify.max_user_watches = 65535

EOL

        run sysctl -w fs.inotify.max_user_watches=65535
    fi

    if [[ ${INSTALL_REDIS} == true ]]; then
        echo "Kernel optimization for Redis..."

        run bash -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"

        if [[ ! -f /etc/rc.local ]]; then
            run touch /etc/rc.local
        fi

        # Make the change persistent.
        cat >> /etc/rc.local <<EOL
###################################################################
# Custom optimization for LEMPer
#
echo never > /sys/kernel/mm/transparent_hugepage/enabled
EOL
    fi

    run sysctl -p
}

echo "[LEMPer Stack Basic Server Optimization]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_server_optimization "$@"