#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer is a simple LEMP stack installer for Debian/Ubuntu Linux         |
# |-------------------------------------------------------------------------+
# | Min requirement   : GNU/Linux Debian 8, Ubuntu 18.04 or Linux Mint 17   |
# | Last Update       : 13/02/2021                                          |
# | Author            : MasEDI.Net (me@masedi.net)                          |
# | Version           : 2.x.x                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2022 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

# Work even if somebody does "bash remove.sh".
#set -exv -o pipefail # For verbose output.
set -e -o pipefail

# Try to re-export global path.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Get installer base directory.
export BASE_DIR && \
BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    . "${BASE_DIR}/scripts/utils.sh"
fi

# Make sure only root can run this installer script.
requires_root "$@"

# Make sure only supported distribution can run this installer script.
preflight_system_check

##
# Main LEMPer Uninstaller
#
header_msg

echo "Are you sure to remove LEMPer Stack installation?"
echo "Please ensure that you've backed up your critical data!"
echo ""

if [[ "${AUTO_REMOVE}" == false ]]; then
    read -rt 20 -p "Press [Enter] to continue..." </dev/tty
fi

# Fix broken install, first?
if [[ "${FIX_BROKEN_INSTALL}" == true ]]; then
    run dpkg --configure -a
    run apt-get install -q -y --fix-broken
fi

### Remove Nginx ###
if [ -f ./scripts/remove_nginx.sh ]; then
    echo ""
    . ./scripts/remove_nginx.sh
fi

### Remove MySQL ###
if [ -f ./scripts/remove_mariadb.sh ]; then
    echo ""
    . ./scripts/remove_mariadb.sh
fi

### Remove PostgreSQL ###
if [ -f ./scripts/remove_postgres.sh ]; then
    echo ""
    . ./scripts/remove_postgres.sh
fi

### Remove PHP & FPM ###
if [ -f ./scripts/remove_php.sh ]; then
    echo ""
    . ./scripts/remove_php.sh
fi

### Remove Redis ###
if [ -f ./scripts/remove_redis.sh ]; then
    echo ""
    . ./scripts/remove_redis.sh
fi

### Remove MongoDB ###
if [ -f ./scripts/remove_mongodb.sh ]; then
    echo ""
    . ./scripts/remove_mongodb.sh
fi

### Remove PHP & FPM ###
if [ -f ./scripts/remove_memcached.sh ]; then
    echo ""
    . ./scripts/remove_memcached.sh
fi

### Mail server installation ###
if [ -f ./scripts/remove_mailer.sh ]; then
    echo ""
    . ./scripts/remove_mailer.sh
fi

### Remove FTP installation ###
if [[ "${FTP_SERVER_NAME}" == "pureftpd" || "${FTP_SERVER_NAME}" == "pure-ftpd" ]]; then
    if [ -f ./scripts/remove_pureftpd.sh ]; then
        echo ""
        . ./scripts/remove_pureftpd.sh
    fi
else
    if [ -f ./scripts/remove_vsftpd.sh ]; then
        echo ""
        . ./scripts/remove_vsftpd.sh
    fi
fi

### Remove Fail2ban ###
if [ -f ./scripts/remove_fail2ban.sh ]; then
    echo ""
    . ./scripts/remove_fail2ban.sh
fi

### Remove Certbot ###
if [ -f ./scripts/remove_certbotle.sh ]; then
    echo ""
    . ./scripts/remove_certbotle.sh
fi

### Remove server security setup ###
if [ -f ./scripts/server_security.sh ]; then
    echo ""
    . ./scripts/server_security.sh --remove
fi

### Remove default user account ###
echo ""
echo "Removing created default account..."

if [[ "${AUTO_REMOVE}" == true ]]; then
    REMOVE_ACCOUNT="y"
else
    while [[ "${REMOVE_ACCOUNT}" != "y" && "${REMOVE_ACCOUNT}" != "n" ]]; do
read -rp "Remove default LEMPer account? [y/n]: " -i y -e REMOVE_ACCOUNT
    done
fi

if [[ "${REMOVE_ACCOUNT}" == Y* || "${REMOVE_ACCOUNT}" == y* || "${FORCE_REMOVE}" == true ]]; then
    if [[ "$(type -t delete_account)" == "function" ]]; then
        delete_account "${LEMPER_USERNAME}"
    fi
fi

### Remove created swap ###
echo ""
echo "Removing created swap..."

if [[ "${AUTO_REMOVE}" == true ]]; then
    REMOVE_SWAP="y"
else
    while [[ "${REMOVE_SWAP}" != "y" && "${REMOVE_SWAP}" != "n" ]]; do
read -rp "Remove created Swap? [y/n]: " -e REMOVE_SWAP
    done
fi

if [[ "${REMOVE_SWAP}" == Y* || "${REMOVE_SWAP}" == y* || "${FORCE_REMOVE}" == true ]]; then
    if [[ "$(type -t remove_swap)" == "function" ]]; then
        remove_swap
    fi
fi

### Remove web tools ###
[ -f /usr/local/bin/lemper-cli ] && run rm -f /usr/local/bin/lemper-cli
[ -d /usr/local/lib/lemper ] && run rm -fr /usr/local/lib/lemper

# Clean up existing lemper config.
[ -f /etc/lemper/lemper.conf ] && run rm -f /etc/lemper/lemper.conf
[ -d /etc/lemper/cli-plugins ] && run rm -fr /etc/lemper/cli-plugins

### Remove unnecessary packages ###
echo -e "\nCleaning up unnecessary packages..."

if [[ "${FORCE_REMOVE}" == true ]]; then
    [ -d /tmp/lemper ] && run rm -fr /tmp/lemper
fi

run apt-get autoremove -q -y && \
run apt-get autoclean -q -y && \
run apt-get clean -q -y

status -e "\nLEMPer Stack has been removed completely."
warning -e "\nDid you know? that we're so sad to see you leave :'(
If you are not satisfied with LEMPer Stack or have 
any other reasons to uninstall it, please let us know ^^

Submit your issue here: https://github.com/joglomedia/LEMPer/issues"

footer_msg
