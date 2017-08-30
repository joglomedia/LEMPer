#!/usr/bin/env bash

# Install Postfix mail server
function install_postfix {
    echo "Installing Postfix Mail Server..."

    apt-get install -y mailutils postfix

    # Update local time
    apt-get install -y ntpdate
    ntpdate -d cn.pool.ntp.org
}

header_msg
echo -n "Do you want to install Postfix Mail Server? [Y/n]: "
read pfinstall

if [[ "$pfinstall" == "Y" || "$pfinstall" == "y" || "$pfinstall" == "yes" ]]; then
    install_postfix
fi
