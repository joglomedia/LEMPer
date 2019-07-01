#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo -e "\nWelcome to Postfix installation script"

# Install Postfix mail server
function install_postfix {
    echo -e "\nInstalling Postfix Mail Server..."

    run apt-get install -y mailutils postfix

    # Update local time
    run apt-get install -y ntpdate
    run ntpdate -d cn.pool.ntp.org
}

#header_msg
echo -en "\nDo you want to install Postfix Mail Server? [Y/n]: "
read pfinstall

if [[ "$pfinstall" == Y* || "$pfinstall" == y* ]]; then
    install_postfix
fi
