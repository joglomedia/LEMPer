#!/usr/bin/env bash

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    . ${BASEDIR}/helper.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "You need to be root to run this script"
    exit 1
fi

echo ""
echo "Welcome to Mailer installation script"
echo ""

# Install Postfix mail server
function install_postfix() {
    echo -e "Installing Postfix Mail Transfer Agent..."

    run apt-get install -y mailutils postfix >> lemper.log 2>&1

    # Update local time
    run apt-get install -y ntpdate >> lemper.log 2>&1
    run ntpdate -d cn.pool.ntp.org >> lemper.log 2>&1
}

## TODO: Add Dovecot
# https://www.linode.com/docs/email/postfix/email-with-postfix-dovecot-and-mysql/

## Main
while [[ $INSTALL_POSTFIX != "y" && $INSTALL_POSTFIX != "n" ]]; do
    read -p "Do you want to install Postfix Mail Transfer Agent? [y/n]: " -e INSTALL_POSTFIX
done
if [[ "$INSTALL_POSTFIX" == Y* || "$INSTALL_POSTFIX" == y* ]]; then
    if [[ -n $(which postfix) ]]; then
        warning -e "\nPostfix already exists. Installation skipped..."
    else
        install_postfix "$@"
    fi
fi
