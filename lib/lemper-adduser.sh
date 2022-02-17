#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Lemper Create - Simple LEMP Virtual Host Creator                        |
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

# Version control.
#PROG_NAME=$(basename "$0")
#PROG_VER="2.x.x"
#CMD_PARENT="lemper-cli"
#CMD_NAME="adduser"

# Make sure only root can access and not direct access.
if ! declare -F "requires_root" &>/dev/null; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

function header_msg() {
    clear
    cat <<- EOL
#==========================================================================#
#         Welcome to LEMPer Stack Manager for Debian/Ubuntu server         #
#==========================================================================#
#                 A simple tool to add new user into system.               #
#                                                                          #
#        For more information please visit https://masedi.net/lemper       #
#==========================================================================#
EOL
}

header_msg

echo -en "\nAdd new user? [y/n]: "
read -r tambah

while [[ "${tambah}" != n* && "${tambah}" != N* ]]; do
    echo -en "\nUsername: "
    read -r namauser
    echo -n "Password: "
    read -rs katasandi

    echo -en "\nExpire date [yyyy-mm-dd]? '-1' or 'unlimited' for non expiry account: "
    read -r expired
    if [[ "${expired}" != "unlimited" && "${expired}" != "-1" ]]; then
    	setexpiredate="-e $expired"
    else
    	setexpiredate=""
    fi

    echo -n "Allow Bash shell access? [y/n]: "
    read -r aksessh
    if [[ "${aksessh}" == y* || "${aksessh}" == Y* ]]; then
    	setusershell="-s /bin/bash"
    else
    	setusershell="-s /bin/false"
    fi

    echo -n "Create home directory? [y/n]: "
    read -r enablehomedir
    if [[ "${enablehomedir}" == y* ]]; then
    	sethomedir="-d /home/${namauser} -m"
    else
    	sethomedir="-d /home/${namauser} -M"
    fi

    echo -n "Set users group? [y/n]: "
    read -r setug
    if [[ "${setug}" == y* ]]; then
    	setgroup="-g users"
    else
    	setgroup=""
    fi

    #user_exists=$(grep -c '^${namauser}:' /etc/passwd)

    if [[ -z $(getent passwd "${namauser}") ]]; then
        useradd "${sethomedir}" "${setexpiredate}" "${setgroup}" "${setusershell}" "${namauser}"
        echo "${namauser}:${katasandi}" | chpasswd

        echo -n "Add user ${namauser} to sudoers? [y/n]: "
        read -r setsudoers
        if [[ "${setsudoers}" == y* ]]; then
        	usermod -aG sudo "${namauser}"
        fi
    else
        echo -e "\nUser '${namauser}' already exits."
        sleep 1
    fi

    header_msg

    echo -en "\nAdd another user? [y/n]: "
    read -r tambah
done
