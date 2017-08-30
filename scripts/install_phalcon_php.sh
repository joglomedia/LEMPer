#!/usr/bin/env bash

# Phalcon PHP extension installer
# Min requirement	: GNU/Linux Ubuntu 14.04
# Last Build		: 13/11/2015
# Author			: MasEDI.Net (hi@masedi.net)

# Make sure only root can run this installer script
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root..." 1>&2
	exit 1
fi

clear
echo "#========================================================================="
echo "# PhalconPHP Installer v 1.0.0-beta for Ubuntu VPS, Written by MasEDI.Net "
echo "#========================================================================="
echo "# A small tool to install Phalcon PHP Framework & Zephir Lang Interpreter "
echo "#"
echo "# For more information please visit http://masedi.net/tools/"
echo "#========================================================================="
sleep 2

# Prerequisite packages
apt-get install re2c libpcre3-dev php5-dev gcc make

# Install Zephir
echo -n "Should we install Zephir Interpreter? (y/n): "
read instalzeph
if [[ "${instalzeph}" = "y" || "${instalzeph}" = "yes" ]]; then
	#./zephirinstaller.sh
	# clon Zephir repo
	git clone https://github.com/phalcon/zephir.git

	# Install zephir
	cd zephir
	# install json-c
	./install-json
	# install zephir
	composer install
	./install
fi

git clone http://github.com/phalcon/cphalcon.git
git checkout 2.0.0
cd cphalcon/build
./install
