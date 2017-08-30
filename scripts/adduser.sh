#!/bin/bash
clear
echo "#######################################"
echo "## ##"
echo "## A D D U S E R ##"
echo "## ##"
echo "#######################################"

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: Please use root to add new user."
    exit 1
fi

echo -n "Add new user? (y/n): "
read tambah

while [ "${tambah}" != "n" ]
do
echo -n "Username: "
read namauser
echo -n "Password: "
read katasandi

echo -n "Expire date (yyyy-mm-dd): "
read expired
if [ "${expired}" != "unlimited" ]; then
	setexpiredate="-e $expired"
else
	setexpiredate=""
fi

echo -n "Allow shell access? (y/n): "
read aksessh
if [ "${aksessh}" = "y" ]; then
	setusershell="-s /bin/bash"
else
	setusershell="-s /bin/false"
fi

echo -n "Create home directory? (y/n): "
read enablehomedir
if [ "${enablehomedir}" = "y" ]; then
	sethomedir="-d /home/${namauser} -m"
else
	sethomedir="-d /home/${namauser} -M"
fi

echo -n "Set users group? (y/n): "
read setug
if [ "${setug}" = "y" ]; then
	setgroup="-g users"
else
	setgroup=""
fi

useradd $sethomedir $setexpiredate $setgroup $setusershell $namauser
echo "${namauser}:${katasandi}" | chpasswd

echo -n "Add user ${namauser} to sudoers? (y/n): "
read setsudoers
if [ "${setsudoers}" = "y" ]; then
	usermod -aG sudo $namauser
fi

clear
echo "#######################################"
echo "## ##"
echo "## A D D U S E R ##"
echo "## ##"
echo "#######################################"

echo -n "Add another user? (y/n): "
read tambah
done

