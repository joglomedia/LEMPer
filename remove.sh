#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a simple LEMP stack installer for Debian/Ubuntu            |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 16.04 or Linux Mint 17   |
# | Last Update       : 14/01/2020                                          |
# | Author            : MasEDI.Net (me@masedi.net)                     |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2021 MasEDI.Net (https://masedi.net/lemper           |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

# Work even if somebody does "bash remove.sh".
set -e

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Get installer base directory.
export BASEDIR && \
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [ "$(type -t run)" != "function" ]; then
    . scripts/helper.sh
fi

# Make sure only root can run this installer script.
requires_root

# Make sure only supported distribution can run this installer script.
preflight_system_check


##
# Main LEMPer Uninstaller
#
header_msg

echo "Are you sure to remove LEMP stack installation?"
echo "Please ensure that you've backed up your critical data!"

if ! "${AUTO_REMOVE}"; then
    echo ""
    read -rt 20 -p "Press [Enter] to continue..." </dev/tty
fi

# Fix broken install, first?
echo ""
run dpkg --configure -a
run apt install -qq -y --fix-broken

### Remove Nginx ###
if [ -f scripts/remove_nginx.sh ]; then
    echo ""
    . ./scripts/remove_nginx.sh
fi

### Remove PHP & FPM ###
if [ -f scripts/remove_php.sh ]; then
    echo ""
    . ./scripts/remove_php.sh
fi

### Remove MySQL ###
if [ -f scripts/remove_mariadb.sh ]; then
    echo ""
    . ./scripts/remove_mariadb.sh
fi

### Remove PHP & FPM ###
if [ -f scripts/remove_memcached.sh ]; then
    echo ""
    . ./scripts/remove_memcached.sh
fi

### Remove Redis ###
if [ -f scripts/remove_redis.sh ]; then
    echo ""
    . ./scripts/remove_redis.sh
fi

### Remove MongoDB ###
if [ -f scripts/remove_mongodb.sh ]; then
    echo ""
    . ./scripts/remove_mongodb.sh
fi

### Remove Certbot ###
if [ -f scripts/remove_certbotle.sh ]; then
    echo ""
    . ./scripts/remove_certbotle.sh
fi

### Remove server security ###
if [ -f scripts/secure_server.sh ]; then
    echo ""
    . ./scripts/secure_server.sh remove
fi

### Remove default user account ###
echo ""
echo "Removing created default account..."
if "${AUTO_REMOVE}"; then
    REMOVE_ACCOUNT="y"
else
    while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
    done
fi
if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
    if [ "$(type -t delete_account)" == "function" ]; then
delete_account "lemper"
    fi
fi

### Remove created swap ###
echo ""
echo "Removing created swap..."
if "${AUTO_REMOVE}"; then
    REMOVE_SWAP="y"
else
    while [[ "${REMOVE_SWAP}" != "y" && "${REMOVE_SWAP}" != "n" ]]; do
read -rp "Remove created Swap? [y/n]: " -i y -e REMOVE_SWAP
    done
fi
if [[ "${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y* || "${FORCE_REMOVE}" == true ]]; then
    if [ "$(type -t remove_swap)" == "function" ]; then
remove_swap
    fi
fi

### Remove web tools ###
[ -f /usr/local/bin/lemper-cli ] && run rm -f /usr/local/bin/lemper-cli
[ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper

# Clean up existing lemper config.
[ -f /etc/lemper/lemper.conf ] && run rm -f /etc/lemper/lemper.conf

### Remove unnecessary packages ###
echo -e "\nCleaning up unnecessary packages..."
run apt autoremove -qq -y

status -e "\nLEMP stack has been removed completely."
warning -e "\nDid you know? that we're so sad to see you leave :'(
If you are not satisfied with LEMPer stack or have 
any other reasons to uninstall it, please let us know ^^

Issues: https://github.com/joglomedia/LEMPer/issues"

footer_msg
