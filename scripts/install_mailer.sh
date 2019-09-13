#!/usr/bin/env bash

# Mail Installer
# Min. Requirement  : GNU/Linux Ubuntu 14.04
# Last Build        : 12/07/2019
# Author            : ESLabs.ID (eslabs.id@gmail.com)
# Since Version     : 1.0.0

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellchechk source=scripts/helper.sh
    # shellcheck disable=SC1090
    . "${BASEDIR}/helper.sh"
fi

# Make sure only root can run this installer script.
requires_root

# Install Postfix mail server
function install_postfix() {
    while [[ $INSTALL_POSTFIX != "y" && $INSTALL_POSTFIX != "n" ]]; do
        read -p "Do you want to install Postfix Mail Transfer Agent? [y/n]: " -e INSTALL_POSTFIX
    done
    if [[ "$INSTALL_POSTFIX" == Y* || "$INSTALL_POSTFIX" == y* ]]; then

        echo -e "\nInstalling Postfix Mail Transfer Agent..."

        run apt-get install -y mailutils postfix

        # Update local time
        run apt-get install -y ntpdate
        run ntpdate -d cn.pool.ntp.org

        # Installation status.
        if "${DRYRUN}"; then
            status -e "\nPostfix installed in dryrun mode."
        else
            if [[ $(ps -ef | grep -v grep | grep postfix | wc -l) > 0 ]]; then
                status -e "\nPostfix installed successfully."
            else
                warning -e "\nSomething wrong with Postfix installation."
            fi
        fi
    fi
}

## TODO: Add Dovecot
# https://www.linode.com/docs/email/postfix/email-with-postfix-dovecot-and-mysql/


echo "[Mail Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(command -v postfix) ]]; then
    warning "Postfix already exists. Installation skipped..."
else
    install_postfix "$@"
fi
