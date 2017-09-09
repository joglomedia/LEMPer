#!/usr/bin/env bash

# Phalcon PHP extension installer
# Min requirement   : GNU/Linux Ubuntu 14.04
# Last Build        : 13/11/2015
# Author            : MasEDI.Net (hi@masedi.net)

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    echo "This script must be run as root..."
    exit 1
fi

clear
echo "+=========================================================================+"
echo "+ PhalconPHP Installer v 1.0.0-beta for Ubuntu VPS, Written by MasEDI.Net +"
echo "+=========================================================================+"
echo "+ A small tool to install Phalcon PHP Framework & Zephir Lang Interpreter +"
echo "+                                                                         +"
echo "+        For more information please visit http://masedi.net/tools/       +"
echo "+=========================================================================+"
sleep 1

# Prerequisite packages
apt-get install re2c libpcre3-dev gcc make

# Install Zephir
echo -n "Should we install Zephir Interpreter? [Y/n]: "
read instalzephir
if [[ "${instalzephir}" = "Y" || "${instalzephir}" = "y" || "${instalzephir}" = "yes" ]]; then
    # clon Zephir repo
    git clone https://github.com/phalcon/zephir.git
    cd zephir

    # install json-c
    ./install-json

    # install zephir
    composer install
    ./install
fi

git clone http://github.com/phalcon/cphalcon.git
git checkout master
cd cphalcon/build
./install
