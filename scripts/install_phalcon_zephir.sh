#!/usr/bin/env bash

# Zephir installer
# Min requirement	: GNU/Linux Ubuntu 14.04
# Last Build		: 28/03/2015
# Author			: MasEDI.Net (hi@masedi.net)

# Make sure only root can run this installer script
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root..." 1>&2
	exit 1
fi

# Prerequisite packages
apt-get install re2c libpcre3-dev git

# clon Zephir repo
git clone https://github.com/phalcon/zephir.git

# Install zephir
cd zephir
# install json-c
./install-json
# install zephir
composer install
./install
