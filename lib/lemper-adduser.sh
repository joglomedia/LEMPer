#!/bin/bash
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

# Check if user is root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: Please use root to add new user."
    exit 1
fi

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
